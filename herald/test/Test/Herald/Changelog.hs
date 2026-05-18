module Test.Herald.Changelog (tests) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Text qualified as T
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Hedgehog (Property)
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain, shouldNotContain)
import Test.Herald.Fixtures (pvp)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Changelog (extractSection, prependSection)
import Herald.Pvp (Pvp (..))

tests :: TestTree
tests =
  testGroup
    "Herald.Changelog"
    [ testGroup
        "prependSection"
        [ testProperty "prepend before existing ## header" prop_prepend_before_header
        , testProperty "no ## header appends at end" prop_no_header_appends
        , testProperty "preamble before ## is preserved" prop_preamble_preserved
        ]
    , testGroup
        "extractSection"
        [ testProperty "AC1: dated headers" prop_extract_dated_headers
        , testProperty "AC2: bare headers" prop_extract_bare_headers
        , testProperty "AC3: mixed-format file" prop_extract_mixed_format
        , testProperty "AC4: version not present" prop_extract_not_found
        , testProperty "AC5: first section after preamble" prop_extract_first_section
        , testProperty "AC6: last section to EOF" prop_extract_last_section
        , testProperty "AC7: version prefix safety" prop_extract_prefix_safety
        , testProperty "AC8: empty section body" prop_extract_empty_section
        , testProperty "AC9: leading/trailing blank lines stripped" prop_extract_trimming
        , testProperty "AC10: sub-headers in body" prop_extract_sub_headers
        , testProperty "AC11: CRLF normalised" prop_extract_crlf
        , testProperty "AC12: duplicate headers returns first" prop_extract_duplicate_headers
        , testProperty "AC13: multiple whitespace after ##" prop_extract_multi_whitespace
        ]
    ]

-- prependSection tests

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

prop_preamble_preserved :: Property
prop_preamble_preserved = H.propertyOnce $ do
  content <- H.evalIO $ withSystemTempDirectory "herald-changelog" $ \tmpDir -> do
    let path = tmpDir </> "CHANGELOG.md"
    writeFile path "# Changelog\n\n## 1.0.0.0\n\n- Old entry\n"
    prependSection path "## 2.0.0.0 -- 2026-04-01\n\n- New entry\n"
    T.pack <$> readFile path
  let idxPreamble = T.length . fst $ T.breakOn "# Changelog" content
      idxNew = T.length . fst $ T.breakOn "## 2.0.0.0" content
      idxOld = T.length . fst $ T.breakOn "## 1.0.0.0" content
  H.assertWith (idxPreamble, idxNew) $ uncurry (<)
  H.assertWith (idxNew, idxOld) $ uncurry (<)

-- extractSection tests

prop_extract_dated_headers :: Property
prop_extract_dated_headers = H.propertyOnce $ do
  let result = extractSection (pvp 2 0 0 0) changelogDated
  body <- H.nothingFail result
  body `shouldContain` "Added new feature X"
  body `shouldContain` "PR 100"

prop_extract_bare_headers :: Property
prop_extract_bare_headers = H.propertyOnce $ do
  let result = extractSection (pvp 11 0 0 0) changelogBare
  body <- H.nothingFail result
  body `shouldContain` "Bump cardano-api"

prop_extract_mixed_format :: Property
prop_extract_mixed_format = H.propertyOnce $ do
  dated <- H.nothingFail $ extractSection (pvp 3 0 0 0) changelogMixed
  dated `shouldContain` "Dated entry"
  bare <- H.nothingFail $ extractSection (pvp 2 0 0 0) changelogMixed
  bare `shouldContain` "Bare entry"
  oldDated <- H.nothingFail $ extractSection (pvp 1 0 0 0) changelogMixed
  oldDated `shouldContain` "Old dated entry"

prop_extract_not_found :: Property
prop_extract_not_found = H.propertyOnce $ do
  let result = extractSection (pvp 9 9 9 9) changelogDated
  result H.=== Nothing

prop_extract_first_section :: Property
prop_extract_first_section = H.propertyOnce $ do
  let cl =
        T.unlines
          [ "# Changelog for foo"
          , ""
          , "Some preamble text."
          , ""
          , "## 1.0.0.0 -- 2026-01-01"
          , ""
          , "- First and only section"
          , ""
          ]
  body <- H.nothingFail $ extractSection (pvp 1 0 0 0) cl
  body `shouldContain` "First and only section"

prop_extract_last_section :: Property
prop_extract_last_section = H.propertyOnce $ do
  let cl =
        T.unlines
          [ "## 2.0.0.0"
          , ""
          , "- Second version"
          , ""
          , "## 1.0.0.0"
          , ""
          , "- First version, last in file"
          , "- Another line"
          ]
  body <- H.nothingFail $ extractSection (pvp 1 0 0 0) cl
  body `shouldContain` "First version, last in file"
  body `shouldContain` "Another line"

prop_extract_prefix_safety :: Property
prop_extract_prefix_safety = H.propertyOnce $ do
  let cl =
        T.unlines
          [ "## 1.0.0.1"
          , ""
          , "- Patch release"
          , ""
          , "## 1.0.0"
          , ""
          , "- Original release"
          , ""
          ]
  short <- H.nothingFail $ extractSection (Pvp $ 1 :| [0, 0]) cl
  short `shouldContain` "Original release"
  short `shouldNotContain` "Patch release"
  long <- H.nothingFail $ extractSection (pvp 1 0 0 1) cl
  long `shouldContain` "Patch release"
  long `shouldNotContain` "Original release"

