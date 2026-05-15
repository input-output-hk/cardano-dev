module Herald.VersionFile
  ( readVersionFile
  , writeVersionFile
  )
where

import RIO

import Control.Monad.Trans.Maybe (MaybeT (..), runMaybeT)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Directory (doesFileExist)

import Herald.Pvp (Pvp (..), parsePvp, showPvp)
import Herald.Types (throwHerald)

-- | Read a PVP version from a plain text file.
-- Missing or empty files are treated as 0.0.0.0 with a warning to stderr.
readVersionFile :: FilePath -> IO Pvp
readVersionFile path = do
  mContent <- runMaybeT $ do
    guard =<< liftIO (doesFileExist path)
    raw <- liftIO $ TIO.readFile path
    let stripped = T.strip . stripBom $ raw
    guard . not $ T.null stripped
    pure stripped
  case mContent of
    Nothing -> do
      warnDefault path
      pure defaultVersion
    Just content -> parseVersionContent path content

warnDefault :: FilePath -> IO ()
warnDefault path =
  TIO.hPutStrLn stderr
    $ "Warning: version file missing or empty: "
    <> T.pack path
    <> "; defaulting to 0.0.0.0"

parseVersionContent :: FilePath -> Text -> IO Pvp
parseVersionContent path content = do
  let lines_ = filter (not . T.null) . map T.strip $ T.lines content
  case lines_ of
    [single] ->
      maybe
        (throwHerald $ "Failed to parse version in " <> path <> ": " <> T.unpack single)
        pure
        . parsePvp
        $ T.unpack single
    _ ->
      throwHerald $ "Version file must contain exactly one line: " <> path

-- | Write a PVP version to a plain text file (version + newline, nothing else).
writeVersionFile :: FilePath -> Pvp -> IO ()
writeVersionFile path version =
  writeFileBinary path . encodeUtf8 . T.pack $ showPvp version <> "\n"

defaultVersion :: Pvp
defaultVersion = Pvp (0 :| [0, 0, 0])

-- | Strip UTF-8 BOM if present.
stripBom :: Text -> Text
stripBom t = fromMaybe t $ T.stripPrefix "\xFEFF" t
