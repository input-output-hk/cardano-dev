module Test.Herald.Config.ChangesDir (tests) where

import Data.ByteString (isInfixOf)
import Data.Either (isLeft)
import Data.Text.Encoding (encodeUtf8)
import Data.Yaml (decodeEither', encode)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Config (loadConfig)
import Herald.Types (ProjectConfig (..))

tests :: TestTree
tests =
  testGroup
    "Per-project changes-dir"
    [ testGroup
        "ProjectConfig parsing"
        [ testProperty "project with changes-dir parses" prop_project_changes_dir
        , testProperty "project without changes-dir parses to Nothing" prop_project_no_changes_dir
        , testProperty "changes-dir roundtrips" prop_serialize_changes_dir
        ]
    , testGroup
        "Config loading"
        [ testProperty
            "duplicate changes-dir across projects is rejected"
            prop_load_duplicate_changes_dir
        , testProperty
            "nested per-project changes-dirs are rejected"
            prop_load_nested_changes_dir
        , testProperty
            "per-project changes-dir equal to global is rejected"
            prop_load_per_project_equals_global
        , testProperty
            "per-project changes-dir nested under global is rejected"
            prop_load_nested_with_global
        , testProperty
            "global changes-dir absent with all projects having their own loads"
            prop_load_no_global_all_projects
        , testProperty
            "global changes-dir absent with uncovered project is rejected"
            prop_load_no_global_uncovered
        ]
    ]

-------------------------------------------------------------------------------
-- ProjectConfig parsing
-------------------------------------------------------------------------------

-- | A project with an explicit changes-dir parses it.
prop_project_changes_dir :: Property
prop_project_changes_dir = H.propertyOnce $ do
  pc <-
    H.leftFail . decodeEither' . encodeUtf8 $
      "changelog: CHANGELOG.md\ncabal-file: foo.cabal\nchanges-dir: my-project/.changes\n"
  projectChangesDir (pc :: ProjectConfig) === Just "my-project/.changes"

-- | A project without changes-dir parses to Nothing.
prop_project_no_changes_dir :: Property
prop_project_no_changes_dir = H.propertyOnce $ do
  pc <- H.leftFail . decodeEither' . encodeUtf8 $ "changelog: CHANGELOG.md\ncabal-file: foo.cabal\n"
  projectChangesDir (pc :: ProjectConfig) === Nothing

-- | changes-dir roundtrips through YAML encode/decode.
prop_serialize_changes_dir :: Property
prop_serialize_changes_dir = H.propertyOnce $ do
  pc <-
    H.leftFail . decodeEither' . encodeUtf8 $
      "changelog: CHANGELOG.md\ncabal-file: foo.cabal\nchanges-dir: my-project/.changes\n"
  let output = encode (pc :: ProjectConfig)
  H.assertWith output $ isInfixOf "changes-dir:"
  pc2 <- H.leftFail $ decodeEither' output
  projectChangesDir pc2 === Just "my-project/.changes"

-------------------------------------------------------------------------------
-- Config loading
-------------------------------------------------------------------------------

-- | Two projects sharing the same changes-dir is rejected at config-load time.
prop_load_duplicate_changes_dir :: Property
prop_load_duplicate_changes_dir = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-config" $ \tmpDir -> do
    let configPath = tmpDir </> ".herald.yml"
    writeFile configPath $
      unlines
        [ "git-repo: test/repo"
        , "changes-dir: .changes"
        , "kinds:"
        , "  bugfix:"
        , "    bump: 0.0.0.1"
        , "projects:"
        , "  project-a:"
        , "    changelog: a/CHANGELOG.md"
        , "    changes-dir: shared/.changes"
        , "  project-b:"
        , "    changelog: b/CHANGELOG.md"
        , "    changes-dir: shared/.changes"
        ]
    loadConfig configPath

  H.assertWith result isLeft

-- | A per-project changes-dir nested inside another is rejected.
prop_load_nested_changes_dir :: Property
prop_load_nested_changes_dir = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-config" $ \tmpDir -> do
    let configPath = tmpDir </> ".herald.yml"
    writeFile configPath $
      unlines
        [ "git-repo: test/repo"
        , "changes-dir: .changes"
        , "kinds:"
        , "  bugfix:"
        , "    bump: 0.0.0.1"
        , "projects:"
        , "  project-a:"
        , "    changelog: a/CHANGELOG.md"
        , "    changes-dir: shared"
        , "  project-b:"
        , "    changelog: b/CHANGELOG.md"
        , "    changes-dir: shared/nested"
        ]
    loadConfig configPath

  H.assertWith result isLeft

-- | A per-project changes-dir that equals the global changes-dir is rejected.
prop_load_per_project_equals_global :: Property
prop_load_per_project_equals_global = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-config" $ \tmpDir -> do
    let configPath = tmpDir </> ".herald.yml"
    writeFile configPath $
      unlines
        [ "git-repo: test/repo"
        , "changes-dir: .changes"
        , "kinds:"
        , "  bugfix:"
        , "    bump: 0.0.0.1"
        , "projects:"
        , "  project-a:"
        , "    changelog: a/CHANGELOG.md"
        , "    changes-dir: .changes"
        ]
    loadConfig configPath

  H.assertWith result isLeft

-- | A per-project changes-dir nested under the global changes-dir is rejected.
prop_load_nested_with_global :: Property
prop_load_nested_with_global = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-config" $ \tmpDir -> do
    let configPath = tmpDir </> ".herald.yml"
    writeFile configPath $
      unlines
        [ "git-repo: test/repo"
        , "changes-dir: .changes"
        , "kinds:"
        , "  bugfix:"
        , "    bump: 0.0.0.1"
        , "projects:"
        , "  project-a:"
        , "    changelog: a/CHANGELOG.md"
        , "    changes-dir: .changes/project-a"
        ]
    loadConfig configPath

  H.assertWith result isLeft

-- | When every project has its own changes-dir, the global one can be omitted.
prop_load_no_global_all_projects :: Property
prop_load_no_global_all_projects = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-config" $ \tmpDir -> do
    let configPath = tmpDir </> ".herald.yml"
    writeFile configPath $
      unlines
        [ "git-repo: test/repo"
        , "kinds:"
        , "  bugfix:"
        , "    bump: 0.0.0.1"
        , "projects:"
        , "  project-a:"
        , "    changelog: a/CHANGELOG.md"
        , "    changes-dir: a/.changes"
        , "  project-b:"
        , "    changelog: b/CHANGELOG.md"
        , "    changes-dir: b/.changes"
        ]
    loadConfig configPath

  _ <- H.leftFail result
  H.success

-- | When global changes-dir is absent and a project lacks its own, it is rejected.
prop_load_no_global_uncovered :: Property
prop_load_no_global_uncovered = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-config" $ \tmpDir -> do
    let configPath = tmpDir </> ".herald.yml"
    writeFile configPath $
      unlines
        [ "git-repo: test/repo"
        , "kinds:"
        , "  bugfix:"
        , "    bump: 0.0.0.1"
        , "projects:"
        , "  project-a:"
        , "    changelog: a/CHANGELOG.md"
        , "    changes-dir: a/.changes"
        , "  project-b:"
        , "    changelog: b/CHANGELOG.md"
        ]
    loadConfig configPath

  H.assertWith result isLeft
