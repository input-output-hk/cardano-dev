module Test.Herald.E2E.Batch (tests) where

import Control.Exception (SomeException, catch)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Time (fromGregorian)
import Data.Yaml qualified as Yaml
import System.Directory (createDirectoryIfMissing, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

import Hedgehog (Property, (===))
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain)
import Test.Herald.E2E.Fixtures (setupBatchRepo, setupTestRepo)
import Test.Herald.Fixtures (pvp, testConfigMultiProject, testDay)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Command.Batch (BatchResult (..), CommitMode (..), batchPackage, commitBatchResult)
import Herald.Types (Config (..), Fragment (..), HeraldException (..), ProjectConfig (..))

tests :: TestTree
tests =
  testGroup
    "Batch"
    [ testProperty "batch with explicit version" prop_batch_explicit_version
    , testProperty "batch with auto-version" prop_batch_auto_version
    , testProperty "batch updates changelog" prop_batch_updates_changelog
    , testProperty "full lifecycle output format" prop_full_lifecycle
    , testProperty "non-notable filtering" prop_non_notable_filtering
    , testProperty "batch result contains expected fields" prop_batch_result_fields
    , testProperty "batch with explicit date uses provided date" prop_batch_explicit_date
    , testProperty "batch --commit creates a commit with batch changes" prop_batch_commit
    , testProperty "batch --commit-tag creates a commit and a tag" prop_batch_commit_tag
    , testProperty "batch with no fragments returns Nothing" prop_batch_no_fragments
    , testProperty "batch same project twice returns Nothing on second call" prop_batch_twice
    , testProperty "batch version downgrade is rejected" prop_batch_downgrade
    , testProperty "batch again with new fragments produces second section" prop_batch_idempotent
    , testProperty "batch without .cabal file uses explicit version" prop_batch_no_cabal
    , testProperty "batch rejects invalid fragment (unknown kind)" prop_batch_invalid_fragment
    , testProperty "auto-version without cabal-file is rejected" prop_batch_auto_no_cabal
    , testProperty "auto-version with missing version: line is rejected" prop_batch_auto_missing_version
    , testProperty "explicit version equal to current is accepted" prop_batch_same_version
    , testProperty "unknown project is rejected" prop_batch_unknown_project
    , testProperty
        "downgrade check skipped when version: line is missing"
        prop_batch_downgrade_skipped_missing_version
    , testProperty
        "valid kind does not mask invalid kind in same fragment"
        prop_batch_mixed_valid_invalid_kinds
    , testProperty "missing CHANGELOG.md on disk is a hard error" prop_batch_missing_changelog
    , testProperty "missing .cabal file on disk is a hard error" prop_batch_missing_cabal_file
    ]

-- | Explicit version (9.0.0.0) updates .cabal and changelog; only other-project fragments remain.
prop_batch_explicit_version :: Property
prop_batch_explicit_version = H.propertyOnce $ do
  (cabal, changelog, remaining) <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    Just _ <- batchPackage testConfigMultiProject tmpDir "cardano-api" (Just $ pvp 9 0 0 0) testDay
    cabal <- T.readFile $ tmpDir </> "cardano-api" </> "cardano-api.cabal"
    changelog <- T.readFile $ tmpDir </> "cardano-api" </> "CHANGELOG.md"
    remaining <- sort <$> listDirectory (tmpDir </> ".changes")
    pure (cabal, changelog, remaining)

  cabal `shouldContain` "version: 9.0.0.0"
  changelog `shouldContain` "## 9.0.0.0"
  remaining === ["50-gen-helpers.yml"]

-- | Auto-version: bugfix (patch) + breaking -> max is breaking -> 8.4.1.2 becomes 8.5.0.0.
prop_batch_auto_version :: Property
prop_batch_auto_version = H.propertyOnce $ do
  (cabal, changelog) <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    Just _ <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay
    cabal <- T.readFile $ tmpDir </> "cardano-api" </> "cardano-api.cabal"
    changelog <- T.readFile $ tmpDir </> "cardano-api" </> "CHANGELOG.md"
    pure (cabal, changelog)

  cabal `shouldContain` "version: 8.5.0.0"
  changelog `shouldContain` "## 8.5.0.0"