prop_extract_empty_section :: Property
prop_extract_empty_section = H.propertyOnce $ do
  let cl =
        T.unlines
          [ "## 2.0.0.0"
          , "## 1.0.0.0"
          , ""
          , "- Content of 1.0"
          , ""
          ]
  result <- H.nothingFail $ extractSection (pvp 2 0 0 0) cl
  result H.=== ""
  -- Section with only blank/whitespace lines also returns empty after trimming
  let cl2 =
        T.unlines
          [ "## 2.0.0.0"
          , ""
          , "   "
          , ""
          , "## 1.0.0.0"
          , ""
          , "- Content of 1.0"
          , ""
          ]
  result2 <- H.nothingFail $ extractSection (pvp 2 0 0 0) cl2
  result2 H.=== ""

prop_extract_trimming :: Property
prop_extract_trimming = H.propertyOnce $ do
  let cl =
        T.unlines
          [ "## 1.0.0.0"
          , ""
          , ""
          , "- First entry"
          , ""
          , "- Second entry"
          , ""
          , "   "
          , ""
          ]
  body <- H.nothingFail $ extractSection (pvp 1 0 0 0) cl
  H.annotate $ "Body: " <> show body
  body `shouldContain` "First entry"
  body `shouldContain` "Second entry"
  -- Middle blank line between entries is preserved
  H.assertWith body $ T.isInfixOf "entry\n\n- Second"
  -- No leading blank line
  H.assertWith body $ not . T.isPrefixOf "\n"
  -- No trailing blank/whitespace-only line
  H.assertWith body $ \b ->
    let ls = T.lines b
     in case ls of
          [] -> True
          _ -> T.strip (last ls) /= ""

prop_extract_sub_headers :: Property
prop_extract_sub_headers = H.propertyOnce $ do
  let cl =
        T.unlines
          [ "## 1.0.0.0"
          , ""
          , "### Breaking changes"
          , ""
          , "- Removed old API"
          , ""
          , "### Features"
          , ""
          , "- Added new API"
          , ""
          , "## 0.9.0.0"
          , ""
          , "- Previous release"
          , ""
          ]
  body <- H.nothingFail $ extractSection (pvp 1 0 0 0) cl
  body `shouldContain` "### Breaking changes"
  body `shouldContain` "Removed old API"
  body `shouldContain` "### Features"
  body `shouldContain` "Added new API"
  body `shouldNotContain` "Previous release"

prop_extract_crlf :: Property
prop_extract_crlf = H.propertyOnce $ do
  let cl = "## 1.0.0.0 -- 2026-01-01\r\n\r\n- Entry with CRLF\r\n\r\n## 0.9.0.0\r\n\r\n- Old\r\n"
  body <- H.nothingFail $ extractSection (pvp 1 0 0 0) cl
  body `shouldContain` "Entry with CRLF"
  body `shouldNotContain` "Old"

prop_extract_duplicate_headers :: Property
prop_extract_duplicate_headers = H.propertyOnce $ do
  let cl =
        T.unlines
          [ "## 1.0.0.0"
          , ""
          , "- First occurrence"
          , ""
          , "## 1.0.0.0"
          , ""
          , "- Second occurrence"
          , ""
          ]
  body <- H.nothingFail $ extractSection (pvp 1 0 0 0) cl
  body `shouldContain` "First occurrence"
  body `shouldNotContain` "Second occurrence"

prop_extract_multi_whitespace :: Property
prop_extract_multi_whitespace = H.propertyOnce $ do
  let cl1 =
        T.unlines
          [ "##  1.0.0.0"
          , ""
          , "- Two-space header"
          , ""
          ]
  body1 <- H.nothingFail $ extractSection (pvp 1 0 0 0) cl1
  body1 `shouldContain` "Two-space header"
  let cl2 =
        T.unlines
          [ "##\t1.0.0.0"
          , ""
          , "- Tab header"
          , ""
          ]
  body2 <- H.nothingFail $ extractSection (pvp 1 0 0 0) cl2
  body2 `shouldContain` "Tab header"

-- Test fixtures

changelogDated :: T.Text
changelogDated =
  T.unlines
    [ "# Changelog for cardano-api"
    , ""
    , "## 2.0.0.0 -- 2026-05-01"
    , ""
    , "- Added new feature X"
    , "  (feature)"
    , "  [PR 100](https://github.com/org/repo/pull/100)"
    , ""
    , "## 1.0.0.0 -- 2026-04-01"
    , ""
    , "- Initial release"
    , "  (breaking)"
    , "  [PR 1](https://github.com/org/repo/pull/1)"
    , ""
    ]

changelogBare :: T.Text
changelogBare =
  T.unlines
    [ "# Changelog for cardano-cli"
    , ""
    , "## 11.0.0.0"
    , ""
    , "- Bump cardano-api"
    , "  (maintenance)"
    , ""
    , "## 10.16.0.0"
    , ""
    , "- Added BLS support"
    , "  (feature)"
    , ""
    ]

changelogMixed :: T.Text
changelogMixed =
  T.unlines
    [ "# Changelog"
    , ""
    , "## 3.0.0.0 -- 2026-06-01"
    , ""
    , "- Dated entry"
    , ""
    , "## 2.0.0.0"
    , ""
    , "- Bare entry"
    , ""
    , "## 1.0.0.0 -- 2026-01-01"
    , ""
    , "- Old dated entry"
    , ""
    ]
