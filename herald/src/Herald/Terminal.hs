-- | Interactive terminal prompts for Herald.
--
-- Provides multi-select menus (with j\/k navigation), multi-line input,
-- and integer input.  Falls back to plain numbered-list input when stdout
-- is not a terminal (e.g.\ piped or in CI).
module Herald.Terminal
  ( promptMultiSelect
  , promptMultiLine
  , promptInt
  , stripAnsi
  )
where

import RIO

import Data.Char (isSpace)
import Data.List (zip3)
import Data.Text qualified as T
import System.Console.Haskeline (defaultSettings, getInputLine, runInputT)
import System.Directory (getTemporaryDirectory, removeFile)
import System.Environment (lookupEnv)
import System.IO qualified as IO
import System.Process (callCommand)

import Herald.Types (throwHerald)

-------------------------------------------------------------------------------
-- Multi-select prompt
-------------------------------------------------------------------------------

-- | Prompt the user to select one or more items from a navigable list.
--
-- In a terminal: j\/k or arrows to move, space to toggle, enter to confirm.
-- Non-terminal: falls back to comma-separated number input.
promptMultiSelect :: String -> [a] -> (a -> String) -> IO [a]
promptMultiSelect label items formatItem = do
  when (null items)
    $ throwHerald
    $ "No "
    <> label
    <> "s configured"
  isTerm <- IO.hIsTerminalDevice IO.stdout
  if isTerm then interactiveSelect else fallbackSelect isTerm
 where
  fallbackSelect isTerm = do
    putPrompt isTerm $ "Choose " <> label <> "(s) (comma-separated numbers):"
    forM_ (zip [1 :: Int ..] items) $ \(i, item) ->
      IO.putStrLn $ "  " <> colorise isTerm "36" (show i <> ".") <> " " <> formatItem item
    IO.putStr $ colorise isTerm "36" "> "
    IO.hFlush IO.stdout
    input <- IO.getLine
    case parseSelection items input of
      Just selected | not (null selected) -> pure selected
      _ -> fallbackSelect isTerm

  interactiveSelect = do
    putPrompt True $ "Choose " <> label <> "(s)  [j/k or arrows move, space toggle, enter confirm]"
    let initSelected = replicate (length items) False
    IO.hSetBuffering IO.stdin IO.NoBuffering
    IO.hSetEcho IO.stdin False
    result <-
      menuLoop True 0 initSelected `finally` do
        IO.hSetBuffering IO.stdin IO.LineBuffering
        IO.hSetEcho IO.stdin True
    let selected = [item | (item, sel) <- zip items result, sel]
    if null selected
      then do
        IO.putStrLn $ colorise True "31" "  No selection. Try again."
        interactiveSelect
      else pure selected

  menuLoop firstRender cursor selected = do
    renderMenu firstRender cursor selected
    key <- readKey
    let n = length items
    case key of
      KeyUp -> menuLoop False (max 0 (cursor - 1)) selected
      KeyDown -> menuLoop False (min (n - 1) (cursor + 1)) selected
      KeyToggle ->
        let toggled = zipWith (\i s -> if i == cursor then not s else s) [0 :: Int ..] selected
         in menuLoop False cursor toggled
      KeyConfirm -> do
        clearLines (length items)
        pure selected
      KeyOther -> menuLoop False cursor selected

  renderMenu firstRender cursor selected = do
    unless firstRender $ clearLines (length items)
    forM_ (zip3 [0 :: Int ..] items selected) $ \(i, item, sel) ->
      let pointer = if i == cursor then colorise True "36" "> " else "  "
          check = if sel then colorise True "32" "[x] " else "[ ] "
       in IO.putStrLn $ pointer <> check <> formatItem item
    IO.hFlush IO.stdout

-------------------------------------------------------------------------------
-- Multi-line prompt
-------------------------------------------------------------------------------