-- | New changelog section is prepended above the existing one; old content preserved.
prop_batch_updates_changelog :: Property
prop_batch_updates_changelog = H.propertyOnce $ do
  changelog <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    Just _ <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay
    T.readFile $ tmpDir </> "cardano-api" </> "CHANGELOG.md"

  let idxNew = T.length . fst $ T.breakOn "## 8.5.0.0" changelog
      idxOld = T.length . fst $ T.breakOn "## 8.4.1.2" changelog
  H.annotate $ "New section at offset " <> show idxNew <> ", old at " <> show idxOld
  H.assert $ idxNew < idxOld
  changelog `shouldContain` "Previous change"

-- | Full lifecycle: rendered changelog matches the expected format (R10).
prop_full_lifecycle :: Property
prop_full_lifecycle = H.propertyOnce $ do
  changelog <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    Just _ <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay
    T.readFile $ tmpDir </> "cardano-api" </> "CHANGELOG.md"

  changelog `shouldContain` "## 8.5.0.0"
  changelog `shouldContain` "2026-03-25"

  -- Entries sorted by PR number descending: 99 before 42
  let idx42 = T.length . fst $ T.breakOn "PR 42" changelog
      idx99 = T.length . fst $ T.breakOn "PR 99" changelog
  H.assert $ idx99 < idx42

  changelog `shouldContain` "Fix serialization of Conway certificates"
  changelog `shouldContain` "(bugfix)"
  changelog `shouldContain` "[PR 42](https://github.com/IntersectMBO/cardano-api/pull/42)"

  changelog `shouldContain` "Add Conway era support"
  changelog `shouldContain` "(breaking, feature)"
  changelog `shouldContain` "[PR 99](https://github.com/IntersectMBO/cardano-api/pull/99)"

  changelog `shouldContain` "## 8.4.1.2"

-- | Non-notable fragments (test kind only) contribute to version bump but are hidden from changelog.
prop_non_notable_filtering :: Property
prop_non_notable_filtering = H.propertyOnce $ do
  changelog <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    Just _ <- batchPackage testConfigMultiProject tmpDir "cardano-api-gen" Nothing testDay
    T.readFile $ tmpDir </> "cardano-api-gen" </> "CHANGELOG.md"

  changelog `shouldContain` "## 1.0.0.1"
  H.annotate "Changelog should not contain non-notable entry text"
  H.assert . not $ T.isInfixOf "Add generator helpers" changelog

-- | BatchResult contains the computed version, consumed fragment names, and file paths.
prop_batch_result_fields :: Property
prop_batch_result_fields = H.propertyOnce $ do
  result <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    Just r <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay
    pure r

  batchResultVersion result === pvp 8 5 0 0
  sort (batchResultFragments result) === ["42-fix-serialization.yml", "99-add-conway-support.yml"]
  H.assert $ T.isSuffixOf "CHANGELOG.md" . T.pack $ batchResultChangelog result
  H.assert $ maybe False (T.isSuffixOf ".cabal" . T.pack) $ batchResultCabalFile result

-- | An explicit date appears in the changelog header instead of today's date.
prop_batch_explicit_date :: Property
prop_batch_explicit_date = H.propertyOnce $ do
  changelog <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    let customDay = fromGregorian 2025 12 31
    Just _ <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing customDay
    T.readFile $ tmpDir </> "cardano-api" </> "CHANGELOG.md"

  changelog `shouldContain` "2025-12-31"

