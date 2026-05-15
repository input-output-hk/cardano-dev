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

All four fields are required: `project`, `kind`, `description`, `pr`.
Missing any field is a parse error.
Extra YAML fields are silently ignored.

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
- Spaces in the description are converted to hyphens in the generated filename.
- Creating a fragment for a PR that already has one for the same project is an error (duplicate check).
  The error message contains "already exists" and the existing filename.
- The same PR number may have fragments for different projects (per-project deduplication, not global).
- An unknown project or kind is rejected before writing any file.
  The error contains "Invalid fragment" and "Unknown project" or "Unknown kind".
- `_TEMPLATE.yml` files in the changes directory are skipped by `readAllFragments`.

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

### Version-file projects
21. A fragment for a version-file-based project validates identically to a cabal-file project.
    **Gap:** E2E coverage only; no unit test.
