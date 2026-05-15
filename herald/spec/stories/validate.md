# Validate command

Covers `herald validate` - CI validation of [fragments](fragments.md).
Underpins [R6](../requirements.md#r6-pr-number-is-recorded-and-validated), [R7](../requirements.md#r7-changelog-fragments-are-mandatory).

Uses: [fragments](fragments.md), [config](config.md).

## File validation (`herald validate [FILES...]`)

Validates that fragment files parse correctly and reference valid projects/kinds as defined in the [config](config.md).
- Malformed YAML produces a parse error.
- When validating a mix of good and bad files, only bad files are reported.
- Nonexistent file paths produce a clean error.

## Diff validation (`herald validate --diff`)

Checks that projects with modified files on the current branch have at least one changelog [fragment](fragments.md).

- Only new fragments (added after the fork point from the base branch) count.
- Pre-existing fragments (committed before the fork) do not satisfy the requirement.
- A fragment for the wrong project does not satisfy the modified project.
- A malformed fragment does not satisfy the diff check.
- Changes only in the `.changes/` directory (no project source files touched) do not trigger errors.
- Deleted project files also require a fragment.
- In a multi-project repo, only projects with modified files are checked.
- When both projects are modified but only one has a fragment, only the uncovered project is flagged.
- No commits on the feature branch beyond the base: passes (nothing changed).
- If the branch does not track a remote, fork-point detection fails with a user-friendly error.
- Diff validation only checks project-name presence in fragments, not full fragment validity.
  A fragment with invalid kinds, empty description, and negative PR still satisfies the diff check as long as it names the right project.

## PR validation (`herald validate --pr N`)

Checks that new fragments in the diff have the expected PR number.

- Wrong PR number: error containing "does not match".
- Correct PR number: passes.
- Only mismatched fragments are reported; matching ones are silent.
- `_TEMPLATE.yml` files are skipped.
- `.yaml` extension is checked in addition to `.yml`.
- No new fragments in the diff: passes (nothing to check).
- Malformed YAML fragment in the diff: parse error.
- PR validation only checks PR numbers, not full fragment validity.
  A fragment with unknown kinds and empty description but the correct PR number passes.

## Acceptance criteria

### File validation
1. Well-formed fragment passes.
2. Fragment with unknown kind is rejected.
3. Empty kinds list is rejected.
4. Blank description is rejected.
5. Non-positive PR is rejected.
6. Unknown project is rejected.
7. Version-file project validates normally.
8. Valid file on disk passes.
9. Malformed YAML produces error.
10. Mix of good and bad: only bad reported.
11. Nonexistent file path: clean error.

### Diff validation
12. Missing fragment for modified project is detected.
13. Fragment present for modified project passes.
14. Changes only in `.changes/` are ignored.
15. Only the modified project is flagged (not untouched projects).
16. Root-level project detects changes.
17. No commits on feature branch: passes.
18. Deleted files require a fragment.
19. Pre-existing fragment does not satisfy new changes.
20. Fragment for wrong project does not satisfy.
21. Malformed fragment does not satisfy.
22. Both projects modified, only one has fragment: only uncovered project flagged.
23. Invalid fragment content still satisfies diff check (project-name presence only).
24. Branch with no remote tracking: fork-point detection fails with a user-friendly error.

### PR validation
25. Wrong PR number is detected.
26. Correct PR number passes.
27. Only mismatched fragments reported.
28. Template files are skipped.
29. `.yaml` extension is also checked.
30. No new fragments in diff: passes.
31. Malformed fragment in diff: parse error.
32. Invalid content with matching PR passes (PR-only check).
