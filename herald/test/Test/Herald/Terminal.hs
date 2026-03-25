module Test.Herald.Terminal (tests) where

import Data.Text qualified as T

import Hedgehog (Property, (===))
import Hedgehog.Extras qualified as H
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Terminal (stripAnsi)

tests :: TestTree
tests =
  testGroup
    "Herald.Terminal"
    [ testProperty "stripAnsi removes arrow key escape sequences" prop_strip_arrow_keys
    , testProperty "stripAnsi removes colour codes" prop_strip_colour
    , testProperty "stripAnsi preserves plain text" prop_strip_plain
    , testProperty "stripAnsi handles mixed content" prop_strip_mixed
    , testProperty "stripAnsi handles truncated escape sequence" prop_strip_truncated
    ]

-- | Arrow-key escapes (\ESC[A, \ESC[B, etc.) are stripped completely.
prop_strip_arrow_keys :: Property
prop_strip_arrow_keys = H.propertyOnce $ do
  stripAnsi "hello\ESC[Aworld" === "helloworld"
  stripAnsi "\ESC[B\ESC[Afoo" === "foo"
  stripAnsi "start\ESC[C\ESC[Dend" === "startend"

-- | SGR colour codes (\ESC[31m, \ESC[1;32m, etc.) are stripped.
prop_strip_colour :: Property
prop_strip_colour = H.propertyOnce $ do
  stripAnsi "\ESC[31mred\ESC[0m" === "red"
  stripAnsi "\ESC[1;32mbold green\ESC[0m" === "bold green"

-- | Plain text without escape sequences passes through unchanged.
prop_strip_plain :: Property
prop_strip_plain = H.propertyOnce $ do
  stripAnsi "No escape sequences here" === "No escape sequences here"
  stripAnsi "" === T.empty

-- | Mixed plain text and escape sequences: only the escapes are removed.
prop_strip_mixed :: Property
prop_strip_mixed = H.propertyOnce $ do
  stripAnsi "Fix \ESC[Aserialization\ESC[B bug" === "Fix serialization bug"

-- | Truncated escape sequences (no terminal letter) do not crash.
prop_strip_truncated :: Property
prop_strip_truncated = H.propertyOnce $ do
  -- ESC[ with no following letter
  stripAnsi "hello\ESC[" === "hello"
  -- ESC[ with params but no terminal letter
  stripAnsi "hello\ESC[31" === "hello"
  -- Just ESC with no bracket
  stripAnsi "hello\ESC" === "hello\ESC"
