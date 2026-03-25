-- | High-level git operations for Herald.
--
-- Most functions read directly from the @.git\/@ filesystem via
-- "Herald.Git.Repository".  Diff operations ('findForkPoint', 'changedFiles')
-- shell out to @git@ since they require commit-graph traversal.
module Herald.Git
  ( currentBranch
  , userNick
  , detectGitRepo
  , parseRepoSlug
  , normaliseGitRepo
  , defaultRemoteBranch
  , findForkPoint
  , changedFiles
  , addedFiles
  , gitAdd
  , gitCommit
  , gitTag
  )
where

import RIO

import Control.Monad.Trans.Maybe (MaybeT (..), runMaybeT)
import Data.Char (isAlphaNum, isSpace)
import Data.Text qualified as T
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.Process (readProcessWithExitCode)

import Herald.Git.Repository (GitRepo (..), openRepo, readBranch, readConfigValue)
import Herald.Types (throwHerald)

-------------------------------------------------------------------------------
-- Branch
-------------------------------------------------------------------------------

-- | Get the current git branch name, sanitised for use in filenames.
-- Returns the part after the last @\/@, with non-alphanumeric chars replaced
-- by @_@.  Returns empty string if not in a git repo, on a detached HEAD,
-- or on a well-known default branch.
currentBranch :: IO String
currentBranch = do
  result <- runMaybeT $ do
    repo <- MaybeT $ openRepo "."
    name <- MaybeT $ readBranch repo
    let short = lastSegment '/' name
    guard $ short `notElem` ["main", "master", "develop", "HEAD"]
    pure $ sanitise short
  pure $ fromMaybe "" result
 where
  sanitise = map (\c -> if isAlphaNum c || c == '_' then c else '_')

  lastSegment _ [] = ""
  lastSegment sep s = case break (== sep) s of
    (part, []) -> part
    (_, _ : rest) -> lastSegment sep rest

-------------------------------------------------------------------------------
-- User nick
-------------------------------------------------------------------------------

-- | Get a user nick for fragment filenames.
-- Tries (in order): @scriv.user-nick@, @github.user@, email local-part, @$USER@.
userNick :: IO String
userNick = do
  repo <- openRepo "."
  result <-
    runMaybeT
      $ MaybeT (configGet repo "scriv.user-nick")
      <|> MaybeT (configGet repo "github.user")
      <|> MaybeT (fmap (takeWhile (/= '@')) <$> configGet repo "user.email")
      <|> MaybeT (lookupEnv "USER")
  pure $ fromMaybe "somebody" result
 where
  configGet Nothing _ = pure Nothing
  configGet (Just r) key = readConfigValue r key

-------------------------------------------------------------------------------
-- Git repo detection
-------------------------------------------------------------------------------

-- | Try to extract the owner\/repo slug from the origin remote URL.
-- Returns 'Nothing' when detection fails (no origin remote, unrecognised URL format).
detectGitRepo :: FilePath -> IO (Maybe Text)
detectGitRepo baseDir = runMaybeT $ do
  repo <- MaybeT $ openRepo baseDir
  url <- T.pack <$> MaybeT (readConfigValue repo "remote.origin.url")
  MaybeT . pure $ parseRepoSlug url