-- | Prompt for multiline text.
--
-- When @$VISUAL@ or @$EDITOR@ is set, opens the editor for full multi-line
-- editing (arrow keys, undo, etc.).  Otherwise falls back to haskeline
-- line-by-line input (empty line finishes).
promptMultiLine :: String -> IO Text
promptMultiLine label = go
 where
  go = do
    isTerm <- IO.hIsTerminalDevice IO.stdout
    result <-
      if isTerm then terminalInput else plainInput isTerm
    if T.null result
      then do
        IO.putStrLn $ colorise isTerm "31" "Cannot be empty, try again."
        go
      else pure result

  terminalInput = do
    visual <- lookupEnv "VISUAL"
    editor <- lookupEnv "EDITOR"
    maybe haskelineInput editorInput $ visual <|> editor

  editorInput editor = do
    putPrompt True $ label <> ":"
    IO.putStrLn $ colorise True "36" "  (opening " <> editor <> ")"
    tmpDir <- getTemporaryDirectory
    (path, tmpHandle) <- IO.openTempFile tmpDir "herald-description.txt"
    IO.hClose tmpHandle
    flip finally (removeFile path) $ do
      callCommand $ editor <> " " <> shellQuote path
      T.strip <$> readFileUtf8 path

  haskelineInput = do
    putPrompt True $ label <> " (empty line to finish):"
    lineTexts <- runInputT defaultSettings collect
    pure . T.strip $ T.intercalate "\n" lineTexts
   where
    collect = do
      mLine <- getInputLine "| "
      case mLine of
        Nothing -> pure []
        Just line
          | all isSpace line -> pure []
          | otherwise -> (T.pack line :) <$> collect

  plainInput isTerm = do
    putPrompt isTerm $ label <> " (empty line to finish):"
    lineTexts <- collectLinesPlain isTerm
    pure . T.strip $ T.intercalate "\n" lineTexts

  collectLinesPlain isTerm = do
    IO.putStr $ colorise isTerm "36" "| "
    IO.hFlush IO.stdout
    line <- stripAnsi . T.pack <$> IO.getLine
    if T.null $ T.strip line
      then pure []
      else (line :) <$> collectLinesPlain isTerm

-------------------------------------------------------------------------------
-- Integer prompt
-------------------------------------------------------------------------------

-- | Prompt for a positive integer.
-- Uses haskeline for line editing when in a terminal.
promptInt :: String -> IO Int
promptInt label = go
 where
  go = do
    isTerm <- IO.hIsTerminalDevice IO.stdout
    putPrompt isTerm $ label <> ":"
    input <-
      if isTerm
        then runInputT defaultSettings (getInputLine "> ") >>= maybe (pure "") pure
        else do
          IO.putStr $ colorise isTerm "36" "> "
          IO.hFlush IO.stdout
          IO.getLine
    case readMaybe input of
      Just n | n > 0 -> pure n
      _ -> do
        IO.putStrLn $ colorise isTerm "31" "Enter a positive integer."
        go

-------------------------------------------------------------------------------
-- Internals
-------------------------------------------------------------------------------

data MenuKey = KeyUp | KeyDown | KeyToggle | KeyConfirm | KeyOther

readKey :: IO MenuKey
readKey = do
  c <- IO.getChar
  case c of
    'k' -> pure KeyUp
    'j' -> pure KeyDown
    ' ' -> pure KeyToggle
    '\n' -> pure KeyConfirm
    '\r' -> pure KeyConfirm
    '\ESC' -> do
      c2 <- IO.getChar
      case c2 of
        '[' -> do
          c3 <- IO.getChar
          pure $ case c3 of
            'A' -> KeyUp
            'B' -> KeyDown
            _ -> KeyOther
        _ -> pure KeyOther
    _ -> pure KeyOther

clearLines :: Int -> IO ()
clearLines n = when (n > 0) $ do
  IO.putStr $ "\ESC[" <> show n <> "A"
  IO.putStr "\ESC[J"

putPrompt :: Bool -> String -> IO ()
putPrompt isTerm msg =
  IO.putStrLn $ colorise isTerm "1;32" "? " <> msg

colorise :: Bool -> String -> String -> String
colorise False _ s = s
colorise True code s = "\ESC[" <> code <> "m" <> s <> "\ESC[0m"

parseSelection :: [a] -> String -> Maybe [a]
parseSelection items input = do
  let parts = map (T.strip . T.pack) $ splitOn ',' input
      indexed = zip [1 :: Int ..] items
  indices <- traverse (readMaybe . T.unpack) parts
  traverse (`lookup` indexed) indices

splitOn :: Char -> String -> [String]
splitOn _ [] = []
splitOn delim s = case break (== delim) s of
  (part, []) -> [part]
  (part, _ : rest) -> part : splitOn delim rest

-- | Shell-quote a string by wrapping in single quotes and escaping embedded
-- single quotes.  e.g. @"it's"@ becomes @"'it'\\''s'"@.
shellQuote :: String -> String
shellQuote s = "'" <> concatMap (\c -> if c == '\'' then "'\\''" else [c]) s <> "'"

-- | Strip ANSI escape sequences from text (e.g. arrow key artifacts).
stripAnsi :: Text -> Text
stripAnsi = go
 where
  go t = case T.breakOn "\ESC[" t of
    (before, rest)
      | T.null rest -> before
      | otherwise ->
          let afterEsc = T.drop 2 rest -- drop \ESC[
              afterSeq = T.dropWhile (\c -> c >= '0' && c <= '?' || c == ';') afterEsc
           in before <> go (T.drop 1 afterSeq) -- drop the final letter
