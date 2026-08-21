module Main where

import Control.Exception (catch)
import Control.Monad (forM, forM_, void)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Maybe (hoistMaybe, runMaybeT)
import Data.Text qualified as T
import Data.Time (Day, defaultTimeLocale, getCurrentTime, parseTimeM, utctDay)
import Data.Version (showVersion)
import Options.Applicative
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import Herald.Command.Batch
  ( BatchResult (..)
  , CommitMode (..)
  , DryRunFragment (..)
  , DryRunResult (..)
  , FragmentFate (..)
  , VersionChoice (..)
  , batchPackage
  , commitBatchResult
  , dryRunBatch
  )
import Herald.Command.Init (initConfig)
import Herald.Command.New (NewOptions (..), createFragment, interactiveNew)
import Herald.Command.Next (nextVersion)
import Herald.Command.Validate (validateDiff, validateFiles, validatePR)
import Herald.Config (loadConfig)
import Herald.Fragment.Read (discoverFragmentPaths)
import Herald.Pvp (Pvp, parsePvp, showPvp)
import Herald.Types (Config (..), HeraldException (..), throwHerald)
import Paths_herald qualified as Paths

newtype GlobalOpts = GlobalOpts
  { globalConfig :: FilePath
  }

data Command
  = CmdInit
  | CmdNew !NewOpts
  | CmdValidate !ValidateOpts
  | CmdBatch !BatchOpts
  | CmdNext !NextOpts

-- | Options for 'new'. All fields are optional to support interactive mode.
data NewOpts = NewOpts
  { newOptProjects :: ![String]
  , newOptKinds :: ![String]
  , newOptDescription :: !(Maybe String)
  , newOptPR :: !(Maybe Int)
  }

data ValidateOpts = ValidateOpts
  { validateFiles_ :: ![FilePath]
  , validateDiff_ :: !Bool
  , validatePR_ :: !(Maybe Int)
  }

data BatchOpts = BatchOpts
  { batchPackage_ :: !String
  , batchVersionChoice :: !VersionChoice
  , batchDate :: !(Maybe Day)
  , batchMode :: !BatchMode
  }

-- | Whether to preview a batch (no mutation) or actually run it, optionally
-- committing and\/or tagging.
data BatchMode = DryRun | Execute !CommitMode

newtype NextOpts = NextOpts
  { nextPackage :: String
  }

-------------------------------------------------------------------------------
-- Parsers
-------------------------------------------------------------------------------

globalOptsParser :: Parser GlobalOpts
globalOptsParser =
  GlobalOpts
    <$> strOption
      ( long "config"
          <> short 'c'
          <> metavar "FILE"
          <> value ".herald.yml"
          <> help "Path to herald config file"
      )

newParser :: Parser NewOpts
newParser =
  NewOpts
    <$> many
      ( strOption
          ( long "project"
              <> short 'p'
              <> metavar "NAME[,NAME]"
              <> help "Project(s), comma-separated or repeated"
          )
      )
    <*> many
      ( strOption
          (long "kind" <> short 'k' <> metavar "KIND[,KIND]" <> help "Kind(s), comma-separated or repeated")
      )
    <*> optional
      ( strOption
          ( long "description"
              <> short 'd'
              <> metavar "TEXT"
              <> help "Change description (multiline via shell $'...\\n...')"
          )
      )
    <*> optional (option auto (long "pr" <> metavar "N" <> help "PR number"))

validateParser :: Parser ValidateOpts
validateParser =
  ValidateOpts
    <$> many
      ( argument
          str
          (metavar "[FILES...]" <> help "Changelog fragment files to validate (default: all unreleased)")
      )
    <*> switch
      ( long "diff"
          <> help "Check that projects with modified files have changelog fragments"
      )
    <*> optional
      ( option
          auto
          ( long "pr"
              <> metavar "N"
              <> help "Check that new fragments on this branch have this PR number"
          )
      )

batchParser :: Parser BatchOpts
batchParser =
  BatchOpts
    <$> argument str (metavar "PACKAGE" <> help "Package name")
    <*> versionChoiceParser
    <*> optional
      ( option
          dayReader
          (long "date" <> metavar "YYYY-MM-DD" <> help "Date for the changelog section header (default: today)")
      )
    <*> batchModeParser

-- | Batch requires the caller to choose exactly one of an explicit version or
-- auto-computation; 'UnspecifiedVersion' means neither flag was given.
versionChoiceParser :: Parser VersionChoice
versionChoiceParser =
  ExplicitVersion
    <$> option
      pvpReader
      (long "version" <> short 'v' <> metavar "A.B.C.D" <> help "Explicit version to release")
      <|> flag'
        AutoVersion
        (long "auto-version" <> help "Compute the version automatically from unreleased fragment kinds")
      <|> pure UnspecifiedVersion

