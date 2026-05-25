module Test.Herald.E2E.Validate (tests) where

import Data.Text qualified as T
import Data.Yaml qualified as Yaml
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldFail, shouldPass)
import Test.Herald.E2E.Fixtures (commitAll, git, withFeatureBranch, withGitRepo)
import Test.Herald.E2E.Fixtures.Standard
  ( setupDiffRepo
  , setupMultiDiffRepo
  , setupRootDiffRepo
  , setupTestRepo
  , testConfigDiffRepo
  , testConfigMultiDiffRepo
  , testConfigRootDiffRepo
  )
import Test.Herald.E2E.Fixtures.VersionFile (testConfigVersionFile)
import Test.Herald.Fixtures (testConfigMultiProject)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Command.Validate (validateDiff, validateFiles, validatePR)
import Herald.Fragment (validateFragment)
import Herald.Types (Fragment (..))

tests :: TestTree
tests =
  testGroup
    "Validate"
    [ testGroup
        "validateFragment"
        [ testProperty "validate rejects bad fragment" prop_validate_rejects_bad
        , testProperty "valid fragment passes" prop_validate_fragment_valid
        , testProperty "empty kinds list is rejected" prop_validate_fragment_empty_kinds
        , testProperty "blank description is rejected" prop_validate_fragment_blank_desc
        , testProperty "non-positive PR is rejected" prop_validate_fragment_bad_pr
        , testProperty "unknown project is rejected" prop_validate_fragment_unknown_project
        , testProperty "version-file project validates normally" prop_validate_fragment_version_file
        ]
    , testGroup
        "validateFiles"
        [ testProperty "valid file on disk passes" prop_validate_files_valid
        , testProperty "malformed YAML produces error" prop_validate_files_malformed
        , testProperty "mix of good and bad reports only bad" prop_validate_files_mixed
        ]
    , testGroup
        "validateDiff"
        [ testProperty "missing fragment is detected" prop_validate_diff_missing
        , testProperty "fragment present passes" prop_validate_diff_present
        , testProperty "changes only in .changes/ are ignored" prop_validate_diff_changes_only
        , testProperty "only modified project is flagged" prop_validate_diff_multi_project
        , testProperty "root project detects changes" prop_validate_diff_root_project
        , testProperty "no commits on feature branch passes" prop_validate_diff_no_commits
        , testProperty "deleted files require fragment" prop_validate_diff_deleted
        , testProperty
            "pre-existing fragment does not satisfy new changes"
            prop_validate_diff_preexisting_fragment
        , testProperty
            "fragment for wrong project does not satisfy"
            prop_validate_diff_wrong_project
        , testProperty
            "malformed new fragment does not satisfy"
            prop_validate_diff_malformed_fragment
        , testProperty
            "both projects modified, only one has fragment"
            prop_validate_diff_multi_partial
        , testProperty
            "invalid fragment content still satisfies diff check"
            prop_validate_diff_invalid_content_satisfies
        ]
    , testGroup
        "validatePR"
        [ testProperty "wrong PR number is detected" prop_validate_pr_mismatch
        , testProperty "correct PR number passes" prop_validate_pr_match
        , testProperty "only mismatched fragments reported" prop_validate_pr_partial_mismatch
        , testProperty "template files are skipped" prop_validate_pr_skips_template
        , testProperty ".yaml extension is also checked" prop_validate_pr_yaml_extension
        , testProperty "no new fragments in diff passes" prop_validate_pr_no_new_fragments
        , testProperty
            "malformed fragment in diff reports parse error"
            prop_validate_pr_malformed
        , testProperty
            "invalid fragment content with matching PR passes"
            prop_validate_pr_invalid_content_passes
        ]
    , testGroup
        "validateFiles edge cases"
        [ testProperty "nonexistent file path produces error" prop_validate_files_nonexistent
        ]
    ]

-------------------------------------------------------------------------------
-- validateFragment
-------------------------------------------------------------------------------

-- | A fragment with an unknown kind produces validation errors.
prop_validate_rejects_bad :: Property
prop_validate_rejects_bad = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["nonexistent-kind"]
          , fragmentDescription = "Fix something"
          , fragmentPR = 42
          }
  shouldFail $ validateFragment testConfigMultiProject frag

-- | A well-formed fragment with known project and kind passes.
prop_validate_fragment_valid :: Property
prop_validate_fragment_valid = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "Fix something"
          , fragmentPR = 42
          }
  shouldPass $ validateFragment testConfigMultiProject frag

-- | A fragment with an empty kinds list is rejected.
prop_validate_fragment_empty_kinds :: Property
prop_validate_fragment_empty_kinds = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = []
          , fragmentDescription = "Fix something"
          , fragmentPR = 42
          }
  shouldFail $ validateFragment testConfigMultiProject frag

