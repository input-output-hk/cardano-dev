-- | Version-file project setups and configs for e2e tests.
module Test.Herald.E2E.Fixtures.VersionFile
  ( -- * Repo setup
    setupVersionFileRepo
  , setupVersionFileBatchRepo

    -- * Configs
  , testConfigVersionFile
  )
where

import Data.Map.Strict qualified as Map
import Data.Text.IO qualified as T
import Data.Yaml qualified as Yaml
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Test.Herald.E2E.Fixtures (commitAll, withGitRepo)
import Test.Herald.Fixtures (testConfigMultiProject)

import Herald.Types (Config (..), Fragment (..), ProjectConfig (..), VersionSource (..))

-- | Config for a version-file based project (no .cabal file).
testConfigVersionFile :: Config
testConfigVersionFile =
  Config
    { configGitRepo = "https://github.com/test/repo"
    , configChangesDir = Just ".changes"
    , configKinds = configKinds testConfigMultiProject
    , configProjects =
        Map.fromList
          [
            ( "my-action"
            , ProjectConfig
                { projectChangelog = "my-action/CHANGELOG.md"
                , projectVersionSource = Just $ VersionFile "my-action/version.txt"
                , projectChangesDir = Nothing
                }
            )
          ]
    }

-- | Temp directory with a version-file project, fragment, and CHANGELOG. No git.
setupVersionFileRepo :: (FilePath -> IO a) -> IO a
setupVersionFileRepo action = withSystemTempDirectory "herald-vf-e2e" $ \tmpDir -> do
  let changesDir = tmpDir </> ".changes"
      actionDir = tmpDir </> "my-action"

  createDirectoryIfMissing True changesDir
  createDirectoryIfMissing True actionDir

  Yaml.encodeFile
    (changesDir </> "10-add-cache.yml")
    Fragment
      { fragmentProject = "my-action"
      , fragmentKinds = ["feature"]
      , fragmentDescription = "Add dependency caching"
      , fragmentPR = 10
      }

  writeFile (actionDir </> "version.txt") "1.0.0.0\n"

  T.writeFile
    (actionDir </> "CHANGELOG.md")
    "## 1.0.0.0 -- 2026-01-01\n\n- Initial release\n  (feature)\n  [PR 1](https://github.com/test/repo/pull/1)\n"

  action tmpDir

-- | Same as setupVersionFileRepo but inside a git repo with an initial commit.
setupVersionFileBatchRepo :: (FilePath -> IO a) -> IO a
setupVersionFileBatchRepo action = withGitRepo "herald-vf-batch" $ \tmpDir -> do
  let changesDir = tmpDir </> ".changes"
      actionDir = tmpDir </> "my-action"

  createDirectoryIfMissing True changesDir
  createDirectoryIfMissing True actionDir

  Yaml.encodeFile
    (changesDir </> "10-add-cache.yml")
    Fragment
      { fragmentProject = "my-action"
      , fragmentKinds = ["feature"]
      , fragmentDescription = "Add dependency caching"
      , fragmentPR = 10
      }

  writeFile (actionDir </> "version.txt") "1.0.0.0\n"
  T.writeFile (actionDir </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial release\n"

  commitAll tmpDir "initial"
  action tmpDir
