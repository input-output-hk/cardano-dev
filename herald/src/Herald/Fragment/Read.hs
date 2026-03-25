-- | Reading changelog fragment files from the changes directory.
--
-- Shared by "Herald.Command.Batch", "Herald.Command.Next", and the CLI.
module Herald.Fragment.Read
  ( readAllFragments
  , readProjectFragments
  , discoverFragmentPaths
  )
where

import RIO

import Data.List (sort)
import Data.Yaml qualified as Yaml
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, takeFileName, (</>))

import Herald.Types (Config (..), Fragment (..), throwHerald)

-- | Read all fragment YAML files from the changes directory.
-- Returns @(filename, fragment)@ pairs where filename is relative to the
-- changes directory.
readAllFragments :: Config -> FilePath -> IO [(FilePath, Fragment)]
readAllFragments config baseDir = do
  let changesDir = baseDir </> configChangesDir config
  files <- discoverFragmentFiles changesDir
  forM files $ \f -> do
    frag <-
      either (\err -> throwHerald $ f <> ": " <> Yaml.prettyPrintParseException err) pure
        =<< Yaml.decodeFileEither (changesDir </> f)
    pure (f, frag)

-- | Read fragments belonging to a specific project.
readProjectFragments :: Config -> FilePath -> Text -> IO [(FilePath, Fragment)]
readProjectFragments config baseDir package =
  filter (\(_, frag) -> fragmentProject frag == package)
    <$> readAllFragments config baseDir

-- | List full paths to all @.yml@ fragment files (for validation).
discoverFragmentPaths :: Config -> FilePath -> IO [FilePath]
discoverFragmentPaths config baseDir = do
  let changesDir = baseDir </> configChangesDir config
  files <- discoverFragmentFiles changesDir
  pure [changesDir </> f | f <- files]

-- | List @.yml@/@.yaml@ filenames in a directory (relative, sorted).
-- Files starting with @_@ are skipped (used for templates).
discoverFragmentFiles :: FilePath -> IO [FilePath]
discoverFragmentFiles dir = do
  exists <- doesDirectoryExist dir
  if exists
    then sort . filter isFragment <$> listDirectory dir
    else pure []
 where
  isFragment f = takeExtension f `elem` [".yml", ".yaml"] && not (isTemplate f)
  isTemplate f = case takeFileName f of
    '_' : _ -> True
    _ -> False
