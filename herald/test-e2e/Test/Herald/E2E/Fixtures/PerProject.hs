-- | Per-project changes-dir setups and configs for e2e tests.
module Test.Herald.E2E.Fixtures.PerProject
  ( -- * Repo setup
    setupPerProjectRepo
  , setupPerProjectBatchRepo
  , setupPerProjectDiffRepo
  , setupPerProjectNoGlobalRepo

    -- * Configs
  , testConfigPerProject
  , testConfigPerProjectNoGlobal
  , testConfigPerProjectDiff
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

-- | Config with per-project changes-dir for one project, global for the other.
testConfigPerProject :: Config
testConfigPerProject =
  Config
    { configGitRepo = "https://github.com/test/repo"
    , configChangesDir = Just ".changes"
    , configKinds = configKinds testConfigMultiProject
    , configProjects =
        Map.fromList
          [
            ( "cardano-api"
            , ProjectConfig
                { projectChangelog = "cardano-api/CHANGELOG.md"
                , projectVersionSource = Just $ CabalFile "cardano-api/cardano-api.cabal"
                , projectChangesDir = Just "cardano-api/.changes"
                }
            )
          ,
            ( "cardano-api-gen"
            , ProjectConfig
                { projectChangelog = "cardano-api-gen/CHANGELOG.md"
                , projectVersionSource = Just $ CabalFile "cardano-api-gen/cardano-api-gen.cabal"
                , projectChangesDir = Nothing
                }
            )
          ]
    }

-- | Config where every project has its own changes-dir and no global dir.
testConfigPerProjectNoGlobal :: Config
testConfigPerProjectNoGlobal =
  Config
    { configGitRepo = "https://github.com/test/repo"
    , configChangesDir = Nothing
    , configKinds = configKinds testConfigMultiProject
    , configProjects =
        Map.fromList
          [
            ( "lib-a"
            , ProjectConfig
                { projectChangelog = "lib-a/CHANGELOG.md"
                , projectVersionSource = Just $ CabalFile "lib-a/lib-a.cabal"
                , projectChangesDir = Just "lib-a/.changes"
                }
            )
          ,
            ( "lib-b"
            , ProjectConfig
                { projectChangelog = "lib-b/CHANGELOG.md"
                , projectVersionSource = Just $ CabalFile "lib-b/lib-b.cabal"
                , projectChangesDir = Just "lib-b/.changes"
                }
            )
          ]
    }

-- | Config for diff testing with per-project changes-dir.
testConfigPerProjectDiff :: Config
testConfigPerProjectDiff =
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
                , projectChangesDir = Just "lib-a/.changes"
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

-- | Two-project repo where cardano-api has a per-project changes-dir and
-- cardano-api-gen uses the global one. Fragments exist in both locations.
setupPerProjectRepo :: (FilePath -> IO a) -> IO a
setupPerProjectRepo action = withSystemTempDirectory "herald-per-proj" $ \tmpDir -> do
  let globalChanges = tmpDir </> ".changes"
      perProjectChanges = tmpDir </> "cardano-api" </> ".changes"
      cardanoApiDir = tmpDir </> "cardano-api"
      cardanoApiGenDir = tmpDir </> "cardano-api-gen"

  createDirectoryIfMissing True globalChanges
  createDirectoryIfMissing True perProjectChanges
  createDirectoryIfMissing True cardanoApiDir
  createDirectoryIfMissing True cardanoApiGenDir

  -- Fragment in per-project dir (no project: field needed)
  Yaml.encodeFile
    (perProjectChanges </> "42-fix-serialization.yml")
    Fragment
      { fragmentProject = "cardano-api"
      , fragmentKinds = ["bugfix"]
      , fragmentDescription = "Fix serialization of Conway certificates"
      , fragmentPR = 42
      }

  -- Fragment in global dir for cardano-api (has project: field)
  Yaml.encodeFile
    (globalChanges </> "99-add-conway-support.yml")
    Fragment
      { fragmentProject = "cardano-api"
      , fragmentKinds = ["breaking", "feature"]
      , fragmentDescription = "Add Conway era support"
      , fragmentPR = 99
      }

  -- Fragment in global dir for cardano-api-gen
  Yaml.encodeFile
    (globalChanges </> "50-gen-helpers.yml")
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
      , ""
      , "library"
      , "  build-depends: base"
      ]

  T.writeFile (cardanoApiDir </> "CHANGELOG.md") "## 8.4.1.2\n\n- Previous change\n"
  T.writeFile (cardanoApiGenDir </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial release\n"

  action tmpDir

-- | Same as setupPerProjectRepo but inside a git repo with an initial commit.
setupPerProjectBatchRepo :: (FilePath -> IO a) -> IO a
setupPerProjectBatchRepo action = withGitRepo "herald-per-proj-batch" $ \tmpDir -> do
  let globalChanges = tmpDir </> ".changes"
      perProjectChanges = tmpDir </> "cardano-api" </> ".changes"
      cardanoApiDir = tmpDir </> "cardano-api"
      cardanoApiGenDir = tmpDir </> "cardano-api-gen"

  createDirectoryIfMissing True globalChanges
  createDirectoryIfMissing True perProjectChanges
  createDirectoryIfMissing True cardanoApiDir
  createDirectoryIfMissing True cardanoApiGenDir

  Yaml.encodeFile
    (perProjectChanges </> "42-fix-serialization.yml")
    Fragment
      { fragmentProject = "cardano-api"
      , fragmentKinds = ["bugfix"]
      , fragmentDescription = "Fix serialization of Conway certificates"
      , fragmentPR = 42
      }
  Yaml.encodeFile
    (globalChanges </> "99-add-conway-support.yml")
    Fragment
      { fragmentProject = "cardano-api"
      , fragmentKinds = ["breaking", "feature"]
      , fragmentDescription = "Add Conway era support"
      , fragmentPR = 99
      }
  Yaml.encodeFile
    (globalChanges </> "50-gen-helpers.yml")
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
      , ""
      , "library"
      , "  build-depends: base"
      ]

  T.writeFile (cardanoApiDir </> "CHANGELOG.md") "## 8.4.1.2\n\n- Previous change\n"
  T.writeFile (cardanoApiGenDir </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial release\n"

  commitAll tmpDir "initial"
  action tmpDir

-- | Git repo with per-project changes-dir, on a feature branch.
setupPerProjectDiffRepo :: (FilePath -> IO a) -> IO a
setupPerProjectDiffRepo action = withGitRepo "herald-per-proj-diff" $ \tmpDir -> do
  let libA = tmpDir </> "lib-a"
      libB = tmpDir </> "lib-b"
      libAChanges = tmpDir </> "lib-a" </> ".changes"
  createDirectoryIfMissing True libA
  createDirectoryIfMissing True libB
  createDirectoryIfMissing True libAChanges
  createDirectoryIfMissing True $ tmpDir </> ".changes"
  writeFile (libA </> "lib-a.cabal") "cabal-version: 3.0\nname: lib-a\nversion: 1.0.0.0\n"
  writeFile (libB </> "lib-b.cabal") "cabal-version: 3.0\nname: lib-b\nversion: 1.0.0.0\n"
  T.writeFile (libA </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial\n"
  T.writeFile (libB </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial\n"

  commitAll tmpDir "initial"
  withFeatureBranch tmpDir $ action tmpDir

-- | Two-project repo with no global changes-dir; each project has its own.
setupPerProjectNoGlobalRepo :: (FilePath -> IO a) -> IO a
setupPerProjectNoGlobalRepo action = withSystemTempDirectory "herald-no-global" $ \tmpDir -> do
  let libADir = tmpDir </> "lib-a"
      libBDir = tmpDir </> "lib-b"
      libAChanges = tmpDir </> "lib-a" </> ".changes"
      libBChanges = tmpDir </> "lib-b" </> ".changes"

  createDirectoryIfMissing True libAChanges
  createDirectoryIfMissing True libBChanges

  Yaml.encodeFile
    (libAChanges </> "10-feature.yml")
    Fragment
      { fragmentProject = "lib-a"
      , fragmentKinds = ["feature"]
      , fragmentDescription = "New feature"
      , fragmentPR = 10
      }

  Yaml.encodeFile
    (libBChanges </> "20-bugfix.yml")
    Fragment
      { fragmentProject = "lib-b"
      , fragmentKinds = ["bugfix"]
      , fragmentDescription = "Fix bug"
      , fragmentPR = 20
      }

  writeFile (libADir </> "lib-a.cabal") "cabal-version: 3.0\nname: lib-a\nversion: 1.0.0.0\n"
  writeFile (libBDir </> "lib-b.cabal") "cabal-version: 3.0\nname: lib-b\nversion: 2.0.0.0\n"
  T.writeFile (libADir </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial\n"
  T.writeFile (libBDir </> "CHANGELOG.md") "## 2.0.0.0\n\n- Initial\n"

  action tmpDir
