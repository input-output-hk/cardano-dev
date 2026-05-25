module Herald.Command.Validate
  ( validateFiles
  , validateDiff
  , validatePR
  )
where

import RIO

import Data.Aeson qualified as Aeson
import Data.Aeson.Types (parseEither)
import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Yaml qualified as Yaml
import System.FilePath (takeDirectory, takeExtension, takeFileName, (</>))

import Herald.Fragment (validateDirConsistency, validateFragment)
import Herald.Fragment.Read (injectProject)
import Herald.Git (addedFiles, changedFiles, findForkPoint)
import Herald.Types (Config (..), Fragment (..), ProjectConfig (..), allChangesDirs, findDirProject)

-- | Validate a list of fragment files against the config.
-- Paths are relative to @baseDir@.
-- Returns a list of error messages. Empty list means all valid.
validateFiles :: Config -> FilePath -> [FilePath] -> IO [Text]
validateFiles config baseDir paths = do
  results <- forM paths $ \relPath -> do
    let fullPath = baseDir </> relPath
        prefix e = T.pack relPath <> ": " <> e
        mDirProject = findDirProject config relPath
    result <- parseFragmentWithInference fullPath mDirProject
    pure $ case result of
      Left err -> [prefix $ T.pack err]
      Right frag ->
        let contentErrors = validateFragment config frag
            dirErrors = maybe [] (\dp -> validateDirConsistency config dp frag) mDirProject
         in map prefix $ contentErrors <> dirErrors
  pure $ concat results

-- | Check that every project with files changed since the fork point has at
-- least one *new* changelog fragment (created in the diff).  Pre-existing
-- fragments committed before the fork point do not count.
validateDiff :: Config -> FilePath -> IO [Text]
validateDiff config baseDir = do
  forkPoint <- findForkPoint baseDir
  case forkPoint of
    Nothing ->
      pure ["Could not determine fork point - is this branch tracking a remote?"]
    Just base -> do
      changed <- changedFiles baseDir base
      added <- addedFiles baseDir base
      let changesPrefixes = allChangesDirs config
          newFragmentPaths = filter (isNewFragment changesPrefixes) added
      newFragments <- forM newFragmentPaths $ \path -> do
        let fullPath = baseDir </> path
            mDirProject = findDirProject config path
        result <- parseFragmentWithInference fullPath mDirProject
        pure $ case result of
          Left _ -> Nothing
          Right frag -> case mDirProject of
            Nothing -> Just frag
            Just dirProject
              | null (validateDirConsistency config dirProject frag) -> Just frag
              | otherwise -> Nothing
      let fragmentProjects =
            Set.fromList . map fragmentProject $ catMaybes newFragments
      pure
        . mapMaybe (checkProject changesPrefixes changed fragmentProjects)
        . Map.toList
        $ configProjects config

-- | Check a single project: if any of its files were changed, it must have
-- a fragment.
checkProject
  :: [FilePath]
  -> [FilePath]
  -> Set.Set Text
  -> (Text, ProjectConfig)
  -> Maybe Text
checkProject changesPrefixes changed fragmentProjects (projectName, projectConfig) =
  let projectDir = takeDirectory $ projectChangelog projectConfig
      modified = filter (fileInProject changesPrefixes projectDir) changed
   in if null modified || Set.member projectName fragmentProjects
        then Nothing
        else
          Just
            $ "Project "
            <> projectName
            <> " has modified files but no changelog fragment.\n"
            <> "  Run: herald new"

-- | Check whether a file belongs to a project directory.
-- Excludes files in any changes directory (fragments shouldn't trigger
-- themselves).
fileInProject :: [FilePath] -> FilePath -> FilePath -> Bool
fileInProject changesDirs _ file
  | any (\d -> (d <> "/") `isPrefixOf` file) changesDirs = False
fileInProject _ "." _ = True
fileInProject _ projectDir file =
  (projectDir <> "/") `isPrefixOf` file

-- | Check that new changelog fragments on this branch have the expected PR number.
-- Finds fragment files added since the fork point and verifies each one's PR field.
validatePR :: Config -> FilePath -> Int -> IO [Text]
validatePR config baseDir expectedPR = do
  forkPoint <- findForkPoint baseDir
  case forkPoint of
    Nothing ->
      pure ["Could not determine fork point - is this branch tracking a remote?"]
    Just base -> do
      added <- addedFiles baseDir base
      let changesPrefixes = allChangesDirs config
          newFragments = filter (isNewFragment changesPrefixes) added
      results <- forM newFragments $ \path -> do
        let fullPath = baseDir </> path
            mDirProject = findDirProject config path
        result <- parseFragmentWithInference fullPath mDirProject
        pure $ case result of
          Left err ->
            [T.pack path <> ": " <> T.pack err]
          Right frag
            | fragmentPR frag /= expectedPR ->
                [ T.pack path
                    <> ": PR number "
                    <> T.pack (show $ fragmentPR frag)
                    <> " does not match expected "
                    <> T.pack (show expectedPR)
                ]
            | otherwise -> []
      pure $ concat results

-- | Check whether a path is a new changelog fragment file in any of the
-- changes directories. Template files (starting with @_@) are excluded.
isNewFragment :: [FilePath] -> FilePath -> Bool
isNewFragment prefixes path =
  any (\prefix -> (prefix <> "/") `isPrefixOf` path) prefixes
    && takeExtension path
    `elem` [".yml", ".yaml"]
    && not ("_" `isPrefixOf` takeFileName path)

-- | Parse a fragment file, injecting the project field from the directory
-- if the file is in a per-project changes-dir and lacks a project field.
parseFragmentWithInference :: FilePath -> Maybe Text -> IO (Either String Fragment)
parseFragmentWithInference fullPath mDirProject = do
  result <- Yaml.decodeFileEither @Aeson.Value fullPath
  pure $ do
    value <- first Yaml.prettyPrintParseException result
    let value' = maybe value (`injectProject` value) mDirProject
    parseEither Aeson.parseJSON value'
