module Herald.Command.Init
  ( initConfig
  )
where

import RIO

import Control.Applicative (empty)
import Control.Monad.Trans.Maybe (MaybeT (..), runMaybeT)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (dropExtension, takeExtension, (</>))

import Herald.Git (detectGitRepo)
import Herald.Pvp (showPvp)
import Herald.Types
  ( Config (..)
  , KindDef (..)
  , ProjectConfig (..)
  , VersionSource (..)
  , defaultKinds
  , throwHerald
  )

-- | Write text to a file with explicit UTF-8 encoding, avoiding locale issues.
writeUtf8 :: FilePath -> Text -> IO ()
writeUtf8 path = writeFileBinary path . encodeUtf8

-- | Generate a default herald config file by scanning the repository.
-- Discovers top-level directories (and root) as projects, then writes a commented YAML config.
initConfig :: FilePath -> FilePath -> IO FilePath
initConfig baseDir configPath = do
  exists <- doesFileExist configPath
  when exists
    . throwHerald
    $ configPath
    <> " already exists; refusing to overwrite"

  gitRepo <-
    detectGitRepo baseDir
      >>= maybe (throwHerald "Could not detect origin remote; set git-repo manually in .herald.yml") pure
  projects <- discoverProjects baseDir

  let config =
        Config
          { configGitRepo = gitRepo
          , configChangesDir = ".changes"
          , configKinds = defaultKinds
          , configProjects = projects
          }

  writeUtf8 configPath $ renderCommentedConfig config

  -- Create the changes directory with a template fragment
  let changesDir = baseDir </> configChangesDir config
      templatePath = changesDir </> "_TEMPLATE.yml"
  createDirectoryIfMissing True changesDir
  writeUtf8 templatePath renderTemplate

  pure configPath

-- | Render a Config as YAML with explanatory comments.
renderCommentedConfig :: Config -> Text
renderCommentedConfig config =
  T.unlines
    $ [ "# Herald configuration"
      , "# Changelog and release automation for PVP-versioned Haskell projects"
      , ""
      , "# Git repository URL (used for PR links in changelogs)"
      , "git-repo: " <> configGitRepo config
      , ""
      , "# Directory for changelog fragments, relative to repo root"
      , "# Fragments are YAML files created by 'herald new' and consumed by 'herald batch'"
      , "changes-dir: " <> T.pack (configChangesDir config)
      , ""
      , "# Change kinds and their properties"
      , "#"
      , "# Each kind defines:"
      , "#   notable: if true (default), changes of this kind appear in the changelog"
      , "#           if false, they still bump the version but are omitted from the changelog text"
      , "#   bump:    PVP version component to bump when this kind is present"
      , "#           0.1.0.0 = bump 2nd component (breaking changes)"
      , "#           0.0.1.0 = bump 3rd component (features, compatible changes)"
      , "#           0.0.0.1 = bump 4th component (patches, internal changes)"
      , "#"
      , "# The highest bump across all fragment kinds determines the final version bump."
      , "kinds:"
      ]
    <> renderKinds (configKinds config)
    <> [ ""
       , "# Projects in this repository"
       , "#"
       , "# Each project needs:"
       , "#   changelog:  path to the project's CHANGELOG.md (relative to repo root)"
       , "#   cabal-file:   (optional) path to the project's .cabal file (version is read/updated here)"
       , "#   version-file: (optional) path to a plain-text version file (alternative to cabal-file)"
       , "projects:"
       ]
    <> renderProjects (configProjects config)

renderKinds :: Map Text KindDef -> [Text]
renderKinds = concatMap renderKind . Map.toAscList
 where
  renderKind (name, kd) =
    ["  " <> name <> ":"]
      <> ["    notable: false" | not $ kindNotable kd]
      <> ["    bump: " <> T.pack (showPvp $ kindBump kd)]
      <> maybe [] (\d -> ["    description: " <> d]) (kindDescription kd)

