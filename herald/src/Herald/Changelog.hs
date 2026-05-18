module Herald.Changelog
  ( prependSection
  , extractSection
  )
where

import RIO

import Data.Char (isDigit, isSpace)
import Data.List (findIndex)
import Data.Text qualified as T

import Herald.Pvp (Pvp, showPvp)

extractSection :: Pvp -> Text -> Maybe Text
extractSection version content = do
  let versionStr = T.pack $ showPvp version
      ls = map (T.filter (/= '\r')) $ T.lines content
      matchesTarget line = matchesVersion versionStr line
  idx <- findIndex matchesTarget ls
  let body = drop (idx + 1) ls
      rest = takeWhile (not . isSectionHeader) body
      trimmed = reverse . dropWhile isBlankLine . reverse . dropWhile isBlankLine $ rest
  Just $ T.intercalate "\n" trimmed

prependSection :: FilePath -> Text -> IO ()
prependSection path section = do
  content <- readFileUtf8 path
  let ls = map (T.filter (/= '\r')) $ T.lines content
      (before, after) = break isSectionHeader ls
      newContent = T.unlines $ before ++ T.lines section ++ [""] ++ after
  writeFileUtf8 path newContent

isSectionHeader :: Text -> Bool
isSectionHeader line =
  "##"
    `T.isPrefixOf` line
    && maybe False (isSpace . fst) (T.uncons $ T.drop 2 line)

matchesVersion :: Text -> Text -> Bool
matchesVersion versionStr line
  | not $ isSectionHeader line = False
  | otherwise =
      let afterHashes = T.dropWhile (== '#') line
          afterSpace = T.dropWhile isSpace afterHashes
          (candidate, rest) = T.span (\c -> isDigit c || c == '.') afterSpace
       in candidate
            == versionStr
            && case T.uncons rest of
              Nothing -> True
              Just (c, _) -> not (isDigit c) && c /= '.'

isBlankLine :: Text -> Bool
isBlankLine = T.null . T.strip