-- | --commit creates a git commit containing exactly the batch-changed files.
prop_batch_commit :: Property
prop_batch_commit = H.propertyOnce $ do
  (commitMsg, changedFiles') <- H.evalIO $ setupBatchRepo $ \tmpDir -> do
    Just result <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay
    commitBatchResult tmpDir result Commit
    msg <- readGit tmpDir ["log", "-1", "--format=%s"]
    files <- readGit tmpDir ["diff", "--name-only", "HEAD~1", "HEAD"]
    pure (msg, files)

  T.pack commitMsg `shouldContain` "Release cardano-api-8.5.0.0"

  let files = sort . filter (not . null) . lines $ changedFiles'
  H.assert $ ".changes/42-fix-serialization.yml" `elem` files
  H.assert $ ".changes/99-add-conway-support.yml" `elem` files
  H.assert $ "cardano-api/CHANGELOG.md" `elem` files
  H.assert $ "cardano-api/cardano-api.cabal" `elem` files
  -- Other project's files should NOT be in the commit
  H.assert . not $ any (T.isPrefixOf "cardano-api-gen" . T.pack) files

-- | --commit-tag creates both a commit and a PACKAGE-VERSION tag.
prop_batch_commit_tag :: Property
prop_batch_commit_tag = H.propertyOnce $ do
  tags <- H.evalIO $ setupBatchRepo $ \tmpDir -> do
    Just result <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay
    commitBatchResult tmpDir result CommitTag
    readGit tmpDir ["tag", "-l"]

  T.pack tags `shouldContain` "cardano-api-8.5.0.0"

-- | Batching a project with no fragments returns Nothing (no-op with warning).
prop_batch_no_fragments :: Property
prop_batch_no_fragments = H.propertyOnce $ do
  let configWithEmpty =
        testConfigMultiProject
          { configProjects =
              Map.insert
                "empty-project"
                ProjectConfig
                  { projectChangelog = "empty-project/CHANGELOG.md"
                  , projectCabalFile = Nothing
                  }
                $ configProjects testConfigMultiProject
          }
  result <- H.evalIO $ setupTestRepo $ \tmpDir ->
    batchPackage configWithEmpty tmpDir "empty-project" Nothing testDay

  H.assert $ isNothing result

-- | Batching the same project twice: first succeeds, second returns Nothing (fragments consumed).
prop_batch_twice :: Property
prop_batch_twice = H.propertyOnce $ do
  (first, second) <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    r1 <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay
    r2 <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay
    pure (r1, r2)

  H.assert $ isJust first
  H.assert $ isNothing second

-- | Explicit version lower than current is rejected as a hard error.
prop_batch_downgrade :: Property
prop_batch_downgrade = H.propertyOnce $ do
  caught <- H.evalIO $ setupTestRepo $ \tmpDir ->
    -- Current version is 8.4.1.2; requesting 1.0.0.0 is a downgrade
    (batchPackage testConfigMultiProject tmpDir "cardano-api" (Just $ pvp 1 0 0 0) testDay >> pure False)
      `catch` \(HeraldException _) -> pure True

  H.assert caught

-- | Batching twice with fresh fragments each time produces two changelog sections.
prop_batch_idempotent :: Property
prop_batch_idempotent = H.propertyOnce $ do
  changelog <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    -- First batch
    Just _ <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay
    -- Add new fragments for a second batch
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "200-new-feature.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["feature"]
        , fragmentDescription = "New feature after first batch"
        , fragmentPR = 200
        }
    let day2 = fromGregorian 2026 4 1
    Just _ <- batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing day2
    T.readFile $ tmpDir </> "cardano-api" </> "CHANGELOG.md"

  -- Both sections present
  changelog `shouldContain` "## 8.5.0.0"
  changelog `shouldContain` "## 8.5.1.0"

-- | Batching a project with no .cabal file works when an explicit version is given.
prop_batch_no_cabal :: Property
prop_batch_no_cabal = H.propertyOnce $ do
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
  (result, changelog) <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    r <- batchPackage noCabalConfig tmpDir "cardano-api" (Just $ pvp 2 0 0 0) testDay
    cl <- T.readFile $ tmpDir </> "cardano-api" </> "CHANGELOG.md"
    pure (r, cl)

  H.assert $ isJust result
  changelog `shouldContain` "## 2.0.0.0"

