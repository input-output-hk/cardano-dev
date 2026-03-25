-- | Hedgehog assertion helpers with informative failure messages.
module Test.Herald.Assertions
  ( shouldContain
  , shouldNotContain
  , shouldFail
  , shouldPass
  , shouldSatisfy
  )
where

import Data.Text (Text)
import Data.Text qualified as T

import Hedgehog (MonadTest, (===))
import Hedgehog qualified as H

-- | Assert that @haystack@ contains @needle@ as a substring.
-- On failure, shows both the expected needle and actual text.
shouldContain :: MonadTest m => Text -> Text -> m ()
shouldContain haystack needle = do
  H.annotate $ "Expected to contain: " <> T.unpack needle
  H.annotate $ "Actual:\n" <> T.unpack haystack
  H.assert $ T.isInfixOf needle haystack

-- | Assert that @haystack@ does NOT contain @needle@ as a substring.
shouldNotContain :: MonadTest m => Text -> Text -> m ()
shouldNotContain haystack needle = do
  H.annotate $ "Expected NOT to contain: " <> T.unpack needle
  H.annotate $ "Actual:\n" <> T.unpack haystack
  H.assert . not $ T.isInfixOf needle haystack

-- | Assert that a list of errors is non-empty (i.e. validation failed as expected).
shouldFail :: (MonadTest m, Show a) => [a] -> m ()
shouldFail xs = do
  H.annotate $ "Expected non-empty error list, got: " <> show xs
  H.assert . not $ null xs

-- | Assert that a list of errors is empty (i.e. validation passed).
-- Uses '===' so Hedgehog shows the diff on failure.
shouldPass :: (MonadTest m, Show a, Eq a) => [a] -> m ()
shouldPass xs = xs === []

-- | Assert that a predicate holds, with a custom annotation.
shouldSatisfy :: (MonadTest m, Show a) => a -> (a -> Bool) -> m ()
shouldSatisfy x p = do
  H.annotate $ "Value: " <> show x
  H.assert $ p x
