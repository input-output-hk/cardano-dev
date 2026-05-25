module Herald.Config
  ( loadConfig
  )
where

import RIO

import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Yaml qualified as Yaml

import Herald.Git (normaliseGitRepo)
import Herald.Types (Config (..), ProjectConfig (..))

-- | Load a herald config from a YAML file.
-- The @git-repo@ field is normalised so that bare @owner\/repo@ slugs,
-- SSH URLs, and full HTTPS URLs all produce a usable HTTPS base URL.
-- Validates per-project changes-dir constraints after parsing.
loadConfig :: FilePath -> IO (Either String Config)
loadConfig path = do
  result <- first Yaml.prettyPrintParseException <$> Yaml.decodeFileEither path
  pure $ do
    config <- result
    let normalised = config{configGitRepo = normaliseGitRepo $ configGitRepo config}
    case validateConfig normalised of
      [] -> Right normalised
      errs -> Left $ unlines errs

validateConfig :: Config -> [String]
validateConfig config =
  concat
    [ checkDuplicateChangesDirs config
    , checkNestedChangesDirs config
    , checkUncoveredProjects config
    ]

checkDuplicateChangesDirs :: Config -> [String]
checkDuplicateChangesDirs config =
  let dirs =
        maybeToList (configChangesDir config)
          <> mapMaybe projectChangesDir (Map.elems $ configProjects config)
      findDups [] = []
      findDups (x : xs)
        | x `elem` xs = ["Duplicate changes-dir: " <> x]
        | otherwise = findDups xs
   in findDups dirs

checkNestedChangesDirs :: Config -> [String]
checkNestedChangesDirs config =
  let dirs =
        maybeToList (configChangesDir config)
          <> mapMaybe projectChangesDir (Map.elems $ configProjects config)
      isNested a b = a /= b && ((a <> "/") `isPrefixOf` b || (b <> "/") `isPrefixOf` a)
      pairs = [(a, b) | a <- dirs, b <- dirs, a < b]
   in ["Nested changes-dirs: " <> a <> " and " <> b | (a, b) <- pairs, isNested a b]

checkUncoveredProjects :: Config -> [String]
checkUncoveredProjects config
  | isJust (configChangesDir config) = []
  | otherwise =
      [ "No changes-dir for project " <> show name <> " and no global changes-dir configured"
      | (name, pc) <- Map.toList $ configProjects config
      , isNothing $ projectChangesDir pc
      ]
