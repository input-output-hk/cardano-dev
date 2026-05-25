module Test.Herald.E2E.Validate.PerProject (tests) where

import Data.Text qualified as T
import Data.Yaml qualified as Yaml
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

import Hedgehog (Property)
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain, shouldFail, shouldPass)
import Test.Herald.E2E.Fixtures (commitAll)
import Test.Herald.E2E.Fixtures.PerProject (setupPerProjectDiffRepo, testConfigPerProjectDiff)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Command.Validate (validateDiff, validateFiles, validatePR)
import Herald.Types (Fragment (..))

tests :: TestTree
tests =
  testGroup
    "Validate (per-project changes-dir)"
    [ testGroup
        "validateDiff"
        [ testProperty
            "fragment in per-project dir satisfies requirement"
            prop_diff_per_project_satisfies
        , testProperty
            "changes only in per-project changes-dir are ignored"
            prop_diff_per_project_changes_only
        , testProperty
            "fragment with unknown kind still counts for coverage"
            prop_diff_per_project_content_error_counts
        ]
    , testGroup
        "validatePR"
        [ testProperty
            "fragment in per-project dir with correct PR passes"
            prop_pr_per_project_match
        , testProperty
            "parse error includes details"
            prop_pr_parse_error_includes_details
        ]
    , testGroup
        "validateFiles"
        [ testProperty
            "fragment in per-project dir without project field passes"
            prop_validate_files_inferred_project
        ]
    , testGroup
        "project-directory mismatch"
        [ testProperty
            "fragment with mismatching project in per-project dir is an error"
            prop_validate_dir_mismatch
        , testProperty
            "fragment with matching project in per-project dir passes"
            prop_validate_dir_match
        , testProperty
            "fragment with no project field in per-project dir passes"
            prop_validate_dir_no_project
        ]
    ]

-------------------------------------------------------------------------------
-- validateDiff with per-project dirs
-------------------------------------------------------------------------------

-- | A fragment in a per-project dir satisfies the diff requirement for that project.
prop_diff_per_project_satisfies :: Property
prop_diff_per_project_satisfies = H.propertyOnce $ do
  errors <- H.evalIO $ setupPerProjectDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "lib-a" </> "Foo.hs") "module Foo where\n"
    Yaml.encodeFile
      (tmpDir </> "lib-a" </> ".changes" </> "123-feature.yml")
      Fragment
        { fragmentProject = "lib-a"
        , fragmentKinds = ["feature"]
        , fragmentDescription = "New feature"
        , fragmentPR = 123
        }
    commitAll tmpDir "modify lib-a with fragment in per-project dir"
    validateDiff testConfigPerProjectDiff tmpDir

  shouldPass errors

-- | Changes only in a per-project changes-dir (no source files touched) do not trigger errors.
prop_diff_per_project_changes_only :: Property
prop_diff_per_project_changes_only = H.propertyOnce $ do
  errors <- H.evalIO $ setupPerProjectDiffRepo $ \tmpDir -> do
    Yaml.encodeFile
      (tmpDir </> "lib-a" </> ".changes" </> "200-something.yml")
      Fragment
        { fragmentProject = "lib-a"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Something"
        , fragmentPR = 200
        }
    commitAll tmpDir "add fragment only in per-project dir"
    validateDiff testConfigPerProjectDiff tmpDir

  shouldPass errors

-------------------------------------------------------------------------------
-- validatePR with per-project dirs
-------------------------------------------------------------------------------

-- | A fragment in a per-project dir with the correct PR number passes PR validation.
prop_pr_per_project_match :: Property
prop_pr_per_project_match = H.propertyOnce $ do
  errors <- H.evalIO $ setupPerProjectDiffRepo $ \tmpDir -> do
    Yaml.encodeFile
      (tmpDir </> "lib-a" </> ".changes" </> "42-fix.yml")
      Fragment
        { fragmentProject = "lib-a"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Fix"
        , fragmentPR = 42
        }
    commitAll tmpDir "add fragment in per-project dir"
    validatePR testConfigPerProjectDiff tmpDir 42

  shouldPass errors

-------------------------------------------------------------------------------
-- Project-directory mismatch
-------------------------------------------------------------------------------

