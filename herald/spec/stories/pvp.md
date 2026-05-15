# PVP version handling

Covers parsing, display, bumping, and ordering of PVP version strings.
Underpins [R3](../requirements.md#r3-pvp-versioning-with-auto-bumping-four-part-abcd).

Used by: [batch](batch.md), [next](next.md).

## Parsing

The parser accepts dot-separated non-negative integers of any length (1 to N components).

- Valid: `"8.4.1.2"`, `"0.0.0.0"`, `"42"`, `"1.2.3"`, `"1.2.3.4.5"`.
- Rejected: empty string, non-digit characters, negative numbers, trailing dot, leading dot.
- Leading zeros on individual components are stripped silently: `"01.02.03"` parses as `1.2.3`.

## Display

`showPvp` is the inverse of `parsePvp`.
The roundtrip `parsePvp . showPvp` is the identity for all valid versions.

## Bumping

`bumpPvp level version` increments the digit at the position indicated by `level` and zeros all digits to its right.
If the version has fewer components than the bump position requires, it is extended with zeros first.

Examples:
- `bumpPvp (0.1.0.0) (8.4.1.2)` = `8.5.0.0` (second digit).
- `bumpPvp (0.0.1.0) (8.4.1.2)` = `8.4.2.0` (third digit).
- `bumpPvp (0.0.0.1) (8.4.1.2)` = `8.4.1.3` (fourth digit).
- `bumpPvp (0.0.0.0) (8.4.1.2)` = `8.4.1.2` (identity).
- `bumpPvp (1.0.0.0) (8.4.1.2)` = `9.0.0.0` (first digit).
- `bumpPvp (0.0.0.1) (1.0)` = `1.0.0.1` (extends to four components).

Bumping is monotonic: the result is always >= the input.

When multiple fragment kinds contribute to a release, the maximum bump level wins.
The ordering is: `0.1.0.0` > `0.0.1.0` > `0.0.0.1` > `0.0.0.0`.

## Acceptance criteria

1. `parsePvp` then `showPvp` is the identity for any valid version string.
2. Single-component (`"42"`), three-component (`"1.2.3"`), and five-component (`"1.2.3.4.5"`) versions are accepted.
3. Empty string, non-digit characters, negative numbers, trailing dot, and leading dot are rejected.
4. Leading zeros are stripped silently.
5. Second-digit bump zeros the third and fourth digits.
6. Third-digit bump zeros the fourth digit.
7. Fourth-digit bump increments the fourth digit only.
8. Zero bump is the identity.
9. Bump on a short version extends it to the required length.
10. First-digit bump increments the first digit and zeros the rest (e.g. `8.4.1.2` becomes `9.0.0.0`).
11. Bump on a short version that does not require extension does not extend it (e.g. `bumpPvp (0.1.0.0) (1 :| [0])` = `1 :| [1]`).
12. `bumpPvp result >= input` for any version and bump level (monotonicity).
13. `maximum [patchBump, breakingBump, featureBump] === breakingBump`.
