-- | Reading changelog fragment files from the changes directory.
--
-- Shared by "Herald.Command.Batch", "Herald.Command.Next", and the CLI.
module Herald.Fragment.Read
  ( readAllFragments
  , readProjectFragments
  , discoverFragmentPaths
  , injectProject
  )
where

import RIO

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (parseEither)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Yaml qualified as Yaml
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, takeFileName, (</>))

import Herald.Types (Config (..), Fragment (..), ProjectConfig (..), allChangesDirs, throwHerald)

-- | Read all fragment YAML files from all changes directories.
-- Returns @(path, fragment)@ pairs where path is relative to the base
-- directory (e.g. @.changes\/42-fix.yml@ or @cardano-api\/.changes\/42-fix.yml@).
readAllFragments :: Config -> FilePath -> IO [(FilePath, Fragment)]
readAllFragments config baseDir = do
  globalFrags <- case configChangesDir config of
    Just dir -> readFragmentsFromDir baseDir dir Nothing
    Nothing -> pure []
  perProjectFrags <- fmap concat . forM (Map.toList $ configProjects config) $ \(projectName, pc) ->
    case projectChangesDir pc of
      Just dir -> readFragmentsFromDir baseDir dir (Just projectName)
      Nothing -> pure []
  pure $ globalFrags <> perProjectFrags

-- | Read fragments belonging to a specific project.
readProjectFragments :: Config -> FilePath -> Text -> IO [(FilePath, Fragment)]
readProjectFragments config baseDir package =
  filter (\(_, frag) -> fragmentProject frag == package)
    <$> readAllFragments config baseDir

-- | List paths to all @.yml@ fragment files, relative to the repo root (for validation).
discoverFragmentPaths :: Config -> FilePath -> IO [FilePath]
discoverFragmentPaths config baseDir = do
  let dirs = allChangesDirs config
  fmap concat . forM dirs $ \dir -> do
    let absDir = baseDir </> dir
    files <- discoverFragmentFiles absDir
    pure [dir </> f | f <- files]

-- | Read fragments from a single directory, optionally inferring the project
-- from the directory when the @project@ field is absent.
readFragmentsFromDir :: FilePath -> FilePath -> Maybe Text -> IO [(FilePath, Fragment)]
readFragmentsFromDir baseDir changesDir mProjectName = do
  let absDir = baseDir </> changesDir
  files <- discoverFragmentFiles absDir
  forM files $ \f -> do
    let absPath = absDir </> f
    value <-
      either (\err -> throwHerald $ changesDir </> f <> ": " <> Yaml.prettyPrintParseException err) pure
        =<< Yaml.decodeFileEither absPath
    let value' = maybe value (`injectProject` value) mProjectName
    frag <- case parseEither Aeson.parseJSON value' of
      Left err -> throwHerald $ changesDir </> f <> ": " <> err
      Right fragment -> pure fragment
    pure (changesDir </> f, frag)

-- | Inject a @project@ key into a YAML value if it is absent.
injectProject :: Text -> Aeson.Value -> Aeson.Value
injectProject projectName (Aeson.Object o)
  | KeyMap.member (Key.fromText "project") o = Aeson.Object o
  | otherwise = Aeson.Object $ KeyMap.insert (Key.fromText "project") (Aeson.String projectName) o
injectProject _ v = v

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
