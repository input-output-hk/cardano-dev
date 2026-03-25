-- | Low-level git repository reading from the filesystem.
--
-- Replaces all @System.Process@ \"git\" invocations with direct reads of
-- the @.git\/@ directory structure (HEAD, refs\/tags, packed-refs, config).
module Herald.Git.Repository
  ( GitRepo (..)
  , openRepo
  , readBranch
  , readConfigValue

    -- * Exported for testing
  , lookupGitConfig
  )
where

import RIO

import Control.Monad.Trans.Maybe (MaybeT (..), runMaybeT)
import Data.Text qualified as T
import System.Directory (doesDirectoryExist, doesFileExist, makeAbsolute)
import System.FilePath (isAbsolute, takeDirectory, (</>))

-- | An opened git repository, identified by its @.git@ directory path.
newtype GitRepo = GitRepo {gitDir :: FilePath}
  deriving Show

-------------------------------------------------------------------------------
-- Opening a repository
-------------------------------------------------------------------------------

-- | Discover the git directory starting from @startDir@, walking up parents.
-- Handles both regular repos (@.git/@ directory) and worktrees\/submodules
-- (@.git@ file containing @gitdir: path@).
openRepo :: FilePath -> IO (Maybe GitRepo)
openRepo startDir = makeAbsolute startDir >>= runMaybeT . walk
 where
  walk dir =
    let gitPath = dir </> ".git"
     in tryDirectory gitPath <|> tryGitFile gitPath dir <|> walkUp dir

  walkUp dir = do
    let parent = takeDirectory dir
    guard $ parent /= dir -- stop at filesystem root
    walk parent

  tryDirectory gitPath = do
    guard =<< lift (doesDirectoryExist gitPath)
    pure $ GitRepo gitPath

  tryGitFile gitPath baseDir = do
    guard =<< lift (doesFileExist gitPath)
    content <- lift $ readFileUtf8 gitPath
    target <- MaybeT . pure . T.stripPrefix "gitdir:" $ T.strip content
    let targetPath = T.unpack $ T.strip target
    pure
      . GitRepo
      $ if isAbsolute targetPath
        then targetPath
        else baseDir </> targetPath

-------------------------------------------------------------------------------
-- Reading HEAD
-------------------------------------------------------------------------------

-- | Read the current branch name from @HEAD@.
-- Returns 'Nothing' on detached HEAD or missing file.
readBranch :: GitRepo -> IO (Maybe String)
readBranch (GitRepo gd) = runMaybeT $ do
  let headFile = gd </> "HEAD"
  guard =<< lift (doesFileExist headFile)
  content <- lift $ readFileUtf8 headFile
  fmap T.unpack
    . MaybeT
    . pure
    $ T.stripPrefix "ref: refs/heads/"
    $ T.strip content

-------------------------------------------------------------------------------
-- Reading git config
-------------------------------------------------------------------------------

-- | Read a single value from the repo's @.git\/config@.
--
-- Key format follows git conventions:
--
--   * @\"section.variable\"@   -- looks for @[section]@ then @variable@
--   * @\"section.sub.variable\"@ -- looks for @[section \"sub\"]@ then @variable@
readConfigValue :: GitRepo -> String -> IO (Maybe String)
readConfigValue (GitRepo gd) key = runMaybeT $ do
  let configFile = gd </> "config"
  guard =<< lift (doesFileExist configFile)
  content <- lift $ readFileUtf8 configFile
  fmap T.unpack . MaybeT . pure $ lookupGitConfig (T.pack key) content

-- | Pure lookup in git-config text.  Exported for testing.
lookupGitConfig :: Text -> Text -> Maybe Text
lookupGitConfig key content = go Nothing . map (T.filter (/= '\r')) $ T.lines content
 where
  (targetSection, targetSubsection, targetKey) = splitConfigKey key

  go _ [] = Nothing
  go currentSection (line : rest) =
    case parseSectionHeader $ T.strip line of
      Just section -> go (Just section) rest
      Nothing
        | Just (k, v) <- parseKeyValue $ T.strip line
        , Just (sec, sub) <- currentSection
        , T.toLower sec == targetSection
        , sub == targetSubsection
        , T.toLower (T.strip k) == targetKey ->
            Just $ T.strip v
        | otherwise ->
            go currentSection rest

-- | Parse @section.key@ or @section.subsection.key@ into components.
-- Section and key are lowered; subsection is case-sensitive (per git spec).
splitConfigKey :: Text -> (Text, Maybe Text, Text)
splitConfigKey key = (T.toLower section, subsection, T.toLower variable)
 where
  (section, rest) = T.break (== '.') key
  afterDot = T.drop 1 rest
  (subsection, variable) = case T.breakOnEnd "." afterDot of
    ("", var) -> (Nothing, var)
    (subDot, var) -> (Just $ T.dropEnd 1 subDot, var)

-- | Parse a @[section]@ or @[section \"subsection\"]@ header.
parseSectionHeader :: Text -> Maybe (Text, Maybe Text)
parseSectionHeader line = do
  rest1 <- T.stripPrefix "[" line
  inner <- T.stripSuffix "]" rest1
  let trimmed = T.strip inner
  pure $ case T.breakOn " \"" trimmed of
    (name, quoted)
      | T.null quoted -> (T.strip name, Nothing)
      | otherwise ->
          let subsection = T.dropEnd 1 $ T.drop 2 quoted -- drop leading  \" and trailing \"
           in (T.strip name, Just subsection)

-- | Parse a @key = value@ line, skipping comments and blanks.
parseKeyValue :: Text -> Maybe (Text, Text)
parseKeyValue line
  | T.null line = Nothing
  | T.isPrefixOf "#" line = Nothing
  | T.isPrefixOf ";" line = Nothing
  | T.isInfixOf "=" line =
      let (k, rest) = T.breakOn "=" line
       in Just (T.strip k, T.strip $ T.drop 1 rest)
  | otherwise = Nothing