batchModeParser :: Parser BatchMode
batchModeParser =
  flag'
    DryRun
    (long "dry-run" <> help "Preview the batch without writing, committing, or deleting anything")
    <|> (Execute <$> commitModeParser)

commitModeParser :: Parser CommitMode
commitModeParser =
  flag' CommitTag (long "commit-tag" <> help "Commit batch changes and create a PACKAGE-VERSION tag")
    <|> flag'
      Commit
      (long "commit" <> help "Commit batch changes (changelog, version, removed fragments)")
    <|> pure NoCommit

pvpReader :: ReadM Pvp
pvpReader = eitherReader $ \s ->
  maybe (Left "Invalid PVP version, expected A.B.C.D (e.g. 1.2.3.0)") Right $
    parsePvp s

dayReader :: ReadM Day
dayReader = eitherReader $ \s ->
  maybe (Left "Invalid date, expected YYYY-MM-DD") Right $
    parseTimeM True defaultTimeLocale "%Y-%m-%d" s

nextParser :: Parser NextOpts
nextParser =
  NextOpts
    <$> argument str (metavar "PACKAGE" <> help "Package name")

commandParser :: Parser Command
commandParser =
  subparser
    ( command
        "init"
        ( info
            (pure CmdInit <**> helper)
            (progDesc "Scan the repository and generate .herald.yml with discovered projects")
        )
        <> command
          "new"
          ( info
              (CmdNew <$> newParser <**> helper)
              (progDesc "Create a changelog fragment (interactive unless all flags provided)")
          )
        <> command
          "validate"
          ( info
              (CmdValidate <$> validateParser <**> helper)
              ( progDesc
                  "Validate changelog fragments, check PR numbers match (--pr), and ensure modified projects have changelog fragments (--diff)"
              )
          )
        <> command
          "batch"
          ( info
              (CmdBatch <$> batchParser <**> helper)
              ( progDesc
                  "Collect changelog fragments for PACKAGE, update the changelog file with a new section, bump the version, and remove processed fragments"
              )
          )
        <> command
          "next"
          ( info
              (CmdNext <$> nextParser <**> helper)
              ( progDesc
                  "Print the next version for PACKAGE by applying the highest bump from unreleased changelog fragments to the current version"
              )
          )
    )

-- | Top-level @--version@ flag: prints herald's own version and exits.
-- Distinct from @batch@'s @--version@, which sets the version being released.
versionOption :: Parser (a -> a)
versionOption =
  infoOption
    (showVersion Paths.version)
    (long "version" <> help "Show herald's version and exit")

opts :: ParserInfo (GlobalOpts, Command)
opts =
  info
    ((,) <$> globalOptsParser <*> commandParser <**> helper <**> versionOption)
    ( fullDesc
        <> progDesc "Manage changelog fragments, version bumps, and releases for PVP-versioned projects"
        <> header "herald - changelog and versioning automation"
    )

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

main :: IO ()
main = do
  (globalOpts, cmd) <- execParser opts
  case cmd of
    CmdInit -> do
      path <- initConfig "." (globalConfig globalOpts)
      putStrLn $ "Created config: " <> path
      putStrLn "Please review the generated configuration and adjust as needed."
    _ -> do
      configResult <- loadConfig $ globalConfig globalOpts
      config <-
        either (\err -> throwHerald $ "Loading config: " <> err) pure configResult
      runCommand config cmd
        `catch` \(HeraldException msg) -> do
          hPutStrLn stderr $ "Error: " <> msg
          exitFailure

runCommand :: MonadIO m => Config -> Command -> m ()
runCommand config cmd = case cmd of
  CmdInit -> pure ()
  CmdNew newOpts -> runNew config newOpts
  CmdValidate valOpts -> do
    fileErrors <- do
      files <- case validateFiles_ valOpts of
        [] -> discoverFragmentPaths config "."
        explicit -> pure explicit
      validateFiles config "." files
    diffErrors <-
      if validateDiff_ valOpts
        then validateDiff config "."
        else pure []
    prErrors <- concat <$> forM (validatePR_ valOpts) (validatePR config ".")
    let errors = fileErrors <> diffErrors <> prErrors
    if null errors
      then liftIO $ putStrLn "All changelog fragments valid."
      else do
        throwHerald . T.unpack $ T.intercalate "\n" errors
  CmdBatch batchOpts -> void . runMaybeT $ do
    let package = T.pack $ batchPackage_ batchOpts
        versionChoice = batchVersionChoice batchOpts
    day <- hoistMaybe (batchDate batchOpts) <|> liftIO (utctDay <$> getCurrentTime)
    case batchMode batchOpts of
      DryRun -> do
        result <- dryRunBatch config "." package versionChoice day
        printDryRunResult versionChoice result
      Execute commitMode -> do
        result <- batchPackage config "." package versionChoice day
        reportBatchResult commitMode result
  CmdNext nextOpts -> void . runMaybeT $ do
    pv <-
      nextVersion config "." (T.pack $ nextPackage nextOpts)
        <|> lift
          ( throwHerald $
              "Could not compute next version for "
                <> nextPackage nextOpts
                <> ". Are there unreleased changelog fragments?"
          )
    liftIO . putStrLn $ showPvp pv

