module Herald.Cabal
  ( readCabalVersion
  , writeCabalVersion
  )
where

import RIO

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
writeCabalVersion :: FilePath -> Pvp -> IO ()
writeCabalVersion path version = do
  content <- readFileUtf8 path
  let newContent = T.unlines . map (replaceLine . T.filter (/= '\r')) $ T.lines content
  writeFileUtf8 path newContent
 where
  replaceLine line
    | T.isPrefixOf "version:" line = "version: " <> T.pack (showPvp version)
    | otherwise = line
