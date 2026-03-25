module Herald.Config
  ( loadConfig
  )
where

import RIO

import Data.Yaml qualified as Yaml

import Herald.Git (normaliseGitRepo)
import Herald.Types (Config (..))

-- | Load a herald config from a YAML file.
-- The @git-repo@ field is normalised so that bare @owner\/repo@ slugs,
-- SSH URLs, and full HTTPS URLs all produce a usable HTTPS base URL.
loadConfig :: FilePath -> IO (Either String Config)
loadConfig path = fmap normalise . first Yaml.prettyPrintParseException <$> Yaml.decodeFileEither path
 where
  normalise c = c{configGitRepo = normaliseGitRepo $ configGitRepo c}
