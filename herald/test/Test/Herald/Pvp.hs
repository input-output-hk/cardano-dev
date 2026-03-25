module Test.Herald.Pvp (tests) where

import Data.List.NonEmpty (NonEmpty (..))

import Hedgehog (Gen, Property, forAll, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Herald.Fixtures (breakingBump, featureBump, noBump, patchBump, pvp)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Pvp (Pvp (..), bumpPvp, parsePvp, showPvp)

tests :: TestTree
tests =
  testGroup
    "Herald.Pvp"
    [ testGroup
        "parsePvp"
        [ testProperty "roundtrip four parts" prop_roundtrip
        , testProperty "single part" prop_single_part
        , testProperty "three parts" prop_three_parts
        , testProperty "five parts" prop_five_parts
        , testProperty "rejects empty string" prop_rejects_empty
        , testProperty "rejects non-digit" prop_rejects_non_digit
        , testProperty "rejects negative" prop_rejects_negative
        , testProperty "rejects trailing dot" prop_rejects_trailing_dot
        , testProperty "rejects leading dot" prop_rejects_leading_dot
        ]
    , testGroup
        "bumpPvp"
        [ testProperty "bump 0.1.0.0 (second digit)" prop_bump_second
        , testProperty "bump 0.0.1.0 (third digit)" prop_bump_third
        , testProperty "bump 0.0.0.1 (fourth digit)" prop_bump_fourth
        , testProperty "bump 0.0.0.0 (identity)" prop_bump_identity
        ]
    , testGroup
        "bumpPvp short versions"
        [ testProperty "bump second digit on two-part version" prop_bump_short_second
        , testProperty "bump fourth digit on two-part version extends" prop_bump_short_fourth
        , testProperty "bump first digit (A.0.0.0)" prop_bump_first
        ]
    , testGroup
        "Pvp Ord"
        [ testProperty "different-length versions compare lexicographically" prop_ord_different_length
        ]
    , testGroup
        "parsePvp edge cases"
        [ testProperty "leading zeros are silently stripped" prop_leading_zeros
        ]
    , testGroup
        "properties"
        [ testProperty "max bump level" prop_max_bump
        , testProperty "parsePvp/showPvp roundtrip" prop_roundtrip_property
        , testProperty "bumpPvp result >= input (monotonicity)" prop_bump_monotonic
        ]
    ]

-- parsePvp tests

-- | Parsing and showing a four-part version is a no-op.
prop_roundtrip :: Property
prop_roundtrip = H.propertyOnce $ do
  fmap showPvp (parsePvp "8.4.1.2") === Just "8.4.1.2"
  fmap showPvp (parsePvp "0.0.0.0") === Just "0.0.0.0"
  fmap showPvp (parsePvp "99.0.12.3") === Just "99.0.12.3"

-- | A bare integer is a valid single-component version.
prop_single_part :: Property
prop_single_part = H.propertyOnce $ do
  fmap showPvp (parsePvp "42") === Just "42"

-- | Three-part versions are accepted (not just four).
prop_three_parts :: Property
prop_three_parts = H.propertyOnce $ do
  fmap showPvp (parsePvp "1.2.3") === Just "1.2.3"

-- | Five-part versions are accepted (PVP allows any length).
prop_five_parts :: Property
prop_five_parts = H.propertyOnce $ do
  fmap showPvp (parsePvp "1.2.3.4.5") === Just "1.2.3.4.5"

-- | Empty string is not a valid version.
prop_rejects_empty :: Property
prop_rejects_empty = H.propertyOnce $ do
  parsePvp "" === Nothing

-- | Non-digit characters cause a parse failure.
prop_rejects_non_digit :: Property
prop_rejects_non_digit = H.propertyOnce $ do
  parsePvp "1.2.3.a" === Nothing
  parsePvp "x.2.3.4" === Nothing

-- | Leading minus sign is rejected (components must be non-negative).
prop_rejects_negative :: Property
prop_rejects_negative = H.propertyOnce $ do
  parsePvp "-1.2.3.4" === Nothing

-- | A trailing dot leaves an empty final component.
prop_rejects_trailing_dot :: Property
prop_rejects_trailing_dot = H.propertyOnce $ do
  parsePvp "1.2.3." === Nothing

-- | A leading dot leaves an empty first component.
prop_rejects_leading_dot :: Property
prop_rejects_leading_dot = H.propertyOnce $ do
  parsePvp ".1.2.3" === Nothing

-- bumpPvp tests

-- | Breaking bump (0.1.0.0): increments second digit, zeros the rest.
prop_bump_second :: Property
prop_bump_second = H.propertyOnce $ do
  bumpPvp breakingBump (pvp 8 4 1 2) === pvp 8 5 0 0

-- | Feature bump (0.0.1.0): increments third digit, zeros the rest.
prop_bump_third :: Property
prop_bump_third = H.propertyOnce $ do
  bumpPvp featureBump (pvp 8 4 1 2) === pvp 8 4 2 0

-- | Patch bump (0.0.0.1): increments fourth digit only.
prop_bump_fourth :: Property
prop_bump_fourth = H.propertyOnce $ do
  bumpPvp patchBump (pvp 8 4 1 2) === pvp 8 4 1 3

-- | All-zero bump level is the identity -- version unchanged.
prop_bump_identity :: Property
prop_bump_identity = H.propertyOnce $ do
  bumpPvp noBump (pvp 8 4 1 2) === pvp 8 4 1 2

-- | The maximum of several bump levels is the most significant one.
prop_max_bump :: Property
prop_max_bump = H.propertyOnce $ do
  let bumps = [patchBump, breakingBump, featureBump]
  maximum bumps === breakingBump

-- | For any random PVP value, parse . show is the identity.
prop_roundtrip_property :: Property
prop_roundtrip_property = H.property $ do
  v <- forAll genPvp
  parsePvp (showPvp v) === Just v

-- | Bumping the second digit of a two-part version works without four components.
prop_bump_short_second :: Property
prop_bump_short_second = H.propertyOnce $ do
  bumpPvp breakingBump (Pvp (1 :| [0])) === Pvp (1 :| [1])

-- | Bumping the fourth digit of a two-part version extends it to four components.
prop_bump_short_fourth :: Property
prop_bump_short_fourth = H.propertyOnce $ do
  bumpPvp patchBump (Pvp (1 :| [0])) === pvp 1 0 0 1

-- | Bumping the first digit increments A and zeros everything after.
prop_bump_first :: Property
prop_bump_first = H.propertyOnce $ do
  let firstDigitBump = Pvp (1 :| [0, 0, 0])
  bumpPvp firstDigitBump (pvp 8 4 1 2) === pvp 9 0 0 0

-- | Different-length versions: 1.0 < 1.0.0.0 under derived Ord.
-- This documents the current behaviour -- PVP considers them equivalent,
-- but our Ord is lexicographic-then-length.
prop_ord_different_length :: Property
prop_ord_different_length = H.propertyOnce $ do
  H.assert $ Pvp (1 :| [0]) < Pvp (1 :| [0, 0, 0])
  H.assert $ Pvp (1 :| [0, 0, 0]) > Pvp (1 :| [0])
  -- Same-length comparison still works normally
  H.assert $ pvp 1 0 0 0 == pvp 1 0 0 0
  H.assert $ pvp 1 0 0 1 > pvp 1 0 0 0

-- | Leading zeros in version components are silently stripped by parsePvp.
-- parsePvp "01.02.03" succeeds but showPvp gives "1.2.3".
prop_leading_zeros :: Property
prop_leading_zeros = H.propertyOnce $ do
  fmap showPvp (parsePvp "01.02.03") === Just "1.2.3"
  -- The parsed value equals the non-leading-zero version
  parsePvp "01.02.03" === parsePvp "1.2.3"

-- | For any random PVP and bump level, bumping never decreases the version.
prop_bump_monotonic :: Property
prop_bump_monotonic = H.property $ do
  v <- forAll genPvp
  bump <- forAll genBump
  H.assert $ bumpPvp bump v >= v

genBump :: Gen Pvp
genBump =
  Gen.element [noBump, patchBump, featureBump, breakingBump]

genPvp :: Gen Pvp
genPvp = do
  len <- Gen.int (Range.linear 1 6)
  cs <- Gen.list (Range.singleton len) (Gen.int (Range.linear 0 99))
  case cs of
    (c : rest) -> pure (Pvp (c :| rest))
    [] -> pure (Pvp (0 :| []))
