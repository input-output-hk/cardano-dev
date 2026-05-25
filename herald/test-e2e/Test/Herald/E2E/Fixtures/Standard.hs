-- | Standard multi-project repo setups and configs for e2e tests.
module Test.Herald.E2E.Fixtures.Standard
  ( -- * Repo setup
    setupTestRepo
  , setupBatchRepo
  , setupDiffRepo
  , setupMultiDiffRepo
  , setupRootDiffRepo

    -- * Configs
  , testConfigDiffRepo
  , testConfigMultiDiffRepo
  , testConfigRootDiffRepo
  )
where

import Data.Map.Strict qualified as Map
import Data.Text.IO qualified as T
import Data.Yaml qualified as Yaml
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Test.Herald.E2E.Fixtures (commitAll, withFeatureBranch, withGitRepo)
import Test.Herald.Fixtures (testConfigMultiProject)

import Herald.Types (Config (..), Fragment (..), ProjectConfig (..), VersionSource (..))

-- | Temp directory with two projects, three fragment files, .cabal and CHANGELOG files.
-- No git repo -- just the filesystem layout.
setupTestRepo :: (FilePath -> IO a) -> IO a
setupTestRepo action = withSystemTempDirectory "herald-e2e" $ \tmpDir -> do
  let changesDir = tmpDir </> ".changes"
      cardanoApiDir = tmpDir </> "cardano-api"
      cardanoApiGenDir = tmpDir </> "cardano-api-gen"

  createDirectoryIfMissing True changesDir
  createDirectoryIfMissing True cardanoApiDir
  createDirectoryIfMissing True cardanoApiGenDir

  -- Fragment files
  Yaml.encodeFile
    (changesDir </> "42-fix-serialization.yml")
    Fragment
      { fragmentProject = "cardano-api"
      , fragmentKinds = ["bugfix"]
      , fragmentDescription = "Fix serialization of Conway certificates"
      , fragmentPR = 42
      }

  Yaml.encodeFile
    (changesDir </> "99-add-conway-support.yml")
    Fragment
      { fragmentProject = "cardano-api"
      , fragmentKinds = ["breaking", "feature"]
      , fragmentDescription = "Add Conway era support"
      , fragmentPR = 99
      }

  Yaml.encodeFile
    (changesDir </> "50-gen-helpers.yml")
    Fragment
      { fragmentProject = "cardano-api-gen"
      , fragmentKinds = ["test"]
      , fragmentDescription = "Add generator helpers"
      , fragmentPR = 50
      }

  -- .cabal files
  writeFile
    (cardanoApiDir </> "cardano-api.cabal")
    $ unlines
      [ "cabal-version: 3.0"
      , "name:          cardano-api"
      , "version:       8.4.1.2"
      , "synopsis:      Cardano API"
      , ""
      , "library"
      , "  build-depends: base"
      ]

  writeFile
    (cardanoApiGenDir </> "cardano-api-gen.cabal")
    $ unlines
      [ "cabal-version: 3.0"
      , "name:          cardano-api-gen"
      , "version:       1.0.0.0"
      , "synopsis:      Cardano API generators"
      , ""
      , "library"
      , "  build-depends: base"
      ]

  -- CHANGELOG.md files
  T.writeFile
    (cardanoApiDir </> "CHANGELOG.md")
    "## 8.4.1.2 -- 2026-01-15\n\n- Previous change\n  (bugfix)\n  [PR 10](https://github.com/IntersectMBO/cardano-api/pull/10)\n"

  T.writeFile
    (cardanoApiGenDir </> "CHANGELOG.md")
    "## 1.0.0.0 -- 2026-01-01\n\n- Initial release\n  (feature)\n  [PR 1](https://github.com/IntersectMBO/cardano-api/pull/1)\n"

  action tmpDir

