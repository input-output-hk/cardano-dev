module Herald.Fragment.Render
  ( renderSection
  , isNotable
  )
where

import RIO

import Data.List (sortBy)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Time (Day)

import Herald.Pvp (Pvp, showPvp)
import Herald.Types (Config (..), Fragment (..), KindDef (..))

-- | Render a list of fragments into a markdown changelog section.
renderSection :: Config -> Pvp -> Day -> [Fragment] -> Text
renderSection config version day frags =
  let header = "## " <> T.pack (showPvp version) <> " -- " <> T.pack (show day)
      notable = filter (isNotable config) frags
      sorted = sortBy (comparing $ Down . fragmentPR) notable
      entries = map (renderEntry config) sorted
   in if null entries
        then header <> "\n"
        else T.intercalate "\n" $ header : "" : entries

-- | Check if a fragment has at least one notable kind.
isNotable :: Config -> Fragment -> Bool
isNotable config frag =
  any (\k -> maybe False kindNotable $ Map.lookup k $ configKinds config) $ fragmentKinds frag

renderEntry :: Config -> Fragment -> Text
renderEntry config frag =
  T.intercalate
    "\n"
    [ "- " <> renderDescription (fragmentDescription frag)
    , "  (" <> T.intercalate ", " (fragmentKinds frag) <> ")"
    , "  [PR "
        <> tshow (fragmentPR frag)
        <> "]("
        <> configGitRepo config
        <> "/pull/"
        <> tshow (fragmentPR frag)
        <> ")"
    , ""
    ]

renderDescription :: Text -> Text
renderDescription desc =
  case T.lines desc of
    [] -> ""
    [single] -> single
    (firstLine : rest) -> T.intercalate "\n" $ firstLine : map ("  " <>) rest