-- | A fragment with a blank description is rejected.
prop_validate_fragment_blank_desc :: Property
prop_validate_fragment_blank_desc = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "   "
          , fragmentPR = 42
          }
  shouldFail $ validateFragment testConfigMultiProject frag

-- | A fragment with a non-positive PR number is rejected.
prop_validate_fragment_bad_pr :: Property
prop_validate_fragment_bad_pr = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "Fix something"
          , fragmentPR = 0
          }
  shouldFail $ validateFragment testConfigMultiProject frag

-- | A fragment referencing an unknown project is rejected.
prop_validate_fragment_unknown_project :: Property
prop_validate_fragment_unknown_project = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "nonexistent-package"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "Fix something"
          , fragmentPR = 42
          }
  shouldFail $ validateFragment testConfigMultiProject frag

-- | A fragment for a version-file project validates the same as a cabal-file project.
prop_validate_fragment_version_file :: Property
prop_validate_fragment_version_file = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "my-action"
          , fragmentKinds = ["feature"]
          , fragmentDescription = "Add caching"
          , fragmentPR = 10
          }
  shouldPass $ validateFragment testConfigVersionFile frag

-------------------------------------------------------------------------------
-- validateFiles
-------------------------------------------------------------------------------

-- | A well-formed fragment file on disk passes file validation.
prop_validate_files_valid :: Property
prop_validate_files_valid = H.propertyOnce $ do
  errors <- H.evalIO $ setupTestRepo $ \tmpDir ->
    validateFiles testConfigMultiProject "." [tmpDir </> ".changes" </> "42-fix-serialization.yml"]
  shouldPass errors

-- | Malformed YAML triggers a parse error.
prop_validate_files_malformed :: Property
prop_validate_files_malformed = H.propertyOnce $ do
  errors <- H.evalIO $ withSystemTempDirectory "herald-validate" $ \tmpDir -> do
    let path = tmpDir </> "bad.yml"
    writeFile path "not: valid: yaml: [unterminated"
    validateFiles testConfigMultiProject "." [path]
  shouldFail errors

-- | When validating a mix of good and bad files, only the bad file produces errors.
prop_validate_files_mixed :: Property
prop_validate_files_mixed = H.propertyOnce $ do
  errors <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    let goodPath = tmpDir </> ".changes" </> "42-fix-serialization.yml"
        badPath = tmpDir </> ".changes" </> "bad.yml"
    writeFile badPath "not: valid: yaml: [unterminated"
    validateFiles testConfigMultiProject "." [goodPath, badPath]
  shouldFail errors
  H.assertWith errors $ all (T.isInfixOf "bad.yml")

-------------------------------------------------------------------------------
-- validateDiff
-------------------------------------------------------------------------------

-- | Modifying a project file without adding a fragment triggers a diff error.
prop_validate_diff_missing :: Property
prop_validate_diff_missing = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "my-lib" </> "Lib.hs") "module Lib where\n"
    commitAll tmpDir "add lib"
    validateDiff testConfigDiffRepo tmpDir

  shouldFail errors
  H.assertWith errors $ any (T.isInfixOf "my-lib")

-- | Modifying a project file AND adding a matching fragment passes.
prop_validate_diff_present :: Property
prop_validate_diff_present = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "my-lib" </> "Lib.hs") "module Lib where\n"
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "123-add-lib.yml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["feature"]
        , fragmentDescription = "Add Lib module"
        , fragmentPR = 123
        }
    commitAll tmpDir "add lib with fragment"
    validateDiff testConfigDiffRepo tmpDir

  shouldPass errors

-- | Changes only inside .changes/ (no project source files touched) should not trigger errors.
prop_validate_diff_changes_only :: Property
prop_validate_diff_changes_only = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "200-something.yml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Something"
        , fragmentPR = 200
        }
    commitAll tmpDir "add fragment only"
    validateDiff testConfigDiffRepo tmpDir

  shouldPass errors

-- | In a multi-project repo, only the project with modified files (and no fragment) is flagged.
prop_validate_diff_multi_project :: Property
prop_validate_diff_multi_project = H.propertyOnce $ do
  errors <- H.evalIO $ setupMultiDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "lib-a" </> "Foo.hs") "module Foo where\n"
    commitAll tmpDir "modify lib-a"
    validateDiff testConfigMultiDiffRepo tmpDir

  shouldFail errors
  H.assertWith errors $ any (T.isInfixOf "lib-a")
  H.assertWith errors $ not . any (T.isInfixOf "lib-b")

