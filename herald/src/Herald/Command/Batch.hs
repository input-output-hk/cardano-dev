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
import Herald.Types
  ( Config (..)
  , Fragment (..)
  , KindDef (..)
  , ProjectConfig (..)
  , VersionSource (..)
  , throwHerald
  )
import Herald.VersionFile (readVersionFile, writeVersionFile)

-- | Result of a batch operation, for reporting to the user.
data BatchResult = BatchResult
  { batchResultVersion :: !Pvp
  , batchResultPackage :: !Text
  , batchResultFragments :: ![FilePath]
  , batchResultChangelog :: !FilePath
  , batchResultVersionPath :: !(Maybe FilePath)
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

      -- Read version once for both auto-version and downgrade check
      currentVersion <- readCurrentVersion baseDir projectConfig

      -- Compute version
      version <- maybe (autoVersion currentVersion packageFragments) pure explicitVersion

      -- Reject explicit version that would be a downgrade
      forM_ currentVersion $ \cv ->
        when (version < cv)
          . throwHerald
          $ "Version "
          <> showPvp version
          <> " is lower than current "
          <> showPvp cv

      -- Render section and prepend to changelog
      let section = renderSection config version day packageFragments
      prependSection (baseDir </> projectChangelog projectConfig) section

      -- Update version in the appropriate file
      writeVersion baseDir projectConfig version

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
          , batchResultVersionPath = versionFilePath baseDir projectConfig
          , batchResultChangesDir = configChangesDir config
          }
 where
  autoVersion currentVersion packageFragments = do
    cv <-
      maybe
        (throwHerald "No version source configured; use --version to set version explicitly")
        pure
        currentVersion
    pure . bumpPvp (computeMaxBump config packageFragments) $ cv

-- | Compute the maximum bump level from a list of fragments.
computeMaxBump :: Config -> [Fragment] -> Pvp
computeMaxBump config frags =
  let allKinds = concatMap fragmentKinds frags
      bumps = mapMaybe (fmap kindBump . (`Map.lookup` configKinds config)) allKinds
   in case bumps of
        [] -> Pvp (0 :| [0, 0, 1]) -- default: patch bump
        b : bs -> foldl' max b bs

-- | Read the current version from whichever source is configured.
readCurrentVersion :: FilePath -> ProjectConfig -> IO (Maybe Pvp)
readCurrentVersion baseDir projectConfig = case projectVersionSource projectConfig of
  Just (CabalFile cabalFile) -> readCabalVersion $ baseDir </> cabalFile
  Just (VersionFile versionFile) -> Just <$> readVersionFile (baseDir </> versionFile)
  Nothing -> pure Nothing

-- | Write the version to whichever source is configured.
writeVersion :: FilePath -> ProjectConfig -> Pvp -> IO ()
writeVersion baseDir projectConfig version = case projectVersionSource projectConfig of
  Just (CabalFile cabalFile) -> writeCabalVersion (baseDir </> cabalFile) version
  Just (VersionFile versionFile) -> writeVersionFile (baseDir </> versionFile) version
  Nothing -> pure ()

-- | Absolute path to the version file (cabal or plain text), if configured.
versionFilePath :: FilePath -> ProjectConfig -> Maybe FilePath
versionFilePath baseDir projectConfig = case projectVersionSource projectConfig of
  Just (CabalFile cabalFile) -> Just $ baseDir </> cabalFile
  Just (VersionFile versionFile) -> Just $ baseDir </> versionFile
  Nothing -> Nothing

-- | Stage batch changes, commit, and optionally tag.
commitBatchResult :: FilePath -> BatchResult -> CommitMode -> IO ()
commitBatchResult _ _ NoCommit = pure ()
commitBatchResult baseDir result mode = do
  let changesDir = batchResultChangesDir result
      fragmentPaths = map (changesDir </>) $ batchResultFragments result
      filesToStage =
        fragmentPaths
          <> [batchResultChangelog result]
          <> maybeToList (batchResultVersionPath result)
      pkg = T.unpack $ batchResultPackage result
      ver = showPvp $ batchResultVersion result
      msg = "Release " <> pkg <> "-" <> ver

  gitAdd baseDir filesToStage
  gitCommit baseDir msg

  when (mode == CommitTag)
    $ gitTag baseDir (pkg <> "-" <> ver)
