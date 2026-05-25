module Test.Herald.Fragment (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Yaml (decodeEither')

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldFail, shouldPass)
import Test.Herald.Fixtures (testConfig)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Fragment (validateFragment, validateFragmentDir)
import Herald.Types (Fragment (..))

tests :: TestTree
tests =
  testGroup
    "Herald.Fragment"
    [ testGroup
        "YAML parsing"
        [ testProperty "parse valid fragment" prop_parse_valid
        , testProperty "parse fragment with multiple kinds" prop_parse_multi_kinds
        , testProperty "reject missing project" prop_reject_missing_project
        , testProperty "reject missing pr" prop_reject_missing_pr
        , testProperty "reject missing kind" prop_reject_missing_kind
        , testProperty "reject missing description" prop_reject_missing_description
        ]
    , testGroup
        "validateFragment"
        [ testProperty "valid fragment" prop_validate_valid
        , testProperty "unknown kind" prop_validate_unknown_kind
        , testProperty "unknown project" prop_validate_unknown_project
        , testProperty "empty description" prop_validate_empty_description
        , testProperty "whitespace-only description" prop_validate_whitespace_description
        , testProperty "PR <= 0" prop_validate_bad_pr
        , testProperty "negative PR" prop_validate_negative_pr
        , testProperty "empty kinds list" prop_validate_empty_kinds
        , testProperty "extra YAML fields are silently ignored" prop_parse_extra_fields
        ]
    , testGroup
        "project-directory mismatch"
        [ testProperty
            "mismatching project in per-project dir is an error"
            prop_validate_dir_mismatch
        , testProperty
            "matching project in per-project dir passes"
            prop_validate_dir_match
        , testProperty
            "directory not in config is rejected"
            prop_validate_dir_no_project
        ]
    ]

-- | Helper to build YAML ByteStrings readably.
yaml :: [Text] -> T.Text
yaml = T.unlines

-- YAML parsing tests

-- | A well-formed fragment YAML is decoded with all fields intact.
prop_parse_valid :: Property
prop_parse_valid = H.propertyOnce $ do
  let input =
        encodeUtf8 $
          yaml
            [ "project: cardano-api"
            , "kind:"
            , "  - bugfix"
            , "description: Fix serialization"
            , "pr: 42"
            ]
  frag <- H.leftFail $ decodeEither' input
  fragmentProject frag === "cardano-api"
  fragmentKinds frag === ["bugfix"]
  fragmentDescription frag === "Fix serialization"
  fragmentPR frag === 42

-- | Multiple kinds in a fragment are parsed as a list.
prop_parse_multi_kinds :: Property
prop_parse_multi_kinds = H.propertyOnce $ do
  let input =
        encodeUtf8 $
          yaml
            [ "project: cardano-api"
            , "kind:"
            , "  - bugfix"
            , "  - refactoring"
            , "description: Fix and refactor"
            , "pr: 99"
            ]
  frag <- H.leftFail $ decodeEither' input
  fragmentKinds frag === ["bugfix", "refactoring"]

-- | Missing 'project' field causes a parse error.
prop_reject_missing_project :: Property
prop_reject_missing_project = H.propertyOnce $ do
  let input =
        encodeUtf8 $
          yaml
            [ "kind:"
            , "  - bugfix"
            , "description: Fix something"
            , "pr: 42"
            ]
  case decodeEither' input of
    Left _ -> H.success
    Right (_ :: Fragment) -> H.failure

-- | Missing 'pr' field causes a parse error.
prop_reject_missing_pr :: Property
prop_reject_missing_pr = H.propertyOnce $ do
  let input =
        encodeUtf8 $
          yaml
            [ "project: cardano-api"
            , "kind:"
            , "  - bugfix"
            , "description: Fix something"
            ]
  case decodeEither' input of
    Left _ -> H.success
    Right (_ :: Fragment) -> H.failure

-- | Missing 'kind' field causes a parse error.
prop_reject_missing_kind :: Property
prop_reject_missing_kind = H.propertyOnce $ do
  let input =
        encodeUtf8 $
          yaml
            [ "project: cardano-api"
            , "description: Fix something"
            , "pr: 42"
            ]
  case decodeEither' input of
    Left _ -> H.success
    Right (_ :: Fragment) -> H.failure

-- | Missing 'description' field causes a parse error.
prop_reject_missing_description :: Property
prop_reject_missing_description = H.propertyOnce $ do
  let input =
        encodeUtf8 $
          yaml
            [ "project: cardano-api"
            , "kind:"
            , "  - bugfix"
            , "pr: 42"
            ]
  case decodeEither' input of
    Left _ -> H.success
    Right (_ :: Fragment) -> H.failure

-- validateFragment tests

-- | A fragment with known project, known kinds, non-empty description, and positive PR passes.
prop_validate_valid :: Property
prop_validate_valid = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "Fix serialization"
          , fragmentPR = 42
          }
  shouldPass $ validateFragment testConfig frag