-- | A root-level project (changelog at ".") detects changes correctly.
prop_validate_diff_root_project :: Property
prop_validate_diff_root_project = H.propertyOnce $ do
  errors <- H.evalIO $ setupRootDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "Main.hs") "module Main where\n"
    commitAll tmpDir "add main"
    validateDiff testConfigRootDiffRepo tmpDir

  shouldFail errors
  H.assertWith errors $ any (T.isInfixOf "my-tool")

-------------------------------------------------------------------------------
-- validatePR
-------------------------------------------------------------------------------

-- | A fragment with PR 123 is flagged when --pr expects 999.
prop_validate_pr_mismatch :: Property
prop_validate_pr_mismatch = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "123-add-lib.yml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["feature"]
        , fragmentDescription = "Add Lib module"
        , fragmentPR = 123
        }
    commitAll tmpDir "add fragment"
    validatePR testConfigDiffRepo tmpDir 999

  shouldFail errors
  H.assertWith errors $ any (T.isInfixOf "does not match")

-- | A fragment whose PR matches the expected number passes.
prop_validate_pr_match :: Property
prop_validate_pr_match = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "123-add-lib.yml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["feature"]
        , fragmentDescription = "Add Lib module"
        , fragmentPR = 123
        }
    commitAll tmpDir "add fragment"
    validatePR testConfigDiffRepo tmpDir 123

  shouldPass errors

-- | With two fragments, only the one with a mismatched PR is reported.
prop_validate_pr_partial_mismatch :: Property
prop_validate_pr_partial_mismatch = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "42-fix.yml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Fix"
        , fragmentPR = 42
        }
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "99-feature.yml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["feature"]
        , fragmentDescription = "Feature"
        , fragmentPR = 99
        }
    commitAll tmpDir "add two fragments"
    validatePR testConfigDiffRepo tmpDir 42

  length errors === 1
  H.assertWith errors $ any (T.isInfixOf "99")
  H.assertWith errors $ not . any (T.isInfixOf "42-fix")

-- | Template files (_TEMPLATE.yml) are skipped by PR validation.
prop_validate_pr_skips_template :: Property
prop_validate_pr_skips_template = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    writeFile
      (tmpDir </> ".changes" </> "_TEMPLATE.yml")
      "project: my-lib\nkind:\n  - bugfix\ndescription: template\npr: 0\n"
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "42-fix.yml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Fix"
        , fragmentPR = 42
        }
    commitAll tmpDir "add template and fragment"
    validatePR testConfigDiffRepo tmpDir 42

  shouldPass errors

-- | Fragments with .yaml extension (not just .yml) are also checked.
prop_validate_pr_yaml_extension :: Property
prop_validate_pr_yaml_extension = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "55-old-style.yaml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Old style"
        , fragmentPR = 55
        }
    commitAll tmpDir "add yaml fragment"
    validatePR testConfigDiffRepo tmpDir 99

  shouldFail errors
  H.assertWith errors $ any (T.isInfixOf "55")

-- | A fragment committed on main before the fork point must not satisfy the
-- requirement for new changes on the feature branch.
prop_validate_diff_preexisting_fragment :: Property
prop_validate_diff_preexisting_fragment = H.propertyOnce $ do
  errors <- H.evalIO $ withGitRepo "herald-preexisting" $ \tmpDir -> do
    let pkgDir = tmpDir </> "my-lib"
    createDirectoryIfMissing True pkgDir
    createDirectoryIfMissing True $ tmpDir </> ".changes"
    writeFile (pkgDir </> "my-lib.cabal") "cabal-version: 3.0\nname: my-lib\nversion: 1.0.0.0\n"
    writeFile (pkgDir </> "CHANGELOG.md") "## 1.0.0.0\n\n- Initial\n"
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "10-old-fix.yml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Old fix from a previous cycle"
        , fragmentPR = 10
        }
    commitAll tmpDir "initial with pre-existing fragment"
    withFeatureBranch tmpDir $ do
      writeFile (tmpDir </> "my-lib" </> "Lib.hs") "module Lib where\n"
      commitAll tmpDir "modify lib without new fragment"
      validateDiff testConfigDiffRepo tmpDir

  shouldFail errors
  H.assertWith errors $ any (T.isInfixOf "my-lib")

-- | A new fragment that names a different project does not satisfy the modified project.
prop_validate_diff_wrong_project :: Property
prop_validate_diff_wrong_project = H.propertyOnce $ do
  errors <- H.evalIO $ setupMultiDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "lib-a" </> "Foo.hs") "module Foo where\n"
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "123-lib-b-fix.yml")
      Fragment
        { fragmentProject = "lib-b"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Fix for lib-b"
        , fragmentPR = 123
        }
    commitAll tmpDir "modify lib-a, add fragment for lib-b"
    validateDiff testConfigMultiDiffRepo tmpDir

  shouldFail errors
  H.assertWith errors $ any (T.isInfixOf "lib-a")
  H.assertWith errors $ not . any (T.isInfixOf "lib-b")