renderProjects :: Map Text ProjectConfig -> [Text]
renderProjects = concatMap renderProject . Map.toAscList
 where
  renderProject (name, projectConfig) =
    [ "  " <> name <> ":"
    , "    changelog: " <> T.pack (projectChangelog projectConfig)
    ]
      <> case projectVersionSource projectConfig of
        Just (CabalFile cabalFile) -> ["    cabal-file: " <> T.pack cabalFile]
        Just (VersionFile versionFile) -> ["    version-file: " <> T.pack versionFile]
        Nothing -> []

-- | Render a template changelog fragment with example values.
renderTemplate :: Text
renderTemplate =
  T.unlines
    [ "# Changelog fragment template - copy this file and fill in the fields."
    , "# Or use 'herald new' for interactive creation."
    , "#"
    , "# Files starting with _ are ignored by herald."
    , "#"
    , "# Available projects and kinds are defined in .herald.yml"
    , ""
    , "# Which project this change belongs to (see 'projects' in .herald.yml)"
    , "project: my-project"
    , "# Pull request number associated with this change"
    , "pr: 0"
    , "# One or more change kinds (see 'kinds' in .herald.yml)"
    , "kind:"
    , "  - bugfix"
    , "description: |"
    , "  Describe your change here."
    ]

-- | Scan the base directory for projects.
-- Checks the root directory first (single-project repo), then all top-level subdirectories.
-- Hidden directories (starting with @.@) are excluded.
discoverProjects :: FilePath -> IO (Map Text ProjectConfig)
discoverProjects baseDir = do
  rootProject <- probeRootProject baseDir
  maybe discoverSubProjects (pure . Map.fromList . pure) rootProject
 where
  discoverSubProjects = do
    entries <- filter (not . isHidden) <$> listDirectory baseDir
    subProjects <- catMaybes <$> traverse (probeSubProject baseDir) entries
    pure $ Map.fromList subProjects
  isHidden ('.' : _) = True
  isHidden _ = False

-- | Check if the root directory itself is a single project (has exactly one .cabal file).
probeRootProject :: FilePath -> IO (Maybe (Text, ProjectConfig))
probeRootProject baseDir = do
  cabalFile <- findSingleCabalFile baseDir
  pure $ do
    cf <- cabalFile
    let name = T.pack $ dropExtension cf
    guard $ not $ T.null name
    Just
      ( name
      , ProjectConfig
          { projectChangelog = "CHANGELOG.md"
          , projectVersionSource = Just $ CabalFile cf
          }
      )

-- | Probe a subdirectory as a project.
-- All non-hidden directories are treated as projects. A .cabal file is detected if present.
probeSubProject :: FilePath -> FilePath -> IO (Maybe (Text, ProjectConfig))
probeSubProject baseDir entry = runMaybeT $ do
  guard =<< liftIO (doesDirectoryExist $ baseDir </> entry)
  cabalFile <- liftIO . findSingleCabalFile $ baseDir </> entry
  let name = maybe (T.pack entry) (T.pack . dropExtension) cabalFile
  guard . not $ T.null name
  let versionSource = case cabalFile of
        Just cf -> Just . CabalFile $ entry </> cf
        Nothing -> Just . VersionFile $ entry </> "version.txt"
  pure
    ( name
    , ProjectConfig
        { projectChangelog = entry </> "CHANGELOG.md"
        , projectVersionSource = versionSource
        }
    )

-- | Find exactly one @.cabal@ file in a directory. Returns 'Nothing' if zero or multiple.
findSingleCabalFile :: FilePath -> IO (Maybe FilePath)
findSingleCabalFile dir = runMaybeT $ do
  guard =<< liftIO (doesDirectoryExist dir)
  files <- filter ((== ".cabal") . takeExtension) <$> liftIO (listDirectory dir)
  case files of
    [f] | not . null $ dropExtension f -> pure f
    _ -> empty
