# Version sources

Covers `.cabal` file operations and version file operations - the two backends for reading and writing package versions.
Underpins [R9](../requirements.md#r9-version-source-replacement-on-release), [R11](../requirements.md#r11-version-file-support-for-non-haskell-projects).

Used by: [batch](batch.md), [next](next.md).
See also: [config - version source](config.md#version-source), [ADR 002](../decisions/002-version-file.md).

## `.cabal` file operations

### Reading

`readCabalVersion` extracts the version from the `version:` line.
Extra whitespace around the value is tolerated.
A `.cabal` file without a `version:` line returns `Nothing`.

### Writing

`writeCabalVersion` updates the `version:` line to the new value.
All other content (name, synopsis, build-depends, etc.) is preserved.
Write-then-read roundtrips correctly.

## Version file operations

### Reading

The file is read as text.
BOM, CRLF line endings, and leading/trailing whitespace are stripped before parsing.

- Valid: a single line containing a [PVP](pvp.md) version string.
- Three-component versions (e.g. `"1.2.3"`) are accepted.
- Empty file: treated as `0.0.0.0` with a warning to stderr.
- Missing file: treated as `0.0.0.0` with a warning to stderr.
- Extra text on the version line (e.g. `1.0.0.0 # initial`): parse error.
- Comment lines (e.g. `# version`): parse error.
- Multiple lines: parse error.

### Writing

The entire file is overwritten with `<version>\n`.
If the file does not exist, it is created.
Write-then-read roundtrips correctly.

## Acceptance criteria

### `.cabal` reading
1. `readCabalVersion` extracts a version from a standard `.cabal` file.
2. Extra whitespace around the `version:` value is tolerated.
3. A `.cabal` file without a `version:` line returns `Nothing`.

### `.cabal` writing
4. `writeCabalVersion` updates the version line and preserves all other content.
5. Write-then-read roundtrips correctly.

### Version file reading
6. Reads a valid PVP version from a plain text file.
7. Leading/trailing whitespace is stripped.
8. UTF-8 BOM is stripped.
9. CRLF line endings are handled.
10. Three-component versions are accepted.
11. Empty file returns `0.0.0.0`.
12. Missing file returns `0.0.0.0`.
13. Empty file emits a warning to stderr.
14. Missing file emits a warning to stderr.
15. Extra text on the version line is a parse error.
16. Comment lines are a parse error.
17. Multiple lines are a parse error.

### Version file writing
18. Write-then-read roundtrips correctly.
19. Writing to a non-existent file creates it.
20. Writing overwrites all existing content; file contains exactly `"<version>\n"`.
