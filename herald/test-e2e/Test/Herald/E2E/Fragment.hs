module Test.Herald.E2E.Fragment (tests) where

import Control.Exception (catch)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import System.Directory (doesFileExist)
import System.FilePath (takeFileName, (</>))

import Hedgehog (Property)
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain)
import Test.Herald.E2E.Fixtures (setupTestRepo)
import Test.Herald.Fixtures (testConfigMultiProject)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Command.New (NewOptions (..), createFragment)
import Herald.Fragment.Read (readAllFragments)
import Herald.Types (HeraldException (..))

tests :: TestTree
tests =
  testGroup
    "Fragment creation"
    [ testProperty "multi-project produces distinct files" prop_create_fragment_multi_project
    , testProperty "spaces in description produce clean filename" prop_create_fragment_spaces
    , testProperty "template fragment is skipped by reading" prop_template_skipped
    , testProperty "duplicate fragment for same PR errors with pointer" prop_duplicate_fragment
    , testProperty "same PR different project is allowed" prop_cross_project_duplicate_pr
    , testProperty "invalid project in createFragment errors before writing" prop_invalid_project
    , testProperty "invalid kind in createFragment errors before writing" prop_invalid_kind
    ]

-- | Creating fragments for two different projects produces two distinct .yml files.
prop_create_fragment_multi_project :: Property
prop_create_fragment_multi_project = H.propertyOnce $ do
  (path1, path2) <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    let opts1 = NewOptions "cardano-api" ["breaking", "feature"] "foo" 6777
        opts2 = NewOptions "cardano-api-gen" ["breaking", "feature"] "foo" 6777
    p1 <- createFragment testConfigMultiProject tmpDir opts1
    p2 <- createFragment testConfigMultiProject tmpDir opts2
    assertFileExists p1
    assertFileExists p2
    pure (p1, p2)

  H.assert $ T.isSuffixOf ".yml" $ T.pack path1
  H.assert $ T.isSuffixOf ".yml" $ T.pack path2

-- | Spaces in description are converted to hyphens in the filename (no spaces in filenames).
prop_create_fragment_spaces :: Property
prop_create_fragment_spaces = H.propertyOnce $ do
  path <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    let opts = NewOptions "cardano-api" ["bugfix"] "Fix serialization of Conway certificates" 777
    p <- createFragment testConfigMultiProject tmpDir opts
    assertFileExists p
    pure p

  H.assert $ notElem ' ' $ takeFileName path

-- | _TEMPLATE.yml is not returned by readAllFragments.
prop_template_skipped :: Property
prop_template_skipped = H.propertyOnce $ do
  fragments <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    T.writeFile
      (tmpDir </> ".changes" </> "_TEMPLATE.yml")
      "project: cardano-api\nkind:\n  - bugfix\ndescription: template\npr: 0\n"
    readAllFragments testConfigMultiProject tmpDir

  let names = map fst fragments
  H.assert $ "_TEMPLATE.yml" `notElem` names

-- | Creating a fragment for a PR that already has one errors and names the existing file.
prop_duplicate_fragment :: Property
prop_duplicate_fragment = H.propertyOnce $ do
  errMsg <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    -- Fragment for PR 42 already exists in setupTestRepo
    let opts = NewOptions "cardano-api" ["bugfix"] "Duplicate attempt" 42
    (createFragment testConfigMultiProject tmpDir opts >> pure "no error")
      `catch` \(HeraldException msg) -> pure msg

  T.pack errMsg `shouldContain` "already exists"
  T.pack errMsg `shouldContain` "42-fix-serialization.yml"

-- | Same PR number for a different project is allowed (duplicate check is per-project).
prop_cross_project_duplicate_pr :: Property
prop_cross_project_duplicate_pr = H.propertyOnce $ do
  (path1, path2) <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    -- PR 42 already exists for cardano-api in setupTestRepo
    -- Creating PR 42 for cardano-api-gen should succeed
    let opts = NewOptions "cardano-api-gen" ["bugfix"] "Same PR different project" 42
    p <- createFragment testConfigMultiProject tmpDir opts
    assertFileExists p
    -- Verify original still exists
    let origPath = tmpDir </> ".changes" </> "42-fix-serialization.yml"
    assertFileExists origPath
    pure (p, origPath)

  H.assert $ path1 /= path2

-- | Creating a fragment with an unknown project errors before writing any file.
prop_invalid_project :: Property
prop_invalid_project = H.propertyOnce $ do
  errMsg <- H.evalIO $ setupTestRepo $ \tmpDir ->
    ( createFragment testConfigMultiProject tmpDir (NewOptions "nonexistent" ["bugfix"] "Desc" 999)
        >> pure "no error"
    )
      `catch` \(HeraldException msg) -> pure msg

  T.pack errMsg `shouldContain` "Invalid fragment"
  T.pack errMsg `shouldContain` "Unknown project"

-- | Creating a fragment with an unknown kind errors before writing any file.
prop_invalid_kind :: Property
prop_invalid_kind = H.propertyOnce $ do
  errMsg <- H.evalIO $ setupTestRepo $ \tmpDir ->
    ( createFragment
        testConfigMultiProject
        tmpDir
        (NewOptions "cardano-api" ["nonexistent-kind"] "Desc" 999)
        >> pure "no error"
    )
      `catch` \(HeraldException msg) -> pure msg

  T.pack errMsg `shouldContain` "Invalid fragment"
  T.pack errMsg `shouldContain` "Unknown kind"

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

assertFileExists :: FilePath -> IO ()
assertFileExists path = do
  exists <- doesFileExist path
  if exists then pure () else error $ "Fragment file not found: " <> path
