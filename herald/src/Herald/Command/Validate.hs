module Herald.Command.Validate
  ( validateFiles
  , validateDiff
  , validatePR
  )
where

import RIO

import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Yaml qualified as Yaml
import System.FilePath (takeDirectory, takeExtension, takeFileName, (</>))

import Herald.Fragment (validateFragment)
import Herald.Git (addedFiles, changedFiles, findForkPoint)
import Herald.Types (Config (..), Fragment (..), ProjectConfig (..))

-- | Validate a list of fragment files against the config.
-- Returns a list of error messages. Empty list means all valid.
validateFiles :: Config -> [FilePath] -> IO [Text]
validateFiles config paths = do
  results <- forM paths $ \path -> do
    let prefix e = T.pack path <> ": " <> e
    result <- Yaml.decodeFileEither path
    pure $ case result of
      Left err -> [prefix . T.pack $ Yaml.prettyPrintParseException err]
      Right (frag :: Fragment) -> map prefix $ validateFragment config frag
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
      let changesPrefix = configChangesDir config
          newFragmentPaths = filter (isNewFragment changesPrefix) added
      newFragments <- forM newFragmentPaths $ \path -> do
        let fullPath = baseDir </> path
        result <- Yaml.decodeFileEither fullPath
        pure $ case result of
          Left _ -> Nothing
          Right (frag :: Fragment) -> Just frag
      let fragmentProjects =
            Set.fromList . map fragmentProject $ catMaybes newFragments
      pure
        . mapMaybe (checkProject changesPrefix changed fragmentProjects)
        . Map.toList
        $ configProjects config

-- | Check a single project: if any of its files were changed, it must have
-- a fragment.
checkProject
  :: FilePath
  -> [FilePath]
  -> Set.Set Text
  -> (Text, ProjectConfig)
  -> Maybe Text
checkProject changesPrefix changed fragmentProjects (projectName, projectConfig) =
  let projectDir = takeDirectory $ projectChangelog projectConfig
      modified = filter (fileInProject changesPrefix projectDir) changed
   in if null modified || Set.member projectName fragmentProjects
        then Nothing
        else
          Just
            $ "Project "
            <> projectName
            <> " has modified files but no changelog fragment.\n"
            <> "  Copy "
            <> T.pack changesPrefix
            <> "/_TEMPLATE.yml to "
            <> T.pack changesPrefix
            <> "/<your-fragment>.yml and fill it in,\n"
            <> "  or run: herald new"

-- | Check whether a file belongs to a project directory.
-- Excludes files in the changes directory (fragments shouldn't trigger
-- themselves).
fileInProject :: FilePath -> FilePath -> FilePath -> Bool
fileInProject changesDir _ file
  | (changesDir <> "/") `isPrefixOf` file = False
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
      let changesPrefix = configChangesDir config
          newFragments = filter (isNewFragment changesPrefix) added
      results <- forM newFragments $ \path -> do
        let fullPath = baseDir </> path
        result <- Yaml.decodeFileEither fullPath
        pure $ case result of
          Left err ->
            [T.pack path <> ": " <> T.pack (Yaml.prettyPrintParseException err)]
          Right (frag :: Fragment)
            | fragmentPR frag /= expectedPR ->
                [ T.pack path
                    <> ": PR number "
                    <> T.pack (show $ fragmentPR frag)
                    <> " does not match expected "
                    <> T.pack (show expectedPR)
                ]
            | otherwise -> []
      pure $ concat results

-- | Check whether a path is a new changelog fragment file in the changes
-- directory.  Template files (starting with @_@) are excluded.
isNewFragment :: FilePath -> FilePath -> Bool
isNewFragment prefix path =
  (prefix <> "/")
    `isPrefixOf` path
    && takeExtension path
    `elem` [".yml", ".yaml"]
    && not ("_" `isPrefixOf` takeFileName path)
