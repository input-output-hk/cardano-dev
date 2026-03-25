module Herald.Fragment
  ( validateFragment
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