-- | A malformed YAML file in .changes/ does not count as a valid fragment.
prop_validate_diff_malformed_fragment :: Property
prop_validate_diff_malformed_fragment = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "my-lib" </> "Lib.hs") "module Lib where\n"
    writeFile (tmpDir </> ".changes" </> "123-broken.yml") "not: valid: yaml: [unterminated"
    commitAll tmpDir "modify lib with broken fragment"
    validateDiff testConfigDiffRepo tmpDir

  shouldFail errors
  H.assertWith errors $ any (T.isInfixOf "my-lib")

-- | Both projects modified but only one has a fragment: only the uncovered one is flagged.
prop_validate_diff_multi_partial :: Property
prop_validate_diff_multi_partial = H.propertyOnce $ do
  errors <- H.evalIO $ setupMultiDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "lib-a" </> "Foo.hs") "module Foo where\n"
    writeFile (tmpDir </> "lib-b" </> "Bar.hs") "module Bar where\n"
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "123-lib-a-feature.yml")
      Fragment
        { fragmentProject = "lib-a"
        , fragmentKinds = ["feature"]
        , fragmentDescription = "New feature in lib-a"
        , fragmentPR = 123
        }
    commitAll tmpDir "modify both, fragment only for lib-a"
    validateDiff testConfigMultiDiffRepo tmpDir

  shouldFail errors
  H.assertWith errors $ not . any (T.isInfixOf "lib-a")
  H.assertWith errors $ any (T.isInfixOf "lib-b")

-- | A fragment with correct project but invalid kinds still satisfies validateDiff.
-- validateDiff only checks project-name presence, not fragment validity.
prop_validate_diff_invalid_content_satisfies :: Property
prop_validate_diff_invalid_content_satisfies = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    writeFile (tmpDir </> "my-lib" </> "Lib.hs") "module Lib where\n"
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "123-bad-kinds.yml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["nonexistent-kind"]
        , fragmentDescription = ""
        , fragmentPR = -1
        }
    commitAll tmpDir "modify lib with invalid fragment"
    validateDiff testConfigDiffRepo tmpDir

  -- validateDiff passes because it only checks project name, not validity
  shouldPass errors

-- | When the feature branch has no commits beyond main, --diff passes (nothing changed).
prop_validate_diff_no_commits :: Property
prop_validate_diff_no_commits = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir ->
    validateDiff testConfigDiffRepo tmpDir

  shouldPass errors

-- | Deleting a project file (without adding a fragment) triggers a diff error.
prop_validate_diff_deleted :: Property
prop_validate_diff_deleted = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    git tmpDir ["rm", "my-lib/my-lib.cabal"]
    commitAll tmpDir "delete cabal file"
    validateDiff testConfigDiffRepo tmpDir

  shouldFail errors
  H.assertWith errors $ any (T.isInfixOf "my-lib")

-- | When no new fragments appear in the diff, --pr validation passes (nothing to check).
prop_validate_pr_no_new_fragments :: Property
prop_validate_pr_no_new_fragments = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir ->
    validatePR testConfigDiffRepo tmpDir 42

  shouldPass errors

-- | A malformed YAML fragment in the diff produces a parse error from --pr validation.
prop_validate_pr_malformed :: Property
prop_validate_pr_malformed = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    writeFile
      (tmpDir </> ".changes" </> "77-broken.yml")
      "not: valid: yaml: [unterminated"
    commitAll tmpDir "add broken fragment"
    validatePR testConfigDiffRepo tmpDir 77

  shouldFail errors

-- | A fragment with matching PR but invalid content (unknown kind, empty description)
-- passes validatePR, which only checks PR numbers, not fragment validity.
prop_validate_pr_invalid_content_passes :: Property
prop_validate_pr_invalid_content_passes = H.propertyOnce $ do
  errors <- H.evalIO $ setupDiffRepo $ \tmpDir -> do
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "42-bad-content.yml")
      Fragment
        { fragmentProject = "my-lib"
        , fragmentKinds = ["nonexistent-kind"]
        , fragmentDescription = ""
        , fragmentPR = 42
        }
    commitAll tmpDir "add invalid fragment with correct PR"
    validatePR testConfigDiffRepo tmpDir 42

  -- PR matches, so validatePR passes despite invalid content
  shouldPass errors

-- | Validating a nonexistent file path produces a clean error.
prop_validate_files_nonexistent :: Property
prop_validate_files_nonexistent = H.propertyOnce $ do
  errors <-
    H.evalIO $
      validateFiles testConfigDiffRepo "." ["/tmp/does-not-exist-12345.yml"]

  shouldFail errors
