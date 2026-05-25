module Herald.Fragment
  ( validateFragment
  , validateFragmentDir
  , validateDirConsistency
  )
where

import RIO

import Data.Map.Strict qualified as Map
import Data.Text qualified as T

import Herald.Types (Config (..), Fragment (..))

-- | Validate a fragment against the config.
-- Returns a list of error messages. Empty list means valid.
validateFragment :: Config -> Fragment -> [Text]
validateFragment config frag =
  concat
    [ [ "Unknown project: " <> fragmentProject frag
      | not (Map.member (fragmentProject frag) (configProjects config))
      ]
    , ["Kinds list must not be empty" | null (fragmentKinds frag)]
    , [ "Unknown kind: " <> k
      | k <- fragmentKinds frag
      , not (Map.member k (configKinds config))
      ]
    , ["Description must not be empty" | T.null . T.strip $ fragmentDescription frag]
    , ["PR number must be positive" | fragmentPR frag <= 0]
    ]

-- | Validate a fragment found in a per-project directory.
-- Checks the base fragment validity plus directory-project consistency.
validateFragmentDir :: Config -> Text -> Fragment -> [Text]
validateFragmentDir config dirProject frag =
  validateFragment config frag
    <> validateDirConsistency config dirProject frag

-- | Directory-only consistency checks for a per-project fragment.
-- Does not include content validation ('validateFragment').
validateDirConsistency :: Config -> Text -> Fragment -> [Text]
validateDirConsistency config dirProject frag =
  [ "Directory " <> dirProject <> " does not match any project in config"
  | not (Map.member dirProject (configProjects config))
  ]
    <> [ "Fragment project "
           <> fragmentProject frag
           <> " does not match directory "
           <> dirProject
       | fragmentProject frag /= dirProject
       ]
