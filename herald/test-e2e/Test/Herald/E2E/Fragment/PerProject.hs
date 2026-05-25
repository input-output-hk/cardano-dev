module Test.Herald.E2E.Fragment.PerProject (tests) where

import Control.Exception.Safe (catch)
import Data.List (sort)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import System.FilePath (takeFileName, (</>))

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain)
import Test.Herald.E2E.Fixtures.PerProject (setupPerProjectRepo, testConfigPerProject)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Command.New (NewOptions (..), createFragment)
import Herald.Fragment.Read (readAllFragments, readProjectFragments)
import Herald.Types (Fragment (..), HeraldException (..))

tests :: TestTree
tests =
  testGroup
    "Fragment (per-project changes-dir)"
    [ testProperty
        "new writes to per-project dir when configured"
        prop_new_per_project_dir
    , testProperty
        "new writes to global dir when no per-project dir"
        prop_new_global_dir
    , testProperty
        "readProjectFragments collects from both dirs"
        prop_read_both_dirs
    , testProperty
        "template in per-project dir is skipped"
        prop_template_skipped_per_project
    , testProperty
        "duplicate check scans both dirs"
        prop_duplicate_check_both_dirs
    ]

-- | When a project has a per-project changes-dir, herald new writes there.
prop_new_per_project_dir :: Property
prop_new_per_project_dir = H.propertyOnce $ do
  path <- H.evalIO $ setupPerProjectRepo $ \tmpDir -> do
    let opts = NewOptions "cardano-api" ["bugfix"] "New fix" 200
    createFragment testConfigPerProject tmpDir opts

  T.pack path `shouldContain` "cardano-api/.changes"

-- | When a project has no per-project changes-dir, herald new writes to global.
prop_new_global_dir :: Property
prop_new_global_dir = H.propertyOnce $ do
  path <- H.evalIO $ setupPerProjectRepo $ \tmpDir -> do
    let opts = NewOptions "cardano-api-gen" ["bugfix"] "New fix" 200
    createFragment testConfigPerProject tmpDir opts

  T.pack path `shouldContain` ".changes/"

-- | readProjectFragments collects fragments from both global and per-project dirs.
prop_read_both_dirs :: Property
prop_read_both_dirs = H.propertyOnce $ do
  fragments <- H.evalIO $ setupPerProjectRepo $ \tmpDir ->
    readProjectFragments testConfigPerProject tmpDir "cardano-api"

  -- PR 42 is in per-project dir, PR 99 is in global dir
  let prs = sort $ map (\(_, f) -> fragmentPR f) fragments
  prs === [42, 99]

-- | _TEMPLATE.yml in a per-project dir is skipped.
prop_template_skipped_per_project :: Property
prop_template_skipped_per_project = H.propertyOnce $ do
  fragments <- H.evalIO $ setupPerProjectRepo $ \tmpDir -> do
    T.writeFile
      (tmpDir </> "cardano-api" </> ".changes" </> "_TEMPLATE.yml")
      "project: cardano-api\nkind:\n  - bugfix\ndescription: template\npr: 0\n"
    readAllFragments testConfigPerProject tmpDir

  let names = map fst fragments
  H.assertWith names $ not . any (T.isPrefixOf "_TEMPLATE" . T.pack . takeFileName)

-- | Duplicate check for herald new scans both global and per-project dirs.
prop_duplicate_check_both_dirs :: Property
prop_duplicate_check_both_dirs = H.propertyOnce $ do
  errMsg <- H.evalIO $ setupPerProjectRepo $ \tmpDir -> do
    -- PR 42 already exists in per-project dir
    let opts = NewOptions "cardano-api" ["bugfix"] "Duplicate attempt" 42
    (createFragment testConfigPerProject tmpDir opts >> pure "no error")
      `catch` \(HeraldException msg) -> pure msg

  T.pack errMsg `shouldContain` "already exists"
