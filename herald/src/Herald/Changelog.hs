module Herald.Changelog
  ( prependSection
  )
where

import RIO

import Data.Text qualified as T

-- | Prepend a changelog section before the first existing ## header.
-- If no ## header exists, appends the section at the end.
prependSection :: FilePath -> Text -> IO ()
prependSection path section = do
  content <- readFileUtf8 path
  let ls = map (T.filter (/= '\r')) $ T.lines content
      (before, after) = break (T.isPrefixOf "## ") ls
      newContent = T.unlines $ before ++ T.lines section ++ [""] ++ after
  writeFileUtf8 path newContent
