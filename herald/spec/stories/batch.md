# Batch command

Covers `herald batch PACKAGE` - the core release workflow command.
Underpins [R3](../requirements.md#r3-pvp-versioning-with-auto-bumping-four-part-abcd), [R8](../requirements.md#r8-automated-release-pr-via-github-actions), [R9](../requirements.md#r9-version-source-replacement-on-release).

Uses: [PVP](pvp.md), [fragments](fragments.md), [config](config.md), [changelog](changelog.md), [version sources](version-sources.md).

## Overview

Batching collects unreleased [fragments](fragments.md) for a package, renders a [changelog](changelog.md) section, updates the [version source](version-sources.md), and removes consumed fragments.

## Version computation

Batch requires the caller to choose exactly one of:

- **Explicit** (`--version A.B.C.D` / `-v`): uses the provided version.
  Works even without a configured version source (changelog-only update).
  This `--version` is scoped to `batch` only; see [CLI](cli.md) for the distinct top-level `herald --version`.
- **Auto** (`--auto-version`): reads the current version from the configured version source and applies the maximum [bump](pvp.md#bumping) across all fragment kinds.
  Requires a configured version source; without one it is a hard error.
  If the version source file exists but has no parseable version line, it is a hard error.

Passing both `--version` and `--auto-version` together is rejected.
Omitting both is a hard error: `batch requires an explicit version: pass --version <computed> or --auto-version (preview with --dry-run)` when the current version is computable, or the same message with a placeholder `A.B.C.D` and no `--dry-run` hint when it is not.
The requirement only applies when there are fragments to release: a project with no unreleased fragments still returns `Nothing` (warns) regardless of whether a version flag was given.
`--dry-run` (see below) is exempt from this requirement: omitting both flags there defaults to auto-computation, since nothing is mutated.

## Dry run

`--dry-run` runs fragment validation and version computation but mutates nothing: no changelog write, no version-source write, no fragment deletion, no git action.
Omitting both `--version` and `--auto-version` is allowed in dry-run mode and defaults to auto-computation.
The downgrade check still applies -- dry-run performs the same validation and version computation as a real batch, just without writing the result.
Output:
- The current and new version, with the new version marked auto-computed when it was.
- Each fragment's path, kinds, and fate: included in the changelog, or excluded for having only non-notable kinds.
- The changelog section exactly as a real batch would prepend it.

`--dry-run` is mutually exclusive with `--commit` and `--commit-tag`.

## Downgrade check

An explicit version strictly lower than the current version is rejected.
An explicit version equal to the current version is accepted.
If the version source has no parseable version, the downgrade check is skipped.

## Fragment handling

- Fragments are collected from both the global `changes-dir` (if configured) and the project's per-project `changes-dir` (if configured).
- No unreleased fragments for the package: returns `Nothing` (no-op, warns to stderr).
- Invalid fragments (unknown kinds, unknown projects): hard error before any files are modified.
  A fragment mixing valid and invalid kinds is still rejected (valid kinds do not mask invalid ones).
- Consumed fragment files are deleted from their originating directory after batching.

## File requirements

- The configured `CHANGELOG.md` must exist on disk; missing is a hard error.
- The configured `.cabal` file must exist on disk (when using cabal-file); missing is a hard error.
- The configured version file is created if missing (when using version-file).

## Commit and tag modes

- `--commit`: stages all modified files (changelog, version source, deleted fragments) and creates a git commit.
  Deleted fragments are staged using their originating directory paths (global or per-project).
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

### Auto-version (`--auto-version`)
1. Auto-version computes the correct bump from fragment kinds (e.g. bugfix + breaking = breaking wins, `8.4.1.2` becomes `8.5.0.0`).
2. Auto-version without a configured version source is a hard error.
3. Auto-version with a `.cabal` file missing its `version:` line is a hard error.
4. Auto-version with a missing version-file treats current as `0.0.0.0` and bumps accordingly.

### Explicit version (`--version`)
5. Batch with explicit version updates `.cabal` and changelog.
6. Batch with explicit version on a version-file project writes the version file and changelog.
7. Explicit version equal to current is accepted.
8. Explicit version lower than current (downgrade) is rejected.
9. Downgrade check on version-file projects works identically.
10. Downgrade check is skipped when the version line is missing.
11. Batch without version source uses explicit version for changelog-only update.

### Version choice is required
12. Batch with neither `--version` nor `--auto-version`, and a computable current version, is a hard error whose message includes the concrete auto-computed version to pass.
13. Batch with neither flag, and no computable current version (no version source), is a hard error without a concrete version suggestion.
14. Batch with neither flag but no fragments for the package still returns `Nothing` (warns); the requirement does not block the no-op case.
15. Batch rejects passing both `--version` and `--auto-version` together (enforced structurally by the CLI parser, the same way as the pre-existing `--commit`/`--commit-tag` exclusion; not covered by an automated test).

### Changelog
16. Changelog section is prepended above existing sections.
17. Old content is preserved.
18. Full lifecycle output matches [R10](../requirements.md#r10-changelog-output-format) format: version header, date, entries sorted by PR descending, kind labels, PR links.
19. Non-notable fragments contribute to version bump but are hidden from changelog.
20. Explicit `--date` appears in the changelog header.

### Fragment lifecycle
21. Consumed fragments are deleted from the changes directory.
22. No fragments: returns `Nothing`.
23. Batch twice: second call returns `Nothing`.
24. Re-batch with new fragments produces a second changelog section.
25. Invalid fragment (unknown kind): hard error, no files modified.
26. Mixed valid/invalid kinds in one fragment: still rejected.
27. Unknown project: hard error.

### File requirements
28. Missing `CHANGELOG.md` on disk: hard error.
29. Missing `.cabal` file on disk: hard error.
30. Missing version file: created automatically.

### Commit and tag
31. `--commit` creates a commit containing changelog, version source, and consumed fragments only; files belonging to other projects are excluded.
32. `--commit-tag` creates a commit and a `PACKAGE-VERSION` tag.
33. `--commit` with version-file stages the version file.
34. `--commit-tag` with version-file creates the correct tag.

### Result fields
35. `BatchResult` contains correct package name, version, changelog path, and version source path.
36. Version-file `BatchResult` has correct fields.

### CHaP submission instructions (release PR body)
37. When `chap-instructions` is enabled and the project has a `cabal-file`, the release PR body includes a "Step 2: Submit to CHaP" section with copy-paste commands (branch creation, `add-from-github.sh` with repo URL and subdir, push, `gh pr create`, `gh pr comment`).
38. When the project uses `version-file` only, the CHaP section is omitted.
39. When the `cabal-file` path contains a directory component (e.g. `sub/pkg.cabal`), the `add-from-github.sh` invocation includes the subdir argument.
40. When the `cabal-file` is at the repository root, no subdir argument is passed.

### Per-project `changes-dir`
41. Batch collects fragments from both global and per-project directories.
42. Consumed fragments are deleted from their originating directory (not from a single hardcoded path).
43. `--commit` stages fragment deletions using originating directory paths.
44. Batch with fragments in both global and per-project dirs processes all of them.
45. Batch with fragments only in the per-project dir (no global dir configured) succeeds.

### Dry run (`--dry-run`)
46. `--dry-run` does not modify the changelog, version source, or fragment files on disk.
47. `--dry-run` with neither `--version` nor `--auto-version` defaults to the auto-computed version.
48. `--dry-run` marks the new version as auto-computed when applicable, and not when an explicit version was given (the CLI derives this from which flag was passed; tested at the library level by checking that the resolved version differs correctly between the two choices).
49. `--dry-run` reports each fragment's path, kinds, and fate (included in the changelog, or excluded for non-notable kinds).
50. `--dry-run`'s printed changelog section is identical to what a real batch would prepend for the same inputs.
51. `--dry-run` still applies the downgrade check.
52. `--dry-run` is mutually exclusive with `--commit` and `--commit-tag` (enforced structurally by the CLI parser; not covered by an automated test, same as 15).
