# Extract command

Covers `herald extract` - changelog section extraction for release workflows.
Underpins [R12](../requirements.md#r12-changelog-section-extraction).

Uses: [changelog](changelog.md), [config](config.md).

## Overview

Reads a changelog file and prints the section body for a specific version.
Replaces bespoke per-repository extraction scripts (e.g. cardano-cli's `extract-changelog.sh`).

## Pure function

`extractSection :: Pvp -> Text -> Maybe Text`

- First argument: version to search for (normalised PVP).
- Second argument: full changelog file content.
- Returns: `Just` the section body (without the header line, leading/trailing blank and whitespace-only lines stripped) or `Nothing` if the version is not found.
- An empty section body (header immediately followed by next `## ` header) returns `Just ""`.
- Duplicate headers: returns the first match.
- CRLF: strips `\r` from input before matching (consistent with `prependSection`).

## Header matching

A header line starts at column 0 with `##` followed by one or more whitespace characters, then the canonical PVP version string (produced by `showPvp`).
The character after the version (if any) must not be a digit or `.`.
This accepts any header format regardless of what follows the version string.

Version matching uses the normalised PVP form: input `01.02.03.00` searches for `1.2.3.0`.

## Section boundaries

The section body runs from the line after the matching header to the line before the next section header (exclusive), or to EOF if there is no following header.
A section header is any line starting at column 0 with `##` followed by one or more whitespace characters.
`### ` sub-headers do not terminate a section; they are part of the body.
Content before the first section header (e.g. `# Changelog for ...`) is not part of any section.

## CLI behaviour

Two modes:

1. **Config mode**: `herald extract PACKAGE VERSION`
   Looks up the changelog path from `.herald.yml` via `projects.<PACKAGE>.changelog`.
   Unknown package errors list the available packages.
2. **Override mode**: `herald extract --changelog PATH VERSION`
   PACKAGE is not required.
   If PATH is a directory, appends `CHANGELOG.md`.
   If PATH is `-`, reads from stdin.

VERSION is parsed as PVP; non-PVP input (e.g. `v1.0.0`, `latest`) is rejected.

- Success: prints the section body to stdout with a trailing newline, silent on stderr, exits 0.
- Version not found: prints an error to stderr containing the version string, exits 1.
- Unknown package (config mode): error listing available packages, exits 1.
- Non-UTF8 file: error, exits 1.

## Integration with create-release

The [create-release](release-actions.md#create-release) action calls `herald extract --changelog <path> <version>` for changelog extraction.
When `changelog-path` is empty or the file does not exist, create-release skips extraction and creates the release without a body.

## Acceptance criteria

### Pure function
1. Multi-section changelog with `## VERSION -- DATE` headers: extracts the correct section body.
2. Changelog with bare `## VERSION` headers (no date): extracts the correct section body.
3. Mixed-format file (some headers with dates, some bare): each version extracts correctly.
4. Version not present in changelog: returns `Nothing`.
5. First section in file (preceded only by preamble): extracts correctly.
6. Last section in file (no following `## ` header, content to EOF): extracts correctly.
7. Version prefix safety: `1.0.0` and `1.0.0.1` each extract their own section, no cross-matching.
8. Empty section body (header immediately followed by next header): returns `Just ""`.
9. Leading/trailing blank and whitespace-only lines in section body are stripped.
10. `### ` sub-headers within a section are included in the body, not treated as boundaries.
11. CRLF line endings are normalised before matching.
12. Duplicate version headers: returns the first match.
13. Multiple whitespace characters between `##` and version are accepted.

### CLI
14. `herald extract PACKAGE VERSION` prints the section and exits 0.
15. `herald extract --changelog PATH VERSION` extracts without config lookup.
16. `--changelog` with a directory path appends `CHANGELOG.md`.
17. `--changelog -` reads from stdin.
18. Missing version exits 1 with error containing the version string.
19. Unknown package exits 1 with error listing available packages.
20. Non-PVP version input is rejected.
21. Leading zeros in version input are normalised (e.g. `01.02` searches for `1.2`).
22. Output always ends with a trailing newline.
23. Successful extraction is silent on stderr.
24. Non-UTF8 changelog file: error, exits 1.
