module Test.Herald.Changelog (tests) where

import Data.Text qualified as T
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Hedgehog (Property)
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Changelog (prependSection)

tests :: TestTree
tests =
  testGroup
    "Herald.Changelog"
    [ testProperty "prepend before existing ## header" prop_prepend_before_header
    , testProperty "no ## header appends at end" prop_no_header_appends
    , testProperty "preamble before ## is preserved" prop_preamble_preserved
    ]

-- | Section is inserted before the first ## header.
prop_prepend_before_header :: Property
prop_prepend_before_header = H.propertyOnce $ do
  content <- H.evalIO $ withSystemTempDirectory "herald-changelog" $ \tmpDir -> do
    let path = tmpDir </> "CHANGELOG.md"
    writeFile path "## 1.0.0.0\n\n- Old entry\n"
    prependSection path "## 2.0.0.0 -- 2026-04-01\n\n- New entry\n"
    T.pack <$> readFile path
  let idxNew = T.length . fst $ T.breakOn "## 2.0.0.0" content
      idxOld = T.length . fst $ T.breakOn "## 1.0.0.0" content
  H.assertWith (idxNew, idxOld) $ uncurry (<)
  content `shouldContain` "Old entry"
  content `shouldContain` "New entry"

-- | When the file has no ## header, the section is appended at the end.
prop_no_header_appends :: Property
prop_no_header_appends = H.propertyOnce $ do
  content <- H.evalIO $ withSystemTempDirectory "herald-changelog" $ \tmpDir -> do
    let path = tmpDir </> "CHANGELOG.md"
    writeFile path "# My Project Changelog\n\nSome introductory text.\n"
    prependSection path "## 1.0.0.0 -- 2026-04-01\n\n- First release\n"
    T.pack <$> readFile path
  content `shouldContain` "# My Project Changelog"
  content `shouldContain` "Some introductory text."
  content `shouldContain` "## 1.0.0.0"
  content `shouldContain` "First release"

-- | Preamble text before the first ## header is preserved above the new section.
prop_preamble_preserved :: Property
prop_preamble_preserved = H.propertyOnce $ do
  content <- H.evalIO $ withSystemTempDirectory "herald-changelog" $ \tmpDir -> do
    let path = tmpDir </> "CHANGELOG.md"
    writeFile path "# Changelog\n\n## 1.0.0.0\n\n- Old entry\n"
    prependSection path "## 2.0.0.0 -- 2026-04-01\n\n- New entry\n"
    T.pack <$> readFile path
  -- Preamble should come first, then new section, then old section
  let idxPreamble = T.length . fst $ T.breakOn "# Changelog" content
      idxNew = T.length . fst $ T.breakOn "## 2.0.0.0" content
      idxOld = T.length . fst $ T.breakOn "## 1.0.0.0" content
  H.assertWith (idxPreamble, idxNew) $ uncurry (<)
  H.assertWith (idxNew, idxOld) $ uncurry (<)
