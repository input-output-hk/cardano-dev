# Herald requirements

High-level requirements Herald satisfies.
Detailed behaviour and acceptance criteria live in [stories/](stories/).

For the rationale behind building Herald instead of adopting an existing tool, see [ADR 001](decisions/001-build-vs-buy.md).
For the version-file feature design, see [ADR 002](decisions/002-version-file.md).

## R1: File-based changelog fragments

Each PR must include a changelog fragment file committed to the repo.
This avoids parsing PR descriptions and eliminates merge conflicts on `CHANGELOG.md`.

Stories: [fragments](stories/fragments.md).

## R2: Multiple packages (mono-repo)

The repo may contain multiple packages, each with its own `CHANGELOG.md` and version source.
A fragment is associated with exactly one project.
Release (batching + changelog assembly) is done per-package independently.

Stories: [config](stories/config.md), [batch](stories/batch.md).

## R3: PVP versioning with auto-bumping (four-part: A.B.C.D)

Versions follow [Haskell PVP](https://pvp.haskell.org/), not SemVer.
The parser accepts PVP-shaped version strings of any length; the ecosystem convention is 4-part (e.g. `10.25.0.0` or `0.0.0.1`).

Auto-bumping is based on the most significant kind across all unreleased fragments for a package.
The mapping from kinds to PVP digits is:

| Kind | PVP bump | Example (from `8.4.1.2`) |
|------|----------|--------------------------|
| `breaking` | Bump 2nd digit (A.**B**.0.0) | `8.5.0.0` |
| `feature`, `compatible` | Bump 3rd digit (A.B.**C**.0) | `8.4.2.0` |
| `bugfix`, `optimisation` | Bump 4th digit (A.B.C.**D**) | `8.4.1.3` |
| non-notable only | Bump 4th digit (A.B.C.**D**) | `8.4.1.3` |

The highest-significance kind wins.
Both auto mode and explicit mode are supported.

Stories: [pvp](stories/pvp.md), [batch](stories/batch.md), [next](stories/next.md).

## R4: Multiple kinds per entry (multi-select)

Each changelog entry can have multiple kinds.
Available kinds and their visibility:

| Kind | Appears in changelog |
|------|---------------------|
| `breaking` | yes |
| `feature` | yes |
| `compatible` | yes |
| `bugfix` | yes |
| `optimisation` | yes |
| `refactoring` | no |
| `test` | no |
| `maintenance` | no |
| `release` | no |
| `documentation` | no |

Stories: [fragments](stories/fragments.md), [config](stories/config.md).

## R5: Non-notable kinds are hidden in changelog

Entries where all kinds are non-notable do not appear in the rendered changelog.
If at least one notable kind is present, the entry is visible.
Non-notable entries still contribute to version bumping.

Stories: [changelog](stories/changelog.md).

## R6: PR number is recorded and validated

Each fragment records the PR number.
CI validates that the PR number in the fragment matches the actual PR number.

Stories: [fragments](stories/fragments.md), [validate](stories/validate.md).

## R7: Changelog fragments are mandatory

Every PR must include a fragment.
There is no opt-out mechanism (no `no-changelog` label).

Stories: [validate](stories/validate.md).

## R8: Automated release PR via GitHub Actions

A `workflow_dispatch` action takes a package name and an optional PVP version string, then:
1. Determines the next version (explicit input or auto-computed).
2. Collects unreleased fragments for that package.
3. Generates the version's changelog section.
4. Updates the version source (`.cabal` file or version file).
5. Creates a release commit (tag is deferred to the manual signing step).
6. Pushes to a `release/PACKAGE-VERSION` branch.
7. Opens a PR with the changes.
8. Creates a release changelog fragment for the next cycle (idempotent on re-runs).
9. Updates the PR body with the trigger author, commit signing instructions, and optionally CHaP submission commands.

Provided as reusable composite GitHub Actions (`herald-validate` and `herald-release`).

Stories: [batch](stories/batch.md).

## R9: Version source replacement on release

When batching a release, the version in the relevant version source (`.cabal` file or version file) is automatically updated to the new version.

Stories: [version-sources](stories/version-sources.md), [batch](stories/batch.md).

## R10: Changelog output format

```markdown
## 10.25.0.0 -- 2026-03-25

- Description of the change
  (bugfix, compatible)
  [PR 1234](https://github.com/IntersectMBO/cardano-api/pull/1234)

- Another change
  (feature)
  [PR 1235](https://github.com/IntersectMBO/cardano-api/pull/1235)
```

Stories: [changelog](stories/changelog.md).

## R11: Version-file support for non-Haskell projects

Projects without a `.cabal` file can declare a `version-file` in `.herald.yml`.
The version file is a plain text file containing a single PVP version string.
Herald reads, bumps, and writes the version file identically to a `.cabal` version field.

Stories: [version-sources](stories/version-sources.md), [config](stories/config.md).
Decisions: [ADR 002](decisions/002-version-file.md).

## R12: Release PR shows trigger author

The release PR body identifies the GitHub user who triggered the workflow.
This improves auditability and makes it clear who to contact about signing.
The `herald-release` composite action reads `GITHUB_ACTOR` from the runner environment and includes "Triggered by @USERNAME" in the PR body.

## R13: CHaP submission instructions in release PR

The release PR body includes copy-paste commands for creating a CHaP PR after signing.
Only shown for projects with a `cabal-file` in `.herald.yml`; version-file-only projects omit the section.
The commands resolve the tag SHA at execution time, so they work correctly after the signing rebase.

Stories: [batch](stories/batch.md).

---

## Open questions

The following behaviours are asserted by tests but may be incidental rather than contractual.
They are documented here for review.

1. **Pvp Ord is lexicographic-then-length.**
   `Pvp (1 :| [0]) < Pvp (1 :| [0,0,0])` (shorter is less).
   The test explicitly notes this "documents that Ord is lexicographic-then-length, not PVP equivalence."
   Is this the intended ordering contract, or a side-effect of deriving `Ord` on `NonEmpty`?

2. **Leading zeros are silently stripped.**
   `parsePvp "01.02.03"` succeeds and normalises to `1.2.3`.
   Is silent stripping the desired behaviour, or should leading zeros be rejected?

3. **Downgrade check is skipped when the version line is missing.**
   If the `.cabal` file exists but has no `version:` line, an explicit version (even one that looks like a "downgrade") is accepted because there is no current version to compare against.
   Is this intentional, or should a missing version line be an error when a `.cabal` file is configured?

4. **`validateDiff` only checks project-name presence, not fragment validity.**
   A fragment with invalid kinds, empty description, and negative PR still satisfies the diff check as long as it names the right project.
   Is this intentional separation of concerns (diff check and file validation are independent passes), or should diff validation also require valid fragments?

5. **`validatePR` only checks PR numbers, not fragment validity.**
   A fragment with unknown kinds and empty description but the correct PR number passes PR validation.
   Same question as above: intentional separation, or should PR validation also require valid fragments?

6. **Parser accepts any number of version components (1 to N).**
   The ecosystem standardises on 4-part versions for `.cabal` packages.
   Should the parser reject non-4-part inputs, or is variable length intentional for forward compatibility?

7. **Unknown kinds in fragments are treated as non-notable during rendering.**
   If a fragment references a kind not in the config, it is excluded from the rendered changelog (treated as non-notable).
   During validation this is an error, but during rendering it is silent.
   Should rendering also reject unknown kinds?
