module Herald.Command.Next
  ( nextVersion
  )
where

import RIO

import Control.Monad.Trans.Maybe (MaybeT, hoistMaybe, runMaybeT)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import System.FilePath ((</>))

import Herald.Cabal (readCabalVersion)
import Herald.Command.Batch (computeMaxBump)
import Herald.Fragment (validateFragment)
import Herald.Fragment.Read (readProjectFragments)
import Herald.Pvp (Pvp, bumpPvp)
import Herald.Types (Config (..), ProjectConfig (..), VersionSource (..), throwHerald)
import Herald.VersionFile (readVersionFile)

-- | Compute the next version for a package based on unreleased fragments.
-- Validates all fragments first so that invalid fragments (unknown kinds, etc.)
-- cause a failure rather than being silently ignored by 'computeMaxBump'.
-- Fragment validation always runs, even when no version source is configured,
-- so the current-version lookup is read as a plain value ('Maybe') here rather
-- than short-circuiting immediately.
nextVersion :: MonadIO m => Config -> FilePath -> Text -> MaybeT m Pvp
nextVersion config baseDir package = do
  projectConfig <-
    maybe (throwHerald $ "Unknown project: " <> T.unpack package) pure
      . Map.lookup package
      $ configProjects config

  currentVersion <- lift . runMaybeT $ dispatchVersion projectConfig

  packagePairs <- readProjectFragments config baseDir package

  -- Validate fragments before computing the version, matching batchPackage behaviour
  let errors =
        concatMap
          (\(file, frag) -> map (\e -> T.pack file <> ": " <> e) $ validateFragment config frag)
          packagePairs
  unless (null errors)
    . throwHerald
    . T.unpack
    $ T.intercalate "\n" errors

  let packageFragments = map snd packagePairs

  cv <- hoistMaybe currentVersion
  guard . not $ null packageFragments
  let maxBump = computeMaxBump config packageFragments
  pure $ bumpPvp maxBump cv
 where
  dispatchVersion projectConfig = case projectVersionSource projectConfig of
    Just (CabalFile cabalFile) -> readCabalVersion $ baseDir </> cabalFile
    Just (VersionFile versionFile) -> lift $ readVersionFile (baseDir </> versionFile)
    Nothing -> hoistMaybe Nothing