-- | Print a completed batch's result and perform the requested commit\/tag.
reportBatchResult :: MonadIO m => CommitMode -> BatchResult -> m ()
reportBatchResult commitMode result = do
  liftIO $
    putStrLn $
      "Batched " <> T.unpack (batchResultPackage result) <> " " <> showPvp (batchResultVersion result)
  liftIO $ putStrLn $ "  Changelog: " <> batchResultChangelog result
  forM_ (batchResultVersionPath result) $ \path -> liftIO $ putStrLn $ "  Version file: " <> path
  liftIO $ putStrLn "  Consumed changelog fragments:"
  forM_ (batchResultFragments result) $ \fragment -> liftIO $ putStrLn $ "    " <> fragment
  commitBatchResult "." result commitMode

-- | Whether a version choice leaves the version to be computed rather than
-- pinning it explicitly.
isAutoComputedVersion :: VersionChoice -> Bool
isAutoComputedVersion (ExplicitVersion _) = False
isAutoComputedVersion _ = True

-- | Print a batch dry-run report: current\/new version (marked auto-computed
-- when applicable), each fragment's path\/kinds\/fate, and the changelog
-- section a real batch would prepend.
printDryRunResult :: MonadIO m => VersionChoice -> DryRunResult -> m ()
printDryRunResult versionChoice result = do
  liftIO $ putStrLn $ "Dry run for " <> T.unpack (dryRunPackage result) <> ":"
  liftIO $ putStrLn $ "  Current version: " <> maybe "(none)" showPvp (dryRunCurrentVersion result)
  liftIO $
    putStrLn $
      "  New version:     "
        <> showPvp (dryRunVersion result)
        <> if isAutoComputedVersion versionChoice then " (auto-computed)" else ""
  liftIO $ putStrLn "  Fragments:"
  mapM_ printFragment $ dryRunFragments result
  liftIO $ putStrLn ""
  liftIO $ putStrLn "Changelog section that would be prepended:"
  liftIO . putStrLn . T.unpack $ dryRunSection result
 where
  printFragment frag =
    liftIO $
      putStrLn $
        "    "
          <> dryRunFragmentPath frag
          <> " ("
          <> T.unpack (T.intercalate ", " $ dryRunFragmentKinds frag)
          <> ") - "
          <> case dryRunFragmentFate frag of
            Included -> "included in changelog"
            ExcludedNonNotable ->
              "excluded (non-notable kinds: " <> T.unpack (T.intercalate ", " $ dryRunFragmentKinds frag) <> ")"

-- | Run the 'new' command. If all required options are provided, create fragments
-- directly. Otherwise, enter interactive mode.
runNew :: MonadIO m => Config -> NewOpts -> m ()
runNew config newOpts = do
  let projects = splitCommas $ newOptProjects newOpts
      kinds = splitCommas $ newOptKinds newOpts
  optsList <- case (projects, kinds, newOptDescription newOpts, newOptPR newOpts) of
    (_ : _, _ : _, Just desc, Just pr) ->
      pure [NewOptions (T.pack p) (map T.pack kinds) (T.pack desc) pr | p <- projects]
    _ -> interactiveNew config
  mapM_ (createAndReport config) optsList

createAndReport :: MonadIO m => Config -> NewOptions -> m ()
createAndReport config fragmentOpts = do
  path <- createFragment config "." fragmentOpts
  liftIO $ putStrLn $ "Created changelog fragment: " <> path

-- | Split a list of strings on commas and flatten.
-- e.g. @[\"a,b\", \"c\"] -> [\"a\", \"b\", \"c\"]@
splitCommas :: [String] -> [String]
splitCommas = concatMap (map strip . splitOn ',')
 where
  splitOn _ [] = []
  splitOn delim s = case break (== delim) s of
    (part, []) -> [part]
    (part, _ : rest) -> part : splitOn delim rest
  strip = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')
