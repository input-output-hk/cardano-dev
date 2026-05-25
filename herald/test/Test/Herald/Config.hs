module Test.Herald.Config (tests) where

import Data.ByteString (isInfixOf)
import Data.Functor (void)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Yaml (decodeEither', encode)
import Data.Yaml qualified as Yaml
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Config (loadConfig)
import Herald.Types (KindDef (..), ProjectConfig (..), VersionSource (..))

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
        "ProjectConfig version source"
        [ testProperty "cabal-file is parsed" prop_project_cabal_file
        , testProperty "version-file is parsed" prop_project_version_file
        , testProperty "neither version source is parsed" prop_project_no_version_source
        , testProperty "both cabal-file and version-file is rejected" prop_project_both_rejected
        , testProperty "cabal-file roundtrips" prop_serialize_cabal_file
        , testProperty "version-file roundtrips" prop_serialize_version_file
        , testProperty "no version source roundtrips" prop_serialize_no_version_source
        ]
    , testGroup
        "Config loading with version-file"
        [ testProperty "config with version-file project loads" prop_load_version_file_config
        , testProperty "config with both version sources fails early" prop_load_both_fails
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
  H.assertWith output $ not . isInfixOf "notable"
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

-------------------------------------------------------------------------------
-- ProjectConfig version source parsing
-------------------------------------------------------------------------------

-- | A project with only cabal-file parses to CabalFile.
prop_project_cabal_file :: Property
prop_project_cabal_file = H.propertyOnce $ do
  pc <- H.leftFail . decodeEither' . encodeUtf8 $ "changelog: CHANGELOG.md\ncabal-file: foo.cabal\n"
  projectVersionSource (pc :: ProjectConfig) === Just (CabalFile "foo.cabal")

-- | A project with only version-file parses to VersionFile.
prop_project_version_file :: Property
prop_project_version_file = H.propertyOnce $ do
  pc <-
    H.leftFail . decodeEither' . encodeUtf8 $ "changelog: CHANGELOG.md\nversion-file: version.txt\n"
  projectVersionSource (pc :: ProjectConfig) === Just (VersionFile "version.txt")

-- | A project with neither version source parses to Nothing.
prop_project_no_version_source :: Property
prop_project_no_version_source = H.propertyOnce $ do
  pc <- H.leftFail . decodeEither' . encodeUtf8 $ "changelog: CHANGELOG.md\n"
  projectVersionSource (pc :: ProjectConfig) === Nothing

-- | A project with both cabal-file and version-file is rejected at parse time
-- with a clear error message mentioning both fields.
prop_project_both_rejected :: Property
prop_project_both_rejected = H.propertyOnce $ do
  let yaml = "changelog: CHANGELOG.md\ncabal-file: foo.cabal\nversion-file: version.txt\n"
  case decodeEither' (encodeUtf8 yaml) :: Either Yaml.ParseException ProjectConfig of
    Left err -> do
      let msg = T.pack $ Yaml.prettyPrintParseException err
      msg `shouldContain` "cabal-file"
      msg `shouldContain` "version-file"
    Right _ -> H.failure

-- | CabalFile roundtrips through serialization.
prop_serialize_cabal_file :: Property
prop_serialize_cabal_file = H.propertyOnce $ do
  pc <- H.leftFail . decodeEither' . encodeUtf8 $ "changelog: CHANGELOG.md\ncabal-file: foo.cabal\n"
  let output = encode (pc :: ProjectConfig)
  pc2 <- H.leftFail $ decodeEither' output
  projectVersionSource pc2 === Just (CabalFile "foo.cabal")
  projectChangelog pc2 === "CHANGELOG.md"

-- | VersionFile roundtrips through serialization using flat YAML keys.
prop_serialize_version_file :: Property
prop_serialize_version_file = H.propertyOnce $ do
  pc <-
    H.leftFail . decodeEither' . encodeUtf8 $ "changelog: CHANGELOG.md\nversion-file: version.txt\n"
  let output = encode (pc :: ProjectConfig)
  H.assertWith output $ isInfixOf "version-file:"
  pc2 <- H.leftFail $ decodeEither' output
  projectVersionSource pc2 === Just (VersionFile "version.txt")

-- | No version source roundtrips correctly.
prop_serialize_no_version_source :: Property
prop_serialize_no_version_source = H.propertyOnce $ do
  pc <- H.leftFail . decodeEither' . encodeUtf8 $ "changelog: CHANGELOG.md\n"
  let output = encode (pc :: ProjectConfig)
  pc2 <- H.leftFail $ decodeEither' output
  projectVersionSource pc2 === Nothing

-------------------------------------------------------------------------------
-- Config loading with version-file
-------------------------------------------------------------------------------

-- | A full config with a version-file project loads successfully.
prop_load_version_file_config :: Property
prop_load_version_file_config = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-config" $ \tmpDir -> do
    let configPath = tmpDir </> ".herald.yml"
    writeFile configPath $
      unlines
        [ "git-repo: test/repo"
        , "changes-dir: .changes"
        , "kinds:"
        , "  bugfix:"
        , "    bump: 0.0.0.1"
        , "projects:"
        , "  my-action:"
        , "    changelog: actions/my-action/CHANGELOG.md"
        , "    version-file: actions/my-action/version.txt"
        ]
    loadConfig configPath

  void $ H.leftFail result

-- | A config where a project has both cabal-file and version-file fails to load
-- with a message mentioning both fields.
prop_load_both_fails :: Property
prop_load_both_fails = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-config" $ \tmpDir -> do
    let configPath = tmpDir </> ".herald.yml"
    writeFile configPath $
      unlines
        [ "git-repo: test/repo"
        , "changes-dir: .changes"
        , "kinds:"
        , "  bugfix:"
        , "    bump: 0.0.0.1"
        , "projects:"
        , "  my-project:"
        , "    changelog: CHANGELOG.md"
        , "    cabal-file: my-project.cabal"
        , "    version-file: version.txt"
        ]
    loadConfig configPath

  case result of
    Left err -> do
      let msg = T.pack err
      msg `shouldContain` "cabal-file"
      msg `shouldContain` "version-file"
    Right _ -> H.failure
