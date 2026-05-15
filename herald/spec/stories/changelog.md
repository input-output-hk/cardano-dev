# Changelog rendering and file operations

Covers how Herald renders changelog entries and manages `CHANGELOG.md` files.
Underpins [R5](../requirements.md#r5-non-notable-kinds-are-hidden-in-changelog), [R10](../requirements.md#r10-changelog-output-format).

Used by: [batch](batch.md).

## Entry rendering

Each entry is rendered as:
```
- Description text
  (kind1, kind2)
  [PR N](https://github.com/Org/repo/pull/N)
```

Multi-line descriptions indent continuation lines with 2 spaces.
All kind labels are shown, including non-notable ones, when the entry is visible.

## Ordering

Entries are sorted by PR number descending (highest PR first).
Duplicate PR numbers are both rendered (not deduplicated).

## Filtering

Only [fragments](fragments.md) with at least one notable kind (see [config](config.md)) appear in the rendered output.
Fragments where all kinds are non-notable are excluded.
Fragments with kinds not present in the config are treated as non-notable and excluded.

## Empty sections

An empty fragment list (or all non-notable) still renders the version header and date line.

## File operations

### Prepend

New sections are inserted before the first existing `##` header.
If no `##` header exists, the new section is appended at the end.
Any preamble text (e.g. `# Changelog`) before the first `##` is preserved above the new section.

## Acceptance criteria

### Rendering
1. Single notable fragment produces version header, date, description, kind label, and PR link.
2. Multiple fragments are sorted by PR number descending.
3. All non-notable fragments are excluded from output; version header is still present.
4. Mixed notable/non-notable fragment: entry is visible, all kind labels are shown.
5. Multi-line description: both lines appear in output.
6. Empty fragment list: version header and date are still rendered.
7. Unknown kinds are treated as non-notable; entry is excluded; version header present.
8. Duplicate PR numbers: both entries are rendered.

### File operations
9. New section is prepended before existing `##` header; both old and new entries survive.
10. No `##` header: new section is appended at end; existing content preserved.
11. Preamble text before `##` is preserved above the new section.