-- | Parse a git remote URL (SSH or HTTPS) into a full HTTPS base URL
-- suitable for constructing PR links (e.g. @https:\/\/github.com\/owner\/repo@).
-- Returns 'Nothing' for unsupported formats or when the result does not
-- contain at least two non-empty path segments (owner\/repo).
parseRepoSlug :: Text -> Maybe Text
parseRepoSlug url
  | "git@" `T.isPrefixOf` url =
      -- git@host:owner/repo.git -> https://host/owner/repo
      do
        let rest = T.drop (T.length "git@") url
        -- Require a colon separator (not a slash -- that would be ssh:// style)
        guard $ T.any (== ':') rest
        let host = T.takeWhile (/= ':') rest
            path = T.drop 1 $ T.dropWhile (/= ':') rest
        guard . not $ T.null host
        validateSlug host $ stripDotGit path
  | "https://" `T.isPrefixOf` url =
      -- https://host/owner/repo.git -> https://host/owner/repo
      let parts = T.splitOn "/" . T.drop (T.length "https://") $ url
       in case parts of
            (host : pathParts)
              | not (T.null host) ->
                  validateSlug host . stripDotGit $ T.intercalate "/" pathParts
            _ -> Nothing
  | otherwise = Nothing
 where
  stripDotGit t = fromMaybe t $ T.stripSuffix ".git" t
  -- Require at least owner/repo (two non-empty segments)
  validateSlug host slug = case T.splitOn "/" slug of
    (owner : repo : _)
      | not (T.null owner) && not (T.null repo) ->
          Just $ "https://" <> host <> "/" <> slug
    _ -> Nothing

-- | Normalise a @git-repo@ config value to a full HTTPS base URL.
--
-- Accepts:
--
-- * Full HTTPS URL: @https:\/\/github.com\/owner\/repo@ (passed through)
-- * SSH URL: @git\@host:owner\/repo.git@ (converted via 'parseRepoSlug')
-- * Bare slug: @owner\/repo@ (assumed GitHub: @https:\/\/github.com\/owner\/repo@)
--
-- Returns the original text unchanged if it does not match any known format.
normaliseGitRepo :: Text -> Text
normaliseGitRepo t =
  fromMaybe stripped $ parseRepoSlug stripped <|> bareSlug stripped
 where
  stripped = fromMaybe t $ T.stripSuffix "/" t
  bareSlug s = case T.splitOn "/" s of
    [owner, repo]
      | not $ T.null owner
      , not $ T.null repo
      , T.all isSlugChar owner
      , T.all isSlugChar repo ->
          Just $ "https://github.com/" <> s
    _ -> Nothing
  isSlugChar c = isAlphaNum c || c == '-' || c == '_' || c == '.'

-------------------------------------------------------------------------------
-- Diff operations (require git process)
-------------------------------------------------------------------------------

-- | Read the default remote branch name from @refs\/remotes\/origin\/HEAD@.
-- Falls back to @git symbolic-ref@ if the file doesn't exist.
defaultRemoteBranch :: FilePath -> IO (Maybe String)
defaultRemoteBranch baseDir = runMaybeT $ tryFilesystem <|> tryGitCommand
 where
  tryFilesystem = do
    repo <- MaybeT $ openRepo baseDir
    let headRef = gitDir repo </> "refs" </> "remotes" </> "origin" </> "HEAD"
    guard =<< liftIO (doesFileExist headRef)
    content <- liftIO $ readFileUtf8 headRef
    fmap T.unpack
      . MaybeT
      . pure
      . T.stripPrefix "ref: refs/remotes/origin/"
      $ T.strip content

  tryGitCommand =
    MaybeT $ gitCommandIn baseDir ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]

-- | Find the fork point: the merge-base between HEAD and the default remote branch.
-- Returns the commit hash of the common ancestor.
findForkPoint :: FilePath -> IO (Maybe String)
findForkPoint baseDir = runMaybeT $ do
  branch <- MaybeT $ defaultRemoteBranch baseDir
  MaybeT $ gitCommandIn baseDir ["merge-base", "HEAD", "origin/" <> branch]

-- | List files changed between a commit and HEAD.
changedFiles :: FilePath -> String -> IO [FilePath]
changedFiles baseDir base = do
  result <- gitCommandIn baseDir ["diff", "--name-only", base <> "..HEAD"]
  pure . maybe [] (filter (not . null) . lines) $ result

-- | List files *added* (not modified) between a commit and HEAD.
addedFiles :: FilePath -> String -> IO [FilePath]
addedFiles baseDir base = do
  result <- gitCommandIn baseDir ["diff", "--diff-filter=A", "--name-only", base <> "..HEAD"]
  pure . maybe [] (filter (not . null) . lines) $ result

-------------------------------------------------------------------------------
-- Staging, committing, tagging
-------------------------------------------------------------------------------

-- | Stage a list of files (paths relative to the repo root).
gitAdd :: FilePath -> [FilePath] -> IO ()
gitAdd _ [] = pure ()
gitAdd baseDir paths = gitCommandOrFail baseDir $ ["add", "--"] <> paths

-- | Create a commit with the given message. Only staged changes are committed.
-- Uses @--no-verify@ to skip pre-commit hooks and @--no-gpg-sign@ to avoid
-- GPG signing issues, since this is an automated release commit.
gitCommit :: FilePath -> String -> IO ()
gitCommit baseDir msg = gitCommandOrFail baseDir ["commit", "--no-verify", "--no-gpg-sign", "-m", msg]

-- | Create a lightweight tag at HEAD.
gitTag :: FilePath -> String -> IO ()
gitTag baseDir tag = gitCommandOrFail baseDir ["tag", tag]

-- | Run a git command in a directory, throwing on failure.
gitCommandOrFail :: FilePath -> [String] -> IO ()
gitCommandOrFail dir args = do
  (code, _, err) <- readProcessWithExitCode "git" (["-C", dir] <> args) ""
  case code of
    ExitSuccess -> pure ()
    _ -> throwHerald $ "git " <> unwords args <> " failed: " <> err

-- | Run a git command in a given directory and return trimmed stdout on success.
gitCommandIn :: FilePath -> [String] -> IO (Maybe String)
gitCommandIn dir args = do
  (code, out, _) <- readProcessWithExitCode "git" (["-C", dir] <> args) ""
  pure $ case code of
    ExitSuccess -> Just $ trimEnd out
    _ -> Nothing
 where
  trimEnd = reverse . dropWhile isSpace . reverse
