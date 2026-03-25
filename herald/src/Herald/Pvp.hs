module Herald.Pvp
  ( Pvp (..)
  , BumpLevel
  , parsePvp
  , showPvp
  , bumpPvp
  )
where

import RIO

import Data.Char (isDigit)
import Data.List (intercalate)
import Data.List.NonEmpty (nonEmpty)

-- | A PVP version with one or more dot-separated non-negative integer components.
newtype Pvp = Pvp
  { pvpComponents :: NonEmpty Int
  }
  deriving (Eq, Ord, Show)

-- | PVP bump expressed as a version delta.
-- The leftmost non-zero component indicates which position to bump.
-- e.g. Pvp (0 :| [1, 0, 0]) means bump the 2nd digit and zero everything to its right.
type BumpLevel = Pvp

parsePvp :: String -> Maybe Pvp
parsePvp [] = Nothing
parsePvp s = do
  parts <- traverse parseComponent $ splitOnDot s
  ne <- nonEmpty parts
  pure $ Pvp ne
 where
  splitOnDot str = case break (== '.') str of
    (part, []) -> [part]
    (part, _ : rest) -> part : splitOnDot rest
  parseComponent [] = Nothing
  parseComponent cs
    | all isDigit cs = readMaybe cs
    | otherwise = Nothing

showPvp :: Pvp -> String
showPvp (Pvp cs) = intercalate "." . fmap show $ toList cs

-- | Bump a version by applying a bump level.
-- Finds the leftmost non-zero component in the bump level,
-- increments that component in the version, and zeros everything to its right.
-- If the version has fewer components than the bump position, it is extended with zeros.
-- If the bump level is all zeros, returns the version unchanged.
bumpPvp :: BumpLevel -> Pvp -> Pvp
bumpPvp (Pvp bumpCs) (Pvp verCs) =
  case findBumpIndex 0 $ toList bumpCs of
    Nothing -> Pvp verCs -- all-zero bump level: identity
    Just idx ->
      let verList = toList verCs
          padded = verList ++ replicate (max 0 $ idx + 1 - length verList) 0
          bumped = zipWith (\i v -> if i == idx then v + 1 else if i > idx then 0 else v) [0 ..] padded
       in Pvp . fromMaybe verCs $ nonEmpty bumped
 where
  findBumpIndex _ [] = Nothing
  findBumpIndex i (c : cs)
    | c /= 0 = Just i
    | otherwise = findBumpIndex (i + 1) cs
