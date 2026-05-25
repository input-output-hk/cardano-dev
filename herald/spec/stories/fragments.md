# Changelog fragments

Covers the YAML fragment format, validation rules, and fragment creation.
Underpins [R1](../requirements.md#r1-file-based-changelog-fragments), [R4](../requirements.md#r4-multiple-kinds-per-entry-multi-select), [R6](../requirements.md#r6-pr-number-is-recorded-and-validated), [R7](../requirements.md#r7-changelog-fragments-are-mandatory).

Used by: [batch](batch.md), [validate](validate.md).

## YAML format

```yaml
project: cardano-api
kind:
  - bugfix
  - refactoring
description: |
  Fix serialisation of Conway certificates
pr: 1234
```

All four fields are required in the global changes directory: `project`, `kind`, `description`, `pr`.
Missing any field in the global directory is a parse error.
Extra YAML fields are silently ignored.

### `project` field in per-project directories

When a fragment lives in a per-project `changes-dir` (see [config](config.md)), the `project:` field is optional.
If omitted, the project is inferred from the directory.
If present and it matches the directory's project, it is accepted.
If present and it names a different project, it is a validation error (see [validate](validate.md)).
This prevents accidental miscategorisation from copy-paste or file moves.

## Validation rules

A parsed fragment is valid when all of the following hold:
- `project` matches a project name in the [config](config.md).
- Every entry in `kind` matches a kind name in the config.
- `kind` list is non-empty.
- `description` is non-empty after stripping whitespace.
- `pr` is a positive integer (> 0).

Validation errors are collected (not short-circuited) and reported together.

## Fragment creation (`herald new`)

Creates a fragment file in the changes directory.
- When the project has a per-project `changes-dir`, the fragment is written there.
  Otherwise it is written to the global `changes-dir`.
- Spaces in the description are converted to hyphens in the generated filename.
- Creating a fragment for a PR that already has one for the same project is an error (duplicate check).
  The duplicate check scans both the global and per-project directories.
  The error message contains "already exists" and the existing filename.
- The same PR number may have fragments for different projects (per-project deduplication, not global).
- An unknown project or kind is rejected before writing any file.
  The error contains "Invalid fragment" and "Unknown project" or "Unknown kind".
- `_TEMPLATE.yml` files in any changes directory are skipped by `readAllFragments`.

## Acceptance criteria

### Parsing
1. Well-formed YAML with all four fields parses correctly.
2. Multiple entries under `kind:` are parsed as a list.
3. Missing `project`, `kind`, `description`, or `pr` each produce a parse error.

### Validation
4. A fragment with known project, known kinds, non-empty description, and positive PR passes.
5. Unknown kind is rejected.
6. Unknown project is rejected.
7. Empty description is rejected.
8. Whitespace-only description is rejected.
9. PR number 0 is rejected.
10. Negative PR number is rejected.
11. Empty kinds list is rejected.
12. Multiple validation errors are collected and reported together (not short-circuited on the first failure).
13. Extra YAML fields are silently ignored; known fields still parse.

### Creation
14. Multi-project fragments produce distinct files per project.
15. Spaces in description produce hyphens in filename.
16. `_TEMPLATE.yml` is skipped by `readAllFragments`.
17. Duplicate fragment for same project and PR errors with pointer to existing file.
18. Same PR, different project is allowed.
19. Invalid project errors before writing.
20. Invalid kind errors before writing.

### Per-project `changes-dir`
21. Fragment in a per-project dir without `project:` field parses successfully; project is inferred from directory.
22. Fragment in a per-project dir with matching `project:` field parses successfully.
23. Fragment in a per-project dir with mismatching `project:` field is a validation error.
24. Fragment in the global dir without `project:` field is a parse error.
25. `herald new` writes to the per-project dir when the project has one configured.
26. `herald new` writes to the global dir when the project has no per-project dir.
27. Duplicate check for `herald new` scans both global and per-project directories.
28. `_TEMPLATE.yml` in a per-project dir is skipped by `readAllFragments`.

### Version-file projects
29. A fragment for a version-file-based project validates identically to a cabal-file project.
    **Gap:** E2E coverage only; no unit test.
