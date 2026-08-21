module Herald.Cabal
  ( readCabalVersion
  , writeCabalVersion
  )
where

import RIO

import Data.Char (isSpace)
import Data.List (find)
import Data.Text qualified as T

import Herald.Pvp (Pvp, parsePvp, showPvp)

-- | Read the version from a .cabal file.
readCabalVersion :: FilePath -> IO (Maybe Pvp)
readCabalVersion path = do
  content <- readFileUtf8 path
  pure $ do
    line <- find (T.isPrefixOf "version:") . map (T.filter (/= '\r')) $ T.lines content
    let versionStr = T.strip . T.drop (T.length "version:") $ line
    parsePvp $ T.unpack versionStr

-- | Write a new version to a .cabal file, replacing the existing version: line.
-- All other lines are left byte-identical: line endings (LF or CRLF) and the
-- presence or absence of a final trailing newline are preserved, as is the
-- column alignment between @version:@ and its value.
writeCabalVersion :: FilePath -> Pvp -> IO ()
writeCabalVersion path version = do
  content <- readFileUtf8 path
  let newContent = T.intercalate "\n" . map replaceChunk $ T.splitOn "\n" content
  writeFileUtf8 path newContent
 where
  replaceChunk chunk = maybe (replaceLine chunk) ((<> "\r") . replaceLine) $ T.stripSuffix "\r" chunk

  replaceLine line
    | T.isPrefixOf "version:" line =
        "version:" <> (if T.null padding then " " else padding) <> T.pack (showPvp version)
    | otherwise = line
   where
    padding = T.takeWhile isSpace $ T.drop (T.length "version:") line
