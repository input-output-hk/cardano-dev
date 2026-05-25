module Main where

import Test.Herald.Cabal qualified as Cabal
import Test.Herald.Changelog qualified as Changelog
import Test.Herald.Config qualified as Config
import Test.Herald.Config.ChangesDir qualified as Config.ChangesDir
import Test.Herald.Fragment qualified as Fragment
import Test.Herald.Git qualified as Git
import Test.Herald.Pvp qualified as Pvp
import Test.Herald.Render qualified as Render
import Test.Herald.Terminal qualified as Terminal
import Test.Herald.VersionFile qualified as VersionFile
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "herald"
      [ Pvp.tests
      , Fragment.tests
      , Config.tests
      , Config.ChangesDir.tests
      , Render.tests
      , Cabal.tests
      , Changelog.tests
      , Git.tests
      , Terminal.tests
      , VersionFile.tests
      ]
