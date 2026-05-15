# ADR 002: Support version-file for non-Haskell projects

## Status

Accepted and implemented.

## Context

Herald originally read and wrote versions exclusively via `.cabal` files (`version:` field).
Projects without a `.cabal` file (GitHub Actions, plain scripts, non-Haskell tools) could not use `herald next` or auto-versioned `herald batch`.

The immediate use case was versioning the reusable GitHub Actions (`herald-validate`, `herald-release`) shipped from the same repository.

## Decision

Add a `version-file` field per project in `.herald.yml`, mutually exclusive with `cabal-file`.
The version file is a plain text file containing a single PVP version string (e.g. `1.2.3.0`).

### Configuration

```yaml
projects:
  herald-release:
    changelog: actions/herald-release/CHANGELOG.md
    version-file: actions/herald-release/version.txt
  cardano-api:
    changelog: cardano-api/CHANGELOG.md
    cabal-file: cardano-api/cardano-api.cabal
```

### Internal representation

Replace `projectCabalFile :: Maybe FilePath` with a sum type:

```haskell
data VersionSource
  = CabalFile !FilePath
  | VersionFile !FilePath
```

All call sites that pattern-match on `projectCabalFile` dispatch on `VersionSource` instead.

### File format

- Single line containing a PVP version string.
- Reading strips BOM, CRLF, and leading/trailing whitespace before parsing.
- No comments, no extra text - any non-version content after stripping is a parse error.
- Empty or missing file is treated as version `0.0.0.0` with a warning to stderr.

### Write semantics

- Overwrite the entire file with `<version>\n`.
- Create the file if it does not exist.

### Affected commands

| Command | Change |
|---------|--------|
| `batch` | Read version from version-file, bump, write back. Stage in `--commit`/`--commit-tag` mode. Create file if missing. |
| `next` | Read version from version-file, compute next version. Missing file treated as `0.0.0.0`. |
| `init` | Directories without a `.cabal` file get `version-file: <dir>/version.txt`. |
| `validate` | No change. |
| `new` | No change. |

### Release action

No changes needed - it calls `herald next` and `herald batch` which are version-source agnostic.

## Consequences

- Existing configs using `cabal-file` continue to work without changes.
- `init` now discovers non-cabal directories as projects (behavioural change from before, where they were skipped).
- Mutual exclusion between `cabal-file` and `version-file` is enforced at config parse time, not lazily.
