module Test.Herald.E2E.Next (tests) where

import Control.Exception (catch)
import Data.Map.Strict qualified as Map
import Data.Yaml qualified as Yaml
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Fixtures (pvp, testConfigMultiProject)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Command.Next (nextVersion)
import Herald.Types (Config (..), Fragment (..), HeraldException (..), ProjectConfig (..))

tests :: TestTree
tests =
  testGroup
    "Next"
    [ testProperty "next with no fragments returns Nothing" prop_next_no_fragments
    , testProperty "next with no .cabal file returns Nothing" prop_next_no_cabal
    , testProperty "next computes expected version" prop_next_computes_version
    , testProperty "next rejects invalid fragments" prop_next_invalid_fragment
    , testProperty "next with unknown project is rejected" prop_next_unknown_project
    , testProperty "next with multiple kinds picks max bump" prop_next_multiple_kinds
    ]

-- | nextVersion with no unreleased fragments returns Nothing.
prop_next_no_fragments :: Property
prop_next_no_fragments = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-next" $ \tmpDir -> do
    let changesDir = tmpDir </> ".changes"
        pkgDir = tmpDir </> "cardano-api"
    createDirectoryIfMissing True changesDir
    createDirectoryIfMissing True pkgDir
    writeFile
      (pkgDir </> "cardano-api.cabal")
      "cabal-version: 3.0\nname: cardano-api\nversion: 8.4.1.2\n"
    -- No fragment files
    nextVersion testConfigMultiProject tmpDir "cardano-api"

  result === Nothing

-- | nextVersion with no .cabal file returns Nothing.
prop_next_no_cabal :: Property
prop_next_no_cabal = H.propertyOnce $ do
  let noCabalConfig =
        testConfigMultiProject
          { configProjects =
              Map.fromList
                [
                  ( "cardano-api"
                  , ProjectConfig
                      { projectChangelog = "cardano-api/CHANGELOG.md"
                      , projectCabalFile = Nothing
                      }
                  )
                ]
          }
  result <- H.evalIO $ withSystemTempDirectory "herald-next" $ \tmpDir -> do
    let changesDir = tmpDir </> ".changes"
    createDirectoryIfMissing True changesDir
    Yaml.encodeFile
      (changesDir </> "42-fix.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Fix"
        , fragmentPR = 42
        }
    nextVersion noCabalConfig tmpDir "cardano-api"

  result === Nothing

-- | nextVersion with fragments computes the correct bumped version.
prop_next_computes_version :: Property
prop_next_computes_version = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-next" $ \tmpDir -> do
    let changesDir = tmpDir </> ".changes"
        pkgDir = tmpDir </> "cardano-api"
    createDirectoryIfMissing True changesDir
    createDirectoryIfMissing True pkgDir
    writeFile
      (pkgDir </> "cardano-api.cabal")
      "cabal-version: 3.0\nname: cardano-api\nversion: 8.4.1.2\n"
    Yaml.encodeFile
      (changesDir </> "42-fix.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["breaking"]
        , fragmentDescription = "Breaking change"
        , fragmentPR = 42
        }
    nextVersion testConfigMultiProject tmpDir "cardano-api"

  result === Just (pvp 8 5 0 0)

-- | A fragment with an unknown kind causes next to fail rather than silently
-- ignoring the invalid kind.
prop_next_invalid_fragment :: Property
prop_next_invalid_fragment = H.propertyOnce $ do
  caught <- H.evalIO $ withSystemTempDirectory "herald-next" $ \tmpDir -> do
    let changesDir = tmpDir </> ".changes"
        pkgDir = tmpDir </> "cardano-api"
    createDirectoryIfMissing True changesDir
    createDirectoryIfMissing True pkgDir
    writeFile
      (pkgDir </> "cardano-api.cabal")
      "cabal-version: 3.0\nname: cardano-api\nversion: 8.4.1.2\n"
    Yaml.encodeFile
      (changesDir </> "999-bad-kind.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["nonexistent-kind"]
        , fragmentDescription = "This should fail"
        , fragmentPR = 999
        }
    (nextVersion testConfigMultiProject tmpDir "cardano-api" >> pure False)
      `catch` \(HeraldException _) -> pure True

  H.assert caught

-- | nextVersion with an unknown project throws a HeraldException.
prop_next_unknown_project :: Property
prop_next_unknown_project = H.propertyOnce $ do
  caught <- H.evalIO $ withSystemTempDirectory "herald-next" $ \tmpDir -> do
    createDirectoryIfMissing True $ tmpDir </> ".changes"
    (nextVersion testConfigMultiProject tmpDir "nonexistent-project" >> pure False)
      `catch` \(HeraldException _) -> pure True

  H.assert caught

-- | nextVersion with fragments of different kinds picks the maximum bump.
-- bugfix (patch) + feature (minor) -> feature bump wins.
prop_next_multiple_kinds :: Property
prop_next_multiple_kinds = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-next" $ \tmpDir -> do
    let changesDir = tmpDir </> ".changes"
        pkgDir = tmpDir </> "cardano-api"
    createDirectoryIfMissing True changesDir
    createDirectoryIfMissing True pkgDir
    writeFile
      (pkgDir </> "cardano-api.cabal")
      "cabal-version: 3.0\nname: cardano-api\nversion: 8.4.1.2\n"
    Yaml.encodeFile
      (changesDir </> "42-fix.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Fix something"
        , fragmentPR = 42
        }
    Yaml.encodeFile
      (changesDir </> "99-feature.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["feature"]
        , fragmentDescription = "New feature"
        , fragmentPR = 99
        }
    nextVersion testConfigMultiProject tmpDir "cardano-api"

  -- Feature bump (0.0.1.0) > bugfix (0.0.0.1), so 8.4.1.2 -> 8.4.2.0
  result === Just (pvp 8 4 2 0)
