-- | Git helpers shared across all e2e tests.
module Test.Herald.E2E.Fixtures
  ( -- * Git helpers
    git
  , withGitRepo
  , commitAll
  , withFakeOrigin
  , withFeatureBranch
  )
where

import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

-- | Run a git command in a directory, failing on non-zero exit.
git :: FilePath -> [String] -> IO ()
git dir args = do
  (code, _, err) <- readProcessWithExitCode "git" (["-C", dir] <> args) ""
  case code of
    ExitSuccess -> pure ()
    _ -> error $ "git " <> unwords args <> " failed: " <> err

-- | Create a temp directory with an initialized git repo (main branch).
withGitRepo :: String -> (FilePath -> IO a) -> IO a
withGitRepo label action = withSystemTempDirectory label $ \tmpDir -> do
  git tmpDir ["init", "-b", "main"]
  git tmpDir ["config", "user.email", "test@test.com"]
  git tmpDir ["config", "user.name", "Test"]
  action tmpDir

-- | Stage all files and commit.
commitAll :: FilePath -> String -> IO ()
commitAll dir msg = do
  git dir ["add", "-A"]
  git dir ["commit", "-m", msg]

-- | Set up a fake origin remote pointing at the repo itself,
-- so that defaultRemoteBranch can resolve origin/main.
withFakeOrigin :: FilePath -> IO ()
withFakeOrigin dir = do
  git dir ["remote", "add", "origin", dir]
  git dir ["fetch", "origin"]
  let headPath = dir </> ".git" </> "refs" </> "remotes" </> "origin" </> "HEAD"
  createDirectoryIfMissing True $ takeDirectory headPath
  writeFile headPath "ref: refs/remotes/origin/main\n"

-- | Create a feature branch off current HEAD with a fake origin set up.
withFeatureBranch :: FilePath -> IO a -> IO a
withFeatureBranch dir action = do
  withFakeOrigin dir
  git dir ["checkout", "-b", "feature"]
  action
