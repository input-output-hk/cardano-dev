# Release actions

Covers the reusable composite GitHub Actions for packaging artifacts and creating GitHub releases.
Underpins [R13](../requirements.md#r13-reusable-release-actions).

Uses: [extract](extract.md) (optionally), [changelog](changelog.md).

## Overview

Decompose cardano-cli's monolithic `release-upload.yml` into four independent composite actions in `cardano-dev`.
Each action is a self-contained step that callers compose in their release workflow.

## wait-for-hydra

Already exists in [`input-output-hk/actions`](https://github.com/input-output-hk/actions/tree/main/wait-for-hydra).
Polls Hydra CI check-runs until the required eval succeeds or fails.
No changes needed; callers that do not use Hydra (cardano-api) simply omit it.

## pull-nix-artifacts

`actions/pull-nix-artifacts/`

Downloads nix-built binaries from a flake and uploads them as GitHub artifacts.

### Inputs

- `flake-ref` (required): flake reference, e.g. `github:input-output-hk/cardano-dev/herald-0.3.0.0`.
- `platforms` (required): JSON array of `{"id": "<platform>", "derivation": "<nix-attr-path>"}` entries.
- `artifact-prefix` (optional, defaults to repository name): prefix for uploaded artifact names.

### Behaviour

- Installs nix with IOG cache configuration (`cache.iog.io` substituter, `hydra.iohk.io` public key).
- Resolves the flake and locks it via `nix flake metadata --json`.
- Builds each derivation with `--builders "" --max-jobs 0` (cache-only, no local compilation).
- For platform ids containing `win`: copies the entire `result/bin/` directory (preserving DLLs).
- For other platforms: copies the single binary from `result/bin/`.
- Uploads each platform's files as `{artifact-prefix}-{id}`.

### Platform map examples

**cardano-cli** (Hydra-built):
```json
[
  {"id": "x86_64-linux",  "derivation": "hydraJobs.x86_64-linux.ghc967-x86_64-unknown-linux-musl.packages.cardano-cli:exe:cardano-cli"},
  {"id": "aarch64-linux", "derivation": "hydraJobs.x86_64-linux.ghc967-aarch64-unknown-linux-musl.packages.cardano-cli:exe:cardano-cli"},
  {"id": "x86_64-darwin", "derivation": "hydraJobs.x86_64-darwin.packages.cardano-cli:exe:cardano-cli"},
  {"id": "aarch64-darwin", "derivation": "hydraJobs.aarch64-darwin.packages.cardano-cli:exe:cardano-cli"},
  {"id": "win64",         "derivation": "hydraJobs.x86_64-linux.ghc9122-x86_64-w64-mingw32.packages.cardano-cli:exe:cardano-cli"}
]
```

**Herald** (Hydra-built):
```json
[
  {"id": "x86_64-linux",   "derivation": "hydraJobs.x86_64-linux.herald.release.x86_64-linux"},
  {"id": "aarch64-linux",  "derivation": "hydraJobs.x86_64-linux.herald.release.aarch64-linux"},
  {"id": "x86_64-windows", "derivation": "hydraJobs.x86_64-linux.herald.release.x86_64-windows"},
  {"id": "aarch64-darwin",  "derivation": "hydraJobs.aarch64-darwin.herald.release.aarch64-darwin"}
]
```

## source-tarball

`actions/source-tarball/`

Runs `cabal sdist` for a named package and uploads the resulting `.tar.gz`.

### Inputs

- `package` (required): Cabal package name.
- `artifact-prefix` (optional, defaults to package name): prefix for the uploaded artifact name.
- `project-dir` (optional, defaults to `.`): directory containing `cabal.project`.

### Behaviour

- Does not call `actions/checkout` - caller checks out the repository and configures the build environment.
- Runs `cabal sdist <package>` in `project-dir`.
- Locates the resulting `.tar.gz` in `dist-newstyle/sdist/`.
- Uploads it as `{artifact-prefix}-source`.

## create-release

`actions/create-release/`

The shared core: downloads artifacts, compresses, checksums, extracts changelog, creates GitHub release.

### Inputs

- `artifact-prefix` (required): prefix used by upstream artifact uploads.
- `tag` (required): git tag for the release.
- `tag-prefix` (optional): prefix to strip from tag to produce the release name (e.g. `cardano-cli-`).
- `changelog-path` (optional): path to CHANGELOG.md.
- `changelog-version` (optional): version string to extract from the changelog.
- `dry-run` (optional, defaults to `false`): produce artifacts and checksums but skip GitHub release creation.

### Behaviour

- Downloads all artifacts matching `artifact-prefix` via `actions/download-artifact` with `merge-multiple: true`.
- For artifacts whose name does not contain `win` or `source`: creates `{tag}-{id}.tar.gz`.
- For artifacts whose name contains `win`: creates `{tag}-{id}.zip`.
- For artifacts whose name contains `source`: includes the `.tar.gz` directly (no recompression).
- Generates `{tag}-sha256sums.txt` with one `sha256sum` line per archive.
- Extracts the changelog section for `changelog-version` from `changelog-path`.
  Matches `## VERSION` where the next character is not a digit or `.` (any header format).
  If `changelog-path` is empty or the file does not exist, creates the release without a changelog body.
- Creates or updates a GitHub release for `tag` via `input-output-hk/action-gh-release@v1`.
  Existing releases are updated (idempotent), not duplicated.
- In dry-run mode: uploads compressed archives and checksums as workflow artifacts, skips release creation.

## Acceptance criteria

### pull-nix-artifacts
1. Action accepts a JSON platform-derivation map and flake-ref, builds each derivation.
2. Builds use `--builders "" --max-jobs 0` (cache-only).
3. Windows platform copies entire `result/bin/` directory.
4. Each platform uploaded as a separate artifact named `{artifact-prefix}-{id}`.
5. Action installs nix internally; caller does not need to.

### source-tarball
6. Action accepts a package name, runs `cabal sdist`, uploads the `.tar.gz`.
7. Action does not call `actions/checkout` internally.
8. Optional `project-dir` input for monorepo layouts.

### create-release
9. Unix artifacts compressed as `.tar.gz`, windows as `.zip`.
10. Source tarball artifacts passed through without recompression.
11. SHA256 checksums file covers all archives.
12. Changelog extraction supports both `## VERSION -- DATE` and `## VERSION` headers.
13. Missing changelog path: release created without body.
14. Idempotent: existing release updated, not duplicated.
15. Tag prefix stripped to produce release name.
16. Dry-run mode produces artifacts and checksums but no GitHub release.
