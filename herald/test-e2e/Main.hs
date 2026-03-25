module Main where

import Test.Herald.E2E.Batch qualified as Batch
import Test.Herald.E2E.Fragment qualified as Fragment
import Test.Herald.E2E.Init qualified as Init
import Test.Herald.E2E.Next qualified as Next
import Test.Herald.E2E.Validate qualified as Validate
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "herald-e2e"
      [ Batch.tests
      , Validate.tests
      , Init.tests
      , Fragment.tests
      , Next.tests
      ]
