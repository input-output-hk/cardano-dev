module Main where

import Test.Herald.E2E.Batch qualified as Batch
import Test.Herald.E2E.Batch.PerProject qualified as Batch.PerProject
import Test.Herald.E2E.Fragment qualified as Fragment
import Test.Herald.E2E.Fragment.PerProject qualified as Fragment.PerProject
import Test.Herald.E2E.Init qualified as Init
import Test.Herald.E2E.Next qualified as Next
import Test.Herald.E2E.Validate qualified as Validate
import Test.Herald.E2E.Validate.PerProject qualified as Validate.PerProject
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "herald-e2e"
      [ Batch.tests
      , Batch.PerProject.tests
      , Validate.tests
      , Validate.PerProject.tests
      , Init.tests
      , Fragment.tests
      , Fragment.PerProject.tests
      , Next.tests
      ]
