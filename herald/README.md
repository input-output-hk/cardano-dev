# Herald

[![Hydra](https://img.shields.io/badge/ci-hydra-blue)](https://ci.iog.io/jobset/input-output-hk-cardano-dev)

Changelog and release automation for PVP-versioned Haskell projects.

Herald replaces manual PR-description-based changelog workflows with file-based
changelog fragments. Each PR commits a small YAML file describing the change;
at release time, Herald collects fragments, computes the next PVP version, updates
the changelog and `.cabal` file, and can create a release commit with tag.

## Features

- **PVP versioning** -- 4-part versions (A.B.C.D) with auto-bumping based on change kinds
- **Mono-repo support** -- multiple packages, each with its own changelog and `.cabal` file
- **Multi-select kinds** -- each fragment can have multiple change kinds (e.g. bugfix + refactoring)
- **Non-notable filtering** -- internal changes (test, refactoring, maintenance) bump the version but are hidden from the changelog
- **CI validation** -- validate fragments, check PR numbers, detect missing fragments for modified projects
- **Automated releases** -- GitHub Actions for validation and release PR creation

## Installation

Herald is distributed as a nix flake from the `cardano-dev` repository:

```bash
# Run directly
nix run github:input-output-hk/cardano-dev#herald -- --help

# Enter a dev shell (for development)
nix develop github:input-output-hk/cardano-dev#herald
```

## Quick start

### 1. Initialize a repository

```bash
herald init
```

This scans the repo for projects (directories with `.cabal` files), generates
`.herald.yml` with discovered projects and default change kinds, and creates
a `.changes/_TEMPLATE.yml` template fragment.

### 2. Create a changelog fragment

```bash
# Interactive mode (prompts for project, kinds, description, PR number)
herald new

# Non-interactive mode
herald new --project cardano-api --kind bugfix,refactoring --description "Fix certificate serialization" --pr 1234
```

Fragments are YAML files stored in the changes directory (default: `.changes/`):

```yaml
project: cardano-api
kind:
  - bugfix
  - refactoring
description: |
  Fix serialization of Conway certificates
pr: 1234
```

### 3. Validate fragments (CI)

```bash
# Validate all fragment files
herald validate

# Check that modified projects in the current branch have fragments (requires git history)
herald validate --diff

# Also verify PR numbers in fragments match
herald validate --diff --pr 1234
```

### 4. Compute the next version

```bash
herald next cardano-api
# prints e.g. 8.5.0.0
```

The version is computed from the current `.cabal` version plus the highest
bump level across unreleased fragments for that package.

### 5. Batch a release

```bash
# Auto-compute version from fragments
herald batch cardano-api

# Explicit version
herald batch cardano-api --version 9.0.0.0

# Batch and create a git commit
herald batch cardano-api --commit

# Batch, commit, and create a PACKAGE-VERSION tag
herald batch cardano-api --commit-tag
```

Batching:
1. Collects unreleased fragments for the package
2. Renders a changelog section with the new version and date
3. Prepends the section to the package's `CHANGELOG.md`
4. Updates the `version:` field in the package's `.cabal` file
5. Removes consumed fragment files

## Configuration

Herald is configured via `.herald.yml` (or a custom path with `-c`):

```yaml
# GitHub repository (used for PR links in changelogs)
# Accepts: full HTTPS URL, SSH URL, or owner/repo slug (assumes GitHub)
git-repo: https://github.com/IntersectMBO/cardano-api

# Directory for changelog fragments
changes-dir: .changes

# Change kinds and their properties
kinds:
  breaking:
    bump: 0.1.0.0
    description: the API has changed in a breaking way
  feature:
    bump: 0.0.1.0
    description: introduces a new feature
  compatible:
    bump: 0.0.1.0
    description: the API has changed but is non-breaking
  bugfix:
    bump: 0.0.0.1
    description: fixes a defect
  optimisation:
    bump: 0.0.0.1
    description: measurable performance improvements
  refactoring:
    notable: false
    bump: 0.0.0.1
    description: code quality improvements
  test:
    notable: false
    bump: 0.0.0.1
    description: fixes or modifies tests
  maintenance:
    notable: false
    bump: 0.0.0.1
    description: not directly related to the code
  release:
    notable: false
    bump: 0.0.0.1
    description: related to a new release preparation
  documentation:
    notable: false
    bump: 0.0.0.1
    description: change in code docs, haddocks

# Projects in this repository
projects:
  cardano-api:
    changelog: cardano-api/CHANGELOG.md
    cabal-file: cardano-api/cardano-api.cabal
  cardano-api-gen:
    changelog: cardano-api-gen/CHANGELOG.md
    cabal-file: cardano-api-gen/cardano-api-gen.cabal
```

### Kind properties

- **`bump`** -- PVP version component to bump. `0.1.0.0` bumps the 2nd digit (breaking),
  `0.0.1.0` the 3rd (features), `0.0.0.1` the 4th (patches). The highest bump across
  all fragment kinds determines the final version bump.
- **`notable`** (default: `true`) -- if `false`, entries with only non-notable kinds
  are hidden from the rendered changelog but still contribute to version bumping.
- **`description`** (optional) -- shown in interactive prompts.

## Changelog output format

```markdown
## 8.5.0.0 -- 2026-03-25

- Add Conway era support
  (breaking, feature)
  [PR 99](https://github.com/IntersectMBO/cardano-api/pull/99)

- Fix serialization of Conway certificates
  (bugfix)
  [PR 42](https://github.com/IntersectMBO/cardano-api/pull/42)
```

Entries are sorted by PR number (descending). Each entry shows the description,
kinds in parentheses, and a link to the PR.

## GitHub Actions

Herald provides two reusable GitHub Actions for CI and release automation.
Both use nix to run Herald, so no Haskell toolchain setup is needed.

### Validate changelogs on PRs

Copy `.github/workflows/validate-changelogs.yml` to your repository, or
reference the composite action directly:

```yaml
name: Validate Changelogs

on:
  pull_request:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: cachix/install-nix-action@v30
        with:
          extra_nix_config: |
            trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=
            substituters = https://cache.iog.io/ https://cache.nixos.org/

      - uses: input-output-hk/cardano-dev/herald/.github/actions/validate@main
        # with:
        #   config: .herald.yml     # default
        #   diff: 'true'            # default -- check modified projects have fragments
        #   pr: 'true'              # default -- check PR numbers match
```

The validate action:
- Validates all fragment files parse correctly and reference valid projects/kinds
- Checks that projects with modified files have at least one changelog fragment (`--diff`)
- Verifies PR numbers inside fragments match the pull request (`--pr`)

### Release workflow

Copy `.github/workflows/release.yml` to your repository, or reference the
composite action directly. Trigger via the GitHub UI or CLI:

```bash
gh workflow run release.yml -f package=cardano-api
gh workflow run release.yml -f package=cardano-api -f version=9.0.0.0
```

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      package:
        description: Package name to release (must match a project in .herald.yml)
        required: true
        type: string
      version:
        description: Explicit version (A.B.C.D). Leave empty to auto-compute.
        required: false
        type: string

permissions:
  contents: write
  pull-requests: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: cachix/install-nix-action@v30
        with:
          extra_nix_config: |
            trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=
            substituters = https://cache.iog.io/ https://cache.nixos.org/

      - uses: input-output-hk/cardano-dev/herald/.github/actions/release@main
        with:
          package: ${{ inputs.package }}
          version: ${{ inputs.version }}
          # herald-ref: github:input-output-hk/cardano-dev  # default
          # config: .herald.yml                               # default
```

The release action:
1. Computes the next version (auto or explicit)
2. Creates a `release/PACKAGE-VERSION` branch
3. Batches changelog fragments, commits, and tags (`--commit-tag`)
4. Pushes the branch and tag
5. Opens a PR with the changes
6. Creates a release changelog fragment for the next cycle
7. Updates the PR body with signing instructions

Since the commits are unsigned (created by `github-actions[bot]`), the PR body
includes exact git commands for the maintainer to sign the commits before merging:

```bash
git fetch origin release/cardano-api-9.0.0.0
git checkout release/cardano-api-9.0.0.0
git rebase HEAD~2 --exec 'git commit --amend --no-edit -S'
git tag -f cardano-api-9.0.0.0 HEAD~1
git push --force-with-lease origin release/cardano-api-9.0.0.0
git push --force origin cardano-api-9.0.0.0
```

## CLI reference

```
herald - changelog and versioning automation

Usage: herald [-c|--config FILE] COMMAND

Commands:
  init       Scan the repository and generate .herald.yml
  new        Create a changelog fragment (interactive or scripted)
  validate   Validate fragments, check PR numbers, check diffs
  batch      Collect fragments, update changelog and .cabal, remove fragments
  next       Print the next version for a package
```

### Global options

| Flag | Default | Description |
|------|---------|-------------|
| `-c`, `--config FILE` | `.herald.yml` | Path to herald config file |

### `herald init`

Scans the repository for `.cabal` files, detects the GitHub remote, and writes
a `.herald.yml` config with discovered projects and default kinds. Also creates
`.changes/_TEMPLATE.yml`.

### `herald new`

| Flag | Description |
|------|-------------|
| `-p`, `--project NAME` | Project name(s), comma-separated or repeated |
| `-k`, `--kind KIND` | Kind(s), comma-separated or repeated |
| `-d`, `--description TEXT` | Change description |
| `--pr N` | PR number |

If all flags are provided, creates the fragment non-interactively. Otherwise
launches an interactive prompt with multi-select menus.

### `herald validate`

| Flag | Description |
|------|-------------|
| `[FILES...]` | Specific files to validate (default: all in changes dir) |
| `--diff` | Check that modified projects have changelog fragments |
| `--pr N` | Check that new fragments have this PR number |

### `herald batch PACKAGE`

| Flag | Description |
|------|-------------|
| `-v`, `--version A.B.C.D` | Explicit version (default: auto-compute) |
| `--date YYYY-MM-DD` | Date for changelog header (default: today) |
| `--commit` | Stage and commit batch changes |
| `--commit-tag` | Stage, commit, and create a PACKAGE-VERSION tag |

### `herald next PACKAGE`

Prints the auto-computed next version to stdout. Useful for scripting.
Exit code 1 if no version can be computed (e.g. no fragments).
