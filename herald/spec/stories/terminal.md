# Terminal output handling

Covers ANSI escape sequence stripping for clean text output.

## Behaviour

Herald strips ANSI escape sequences from terminal output to produce clean text for non-interactive contexts (e.g. CI logs, piped output).

- Arrow key sequences (e.g. `\ESC[A`, `\ESC[D`) are removed.
- Colour codes (e.g. `\ESC[31m`, `\ESC[0m`) are removed.
- Plain text without ANSI sequences is preserved unchanged.
- Mixed content (text interleaved with ANSI sequences) retains only the text portions.
- Truncated or malformed escape sequences are handled gracefully.

## Acceptance criteria

1. Arrow key escape sequences are stripped from output.
2. Colour code escape sequences are stripped from output.
3. Plain text without escape sequences passes through unchanged.
4. Mixed text and ANSI sequences retains only the text portions.
5. Truncated escape sequences are handled without error.