-- | A fragment referencing a kind not in the config is rejected.
prop_validate_unknown_kind :: Property
prop_validate_unknown_kind = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["nonexistent-kind"]
          , fragmentDescription = "Fix something"
          , fragmentPR = 42
          }
  shouldFail $ validateFragment testConfig frag

-- | A fragment referencing a project not in the config is rejected.
prop_validate_unknown_project :: Property
prop_validate_unknown_project = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "nonexistent-project"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "Fix something"
          , fragmentPR = 42
          }
  shouldFail $ validateFragment testConfig frag

-- | An empty description is rejected.
prop_validate_empty_description :: Property
prop_validate_empty_description = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = ""
          , fragmentPR = 42
          }
  shouldFail $ validateFragment testConfig frag

-- | PR number <= 0 is rejected.
prop_validate_bad_pr :: Property
prop_validate_bad_pr = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "Fix something"
          , fragmentPR = 0
          }
  shouldFail $ validateFragment testConfig frag

-- | Whitespace-only description is rejected (strip then check empty).
prop_validate_whitespace_description :: Property
prop_validate_whitespace_description = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "   \t  "
          , fragmentPR = 42
          }
  shouldFail $ validateFragment testConfig frag

-- | Negative PR number is rejected (not just zero).
prop_validate_negative_pr :: Property
prop_validate_negative_pr = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "Fix something"
          , fragmentPR = -5
          }
  shouldFail $ validateFragment testConfig frag

-- | An empty kinds list is rejected.
prop_validate_empty_kinds :: Property
prop_validate_empty_kinds = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = []
          , fragmentDescription = "Fix something"
          , fragmentPR = 42
          }
  shouldFail $ validateFragment testConfig frag

-- | Extra unknown YAML fields are silently ignored by the parser.
prop_parse_extra_fields :: Property
prop_parse_extra_fields = H.propertyOnce $ do
  let input =
        encodeUtf8 $
          yaml
            [ "project: cardano-api"
            , "kind:"
            , "  - bugfix"
            , "description: Fix something"
            , "pr: 42"
            , "severity: critical"
            , "author: someone"
            ]
  frag <- H.leftFail $ decodeEither' input
  fragmentProject frag === "cardano-api"
  fragmentKinds frag === ["bugfix"]
  fragmentDescription frag === "Fix something"
  fragmentPR frag === 42

-- project-directory mismatch tests

-- | A fragment in a per-project dir with explicit project naming a different
-- project produces a validation error.
prop_validate_dir_mismatch :: Property
prop_validate_dir_mismatch = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api-gen"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "Fix something"
          , fragmentPR = 42
          }
  shouldFail $ validateFragmentDir testConfig "cardano-api" frag

-- | A fragment in a per-project dir with matching explicit project passes.
prop_validate_dir_match :: Property
prop_validate_dir_match = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "Fix something"
          , fragmentPR = 42
          }
  shouldPass $ validateFragmentDir testConfig "cardano-api" frag

-- | A fragment in a per-project dir whose directory name does not match any
-- project in the config is rejected.
prop_validate_dir_no_project :: Property
prop_validate_dir_no_project = H.propertyOnce $ do
  let frag =
        Fragment
          { fragmentProject = "cardano-api"
          , fragmentKinds = ["bugfix"]
          , fragmentDescription = "Fix something"
          , fragmentPR = 42
          }
  shouldFail $ validateFragmentDir testConfig "nonexistent-project" frag
