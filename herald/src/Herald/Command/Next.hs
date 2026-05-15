module Herald.Command.Next
  ( nextVersion
  )
where

import RIO

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
nextVersion :: Config -> FilePath -> Text -> IO (Maybe Pvp)
nextVersion config baseDir package = do
  projectConfig <-
    maybe (throwHerald $ "Unknown project: " <> T.unpack package) pure
      . Map.lookup package
      $ configProjects config

  currentVersion <- case projectVersionSource projectConfig of
    Just (CabalFile cabalFile) -> readCabalVersion $ baseDir </> cabalFile
    Just (VersionFile versionFile) -> Just <$> readVersionFile (baseDir </> versionFile)
    Nothing -> pure Nothing

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

  pure $ do
    cv <- currentVersion
    _ : _ <- Just packageFragments
    let maxBump = computeMaxBump config packageFragments
    Just $ bumpPvp maxBump cv
