module Test.Herald.VersionFile (tests) where

import Control.Exception (bracket, catch)
import Data.ByteString qualified as BS
import Data.List.NonEmpty (NonEmpty (..))
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import System.FilePath ((</>))
import System.IO (IOMode (..), hClose, hFlush, openFile, stderr)
import System.IO.Temp (withSystemTempDirectory)

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Fixtures (pvp)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Pvp (Pvp (..))
import Herald.Types (HeraldException (..))
import Herald.VersionFile (readVersionFile, writeVersionFile)

tests :: TestTree
tests =
  testGroup
    "Herald.VersionFile"
    [ testGroup
        "readVersionFile"
        [ testProperty "read valid version" prop_read_valid
        , testProperty "read version with surrounding whitespace" prop_read_whitespace
        , testProperty "read version with BOM" prop_read_bom
        , testProperty "read version with CRLF" prop_read_crlf
        , testProperty "read three-component version" prop_read_three_components
        , testProperty "read empty file returns 0.0.0.0" prop_read_empty
        , testProperty "read missing file returns 0.0.0.0" prop_read_missing
        , testProperty "read empty file warns on stderr" prop_read_empty_warns
        , testProperty "read missing file warns on stderr" prop_read_missing_warns
        , testProperty "read file with extra text is an error" prop_read_extra_text
        , testProperty "read file with comment line is an error" prop_read_comment
        , testProperty "read file with multiple lines is an error" prop_read_multiple_lines
        ]
    , testGroup
        "writeVersionFile"
        [ testProperty "write then read roundtrip" prop_write_read_roundtrip
        , testProperty "write creates file if missing" prop_write_creates_file
        , testProperty "write overwrites existing content" prop_write_overwrites
        ]
    ]

-- | Read a valid version from a plain text file.
prop_read_valid :: Property
prop_read_valid = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf "1.2.3.4\n"
    readVersionFile vf
  result === pvp 1 2 3 4

-- | Leading and trailing whitespace is stripped.
prop_read_whitespace :: Property
prop_read_whitespace = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf "  1.2.3.4  \n"
    readVersionFile vf
  result === pvp 1 2 3 4

-- | UTF-8 BOM is stripped before parsing.
prop_read_bom :: Property
prop_read_bom = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    BS.writeFile vf $ BS.pack [0xEF, 0xBB, 0xBF] <> "1.2.3.4\n"
    readVersionFile vf
  result === pvp 1 2 3 4

-- | CRLF line endings are handled.
prop_read_crlf :: Property
prop_read_crlf = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf "1.2.3.4\r\n"
    readVersionFile vf
  result === pvp 1 2 3 4

-- | Three-component PVP versions are accepted.
prop_read_three_components :: Property
prop_read_three_components = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf "1.2.3\n"
    readVersionFile vf
  result === Pvp (1 :| [2, 3])

-- | An empty file is treated as version 0.0.0.0.
prop_read_empty :: Property
prop_read_empty = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf ""
    readVersionFile vf
  result === pvp 0 0 0 0

-- | A missing file is treated as version 0.0.0.0.
prop_read_missing :: Property
prop_read_missing = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir ->
    readVersionFile $ tmpDir </> "nonexistent.txt"
  result === pvp 0 0 0 0

-- | Extra text on the version line is a parse error.
prop_read_extra_text :: Property
prop_read_extra_text = H.propertyOnce $ do
  caught <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf "1.0.0.0 # initial\n"
    (readVersionFile vf >> pure False)
      `catch` \(HeraldException _) -> pure True
  H.assertWith caught id

-- | A file with a comment line is a parse error.
prop_read_comment :: Property
prop_read_comment = H.propertyOnce $ do
  caught <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf "# version\n1.0.0.0\n"
    (readVersionFile vf >> pure False)
      `catch` \(HeraldException _) -> pure True
  H.assertWith caught id

-- | Multiple non-empty lines are a parse error.
prop_read_multiple_lines :: Property
prop_read_multiple_lines = H.propertyOnce $ do
  caught <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf "1.0.0.0\n2.0.0.0\n"
    (readVersionFile vf >> pure False)
      `catch` \(HeraldException _) -> pure True
  H.assertWith caught id

-- | Write followed by read recovers the written version.
prop_write_read_roundtrip :: Property
prop_write_read_roundtrip = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf "1.0.0.0\n"
    writeVersionFile vf (pvp 2 0 0 0)
    readVersionFile vf
  result === pvp 2 0 0 0

-- | Writing to a non-existent file creates it.
prop_write_creates_file :: Property
prop_write_creates_file = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeVersionFile vf (pvp 3 0 0 0)
    readVersionFile vf
  result === pvp 3 0 0 0

-- | Writing overwrites existing content entirely with just version + newline.
prop_write_overwrites :: Property
prop_write_overwrites = H.propertyOnce $ do
  content <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf "old junk content\n1.0.0.0\nmore stuff\n"
    writeVersionFile vf (pvp 5 0 0 0)
    readFile vf
  content === "5.0.0.0\n"

-- | Reading an empty version file emits a warning to stderr.
prop_read_empty_warns :: Property
prop_read_empty_warns = H.propertyOnce $ do
  (_, captured) <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir -> do
    let vf = tmpDir </> "version.txt"
    writeFile vf ""
    captureStderr $ readVersionFile vf
  H.assertWith captured $ not . null

-- | Reading a missing version file emits a warning to stderr.
prop_read_missing_warns :: Property
prop_read_missing_warns = H.propertyOnce $ do
  (_, captured) <- H.evalIO $ withSystemTempDirectory "herald-vf" $ \tmpDir ->
    captureStderr . readVersionFile $ tmpDir </> "nonexistent.txt"
  H.assertWith captured $ not . null

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

captureStderr :: IO a -> IO (a, String)
captureStderr action = withSystemTempDirectory "stderr-capture" $ \dir -> do
  let path = dir </> "stderr.txt"
  bracket
    ( do
        origH <- hDuplicate stderr
        writeH <- openFile path WriteMode
        hDuplicateTo writeH stderr
        hClose writeH
        pure origH
    )
    ( \origH -> do
        hFlush stderr
        hDuplicateTo origH stderr
        hClose origH
    )
    ( \_ -> do
        result <- action
        hFlush stderr
        captured <- readFile path
        length captured `seq` pure (result, captured)
    )
