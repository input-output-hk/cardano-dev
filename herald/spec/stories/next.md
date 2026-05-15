# Next command

Covers `herald next PACKAGE` - version preview.
Underpins [R3](../requirements.md#r3-pvp-versioning-with-auto-bumping-four-part-abcd).

Uses: [PVP](pvp.md), [fragments](fragments.md), [config](config.md), [version sources](version-sources.md).

## Behaviour

Prints the auto-computed next version to stdout.

- No unreleased fragments: returns `Nothing`.
- No configured version source: returns `Nothing`.
- With fragments and a version source: reads the current version, applies the maximum [bump](pvp.md#bumping), returns the result.
- When multiple fragment kinds are present, the maximum bump wins (e.g. bugfix + feature = feature bump).
- Invalid fragments (unknown kinds): hard error.
- Unknown project: hard error.

### Version-file projects

- Reads from the version file.
- Missing file treated as `0.0.0.0` with warning to stderr.

## Acceptance criteria

1. No fragments: returns `Nothing`.
2. No version source: returns `Nothing`.
3. With breaking fragment: computes correct bumped version (e.g. `8.4.1.2` becomes `8.5.0.0`).
4. Invalid fragment (unknown kind): hard error.
5. Unknown project: hard error.
6. Multiple kinds: maximum bump wins (e.g. bugfix + feature = `8.4.2.0`).
7. Version-file project: computes version from file.
8. Missing version-file: treats as `0.0.0.0`, bumps accordingly.
