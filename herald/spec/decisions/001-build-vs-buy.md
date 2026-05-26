# ADR 001: Build a custom tool vs adopt an existing one

## Status

Accepted.

## Context

The cardano-api and related repositories used PR-description-based changelog workflows: contributors embedded a YAML block in the PR description with `description`, `type`, and `projects`.
At release time, a maintainer ran `download-prs.sh` and `generate-pr-changelogs.sh` to download all PRs from GitHub and generate markdown.
Version bumps in `.cabal` files were manual, and a separate `tag.sh` script handled tagging with safety checks.

See: https://github.com/input-output-hk/cardano-dev/issues/17

### Pain points

- Downloading all PRs is slow and requires network access.
- Depends on contributors correctly formatting YAML in PR descriptions (easy to get wrong).
- Requires `jq`, `yq`, `gh` tooling.
- Custom scripts to maintain.

## Tool survey

No existing tool satisfies all requirements out of the box.
The core problem is that every tool with auto version bumping is hardwired to SemVer (3-part versions).

### Evaluated tools

| Tool | 4-part PVP | Fragments | Mono-repo | Multi-kind | Hidden kinds | Custom format | Auto bump | nixpkgs |
|---|---|---|---|---|---|---|---|---|
| **Towncrier** | yes (pass-through) | yes | yes | multi-file | yes (`showcontent`) | yes (Jinja2) | no | yes |
| **Scriv** | yes (pass-through) | yes | no | yes (in-file) | partial | yes (Jinja2) | no | no |
| **Reno** | yes (pass-through) | yes | no | yes (YAML) | no | limited (RST) | no | yes |
| **Changie** | no (rejects) | yes | yes | no | workaround | yes (Go tmpl) | SemVer only | yes |
| **git-cliff** | no (bump SemVer) | no | yes | n/a | n/a | yes (Tera) | SemVer only | yes |
| **Knope** | no | yes | yes | yes | ? | limited | SemVer only | no |
| **Changesets** | no | yes | yes | yes | no | yes | SemVer only | no |
| **release-please** | custom code needed | no | yes | n/a | n/a | limited | SemVer only | no |

### Towncrier - best candidate

Meets R1, R2, R5, R7, R10 natively:
- File-based fragments (core design).
- Mono-repo with per-package changelogs (via `[[tool.towncrier.section]]`).
- Hidden kinds via `showcontent = false` per fragment type.
- Any version string (version-agnostic - never parses versions).
- Fully customisable output via Jinja2 templates.
- Available in nixpkgs (`python3Packages.towncrier`).

Gaps:
- **R3 (auto PVP bumping):** Towncrier does not bump versions at all.
  A custom script is needed to read fragment kinds, determine the highest-significance kind, and compute the next PVP version from the latest git tag.
- **R4 (multi-kind per entry):** Towncrier encodes the kind in the fragment filename (`123.bugfix.md`).
  A PR with multiple kinds creates multiple fragment files (e.g. `123.bugfix.md` + `123.refactoring.md`).
  This works but is not single-file multi-select.
- **R9 (`.cabal` replacement):** Towncrier does not modify `.cabal` files.
  The release script must handle this.

### Changie - partial fit, blocking limitations

Meets R1, R2, R10 natively.
Has mono-repo projects and `.cabal` replacements built in.

Blockers:
- **R3:** Rejects 4-part PVP versions (`changie batch 0.0.0.1` fails with `part string is not a supported version or version increment`).
- **R4:** Built-in `kinds` is single-select only.
  Workaround: use a custom string field, losing the interactive kind picker.
- **R3 (auto bump):** Only supports SemVer `major`/`minor`/`patch`/`auto`.

### Other tools - ruled out

- **git-cliff:** No file-based fragments (commit-based). SemVer-only bumping.
- **Knope, Changesets:** SemVer-only. Not in nixpkgs.
- **release-please:** No fragments. SemVer-only. Requires custom TypeScript for PVP.
- **Scriv:** No mono-repo support. Not in nixpkgs.
- **Reno:** No mono-repo support. RST-centric output.

## Decision

Every approach requires a custom PVP version-bumping script - no tool provides this.

| Approach | Pros | Cons |
|----------|------|------|
| **Towncrier + PVP script** | Battle-tested, Jinja2 templates, native hidden kinds, in nixpkgs | Multi-kind = multi-file, no `.cabal` replacement |
| **Changie + wrapper** | Mono-repo projects, `.cabal` replacement, Go templates | Must work around SemVer-only `batch`, must work around single-select kinds |
| **Custom tool** | Full control, PVP-native, no tool limitations | More code to write and maintain |

A fully custom tool (Herald) was built.
It handles all requirements natively: PVP 4-part versioning with auto-bumping, multi-select kinds, mono-repo projects, non-notable filtering, fragment validation, and automated release PR creation.
Tagging is available via `herald batch --commit-tag`, replacing the need for a separate `tag.sh` script.
The release action uses `--commit` only; tagging is deferred to the manual signing step.

Herald is implemented in Haskell, built with nix (GHC 9.12.2), and distributed as a flake app at `github:input-output-hk/cardano-dev#herald`.
