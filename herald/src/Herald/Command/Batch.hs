module Herald.Command.Batch
  ( batchPackage
  , dryRunBatch
  , BatchResult (..)
  , CommitMode (..)
  , VersionChoice (..)
  , DryRunResult (..)
  , DryRunFragment (..)
  , FragmentFate (..)
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
import Herald.Fragment.Render (isNotable, renderSection)
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
-- Fragment paths are stored relative to the base directory.
data BatchResult = BatchResult
  { batchResultVersion :: !Pvp
  , batchResultPackage :: !Text
  , batchResultFragments :: ![FilePath]
  , batchResultChangelog :: !FilePath
  , batchResultVersionPath :: !(Maybe FilePath)
  }
  deriving Show

-- | Whether to commit and/or tag after batching.
data CommitMode = NoCommit | Commit | CommitTag
  deriving (Eq, Show)

-- | How the release version for a batch is chosen.
-- 'UnspecifiedVersion' is a hard error for 'batchPackage' (see 'planBatch'):
-- there is no silent default, so a release version is never guessed by
-- accident. 'dryRunBatch' is the one exception -- it treats
-- 'UnspecifiedVersion' as 'AutoVersion', since nothing is written.
data VersionChoice
  = ExplicitVersion !Pvp
  | AutoVersion
  | UnspecifiedVersion
  deriving (Eq, Show)

-- | Whether a fragment's kinds are notable enough to appear in the changelog.
-- Mirrors 'Herald.Fragment.Render.isNotable'.
data FragmentFate = Included | ExcludedNonNotable
  deriving (Eq, Show)

-- | A single fragment's dry-run preview: where it came from, its kinds, and its fate.
data DryRunFragment = DryRunFragment
  { dryRunFragmentPath :: !FilePath
  , dryRunFragmentKinds :: ![Text]
  , dryRunFragmentFate :: !FragmentFate
  }
  deriving (Eq, Show)

-- | Preview of what a batch would do, without mutating anything.
data DryRunResult = DryRunResult
  { dryRunPackage :: !Text
  , dryRunCurrentVersion :: !(Maybe Pvp)
  , dryRunVersion :: !Pvp
  , dryRunFragments :: ![DryRunFragment]
  , dryRunSection :: !Text
  , dryRunChangelog :: !FilePath
  }
  deriving Show

-- | Batch changelog fragments for a package: compute version, render section,
-- prepend to CHANGELOG.md, update .cabal version, and remove processed fragments.
-- Returns 'Nothing' (with a warning) when no fragments exist for the package.
-- 'UnspecifiedVersion' is a hard error: batch never guesses a release version
-- silently, the caller must choose 'ExplicitVersion' or 'AutoVersion'.
batchPackage :: Config -> FilePath -> Text -> VersionChoice -> Day -> IO (Maybe BatchResult)
batchPackage config baseDir package versionChoice day =
  traverse (applyPlan baseDir) =<< planBatch config baseDir package versionChoice day

-- | Like 'batchPackage', but performs no mutation: no changelog write, no
-- version-source write, no fragment deletion. Unlike 'batchPackage',
-- 'UnspecifiedVersion' is not an error here -- it defaults to
-- auto-computation, since nothing is written.
dryRunBatch :: Config -> FilePath -> Text -> VersionChoice -> Day -> IO (Maybe DryRunResult)
dryRunBatch config baseDir package versionChoice day =
  fmap (toDryRunResult config baseDir)
    <$> planBatch config baseDir package (defaultToAuto versionChoice) day
 where
  defaultToAuto UnspecifiedVersion = AutoVersion
  defaultToAuto choice = choice

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
  let filesToStage =
        batchResultFragments result
          <> [batchResultChangelog result]
          <> maybeToList (batchResultVersionPath result)
      pkg = T.unpack $ batchResultPackage result
      ver = showPvp $ batchResultVersion result
      msg = "Release " <> pkg <> "-" <> ver

  gitAdd baseDir filesToStage
  gitCommit baseDir msg

  when (mode == CommitTag)
    $ gitTag baseDir (pkg <> "-" <> ver)

-------------------------------------------------------------------------------
-- Batch planning (shared read-only phase)
-------------------------------------------------------------------------------

-- | Everything needed to either apply a batch's changes ('applyPlan') or
-- report them without mutating anything ('toDryRunResult').
data BatchPlan = BatchPlan
  { planPackage :: !Text
  , planProjectConfig :: !ProjectConfig
  , planFragmentPairs :: ![(FilePath, Fragment)]
  , planCurrentVersion :: !(Maybe Pvp)
  , planVersion :: !Pvp
  , planSection :: !Text
  }

-- | Validate fragments, resolve the release version, and render the
-- changelog section, without writing or deleting anything.
-- Returns 'Nothing' (with a warning) when no fragments exist for the package.
planBatch :: Config -> FilePath -> Text -> VersionChoice -> Day -> IO (Maybe BatchPlan)
planBatch config baseDir package versionChoice day = do
  projectConfig <-
    maybe (throwHerald $ "Unknown project: " <> T.unpack package) pure
      . Map.lookup package
      $ configProjects config

  packagePairs <- readProjectFragments config baseDir package

  if null packagePairs
    then do
      TIO.hPutStrLn stderr
        $ "Warning: no changelog fragments found for "
        <> package
        <> "; nothing to do"
      pure Nothing
    else do
      -- Validate fragments before resolving the version or modifying anything
      let errors =
            concatMap
              (\(file, frag) -> map (\e -> T.pack file <> ": " <> e) $ validateFragment config frag)
              packagePairs
      unless (null errors)
        . throwHerald
        . T.unpack
        $ T.intercalate "\n" errors

      let packageFragments = map snd packagePairs

      -- Read version once for both version resolution and the downgrade check
      currentVersion <- readCurrentVersion baseDir projectConfig

      version <- resolveVersion currentVersion packageFragments

      -- Reject an explicit version that would be a downgrade
      forM_ currentVersion $ \cv ->
        when (version < cv)
          . throwHerald
          $ "Version "
          <> showPvp version
          <> " is lower than current "
          <> showPvp cv

      let section = renderSection config version day packageFragments

      pure
        . Just
        $ BatchPlan
          { planPackage = package
          , planProjectConfig = projectConfig
          , planFragmentPairs = packagePairs
          , planCurrentVersion = currentVersion
          , planVersion = version
          , planSection = section
          }
 where
  resolveVersion currentVersion packageFragments = case versionChoice of
    ExplicitVersion v -> pure v
    AutoVersion -> autoVersion currentVersion packageFragments
    UnspecifiedVersion ->
      throwHerald
        . T.unpack
        $ versionRequiredMessage (bumpPvp (computeMaxBump config packageFragments) <$> currentVersion)

  autoVersion currentVersion packageFragments = do
    cv <-
      maybe
        (throwHerald "No version source configured; use --version to set version explicitly")
        pure
        currentVersion
    pure . bumpPvp (computeMaxBump config packageFragments) $ cv

-- | Actionable error for a missing version choice: names the concrete
-- auto-computed version to pass when one is computable, and omits the
-- suggestion (there is nothing helpful to say) when it is not.
versionRequiredMessage :: Maybe Pvp -> Text
versionRequiredMessage mPreview =
  "batch requires an explicit version: pass --version "
    <> maybe "A.B.C.D" (T.pack . showPvp) mPreview
    <> " or --auto-version"
    <> maybe "" (const " (preview with --dry-run)") mPreview

-- | Apply a plan's changes: prepend the changelog section, write the
-- version, and remove the consumed fragment files.
applyPlan :: FilePath -> BatchPlan -> IO BatchResult
applyPlan baseDir plan = do
  let projectConfig = planProjectConfig plan
  prependSection (baseDir </> projectChangelog projectConfig) (planSection plan)
  writeVersion baseDir projectConfig (planVersion plan)
  forM_ (planFragmentPairs plan) $ \(file, _) -> removeFile $ baseDir </> file
  pure
    BatchResult
      { batchResultVersion = planVersion plan
      , batchResultPackage = planPackage plan
      , batchResultFragments = map fst $ planFragmentPairs plan
      , batchResultChangelog = baseDir </> projectChangelog projectConfig
      , batchResultVersionPath = versionFilePath baseDir projectConfig
      }

-- | Turn a plan into a dry-run report: classify each fragment's fate and
-- resolve the changelog path, without touching the filesystem.
toDryRunResult :: Config -> FilePath -> BatchPlan -> DryRunResult
toDryRunResult config baseDir plan =
  DryRunResult
    { dryRunPackage = planPackage plan
    , dryRunCurrentVersion = planCurrentVersion plan
    , dryRunVersion = planVersion plan
    , dryRunFragments = map toDryRunFragment $ planFragmentPairs plan
    , dryRunSection = planSection plan
    , dryRunChangelog = baseDir </> projectChangelog (planProjectConfig plan)
    }
 where
  toDryRunFragment (file, frag) =
    DryRunFragment
      { dryRunFragmentPath = file
      , dryRunFragmentKinds = fragmentKinds frag
      , dryRunFragmentFate = if isNotable config frag then Included else ExcludedNonNotable
      }

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
