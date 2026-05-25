module Main where

import Control.Exception (catch)
import Data.Text qualified as T
import Data.Time (Day, defaultTimeLocale, getCurrentTime, parseTimeM, utctDay)
import Options.Applicative
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import Herald.Command.Batch (BatchResult (..), CommitMode (..), batchPackage, commitBatchResult)
import Herald.Command.Init (initConfig)
import Herald.Command.New (NewOptions (..), createFragment, interactiveNew)
import Herald.Command.Next (nextVersion)
import Herald.Command.Validate (validateDiff, validateFiles, validatePR)
import Herald.Config (loadConfig)
import Herald.Fragment.Read (discoverFragmentPaths)
import Herald.Pvp (Pvp, parsePvp, showPvp)
import Herald.Types (Config (..), HeraldException (..), throwHerald)

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
  , batchVersion :: !(Maybe Pvp)
  , batchDate :: !(Maybe Day)
  , batchCommitMode :: !CommitMode
  }

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
    <*> optional
      (option pvpReader (long "version" <> short 'v' <> metavar "A.B.C.D" <> help "Explicit version"))
    <*> optional
      ( option
          dayReader
          (long "date" <> metavar "YYYY-MM-DD" <> help "Date for the changelog section header (default: today)")
      )
    <*> commitModeParser

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

opts :: ParserInfo (GlobalOpts, Command)
opts =
  info
    ((,) <$> globalOptsParser <*> commandParser <**> helper)
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

runCommand :: Config -> Command -> IO ()
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
    prErrors <- case validatePR_ valOpts of
      Just pr -> validatePR config "." pr
      Nothing -> pure []
    let errors = fileErrors <> diffErrors <> prErrors
    if null errors
      then putStrLn "All changelog fragments valid."
      else do
        throwHerald . T.unpack $ T.intercalate "\n" errors
  CmdBatch batchOpts -> do
    let version = batchVersion batchOpts
    day <- maybe (utctDay <$> getCurrentTime) pure $ batchDate batchOpts
    mResult <- batchPackage config "." (T.pack $ batchPackage_ batchOpts) version day
    case mResult of
      Nothing -> pure ()
      Just result -> do
        putStrLn $ "Batched " <> batchPackage_ batchOpts <> " " <> showPvp (batchResultVersion result)
        putStrLn $ "  Changelog: " <> batchResultChangelog result
        maybe (pure ()) (\path -> putStrLn $ "  Version file: " <> path) $ batchResultVersionPath result
        putStrLn "  Consumed changelog fragments:"
        mapM_ (\f -> putStrLn $ "    " <> f) $ batchResultFragments result
        commitBatchResult "." result $ batchCommitMode batchOpts
  CmdNext nextOpts -> do
    result <- nextVersion config "." (T.pack $ nextPackage nextOpts)
    maybe
      ( throwHerald $
          "Could not compute next version for "
            <> nextPackage nextOpts
            <> ". Are there unreleased changelog fragments?"
      )
      (putStrLn . showPvp)
      result

-- | Run the 'new' command. If all required options are provided, create fragments
-- directly. Otherwise, enter interactive mode.
runNew :: Config -> NewOpts -> IO ()
runNew config newOpts = do
  let projects = splitCommas $ newOptProjects newOpts
      kinds = splitCommas $ newOptKinds newOpts
  optsList <- case (projects, kinds, newOptDescription newOpts, newOptPR newOpts) of
    (_ : _, _ : _, Just desc, Just pr) ->
      pure [NewOptions (T.pack p) (map T.pack kinds) (T.pack desc) pr | p <- projects]
    _ -> interactiveNew config
  mapM_ (createAndReport config) optsList

createAndReport :: Config -> NewOptions -> IO ()
createAndReport config fragmentOpts = do
  path <- createFragment config "." fragmentOpts
  putStrLn $ "Created changelog fragment: " <> path

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
