module Test.Herald.Config (tests) where

import Data.ByteString (isInfixOf)
import Data.Text.Encoding (encodeUtf8)
import Data.Yaml (decodeEither', encode)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Config (loadConfig)
import Herald.Types (KindDef (..))

tests :: TestTree
tests =
  testGroup
    "Herald.Config"
    [ testGroup
        "KindDef parsing"
        [ testProperty "notable defaults to true when omitted" prop_notable_default
        , testProperty "notable false is parsed" prop_notable_false
        , testProperty "description is parsed when present" prop_description_present
        , testProperty "description is absent when omitted" prop_description_absent
        ]
    , testGroup
        "Config loading"
        [ testProperty "missing required fields produces parse error" prop_load_missing_fields
        ]
    , testGroup
        "KindDef serialization"
        [ testProperty "notable true is omitted from output" prop_serialize_notable_true
        , testProperty "notable false is present in output" prop_serialize_notable_false
        , testProperty "description is omitted when Nothing" prop_serialize_no_description
        , testProperty "description is present when Just" prop_serialize_with_description
        ]
    ]

-- | When 'notable' is absent from YAML, it defaults to True.
prop_notable_default :: Property
prop_notable_default = H.propertyOnce $ do
  kd <- H.leftFail . decodeEither' . encodeUtf8 $ "bump: 0.0.0.1\n"
  kindNotable kd === True

-- | Explicit 'notable: false' is parsed correctly.
prop_notable_false :: Property
prop_notable_false = H.propertyOnce $ do
  kd <- H.leftFail . decodeEither' . encodeUtf8 $ "notable: false\nbump: 0.0.0.1\n"
  kindNotable kd === False

-- | The 'description' field is parsed when present.
prop_description_present :: Property
prop_description_present = H.propertyOnce $ do
  kd <- H.leftFail . decodeEither' . encodeUtf8 $ "bump: 0.0.0.1\ndescription: fixes a defect\n"
  kindDescription kd === Just "fixes a defect"

-- | The 'description' field is Nothing when omitted.
prop_description_absent :: Property
prop_description_absent = H.propertyOnce $ do
  kd <- H.leftFail . decodeEither' . encodeUtf8 $ "bump: 0.0.0.1\n"
  kindDescription kd === Nothing

-- | When notable is True (default), the key is omitted from serialized output.
prop_serialize_notable_true :: Property
prop_serialize_notable_true = H.propertyOnce $ do
  kd <- H.leftFail . decodeEither' . encodeUtf8 $ "bump: 0.1.0.0\n"
  let output = encode (kd :: KindDef)
  H.assert . not $ isInfixOf "notable" output
  -- Roundtrip preserves the value
  kd2 <- H.leftFail $ decodeEither' output
  kindNotable kd2 === True
  kindBump kd === kindBump kd2

-- | When notable is False, it appears in serialized output.
prop_serialize_notable_false :: Property
prop_serialize_notable_false = H.propertyOnce $ do
  kd <- H.leftFail . decodeEither' . encodeUtf8 $ "notable: false\nbump: 0.0.1.0\n"
  let output = encode (kd :: KindDef)
  kd2 <- H.leftFail $ decodeEither' output
  kindNotable kd2 === False

-- | description: Nothing roundtrips correctly (key omitted).
prop_serialize_no_description :: Property
prop_serialize_no_description = H.propertyOnce $ do
  kd <- H.leftFail . decodeEither' . encodeUtf8 $ "bump: 0.0.0.1\n"
  let output = encode (kd :: KindDef)
  kd2 <- H.leftFail $ decodeEither' output
  kindDescription kd2 === Nothing

-- | description: Just roundtrips correctly.
prop_serialize_with_description :: Property
prop_serialize_with_description = H.propertyOnce $ do
  kd <- H.leftFail . decodeEither' . encodeUtf8 $ "bump: 0.0.0.1\ndescription: fixes a defect\n"
  let output = encode (kd :: KindDef)
  kd2 <- H.leftFail $ decodeEither' output
  kindDescription kd2 === Just "fixes a defect"

-- | A YAML config with missing required fields returns Left.
prop_load_missing_fields :: Property
prop_load_missing_fields = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-config" $ \tmpDir -> do
    let configPath = tmpDir </> ".herald.yml"
    -- Missing 'projects' and 'kinds' fields
    writeFile configPath "git-repo: test/repo\nchanges-dir: .changes\n"
    loadConfig configPath

  case result of
    Left _ -> H.success
    Right _ -> H.failure
