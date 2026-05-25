module Test.Herald.E2E.Batch.PerProject (tests) where

import Control.Monad (when)
import Data.List (sort)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import System.Directory (doesFileExist, listDirectory, removeFile)
import System.FilePath ((</>))
import System.Process (readProcessWithExitCode)

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain)
import Test.Herald.E2E.Fixtures.PerProject
  ( setupPerProjectBatchRepo
  , setupPerProjectNoGlobalRepo
  , setupPerProjectRepo
  , testConfigPerProject
  , testConfigPerProjectNoGlobal
  )
import Test.Herald.Fixtures (testDay)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Command.Batch (BatchResult (..), CommitMode (..), batchPackage, commitBatchResult)

tests :: TestTree
tests =
  testGroup
    "Batch (per-project changes-dir)"
    [ testProperty
        "batch collects from both global and per-project dirs"
        prop_batch_both_dirs
    , testProperty
        "consumed fragments deleted from originating dirs"
        prop_batch_deletes_from_origin
    , testProperty
        "batch with fragments only in per-project dir succeeds"
        prop_batch_per_project_only
    , testProperty
        "batch with no global dir configured succeeds"
        prop_batch_no_global_dir
    , testProperty
        "commit stages fragment deletions from both dirs"
        prop_batch_commit_both_dirs
    ]

-- | Batch collects fragments from both the global and per-project directories.
prop_batch_both_dirs :: Property
prop_batch_both_dirs = H.propertyOnce $ do
  result <- H.evalIO $ setupPerProjectRepo $ \tmpDir ->
    batchPackage testConfigPerProject tmpDir "cardano-api" Nothing testDay

  br <- H.nothingFail result
  let frags = sort $ batchResultFragments br
  length frags === 2

-- | Consumed fragments are deleted from their originating directory.
prop_batch_deletes_from_origin :: Property
prop_batch_deletes_from_origin = H.propertyOnce $ do
  (perProjectExists, globalExists, globalRemaining) <- H.evalIO $ setupPerProjectRepo $ \tmpDir -> do
    Just _ <- batchPackage testConfigPerProject tmpDir "cardano-api" Nothing testDay
    ppExists <- doesFileExist $ tmpDir </> "cardano-api" </> ".changes" </> "42-fix-serialization.yml"
    gExists <- doesFileExist $ tmpDir </> ".changes" </> "99-add-conway-support.yml"
    gRemaining <- sort <$> listDirectory (tmpDir </> ".changes")
    pure (ppExists, gExists, gRemaining)

  H.assertWith perProjectExists not
  H.assertWith globalExists not
  globalRemaining === ["50-gen-helpers.yml"]

-- | Batch works when fragments exist only in the per-project dir.
prop_batch_per_project_only :: Property
prop_batch_per_project_only = H.propertyOnce $ do
  changelog <- H.evalIO $ setupPerProjectRepo $ \tmpDir -> do
    let globalFrag = tmpDir </> ".changes" </> "99-add-conway-support.yml"
    exists <- doesFileExist globalFrag
    when exists $ removeFile globalFrag
    Just _ <- batchPackage testConfigPerProject tmpDir "cardano-api" Nothing testDay
    T.readFile $ tmpDir </> "cardano-api" </> "CHANGELOG.md"

  changelog `shouldContain` "Fix serialization"

-- | Batch works when there is no global changes-dir at all.
prop_batch_no_global_dir :: Property
prop_batch_no_global_dir = H.propertyOnce $ do
  changelog <- H.evalIO $ setupPerProjectNoGlobalRepo $ \tmpDir -> do
    Just _ <- batchPackage testConfigPerProjectNoGlobal tmpDir "lib-a" Nothing testDay
    T.readFile $ tmpDir </> "lib-a" </> "CHANGELOG.md"

  changelog `shouldContain` "New feature"

-- | --commit stages fragment deletions from both global and per-project dirs.
prop_batch_commit_both_dirs :: Property
prop_batch_commit_both_dirs = H.propertyOnce $ do
  committedFiles <- H.evalIO $ setupPerProjectBatchRepo $ \tmpDir -> do
    Just result <- batchPackage testConfigPerProject tmpDir "cardano-api" Nothing testDay
    commitBatchResult tmpDir result Commit
    readGit tmpDir ["diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"]

  let files = T.pack committedFiles
  files `shouldContain` "cardano-api/.changes/42-fix-serialization.yml"
  files `shouldContain` ".changes/99-add-conway-support.yml"
  files `shouldContain` "cardano-api/CHANGELOG.md"
  files `shouldContain` "cardano-api/cardano-api.cabal"

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

readGit :: FilePath -> [String] -> IO String
readGit dir args = do
  (_, out, _) <- readProcessWithExitCode "git" (["-C", dir] <> args) ""
  pure out
