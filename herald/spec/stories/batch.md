# Batch command

Covers `herald batch PACKAGE` - the core release workflow command.
Underpins [R3](../requirements.md#r3-pvp-versioning-with-auto-bumping-four-part-abcd), [R8](../requirements.md#r8-automated-release-pr-via-github-actions), [R9](../requirements.md#r9-version-source-replacement-on-release).

Uses: [PVP](pvp.md), [fragments](fragments.md), [config](config.md), [changelog](changelog.md), [version sources](version-sources.md).

## Overview

Batching collects unreleased [fragments](fragments.md) for a package, renders a [changelog](changelog.md) section, updates the [version source](version-sources.md), and removes consumed fragments.

## Version computation

- **Auto mode** (no `--version`): reads the current version from the configured version source and applies the maximum [bump](pvp.md#bumping) across all fragment kinds.
  Auto mode requires a configured version source; without one it is a hard error.
  If the version source file exists but has no parseable version line, it is a hard error.
- **Explicit mode** (`--version A.B.C.D`): uses the provided version.
  Explicit mode works even without a configured version source (changelog-only update).

## Downgrade check

An explicit version strictly lower than the current version is rejected.
An explicit version equal to the current version is accepted.
If the version source has no parseable version, the downgrade check is skipped.

## Fragment handling

- No unreleased fragments for the package: returns `Nothing` (no-op, warns to stderr).
- Invalid fragments (unknown kinds, unknown projects): hard error before any files are modified.
  A fragment mixing valid and invalid kinds is still rejected (valid kinds do not mask invalid ones).
- Consumed fragment files are deleted after batching.

## File requirements

- The configured `CHANGELOG.md` must exist on disk; missing is a hard error.
- The configured `.cabal` file must exist on disk (when using cabal-file); missing is a hard error.
- The configured version file is created if missing (when using version-file).

## Commit and tag modes

- `--commit`: stages all modified files (changelog, version source, deleted fragments) and creates a git commit.
  The commit message contains `Release PACKAGE-VERSION`.
  Files belonging to other projects are not included.
- `--commit-tag`: same as `--commit`, plus creates a `PACKAGE-VERSION` git tag.

## Date override

`--date YYYY-MM-DD` overrides the date in the changelog header (default: today).

## Idempotency

Batching twice in a row returns `Nothing` on the second call (all fragments were consumed).
Adding new fragments after a batch and batching again produces a second changelog section; both sections are present.

## Result

A successful batch returns:
- The computed version.
- The list of consumed fragment filenames (sorted).
- The changelog path (ending in `CHANGELOG.md`).
- The version source path (`.cabal` or version file).

## Acceptance criteria

### Auto-version
1. Auto-version computes the correct bump from fragment kinds (e.g. bugfix + breaking = breaking wins, `8.4.1.2` becomes `8.5.0.0`).
2. Auto-version without a configured version source is a hard error.
3. Auto-version with a `.cabal` file missing its `version:` line is a hard error.
4. Auto-version with a missing version-file treats current as `0.0.0.0` and bumps accordingly.

### Explicit version
5. Batch with explicit version updates `.cabal` and changelog.
6. Batch with explicit version on a version-file project writes the version file and changelog.
7. Explicit version equal to current is accepted.
8. Explicit version lower than current (downgrade) is rejected.
9. Downgrade check on version-file projects works identically.
10. Downgrade check is skipped when the version line is missing.
11. Batch without version source uses explicit version for changelog-only update.

### Changelog
12. Changelog section is prepended above existing sections.
13. Old content is preserved.
14. Full lifecycle output matches [R10](../requirements.md#r10-changelog-output-format) format: version header, date, entries sorted by PR descending, kind labels, PR links.
15. Non-notable fragments contribute to version bump but are hidden from changelog.
16. Explicit `--date` appears in the changelog header.

### Fragment lifecycle
17. Consumed fragments are deleted from the changes directory.
18. No fragments: returns `Nothing`.
19. Batch twice: second call returns `Nothing`.
20. Re-batch with new fragments produces a second changelog section.
21. Invalid fragment (unknown kind): hard error, no files modified.
22. Mixed valid/invalid kinds in one fragment: still rejected.
23. Unknown project: hard error.

### File requirements
24. Missing `CHANGELOG.md` on disk: hard error.
25. Missing `.cabal` file on disk: hard error.
26. Missing version file: created automatically.

### Commit and tag
27. `--commit` creates a commit containing changelog, version source, and consumed fragments only; files belonging to other projects are excluded.
28. `--commit-tag` creates a commit and a `PACKAGE-VERSION` tag.
29. `--commit` with version-file stages the version file.
30. `--commit-tag` with version-file creates the correct tag.

### Result fields
31. `BatchResult` contains correct package name, version, changelog path, and version source path.
32. Version-file `BatchResult` has correct fields.

### CHaP submission instructions (release PR body)
33. When `chap-instructions` is enabled and the project has a `cabal-file`, the release PR body includes a "Step 2: Submit to CHaP" section with copy-paste commands (branch creation, `add-from-github.sh` with repo URL and subdir, push, `gh pr create`, `gh pr comment`).
34. When the project uses `version-file` only, the CHaP section is omitted.
35. When the `cabal-file` path contains a directory component (e.g. `sub/pkg.cabal`), the `add-from-github.sh` invocation includes the subdir argument.
36. When the `cabal-file` is at the repository root, no subdir argument is passed.