-- | A fragment in a per-project dir with explicit project naming a different
-- project is a validation error.
prop_validate_dir_mismatch :: Property
prop_validate_dir_mismatch = H.propertyOnce $ do
  errors <- H.evalIO $ setupPerProjectDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "lib-a" </> "Foo.hs") "module Foo where\n"
    -- Fragment in lib-a/.changes/ but project: says lib-b
    Yaml.encodeFile
      (tmpDir </> "lib-a" </> ".changes" </> "99-mismatch.yml")
      Fragment
        { fragmentProject = "lib-b"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Misplaced fragment"
        , fragmentPR = 99
        }
    commitAll tmpDir "add mismatched fragment"
    validateDiff testConfigPerProjectDiff tmpDir

  shouldFail errors

-- | A fragment in a per-project dir with matching explicit project passes.
prop_validate_dir_match :: Property
prop_validate_dir_match = H.propertyOnce $ do
  errors <- H.evalIO $ setupPerProjectDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "lib-a" </> "Foo.hs") "module Foo where\n"
    Yaml.encodeFile
      (tmpDir </> "lib-a" </> ".changes" </> "99-match.yml")
      Fragment
        { fragmentProject = "lib-a"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Correctly placed fragment"
        , fragmentPR = 99
        }
    commitAll tmpDir "add matching fragment"
    validateDiff testConfigPerProjectDiff tmpDir

  shouldPass errors

-- | A fragment in a per-project dir with no project field passes
-- (project is inferred from directory).
prop_validate_dir_no_project :: Property
prop_validate_dir_no_project = H.propertyOnce $ do
  errors <- H.evalIO $ setupPerProjectDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "lib-a" </> "Foo.hs") "module Foo where\n"
    -- Write a fragment without project: field manually
    writeFile
      (tmpDir </> "lib-a" </> ".changes" </> "99-inferred.yml")
      "kind:\n  - bugfix\ndescription: Inferred project\npr: 99\n"
    commitAll tmpDir "add fragment without project field"
    validateDiff testConfigPerProjectDiff tmpDir

  shouldPass errors

-------------------------------------------------------------------------------
-- Fix 1: content errors don't block coverage
-------------------------------------------------------------------------------

-- | A fragment with an unknown kind in a per-project dir still counts for
-- diff coverage (validateDiff only checks dir consistency, not content).
prop_diff_per_project_content_error_counts :: Property
prop_diff_per_project_content_error_counts = H.propertyOnce $ do
  errors <- H.evalIO $ setupPerProjectDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "lib-a" </> "Foo.hs") "module Foo where\n"
    Yaml.encodeFile
      (tmpDir </> "lib-a" </> ".changes" </> "123-bad-kind.yml")
      Fragment
        { fragmentProject = "lib-a"
        , fragmentKinds = ["nonexistent-kind"]
        , fragmentDescription = "Has unknown kind"
        , fragmentPR = 123
        }
    commitAll tmpDir "add fragment with unknown kind"
    validateDiff testConfigPerProjectDiff tmpDir

  shouldPass errors

-------------------------------------------------------------------------------
-- Fix 2: parse errors include details
-------------------------------------------------------------------------------

-- | A malformed YAML fragment produces an error with parse details, not just
-- "failed to parse fragment".
prop_pr_parse_error_includes_details :: Property
prop_pr_parse_error_includes_details = H.propertyOnce $ do
  errors <- H.evalIO $ setupPerProjectDiffRepo $ \tmpDir -> do
    writeFile
      (tmpDir </> "lib-a" </> ".changes" </> "42-bad.yml")
      "this is not valid yaml: [unclosed"
    commitAll tmpDir "add malformed fragment"
    validatePR testConfigPerProjectDiff tmpDir 42

  shouldFail errors
  let combined = T.intercalate "\n" errors
  shouldContain combined "42-bad.yml"

-------------------------------------------------------------------------------
-- Fix 6: validateFiles with inference
-------------------------------------------------------------------------------

-- | validateFiles infers the project from the per-project directory when
-- the fragment omits the project: field.
prop_validate_files_inferred_project :: Property
prop_validate_files_inferred_project = H.propertyOnce $ do
  errors <- H.evalIO $ setupPerProjectDiffRepo $ \tmpDir -> do
    createDirectoryIfMissing True (tmpDir </> "lib-a" </> ".changes")
    writeFile
      (tmpDir </> "lib-a" </> ".changes" </> "10-inferred.yml")
      "kind:\n  - bugfix\ndescription: Inferred project\npr: 10\n"
    validateFiles testConfigPerProjectDiff tmpDir ["lib-a/.changes/10-inferred.yml"]

  shouldPass errors
