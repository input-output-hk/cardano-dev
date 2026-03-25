module Test.Herald.Render (tests) where

import Data.Text qualified as T

import Hedgehog (Property)
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain, shouldNotContain)
import Test.Herald.Fixtures (testConfig, testDay, testVersion)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Fragment.Render (renderSection)
import Herald.Types (Fragment (..))

tests :: TestTree
tests =
  testGroup
    "Herald.Fragment.Render"
    [ testProperty "single notable fragment" prop_single_notable
    , testProperty "multiple fragments sorted by PR" prop_sorted_by_pr
    , testProperty "all non-notable excluded" prop_non_notable_excluded
    , testProperty "mixed notable and non-notable" prop_mixed_notable
    , testProperty "multi-line description" prop_multiline_description
    , testProperty "empty fragment list" prop_empty_fragments
    , testProperty "unknown kinds treated as non-notable" prop_unknown_kind_non_notable
    , testProperty "duplicate PR numbers both rendered" prop_duplicate_pr
    ]

-- | A single notable fragment renders with version header, date, description, kind, and PR link.
prop_single_notable :: Property
prop_single_notable = H.propertyOnce $ do
  let frags =
        [ Fragment
            { fragmentProject = "cardano-api"
            , fragmentKinds = ["bugfix"]
            , fragmentDescription = "Fix serialization of Conway certificates"
            , fragmentPR = 42
            }
        ]
      result = renderSection testConfig testVersion testDay frags
  result `shouldContain` "## 8.5.0.0"
  result `shouldContain` "2026-03-25"
  result `shouldContain` "Fix serialization of Conway certificates"
  result `shouldContain` "(bugfix)"
  result `shouldContain` "PR 42"

-- | Multiple fragments appear sorted by PR number (descending).
prop_sorted_by_pr :: Property
prop_sorted_by_pr = H.propertyOnce $ do
  let frags =
        [ Fragment
            { fragmentProject = "cardano-api"
            , fragmentKinds = ["bugfix"]
            , fragmentDescription = "Second fix"
            , fragmentPR = 42
            }
        , Fragment
            { fragmentProject = "cardano-api"
            , fragmentKinds = ["feature"]
            , fragmentDescription = "First feature"
            , fragmentPR = 99
            }
        ]
      result = renderSection testConfig testVersion testDay frags
      idx42 = T.breakOn "PR 42" result
      idx99 = T.breakOn "PR 99" result
  result `shouldContain` "PR 42"
  result `shouldContain` "PR 99"
  -- PR 99 should appear before PR 42 (shorter prefix means earlier position)
  H.assert $ T.length (fst idx99) < T.length (fst idx42)

-- | Fragments with only non-notable kinds are excluded from the rendered output.
prop_non_notable_excluded :: Property
prop_non_notable_excluded = H.propertyOnce $ do
  let frags =
        [ Fragment
            { fragmentProject = "cardano-api"
            , fragmentKinds = ["test"]
            , fragmentDescription = "Add test for X"
            , fragmentPR = 50
            }
        ]
      result = renderSection testConfig testVersion testDay frags
  result `shouldContain` "## 8.5.0.0"
  result `shouldNotContain` "Add test for X"

-- | A fragment with a mix of notable and non-notable kinds is included,
-- and ALL kind labels appear in the parenthesized list.
prop_mixed_notable :: Property
prop_mixed_notable = H.propertyOnce $ do
  let frags =
        [ Fragment
            { fragmentProject = "cardano-api"
            , fragmentKinds = ["bugfix", "refactoring"]
            , fragmentDescription = "Fix and refactor"
            , fragmentPR = 42
            }
        ]
      result = renderSection testConfig testVersion testDay frags
  result `shouldContain` "Fix and refactor"
  result `shouldContain` "bugfix"
  result `shouldContain` "refactoring"

-- | Multi-line descriptions are preserved in the rendered output.
prop_multiline_description :: Property
prop_multiline_description = H.propertyOnce $ do
  let frags =
        [ Fragment
            { fragmentProject = "cardano-api"
            , fragmentKinds = ["bugfix"]
            , fragmentDescription = "Fix line one\nFix line two"
            , fragmentPR = 42
            }
        ]
      result = renderSection testConfig testVersion testDay frags
  result `shouldContain` "Fix line one"
  result `shouldContain` "Fix line two"

-- | An empty fragment list still renders the version header.
prop_empty_fragments :: Property
prop_empty_fragments = H.propertyOnce $ do
  let result = renderSection testConfig testVersion testDay []
  result `shouldContain` "## 8.5.0.0"
  result `shouldContain` "2026-03-25"

-- | Fragments with kinds not present in the config are treated as non-notable
-- and excluded from the rendered output.
prop_unknown_kind_non_notable :: Property
prop_unknown_kind_non_notable = H.propertyOnce $ do
  let frags =
        [ Fragment
            { fragmentProject = "cardano-api"
            , fragmentKinds = ["nonexistent-kind"]
            , fragmentDescription = "This should be hidden"
            , fragmentPR = 77
            }
        ]
      result = renderSection testConfig testVersion testDay frags
  result `shouldContain` "## 8.5.0.0"
  result `shouldNotContain` "This should be hidden"
  result `shouldNotContain` "PR 77"

-- | Two fragments with the same PR number are both rendered.
prop_duplicate_pr :: Property
prop_duplicate_pr = H.propertyOnce $ do
  let frags =
        [ Fragment
            { fragmentProject = "cardano-api"
            , fragmentKinds = ["bugfix"]
            , fragmentDescription = "First fix"
            , fragmentPR = 42
            }
        , Fragment
            { fragmentProject = "cardano-api"
            , fragmentKinds = ["feature"]
            , fragmentDescription = "Second entry same PR"
            , fragmentPR = 42
            }
        ]
      result = renderSection testConfig testVersion testDay frags
  result `shouldContain` "First fix"
  result `shouldContain` "Second entry same PR"
