module Test.Herald.E2E.Init (tests) where

import Control.Exception (catch)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as T
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import Hedgehog (Property)
import Hedgehog qualified as H
import Hedgehog.Extras qualified as H
import Test.Herald.Assertions (shouldContain)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Command.Init (initConfig)
import Herald.Config (loadConfig)
import Herald.Types (Config (..), HeraldException (..))

tests :: TestTree
tests =
  testGroup
    "Init"
    [ testProperty "skips directories with empty-name cabal files" prop_init_skips_empty_name
    , testProperty "discovers non-cabal directories as projects" prop_init_non_cabal_dirs
    , testProperty "discovers root-level single project" prop_init_root_project
    , testProperty "creates template fragment" prop_init_creates_template
    , testProperty "re-init on existing config errors" prop_init_existing_config
    , testProperty "init with no remote fails" prop_init_no_remote
    , testProperty "init with HTTPS remote extracts slug" prop_init_https_remote
    ]

-- | Directories containing .cabal files with empty basenames (e.g. .ghc-wasm/.cabal)
-- are not included as projects.
prop_init_skips_empty_name :: Property
prop_init_skips_empty_name = H.propertyOnce $ do
  config <- H.evalIO $ withFakeGitDir "herald-init" $ \tmpDir -> do
    let bogusDir = tmpDir </> ".ghc-wasm"
        goodDir = tmpDir </> "my-package"
    createDirectoryIfMissing True bogusDir
    createDirectoryIfMissing True goodDir
    writeFile (bogusDir </> ".cabal") "cabal-version: 3.0\nname: ghost\n"
    writeFile
      (goodDir </> "my-package.cabal")
      "cabal-version: 3.0\nname: my-package\nversion: 1.0.0.0\n"
    initAndLoad tmpDir

  let projectNames = Map.keys $ configProjects config
  H.assert $ "my-package" `elem` projectNames
  H.assert $ "" `notElem` projectNames

-- | Subdirectories without .cabal files are still discovered using their directory name.
prop_init_non_cabal_dirs :: Property
prop_init_non_cabal_dirs = H.propertyOnce $ do
  config <- H.evalIO $ withFakeGitDir "herald-init" $ \tmpDir -> do
    let withCabal = tmpDir </> "my-lib"
        withoutCabal = tmpDir </> "my-docs"
    createDirectoryIfMissing True withCabal
    createDirectoryIfMissing True withoutCabal
    writeFile (withCabal </> "my-lib.cabal") "cabal-version: 3.0\nname: my-lib\nversion: 1.0.0.0\n"
    initAndLoad tmpDir

  let projectNames = Map.keys $ configProjects config
  H.assert $ "my-lib" `elem` projectNames
  H.assert $ "my-docs" `elem` projectNames

-- | A single .cabal file in the root produces one project named after that file.
prop_init_root_project :: Property
prop_init_root_project = H.propertyOnce $ do
  config <- H.evalIO $ withFakeGitDir "herald-init" $ \tmpDir -> do
    writeFile (tmpDir </> "my-tool.cabal") "cabal-version: 3.0\nname: my-tool\nversion: 0.1.0.0\n"
    initAndLoad tmpDir

  let projects = Map.toList $ configProjects config
  case projects of
    [(name, _)] -> H.assert $ name == "my-tool"
    _ -> H.failure

-- | Init creates a _TEMPLATE.yml file containing the project and kind fields.
prop_init_creates_template :: Property
prop_init_creates_template = H.propertyOnce $ do
  template <- H.evalIO $ withFakeGitDir "herald-init" $ \tmpDir -> do
    let goodDir = tmpDir </> "my-pkg"
    createDirectoryIfMissing True goodDir
    writeFile (goodDir </> "my-pkg.cabal") "cabal-version: 3.0\nname: my-pkg\nversion: 1.0.0.0\n"

    _ <- initConfig tmpDir (tmpDir </> ".herald.yml")
    let templatePath = tmpDir </> ".changes" </> "_TEMPLATE.yml"
    exists <- doesFileExist templatePath
    if exists
      then T.readFile templatePath
      else error "Template fragment not created"

  template `shouldContain` "project:"
  template `shouldContain` "kind:"

-- | Re-running init when .herald.yml already exists errors.
prop_init_existing_config :: Property
prop_init_existing_config = H.propertyOnce $ do
  errMsg <- H.evalIO $ withFakeGitDir "herald-reinit" $ \tmpDir -> do
    let configPath = tmpDir </> ".herald.yml"
    writeFile configPath "existing config"
    (initConfig tmpDir configPath >> pure "no error")
      `catch` \(HeraldException msg) -> pure msg

  T.pack errMsg `shouldContain` "already exists"

-- | Init without a git remote (no .git/config with origin) errors.
prop_init_no_remote :: Property
prop_init_no_remote = H.propertyOnce $ do
  errMsg <- H.evalIO $ withSystemTempDirectory "herald-no-remote" $ \tmpDir -> do
    -- Create .git dir but no remote config
    createDirectoryIfMissing True $ tmpDir </> ".git"
    writeFile (tmpDir </> ".git" </> "config") "[core]\n\tbare = false\n"
    writeFile (tmpDir </> ".git" </> "HEAD") "ref: refs/heads/main\n"
    (initConfig tmpDir (tmpDir </> ".herald.yml") >> pure "no error")
      `catch` \(HeraldException msg) -> pure msg

  T.pack errMsg `shouldContain` "Could not detect origin remote"

-- | Init with an HTTPS remote URL extracts the owner/repo slug.
prop_init_https_remote :: Property
prop_init_https_remote = H.propertyOnce $ do
  config <- H.evalIO $ withSystemTempDirectory "herald-https" $ \tmpDir -> do
    createDirectoryIfMissing True $ tmpDir </> ".git"
    writeFile
      (tmpDir </> ".git" </> "config")
      "[remote \"origin\"]\n\turl = https://github.com/MyOrg/my-repo.git\n"
    writeFile (tmpDir </> ".git" </> "HEAD") "ref: refs/heads/main\n"
    let goodDir = tmpDir </> "my-pkg"
    createDirectoryIfMissing True goodDir
    writeFile (goodDir </> "my-pkg.cabal") "cabal-version: 3.0\nname: my-pkg\nversion: 1.0.0.0\n"
    initAndLoad tmpDir

  configGitRepo config `shouldContain` "https://github.com/MyOrg/my-repo"

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

-- | Create a temp directory with a minimal .git dir (enough for detectGitRepo).
withFakeGitDir :: String -> (FilePath -> IO a) -> IO a
withFakeGitDir label action = withSystemTempDirectory label $ \tmpDir -> do
  createDirectoryIfMissing True $ tmpDir </> ".git"
  writeFile
    (tmpDir </> ".git" </> "config")
    "[remote \"origin\"]\n\turl = git@github.com:test/repo.git\n"
  writeFile (tmpDir </> ".git" </> "HEAD") "ref: refs/heads/main\n"
  action tmpDir

-- | Run initConfig then loadConfig, failing on parse errors.
initAndLoad :: FilePath -> IO Config
initAndLoad tmpDir = do
  let configPath = tmpDir </> ".herald.yml"
  _ <- initConfig tmpDir configPath
  result <- loadConfig configPath
  case result of
    Left err -> error $ "Failed to load generated config: " <> err
    Right c -> pure c
