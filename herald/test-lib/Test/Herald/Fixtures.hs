-- | Shared test data for Herald test suites.
module Test.Herald.Fixtures
  ( -- * PVP helpers
    pvp
  , breakingBump
  , featureBump
  , patchBump
  , noBump

    -- * Shared fixtures
  , testKinds
  , testDay
  , testVersion
  , testConfig
  , testConfigMultiProject
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Time (Day, fromGregorian)

import Herald.Pvp (Pvp (..))
import Herald.Types (Config (..), KindDef (..), ProjectConfig (..), VersionSource (..))

-- | Construct a four-component PVP version.
pvp :: Int -> Int -> Int -> Int -> Pvp
pvp a b c d = Pvp (a :| [b, c, d])

-- | Bump the second digit (A.B.0.0) -- breaking change.
breakingBump :: Pvp
breakingBump = pvp 0 1 0 0

-- | Bump the third digit (A.B.C.0) -- new feature / compatible change.
featureBump :: Pvp
featureBump = pvp 0 0 1 0

-- | Bump the fourth digit (A.B.C.D) -- bugfix / patch.
patchBump :: Pvp
patchBump = pvp 0 0 0 1

-- | All-zero bump level -- identity (no version change).
noBump :: Pvp
noBump = pvp 0 0 0 0

-- | Standard set of kinds used across tests.
testKinds :: Map Text KindDef
testKinds =
  Map.fromList
    [ ("breaking", KindDef True breakingBump (Just "the API has changed in a breaking way"))
    , ("feature", KindDef True featureBump (Just "introduces a new feature"))
    , ("bugfix", KindDef True patchBump (Just "fixes a defect"))
    , ("refactoring", KindDef False patchBump Nothing)
    , ("test", KindDef False patchBump Nothing)
    ]

testDay :: Day
testDay = fromGregorian 2026 3 25

testVersion :: Pvp
testVersion = pvp 8 5 0 0

-- | Config with a single project (cardano-api).
testConfig :: Config
testConfig =
  Config
    { configGitRepo = "https://github.com/IntersectMBO/cardano-api"
    , configChangesDir = Just ".changes"
    , configKinds = testKinds
    , configProjects =
        Map.fromList
          [
            ( "cardano-api"
            , ProjectConfig "cardano-api/CHANGELOG.md" (Just $ CabalFile "cardano-api/cardano-api.cabal") Nothing
            )
          ]
    }

-- | Config with two projects (for e2e / batch tests).
testConfigMultiProject :: Config
testConfigMultiProject =
  testConfig
    { configProjects =
        Map.fromList
          [
            ( "cardano-api"
            , ProjectConfig "cardano-api/CHANGELOG.md" (Just $ CabalFile "cardano-api/cardano-api.cabal") Nothing
            )
          ,
            ( "cardano-api-gen"
            , ProjectConfig
                "cardano-api-gen/CHANGELOG.md"
                (Just $ CabalFile "cardano-api-gen/cardano-api-gen.cabal")
                Nothing
            )
          ]
    }
