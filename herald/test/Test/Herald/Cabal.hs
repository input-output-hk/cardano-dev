module Test.Herald.Cabal (tests) where

import Data.Text qualified as T
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain)
import Test.Herald.Fixtures (pvp)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Cabal (readCabalVersion, writeCabalVersion)

tests :: TestTree
tests =
  testGroup
    "Herald.Cabal"
    [ testProperty "read version from .cabal" prop_read_version
    , testProperty "read version with spaces" prop_read_version_spaces
    , testProperty "no version line returns Nothing" prop_read_no_version
    , testProperty "write version preserves file" prop_write_preserves
    , testProperty "write then read roundtrip" prop_write_read_roundtrip
    ]

sampleCabal :: String
sampleCabal =
  unlines
    [ "cabal-version: 3.0"
    , "name:          cardano-api"
    , "version:       8.4.1.2"
    , "synopsis:      Test package"
    , ""
    , "library"
    , "  build-depends: base"
    ]

sampleCabalSpaces :: String
sampleCabalSpaces =
  unlines
    [ "cabal-version: 3.0"
    , "name:          cardano-api"
    , "version:        8.4.1.2"
    , "synopsis:      Test package"
    ]

-- | A .cabal file without a version: line returns Nothing.
prop_read_no_version :: Property
prop_read_no_version = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-test" $ \tmpDir -> do
    let cabalFile = tmpDir </> "test.cabal"
    writeFile cabalFile $ unlines ["cabal-version: 3.0", "name: test-pkg", "synopsis: No version"]
    readCabalVersion cabalFile
  result === Nothing

-- | Extracts the version from a standard .cabal file.
prop_read_version :: Property
prop_read_version = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-test" $ \tmpDir -> do
    let cabalFile = tmpDir </> "test.cabal"
    writeFile cabalFile sampleCabal
    readCabalVersion cabalFile
  result === Just (pvp 8 4 1 2)

-- | Extra whitespace around the version value is tolerated.
prop_read_version_spaces :: Property
prop_read_version_spaces = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-test" $ \tmpDir -> do
    let cabalFile = tmpDir </> "test.cabal"
    writeFile cabalFile sampleCabalSpaces
    readCabalVersion cabalFile
  result === Just (pvp 8 4 1 2)

-- | Writing a new version updates the version: line but preserves all other content.
prop_write_preserves :: Property
prop_write_preserves = H.propertyOnce $ do
  content <- H.evalIO $ withSystemTempDirectory "herald-test" $ \tmpDir -> do
    let cabalFile = tmpDir </> "test.cabal"
    writeFile cabalFile sampleCabal
    writeCabalVersion cabalFile (pvp 9 0 0 0)
    T.pack <$> readFile cabalFile
  content `shouldContain` "version:"
  content `shouldContain` "9.0.0.0"
  content `shouldContain` "name:          cardano-api"
  content `shouldContain` "synopsis:      Test package"
  content `shouldContain` "build-depends: base"

-- | write followed by read recovers the written version.
prop_write_read_roundtrip :: Property
prop_write_read_roundtrip = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTmpDirectory "herald-test" $ \tmpDir -> do
    let cabalFile = tmpDir </> "test.cabal"
    writeFile cabalFile sampleCabal
    writeCabalVersion cabalFile (pvp 9 0 0 0)
    readCabalVersion cabalFile
  result === Just (pvp 9 0 0 0)
 where
  -- withSystemTmpDirectory is just an alias for clarity in this context
  withSystemTmpDirectory = withSystemTempDirectory
