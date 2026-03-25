module Herald.Command.Batch
  ( batchPackage
  , BatchResult (..)
  , CommitMode (..)
  , commitBatchResult
  , computeMaxBump
  )
where

import RIO

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (Day)
import System.Directory (removeFile)
import System.FilePath ((</>))

import Herald.Cabal (readCabalVersion, writeCabalVersion)
import Herald.Changelog (prependSection)
import Herald.Fragment (validateFragment)
import Herald.Fragment.Read (readProjectFragments)
import Herald.Fragment.Render (renderSection)
import Herald.Git (gitAdd, gitCommit, gitTag)
import Herald.Pvp (Pvp (..), bumpPvp, showPvp)
import Herald.Types (Config (..), Fragment (..), KindDef (..), ProjectConfig (..), throwHerald)

-- | Result of a batch operation, for reporting to the user.
data BatchResult = BatchResult
  { batchResultVersion :: !Pvp
  , batchResultPackage :: !Text
  , batchResultFragments :: ![FilePath]
  , batchResultChangelog :: !FilePath
  , batchResultCabalFile :: !(Maybe FilePath)
  , batchResultChangesDir :: !FilePath
  }
  deriving Show

-- | Whether to commit and/or tag after batching.
data CommitMode = NoCommit | Commit | CommitTag
  deriving (Eq, Show)

-- | Batch changelog fragments for a package: compute version, render section,
-- prepend to CHANGELOG.md, update .cabal version, and remove processed fragments.
-- Returns 'Nothing' (with a warning) when no fragments exist for the package.
batchPackage :: Config -> FilePath -> Text -> Maybe Pvp -> Day -> IO (Maybe BatchResult)
batchPackage config baseDir package explicitVersion day = do
  projectConfig <-
    maybe (throwHerald $ "Unknown project: " <> T.unpack package) pure
      . Map.lookup package
      $ configProjects config
  let changesDir = baseDir </> configChangesDir config

  packagePairs <- readProjectFragments config baseDir package

  if null packagePairs
    then do
      TIO.hPutStrLn stderr
        $ "Warning: no changelog fragments found for "
        <> package
        <> "; nothing to do"
      pure Nothing
    else do
      -- Validate fragments before modifying anything
      let errors =
            concatMap
              (\(file, frag) -> map (\e -> T.pack file <> ": " <> e) $ validateFragment config frag)
              packagePairs
      unless (null errors)
        . throwHerald
        . T.unpack
        $ T.intercalate "\n" errors

      let packageFragments = map snd packagePairs

      -- Compute version
      version <- maybe (autoVersion projectConfig packageFragments) pure explicitVersion

      -- Warn if explicit version is a downgrade
      forM_ (projectCabalFile projectConfig) $ \cf -> do
        currentVersion <- readCabalVersion (baseDir </> cf)
        forM_ currentVersion $ \cv ->
          when (version < cv)
            . throwHerald
            $ "Version "
            <> showPvp version
            <> " is lower than current "
            <> showPvp cv
            <> " in "
            <> cf

      -- Render section and prepend to changelog
      let section = renderSection config version day packageFragments
      prependSection (baseDir </> projectChangelog projectConfig) section

      -- Update .cabal version (if cabal-file is configured)
      forM_ (projectCabalFile projectConfig) $ \cf ->
        writeCabalVersion (baseDir </> cf) version

      -- Remove processed fragment files
      forM_ packagePairs $ \(file, _) ->
        removeFile $ changesDir </> file

      pure
        . Just
        $ BatchResult
          { batchResultVersion = version
          , batchResultPackage = package
          , batchResultFragments = map fst packagePairs
          , batchResultChangelog = baseDir </> projectChangelog projectConfig
          , batchResultCabalFile = (baseDir </>) <$> projectCabalFile projectConfig
          , batchResultChangesDir = configChangesDir config
          }
 where
  autoVersion projectConfig packageFragments = do
    cabalPath <-
      maybe (throwHerald "No cabal-file configured; use --version to set version explicitly") pure
        $ projectCabalFile projectConfig
    currentVersion <-
      readCabalVersion (baseDir </> cabalPath)
        >>= maybe (throwHerald "Could not read current version from .cabal") pure
    pure . bumpPvp (computeMaxBump config packageFragments) $ currentVersion

-- | Compute the maximum bump level from a list of fragments.
computeMaxBump :: Config -> [Fragment] -> Pvp
computeMaxBump config frags =
  let allKinds = concatMap fragmentKinds frags
      bumps = mapMaybe (fmap kindBump . (`Map.lookup` configKinds config)) allKinds
   in case bumps of
        [] -> Pvp (0 :| [0, 0, 1]) -- default: patch bump
        b : bs -> foldl' max b bs

-- | Stage batch changes, commit, and optionally tag.
commitBatchResult :: FilePath -> BatchResult -> CommitMode -> IO ()
commitBatchResult _ _ NoCommit = pure ()
commitBatchResult baseDir result mode = do
  let changesDir = batchResultChangesDir result
      fragmentPaths = map (changesDir </>) $ batchResultFragments result
      filesToStage =
        fragmentPaths
          <> [batchResultChangelog result]
          <> maybeToList (batchResultCabalFile result)
      pkg = T.unpack $ batchResultPackage result
      ver = showPvp $ batchResultVersion result
      msg = "Release " <> pkg <> "-" <> ver

  gitAdd baseDir filesToStage
  gitCommit baseDir msg

  when (mode == CommitTag)
    $ gitTag baseDir (pkg <> "-" <> ver)