-- | A fragment with an unknown kind causes batch to fail before modifying any files.
prop_batch_invalid_fragment :: Property
prop_batch_invalid_fragment = H.propertyOnce $ do
  (caught, changelogUnchanged) <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    -- Write a fragment with an invalid kind
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "999-bad-kind.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["nonexistent-kind"]
        , fragmentDescription = "This should fail"
        , fragmentPR = 999
        }
    changelogBefore <- T.readFile $ tmpDir </> "cardano-api" </> "CHANGELOG.md"
    wasCaught <-
      (batchPackage testConfigMultiProject tmpDir "cardano-api" (Just $ pvp 9 0 0 0) testDay >> pure False)
        `catch` \(HeraldException _) -> pure True
    changelogAfter <- T.readFile $ tmpDir </> "cardano-api" </> "CHANGELOG.md"
    pure (wasCaught, changelogBefore == changelogAfter)

  H.assert caught
  H.assert changelogUnchanged

-- | Auto-version without a cabal-file configured is rejected because there is
-- no current version to bump from.
prop_batch_auto_no_cabal :: Property
prop_batch_auto_no_cabal = H.propertyOnce $ do
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
  caught <- H.evalIO $ setupTestRepo $ \tmpDir ->
    (batchPackage noCabalConfig tmpDir "cardano-api" Nothing testDay >> pure False)
      `catch` \(HeraldException _) -> pure True

  H.assert caught

-- | Auto-version fails when the .cabal file has no version: line, since there
-- is no base version to compute the bump from.
prop_batch_auto_missing_version :: Property
prop_batch_auto_missing_version = H.propertyOnce $ do
  caught <- H.evalIO $ withSystemTempDirectory "herald-batch" $ \tmpDir -> do
    let changesDir = tmpDir </> ".changes"
        pkgDir = tmpDir </> "cardano-api"
    createDirectoryIfMissing True changesDir
    createDirectoryIfMissing True pkgDir
    writeFile
      (pkgDir </> "cardano-api.cabal")
      "cabal-version: 3.0\nname: cardano-api\n"
    T.writeFile (pkgDir </> "CHANGELOG.md") "## Old\n\n- Previous\n"
    Yaml.encodeFile
      (changesDir </> "42-fix.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Fix something"
        , fragmentPR = 42
        }
    (batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay >> pure False)
      `catch` \(HeraldException _) -> pure True

  H.assert caught

-- | Explicit version equal to the current .cabal version is accepted -- the
-- downgrade check only rejects strictly lower versions.
prop_batch_same_version :: Property
prop_batch_same_version = H.propertyOnce $ do
  result <- H.evalIO $ setupTestRepo $ \tmpDir ->
    -- Current version in setupTestRepo is 8.4.1.2
    batchPackage testConfigMultiProject tmpDir "cardano-api" (Just $ pvp 8 4 1 2) testDay

  H.assert $ isJust result

-- | Batching a project that does not exist in the config is rejected.
prop_batch_unknown_project :: Property
prop_batch_unknown_project = H.propertyOnce $ do
  caught <- H.evalIO $ setupTestRepo $ \tmpDir ->
    (batchPackage testConfigMultiProject tmpDir "nonexistent" Nothing testDay >> pure False)
      `catch` \(HeraldException _) -> pure True

  H.assert caught