-- | Same layout as setupTestRepo but inside an initialized git repo with an initial commit.
setupBatchRepo :: (FilePath -> IO a) -> IO a
setupBatchRepo action = withGitRepo "herald-batch" $ \tmpDir -> do
  let changesDir = tmpDir </> ".changes"
      cardanoApiDir = tmpDir </> "cardano-api"
      cardanoApiGenDir = tmpDir </> "cardano-api-gen"

  createDirectoryIfMissing True changesDir
  createDirectoryIfMissing True cardanoApiDir
  createDirectoryIfMissing True cardanoApiGenDir

  Yaml.encodeFile
    (changesDir </> "42-fix-serialization.yml")
    Fragment
      { fragmentProject = "cardano-api"
      , fragmentKinds = ["bugfix"]
      , fragmentDescription = "Fix serialization of Conway certificates"
      , fragmentPR = 42
      }
  Yaml.encodeFile
    (changesDir </> "99-add-conway-support.yml")
    Fragment
      { fragmentProject = "cardano-api"
      , fragmentKinds = ["breaking", "feature"]
      , fragmentDescription = "Add Conway era support"
      , fragmentPR = 99
      }
  Yaml.encodeFile
    (changesDir </> "50-gen-helpers.yml")
    Fragment
      { fragmentProject = "cardano-api-gen"
      , fragmentKinds = ["test"]
      , fragmentDescription = "Add generator helpers"
      , fragmentPR = 50
      }

  writeFile
    (cardanoApiDir </> "cardano-api.cabal")
    $ unlines
      [ "cabal-version: 3.0"
      , "name:          cardano-api"
      , "version:       8.4.1.2"
      , "synopsis:      Cardano API"
      , ""
      , "library"
      , "  build-depends: base"
      ]
  writeFile
    (cardanoApiGenDir </> "cardano-api-gen.cabal")
    $ unlines
      [ "cabal-version: 3.0"
      , "name:          cardano-api-gen"
      , "version:       1.0.0.0"
      , "synopsis:      Cardano API generators"
      , ""
      , "library"
      , "  build-depends: base"
      ]
  T.writeFile (cardanoApiDir </> "CHANGELOG.md") "## 8.4.1.2\n\n- Previous change\n"
  T.writeFile (cardanoApiGenDir </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial release\n"

  commitAll tmpDir "initial"
  action tmpDir

-- | Git repo with a single project (my-lib), committed on main, then switched to a feature branch.
setupDiffRepo :: (FilePath -> IO a) -> IO a
setupDiffRepo action = withGitRepo "herald-diff" $ \tmpDir -> do
  let pkgDir = tmpDir </> "my-lib"
  createDirectoryIfMissing True pkgDir
  writeFile
    (pkgDir </> "my-lib.cabal")
    "cabal-version: 3.0\nname: my-lib\nversion: 1.0.0.0\n"
  T.writeFile (pkgDir </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial\n"
  createDirectoryIfMissing True $ tmpDir </> ".changes"
  Yaml.encodeFile (tmpDir </> ".herald.yml") testConfigDiffRepo

  commitAll tmpDir "initial"
  withFeatureBranch tmpDir $ action tmpDir

-- | Git repo with two subprojects (lib-a, lib-b), committed on main, then switched to a feature branch.
setupMultiDiffRepo :: (FilePath -> IO a) -> IO a
setupMultiDiffRepo action = withGitRepo "herald-multi-diff" $ \tmpDir -> do
  let libA = tmpDir </> "lib-a"
      libB = tmpDir </> "lib-b"
  createDirectoryIfMissing True libA
  createDirectoryIfMissing True libB
  writeFile (libA </> "lib-a.cabal") "cabal-version: 3.0\nname: lib-a\nversion: 1.0.0.0\n"
  writeFile (libB </> "lib-b.cabal") "cabal-version: 3.0\nname: lib-b\nversion: 1.0.0.0\n"
  T.writeFile (libA </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial\n"
  T.writeFile (libB </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial\n"
  createDirectoryIfMissing True $ tmpDir </> ".changes"

  commitAll tmpDir "initial"
  withFeatureBranch tmpDir $ action tmpDir

-- | Git repo with a single root-level project (my-tool.cabal in root), on a feature branch.
setupRootDiffRepo :: (FilePath -> IO a) -> IO a
setupRootDiffRepo action = withGitRepo "herald-root-diff" $ \tmpDir -> do
  writeFile (tmpDir </> "my-tool.cabal") "cabal-version: 3.0\nname: my-tool\nversion: 1.0.0.0\n"
  T.writeFile (tmpDir </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial\n"
  createDirectoryIfMissing True $ tmpDir </> ".changes"

  commitAll tmpDir "initial"
  withFeatureBranch tmpDir $ action tmpDir

-------------------------------------------------------------------------------
-- Test configs
-------------------------------------------------------------------------------

-- | Config for the single-project diff test repo.
testConfigDiffRepo :: Config
testConfigDiffRepo =
  Config
    { configGitRepo = "https://github.com/test/repo"
    , configChangesDir = Just ".changes"
    , configKinds = configKinds testConfigMultiProject
    , configProjects =
        Map.fromList
          [
            ( "my-lib"
            , ProjectConfig
                { projectChangelog = "my-lib/CHANGELOG.md"
                , projectVersionSource = Just $ CabalFile "my-lib/my-lib.cabal"
                , projectChangesDir = Nothing
                }
            )
          ]
    }

-- | Config for the two-project diff test repo.
testConfigMultiDiffRepo :: Config
testConfigMultiDiffRepo =
  Config
    { configGitRepo = "https://github.com/test/repo"
    , configChangesDir = Just ".changes"
    , configKinds = configKinds testConfigMultiProject
    , configProjects =
        Map.fromList
          [
            ( "lib-a"
            , ProjectConfig
                { projectChangelog = "lib-a/CHANGELOG.md"
                , projectVersionSource = Just $ CabalFile "lib-a/lib-a.cabal"
                , projectChangesDir = Nothing
                }
            )
          ,
            ( "lib-b"
            , ProjectConfig
                { projectChangelog = "lib-b/CHANGELOG.md"
                , projectVersionSource = Just $ CabalFile "lib-b/lib-b.cabal"
                , projectChangesDir = Nothing
                }
            )
          ]
    }

-- | Config for the root-level single-project diff repo.
testConfigRootDiffRepo :: Config
testConfigRootDiffRepo =
  Config
    { configGitRepo = "https://github.com/test/repo"
    , configChangesDir = Just ".changes"
    , configKinds = configKinds testConfigMultiProject
    , configProjects =
        Map.fromList
          [
            ( "my-tool"
            , ProjectConfig
                { projectChangelog = "CHANGELOG.md"
                , projectVersionSource = Just $ CabalFile "my-tool.cabal"
                , projectChangesDir = Nothing
                }
            )
          ]
    }
