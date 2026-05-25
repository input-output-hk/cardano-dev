# Init command

Covers `herald init` - repository initialisation.

Uses: [config](config.md).

## Project discovery

- Discovers subdirectories containing `.cabal` files as projects (named after the `.cabal` file).
- Discovers a root-level `.cabal` file as a single project.
- Directories without a `.cabal` file are discovered as projects using their directory name, with `version-file: <dir>/version.txt` set automatically.
  See [ADR 002](../decisions/002-version-file.md) for rationale.
- Directories with empty-name `.cabal` files (e.g. `.ghc-wasm/.cabal`) are skipped.

## Git remote detection

- Reads the origin remote URL from `.git/config` (see [config - git config parsing](config.md#git-config-parsing)).
- Supports both SSH and HTTPS remote URLs.
- No origin remote: hard error ("Could not detect origin remote").

## Template

Creates `_TEMPLATE.yml` in the changes directory containing `project:` and `kind:` fields.

## Guard

Re-running `init` when `.herald.yml` already exists is an error ("already exists").

## Per-project `changes-dir`

`herald init` does not generate per-project `changes-dir` entries.
Users add these manually after initialisation.

## Generated config comments

The projects section includes a comment block mentioning `cabal-file`, `version-file`, and the optional per-project `changes-dir`.

## Acceptance criteria

1. Directories with empty-name `.cabal` files are skipped; valid packages are discovered.
2. Directories without `.cabal` files are discovered as projects with `version-file` set.
3. Root-level single `.cabal` file produces one project.
4. `_TEMPLATE.yml` is created with `project:` and `kind:` fields.
5. Re-init on existing config errors with "already exists".
6. No git remote: error with "Could not detect origin remote".
7. HTTPS remote URL is correctly extracted into config.
8. Directories with `.cabal` get `CabalFile`; without get `VersionFile`.
9. Generated `.herald.yml` text contains `"version-file"` in comments.
10. Generated `.herald.yml` text mentions `changes-dir` as an optional per-project field in comments.
11. `herald init` does not generate per-project `changes-dir` entries.
