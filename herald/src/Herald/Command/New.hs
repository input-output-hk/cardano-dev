module Herald.Command.New
  ( NewOptions (..)
  , createFragment
  , interactiveNew
  )
where

import RIO

import Data.Char (isAlphaNum)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import Data.Yaml qualified as Yaml
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

import Herald.Fragment (validateFragment)
import Herald.Fragment.Read (readProjectFragments)
import Herald.Git (currentBranch, userNick)
import Herald.Terminal (promptInt, promptMultiLine, promptMultiSelect)
import Herald.Types (Config (..), Fragment (..), KindDef (..), throwHerald)

data NewOptions = NewOptions
  { newProject :: !Text
  , newKinds :: ![Text]
  , newDescription :: !Text
  , newPR :: !Int
  }
  deriving (Eq, Show)

-- | Create a new changelog fragment file.
-- Uses scriv-style naming: @{YYYYMMDD_HHMMSS}_{user}_{branch}.yml@.
-- Empty components (no user, no branch) are dropped.
createFragment :: Config -> FilePath -> NewOptions -> IO FilePath
createFragment config baseDir opts = do
  let frag = Fragment (newProject opts) (newKinds opts) (newDescription opts) (newPR opts)
      errors = validateFragment config frag
  unless (null errors)
    . throwHerald
    $ "Invalid fragment: "
    <> T.unpack (T.intercalate ", " errors)

  -- Check for existing fragment with same PR and project
  existing <- readProjectFragments config baseDir (newProject opts)
  case filter (\(_, f) -> fragmentPR f == newPR opts) existing of
    (path, _) : _ ->
      throwHerald
        $ "A fragment for PR "
        <> show (newPR opts)
        <> " already exists: "
        <> configChangesDir config
        <> "/"
        <> path
        <> " -- update that file instead"
    [] -> pure ()

  filename <- generateFilename $ newProject opts
  let outDir = baseDir </> configChangesDir config
      outPath = outDir </> filename

  createDirectoryIfMissing True outDir
  Yaml.encodeFile outPath frag
  pure outPath

-- | Interactive mode: prompt the user for all fragment fields.
-- Returns one 'NewOptions' per selected project.
interactiveNew :: Config -> IO [NewOptions]
interactiveNew config = do
  let projectNames = sort . Map.keys $ configProjects config
      kindPairs = Map.toAscList $ configKinds config
      formatKind (name, kd) = case kindDescription kd of
        Just desc -> T.unpack name <> " - " <> T.unpack desc
        Nothing -> T.unpack name

  projects <- promptMultiSelect "project" projectNames T.unpack
  TIO.hPutStrLn stdout $ "  Selected: " <> T.intercalate ", " projects

  kinds <- map fst <$> promptMultiSelect "kind" kindPairs formatKind
  TIO.hPutStrLn stdout $ "  Selected: " <> T.intercalate ", " kinds

  description <- promptMultiLine "Description"
  prNumber <- promptInt "PR number"

  pure [NewOptions p kinds description prNumber | p <- projects]

-------------------------------------------------------------------------------
-- Filename generation
-------------------------------------------------------------------------------

-- | Generate a scriv-style filename: @{timestamp}_{project}_{user}_{branch}.yml@.
-- Empty components are dropped so the name stays clean.
generateFilename :: Text -> IO FilePath
generateFilename project = do
  now <- getCurrentTime
  let timestamp = formatTime defaultTimeLocale "%Y%m%d_%H%M%S" now
      projectSlug = sanitise $ T.unpack project
  nick <- userNick
  branch <- currentBranch
  let parts = filter (not . null) [timestamp, projectSlug, nick, branch]
  pure $ joinWith "_" parts <> ".yml"
 where
  sanitise = map (\c -> if isAlphaNum c || c == '_' || c == '-' then c else '_')
  joinWith _ [] = ""
  joinWith _ [x] = x
  joinWith sep (x : xs) = x <> sep <> joinWith sep xs