-- | When the .cabal file has no parseable version: line, the downgrade check
-- is silently skipped because there is no current version to compare against.
-- An explicit version succeeds regardless of what it is.
prop_batch_downgrade_skipped_missing_version :: Property
prop_batch_downgrade_skipped_missing_version = H.propertyOnce $ do
  result <- H.evalIO $ withSystemTempDirectory "herald-batch" $ \tmpDir -> do
    let changesDir = tmpDir </> ".changes"
        pkgDir = tmpDir </> "cardano-api"
    createDirectoryIfMissing True changesDir
    createDirectoryIfMissing True pkgDir
    writeFile
      (pkgDir </> "cardano-api.cabal")
      "cabal-version: 3.0\nname: cardano-api\n"
    T.writeFile (pkgDir </> "CHANGELOG.md") "## Old\n\n- Previous\n"
    Yaml.encodeFile
      (changesDir </> "42-fix.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Fix something"
        , fragmentPR = 42
        }
    -- 1.0.0.0 could be a downgrade, but no current version to compare against
    batchPackage testConfigMultiProject tmpDir "cardano-api" (Just $ pvp 1 0 0 0) testDay

  H.assert $ isJust result

-- | A fragment mixing valid and invalid kinds is rejected -- a valid kind does
-- not mask an invalid one.
prop_batch_mixed_valid_invalid_kinds :: Property
prop_batch_mixed_valid_invalid_kinds = H.propertyOnce $ do
  caught <- H.evalIO $ setupTestRepo $ \tmpDir -> do
    Yaml.encodeFile
      (tmpDir </> ".changes" </> "999-mixed.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["bugfix", "nonexistent-kind"]
        , fragmentDescription = "Mixed kinds"
        , fragmentPR = 999
        }
    (batchPackage testConfigMultiProject tmpDir "cardano-api" (Just $ pvp 9 0 0 0) testDay >> pure False)
      `catch` \(HeraldException _) -> pure True

  H.assert caught

-- | Batching when CHANGELOG.md does not exist on disk is a hard error.
prop_batch_missing_changelog :: Property
prop_batch_missing_changelog = H.propertyOnce $ do
  caught <- H.evalIO $ withSystemTempDirectory "herald-batch" $ \tmpDir -> do
    let changesDir = tmpDir </> ".changes"
        pkgDir = tmpDir </> "cardano-api"
    createDirectoryIfMissing True changesDir
    createDirectoryIfMissing True pkgDir
    writeFile
      (pkgDir </> "cardano-api.cabal")
      $ unlines ["cabal-version: 3.0", "name: cardano-api", "version: 8.4.1.2"]
    -- Deliberately do NOT create CHANGELOG.md
    Yaml.encodeFile
      (changesDir </> "42-fix.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Fix something"
        , fragmentPR = 42
        }
    (batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay >> pure False)
      `catch` \(_ :: SomeException) -> pure True

  H.assert caught

-- | Batching when the configured .cabal file does not exist on disk is a hard error.
prop_batch_missing_cabal_file :: Property
prop_batch_missing_cabal_file = H.propertyOnce $ do
  caught <- H.evalIO $ withSystemTempDirectory "herald-batch" $ \tmpDir -> do
    let changesDir = tmpDir </> ".changes"
        pkgDir = tmpDir </> "cardano-api"
    createDirectoryIfMissing True changesDir
    createDirectoryIfMissing True pkgDir
    -- Deliberately do NOT create .cabal file
    T.writeFile (pkgDir </> "CHANGELOG.md") "## Old\n\n- Previous\n"
    Yaml.encodeFile
      (changesDir </> "42-fix.yml")
      Fragment
        { fragmentProject = "cardano-api"
        , fragmentKinds = ["bugfix"]
        , fragmentDescription = "Fix something"
        , fragmentPR = 42
        }
    -- Auto-version needs the .cabal file to read current version
    (batchPackage testConfigMultiProject tmpDir "cardano-api" Nothing testDay >> pure False)
      `catch` \(_ :: SomeException) -> pure True

  H.assert caught

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

-- | Run a git command and return its stdout.
readGit :: FilePath -> [String] -> IO String
readGit dir args = do
  (_, out, _) <- readProcessWithExitCode "git" (["-C", dir] <> args) ""
  pure out
