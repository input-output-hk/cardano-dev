# Release actions

Covers the reusable composite GitHub Actions for packaging artifacts and creating GitHub releases.
Underpins [R13](../requirements.md#r13-reusable-release-actions).

Uses: [extract](extract.md), [changelog](changelog.md).

## Overview

Decompose cardano-cli's monolithic `release-upload.yml` into three independent composite actions in `cardano-dev`.
Each action is a self-contained step that callers compose in their release workflow.

A fourth action, `wait-for-hydra`, already exists in [`input-output-hk/actions`](https://github.com/input-output-hk/actions/tree/latest/wait-for-hydra).
It polls Hydra CI check-runs until the required eval succeeds or fails.
No changes needed; callers that do not use Hydra (cardano-api) simply omit it.

## pull-nix-artifacts

`actions/pull-nix-artifacts/`

Downloads nix-built binaries from the IOG binary cache and uploads them as GitHub artifacts.

### Inputs

- `flake-ref` (required): flake reference, e.g. `github:input-output-hk/cardano-dev/herald-0.3.0.0`.
- `platforms` (required): JSON string - array of `{"id": "<platform>", "derivation": "<nix-attr-path>"}` entries.
- `artifact-prefix` (optional, defaults to repository name): prefix for uploaded artifact names.

### Outputs

- `locked-url`: the locked flake URL resolved via `nix flake metadata --json`.

### Behaviour

- Caller provides nix (the action does not install it).
- Validates the `platforms` JSON structure: must be a non-empty array, each entry must have `id` and `derivation` string fields.
- Resolves the flake and locks it via `nix flake metadata --json`.
  Exposes the locked URL as the `locked-url` output.
- Loops over all platforms in a single job (all downloads run on the same runner - cache-only fetch is platform-independent).
- Downloads each derivation from the IOG binary cache using `--builders "" --max-jobs 0` (no local compilation, no remote builders - fetches from substituters only, fails if not cached).
- Copies all files from `result/bin/` using `cp --dereference` (nix store paths are symlinks).
  Trusts that nix store permissions preserve the executable bit.
- If any platform's download fails, the action fails immediately (no partial releases).
- Uploads each platform's files as `{artifact-prefix}-{id}` with 1-day retention.

### Platform map examples

**cardano-cli** (Hydra-built):
```json
[
  {"id": "x86_64-linux",  "derivation": "hydraJobs.x86_64-linux.ghc967-x86_64-unknown-linux-musl.packages.cardano-cli:exe:cardano-cli"},
  {"id": "aarch64-linux", "derivation": "hydraJobs.x86_64-linux.ghc967-aarch64-unknown-linux-musl.packages.cardano-cli:exe:cardano-cli"},
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

### Outputs

- `filename`: the exact filename of the uploaded tarball (e.g. `cardano-api-10.14.0.0.tar.gz`).

### Behaviour

- Does not call `actions/checkout` - caller checks out the repository.
- Caller provides GHC and cabal (the action does not install them).
- Runs `cabal sdist <package>` in `project-dir`.
- Runs `cabal check` in the package directory.
  Fails on any warning or error (strict mode).
- Locates the resulting `.tar.gz` in `dist-newstyle/sdist/`.
- Uploads it as `{artifact-prefix}-source` with 1-day retention.
- One package per invocation.
  Callers use multiple steps or a matrix for multiple packages.

## create-release

`actions/create-release/`

The shared core: downloads artifacts, compresses, checksums, creates GitHub release.

### Inputs

- `artifact-prefix` (required): prefix used by upstream artifact uploads.
- `tag` (required): git tag for the release.
- `tag-prefix` (optional): prefix to strip from tag to produce the release name (e.g. `cardano-cli-`).
  If set, `tag` must start with `tag-prefix`; otherwise the action errors.
  If empty, the release name equals the full tag.
- `changelog-path` (optional): path to CHANGELOG.md.
- `changelog-version` (optional): version string to extract from the changelog.
  `changelog-path` and `changelog-version` must both be provided or both be absent.
  Providing one without the other is an error.
- `herald-version` (optional, defaults to `github:input-output-hk/cardano-dev`): flake reference for installing Herald.
  Matches the `herald-ref` convention in `herald-release` and `herald-validate` actions.
  Callers can pin to a specific tag or revision for reproducibility.
- `draft` (optional, defaults to `false`): when true, creates a draft release instead of a published one.
- `dry-run` (optional, defaults to `false`): run the full pipeline (compress, checksum, extract changelog) but skip GitHub release creation.

### Outputs

- `release-url`: the URL of the created or updated GitHub release.
  Empty string in dry-run mode.

### Behaviour

- Installs Herald via `nix build` from the `herald-version` flake reference.
- Downloads all artifacts matching `{artifact-prefix}-*` via `actions/download-artifact@v4` with `merge-multiple: true` and `pattern: '{artifact-prefix}-*'`.
  At least one artifact must match; otherwise the action errors.
- Compression:
  - For artifacts whose name contains `source`: renames the `.tar.gz` to `{tag}-source.tar.gz` (no recompression).
  - For artifacts whose name contains `win`: creates `{tag}-{id}.zip` with flat files at the root.
  - For all other artifacts: creates `{tag}-{id}.tar.gz` with flat files at the root.
- Generates `{tag}-sha256sums.txt` covering all archives (binaries and source).
  Standard sha256sum format: `<hash>  <filename>` with filename only (no path).
- Changelog extraction (when both `changelog-path` and `changelog-version` are provided):
  - Runs `herald extract --changelog <changelog-path> <changelog-version>`.
  - If the changelog file does not exist, the action errors (not a silent skip).
  - If extraction fails (version not found, parse error), the action errors - the release is aborted.
  - Wraps the extracted body: `## Changelog\n\n<body>\n`.
- Creates or updates a GitHub release for `tag` via `input-output-hk/action-gh-release@v1`.
  Release name is produced by stripping `tag-prefix` from `tag`.
  On re-run, all existing assets with matching names are replaced (not duplicated).
  The release body is always updated to the latest extracted changelog.
- In dry-run mode: uploads compressed archives and checksums as workflow artifacts (1-day retention), skips release creation, outputs empty `release-url`.

### Permissions

Callers must grant the workflow token:
- `contents: write` - required by `create-release` for creating/updating GitHub releases and uploading assets.
- `actions: read` - required by `create-release` for downloading artifacts from the same workflow run (implicit in most configurations).

## Trigger patterns

Callers typically trigger release workflows via one or more of:

- `push.tags` - fires when a tag is pushed.
  Most common for automated releases.
- `release.types: [published]` - fires when a release is published via the GitHub UI.
  The release's tag must exist for artifact attachment to work.
- `workflow_dispatch` with an optional `target_tag` input - manual trigger for debugging or retroactive releases.
  When no tag is specified, callers should set `dry-run: true` to prevent creating a release from a tagless commit.

## Example caller workflow

**cardano-cli** (Hydra binary release):
```yaml
name: Release
on:
  push:
    tags: ['cardano-cli-*']
  workflow_dispatch:
    inputs:
      target_tag:
        description: Tag to release (empty for dry-run)
        default: ''

env:
  GH_TOKEN: ${{ github.token }}

jobs:
  resolve:
    runs-on: ubuntu-latest
    outputs:
      tag: ${{ steps.tag.outputs.value }}
      version: ${{ steps.tag.outputs.version }}
      dry-run: ${{ steps.tag.outputs.dry-run }}
      flake-ref: ${{ steps.tag.outputs.flake-ref }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true
      - name: Resolve tag
        id: tag
        run: |
          if [[ -n "${{ inputs.target_tag }}" ]]; then
            TAG="${{ inputs.target_tag }}"
            DRY="false"
          else
            TAG=$(git tag --points-at HEAD | head -n 1)
            if [[ -z "$TAG" ]]; then
              TAG="${{ github.ref_name }}"
              DRY="true"
            else
              DRY="false"
            fi
          fi
          VERSION="${TAG#cardano-cli-}"
          echo "value=$TAG" >> "$GITHUB_OUTPUT"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          echo "dry-run=$DRY" >> "$GITHUB_OUTPUT"
          echo "flake-ref=github:${{ github.repository }}/$TAG" >> "$GITHUB_OUTPUT"

  wait-for-hydra:
    needs: [resolve]
    runs-on: ubuntu-latest
    steps:
      - uses: input-output-hk/actions/wait-for-hydra@latest
        with:
          ref: ${{ needs.resolve.outputs.tag }}

  pull:
    needs: [resolve, wait-for-hydra]
    runs-on: ubuntu-latest
    steps:
      - uses: cachix/install-nix-action@v30
        with:
          extra_nix_config: |
            trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=
            substituters = https://cache.iog.io/ https://cache.nixos.org/
      - uses: input-output-hk/cardano-dev/actions/pull-nix-artifacts@main
        id: pull
        with:
          flake-ref: ${{ needs.resolve.outputs.flake-ref }}
          artifact-prefix: cardano-cli
          platforms: |
            [
              {"id": "x86_64-linux",   "derivation": "hydraJobs.x86_64-linux.ghc967-x86_64-unknown-linux-musl.packages.cardano-cli:exe:cardano-cli"},
              {"id": "aarch64-linux",  "derivation": "hydraJobs.x86_64-linux.ghc967-aarch64-unknown-linux-musl.packages.cardano-cli:exe:cardano-cli"},
              {"id": "aarch64-darwin", "derivation": "hydraJobs.aarch64-darwin.packages.cardano-cli:exe:cardano-cli"},
              {"id": "win64",          "derivation": "hydraJobs.x86_64-linux.ghc9122-x86_64-w64-mingw32.packages.cardano-cli:exe:cardano-cli"}
            ]
      - name: Provenance summary
        run: echo "Locked flake URL - ${{ steps.pull.outputs.locked-url }}" >> "$GITHUB_STEP_SUMMARY"

  release:
    needs: [resolve, pull]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v30
        with:
          extra_nix_config: |
            trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=
            substituters = https://cache.iog.io/ https://cache.nixos.org/
      - uses: input-output-hk/cardano-dev/actions/create-release@main
        with:
          artifact-prefix: cardano-cli
          tag: ${{ needs.resolve.outputs.tag }}
          tag-prefix: cardano-cli-
          changelog-path: cardano-cli/CHANGELOG.md
          changelog-version: ${{ needs.resolve.outputs.version }}
          dry-run: ${{ needs.resolve.outputs.dry-run }}
```

## Acceptance criteria

### pull-nix-artifacts
1. Action accepts a JSON platform-derivation map and flake-ref, downloads each derivation.
2. Downloads use `--builders "" --max-jobs 0` (cache-only, no local compilation).
3. All platforms downloaded in a single job (no matrix needed - cache fetch is platform-independent).
4. Flake is locked via `nix flake metadata --json` before downloads; all platforms use the same resolved revision.
5. Locked flake URL exposed as the `locked-url` output.
6. Copies all files from `result/bin/` using `cp --dereference` for every platform.
7. Each platform uploaded as a separate artifact named `{artifact-prefix}-{id}` with 1-day retention.
8. Caller provides nix; the action does not install it.
9. Validates `platforms` JSON: non-empty array, each entry has `id` and `derivation` string fields.
10. Any single platform download failure fails the entire action immediately.

### source-tarball
11. Action accepts a package name, runs `cabal sdist`, uploads the `.tar.gz`.
12. Runs `cabal check` after sdist; fails on any warning or error.
13. Action does not call `actions/checkout` internally.
14. Caller provides GHC and cabal; the action does not install them.
15. Optional `project-dir` input for monorepo layouts.
16. Outputs the exact tarball filename.
17. One package per invocation.

### create-release
18. Unix artifacts compressed as `.tar.gz` with flat files at the root.
19. Windows artifacts compressed as `.zip` with flat files at the root.
20. Source tarball artifacts renamed to `{tag}-source.tar.gz` (no recompression).
21. SHA256 checksums file covers all archives (binaries and source), standard `<hash>  <filename>` format.
22. Changelog extraction calls `herald extract --changelog`; body wrapped with `## Changelog` header.
23. `changelog-path` and `changelog-version` must both be present or both absent; partial is an error.
24. Missing changelog file (when path is provided) errors, not silently skips.
25. Extraction failure (version not found, parse error) aborts the release.
26. No changelog inputs: release created without body.
27. Idempotent: existing release updated, all assets with matching names replaced.
28. Release body always updated to latest extracted changelog on re-run.
29. Tag prefix stripped to produce release name; tag must start with prefix if set, otherwise error.
30. Release name equals full tag when tag-prefix is empty.
31. `draft` input controls whether the release is created as draft or published.
32. Dry-run mode runs the full pipeline (compress, checksum, extract) but skips release creation.
33. Dry-run uploads archives and checksums as workflow artifacts with 1-day retention.
34. Dry-run outputs empty `release-url`.
35. Herald installed via `nix build` from the `herald-version` flake reference (default `github:input-output-hk/cardano-dev`).
36. Downloads artifacts filtered by `pattern: '{artifact-prefix}-*'`; at least one must match.
37. Outputs the GitHub release URL.
38. Uses `input-output-hk/action-gh-release@v1`.
39. Tag existence is not checked by the action; GitHub creates the tag if needed.
40. Requires `contents: write` permission on the workflow token.
