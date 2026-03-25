module Herald.Types
  ( KindDef (..)
  , Fragment (..)
  , ProjectConfig (..)
  , Config (..)
  , HeraldException (..)
  , throwHerald
  , defaultKinds
  )
where

import RIO

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.Map.Strict qualified as Map

import Herald.Pvp (BumpLevel, Pvp (..), parsePvp, showPvp)

-- | User-facing error with a clean message (no backtrace noise).
newtype HeraldException = HeraldException String

instance Show HeraldException where
  show (HeraldException msg) = msg

instance Exception HeraldException where
  displayException (HeraldException msg) = msg

-- | Throw a user-facing error with a clean message.
throwHerald :: MonadIO m => String -> m a
throwHerald = throwIO . HeraldException

data KindDef = KindDef
  { kindNotable :: !Bool
  , kindBump :: !BumpLevel
  , kindDescription :: !(Maybe Text)
  }
  deriving (Eq, Show)

instance FromJSON KindDef where
  parseJSON = withObject "KindDef" $ \o -> do
    notable <- fromMaybe True <$> o .:? "notable"
    bumpStr <- o .: "bump"
    pvp <- maybe (fail $ "Invalid PVP version in bump: " <> bumpStr) pure $ parsePvp bumpStr
    desc <- o .:? "description"
    pure $ KindDef notable pvp desc

instance ToJSON KindDef where
  toJSON kd =
    object
      $ ["notable" .= kindNotable kd | not $ kindNotable kd]
      <> ["bump" .= showPvp (kindBump kd)]
      <> maybe [] (\d -> ["description" .= d]) (kindDescription kd)

data Fragment = Fragment
  { fragmentProject :: !Text
  , fragmentKinds :: ![Text]
  , fragmentDescription :: !Text
  , fragmentPR :: !Int
  }
  deriving (Eq, Show)

instance FromJSON Fragment where
  parseJSON = withObject "Fragment" $ \o ->
    Fragment
      <$> o
      .: "project"
      <*> o
      .: "kind"
      <*> o
      .: "description"
      <*> o
      .: "pr"

instance ToJSON Fragment where
  toJSON f =
    object
      [ "project" .= fragmentProject f
      , "kind" .= fragmentKinds f
      , "description" .= fragmentDescription f
      , "pr" .= fragmentPR f
      ]

data ProjectConfig = ProjectConfig
  { projectChangelog :: !FilePath
  , projectCabalFile :: !(Maybe FilePath)
  }
  deriving (Eq, Show)

instance FromJSON ProjectConfig where
  parseJSON = withObject "ProjectConfig" $ \o ->
    ProjectConfig
      <$> o
      .: "changelog"
      <*> o
      .:? "cabal-file"

instance ToJSON ProjectConfig where
  toJSON pc =
    object
      $ [ "changelog" .= projectChangelog pc
        ]
      <> maybe [] (\cf -> ["cabal-file" .= cf]) (projectCabalFile pc)

data Config = Config
  { configGitRepo :: !Text
  , configChangesDir :: !FilePath
  , configKinds :: !(Map Text KindDef)
  , configProjects :: !(Map Text ProjectConfig)
  }
  deriving (Eq, Show)

instance FromJSON Config where
  parseJSON = withObject "Config" $ \o ->
    Config
      <$> o
      .: "git-repo"
      <*> o
      .: "changes-dir"
      <*> o
      .: "kinds"
      <*> o
      .: "projects"

instance ToJSON Config where
  toJSON c =
    object
      [ "git-repo" .= configGitRepo c
      , "changes-dir" .= configChangesDir c
      , "kinds" .= configKinds c
      , "projects" .= configProjects c
      ]

-- | Default kinds shipped with every new herald config.
defaultKinds :: Map Text KindDef
defaultKinds =
  Map.fromList
    [ ("breaking", KindDef True (Pvp (0 :| [1, 0, 0])) (Just "the API has changed in a breaking way"))
    , ("feature", KindDef True (Pvp (0 :| [0, 1, 0])) (Just "introduces a new feature"))
    , ("compatible", KindDef True (Pvp (0 :| [0, 1, 0])) (Just "the API has changed but is non-breaking"))
    , ("bugfix", KindDef True (Pvp (0 :| [0, 0, 1])) (Just "fixes a defect"))
    , ("optimisation", KindDef True (Pvp (0 :| [0, 0, 1])) (Just "measurable performance improvements"))
    , ("refactoring", KindDef False (Pvp (0 :| [0, 0, 1])) (Just "code quality improvements"))
    , ("test", KindDef False (Pvp (0 :| [0, 0, 1])) (Just "fixes or modifies tests"))
    , ("maintenance", KindDef False (Pvp (0 :| [0, 0, 1])) (Just "not directly related to the code"))
    , ("release", KindDef False (Pvp (0 :| [0, 0, 1])) (Just "related to a new release preparation"))
    , ("documentation", KindDef False (Pvp (0 :| [0, 0, 1])) (Just "change in code docs, haddocks"))
    ]
