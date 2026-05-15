# Configuration

Covers the `.herald.yml` format, kind properties, version sources, git URL normalisation, and serialisation.
Underpins [R2](../requirements.md#r2-multiple-packages-mono-repo), [R11](../requirements.md#r11-version-file-support-for-non-haskell-projects).

Used by: all commands.
See also: [ADR 002 - version-file](../decisions/002-version-file.md).

## File format

`.herald.yml` (or custom path via `-c`):

```yaml
git-repo: https://github.com/IntersectMBO/cardano-api
changes-dir: .changes
kinds:
  breaking:
    bump: 0.1.0.0
    description: the API has changed in a breaking way
  bugfix:
    notable: false
    bump: 0.0.0.1
    description: fixes a defect
projects:
  cardano-api:
    changelog: cardano-api/CHANGELOG.md
    cabal-file: cardano-api/cardano-api.cabal
```

Missing `projects` or `kinds` is a parse error.

## Kind properties

- `bump` (required) - [PVP](pvp.md) version component to bump.
- `notable` (default: `true`) - if `false`, entries with only non-notable kinds are hidden from the [rendered changelog](changelog.md) but still contribute to version bumping.
- `description` (optional) - shown in interactive prompts.

### Serialisation

- When `notable` is `true` (default), the key is omitted from serialised output.
- When `notable` is `false`, it is present in serialised output.
- `description` is omitted when `Nothing`.
- All fields roundtrip through YAML encode/decode without loss.

## Version source

Each project may declare exactly one version source:
- `cabal-file: path/to/package.cabal` - version is read from/written to the `version:` field.
  See [version sources](version-sources.md) for `.cabal` file operations.
- `version-file: path/to/version.txt` - version is read from/written to a plain text file.
  See [version sources](version-sources.md) for version file operations.

Mutual exclusion is enforced at config parse time (not lazily).
Setting both `cabal-file` and `version-file` on the same project is an immediate parse error; the error message mentions both field names.
When neither is set, [next](next.md) returns `Nothing` and [batch](batch.md) requires `--version`.

### Serialisation

`VersionSource` serialises as flat YAML keys (`cabal-file:` or `version-file:`), not a tagged union.
Existing configs are unchanged by the version-file addition.
All variants (`CabalFile`, `VersionFile`, `Nothing`) roundtrip correctly.

## Git repo URL normalisation

The `git-repo` field accepts three formats:
- SSH URL (`git@github.com:Org/repo.git`) - normalised to HTTPS, `.git` suffix stripped.
- HTTPS URL (`https://github.com/Org/repo.git`) - `.git` suffix stripped.
- Bare slug (`Org/repo`) - GitHub is assumed, expanded to `https://github.com/Org/repo`.

Trailing slashes are stripped.
Unrecognised formats (e.g. `svn://`) pass through unchanged.

Invalid inputs that return `Nothing`:
- SSH URL without a colon separator (`git@github.com`).
- SSH URL with slash instead of colon (`git@github.com/owner/repo.git`).
- HTTPS URL with no path (`https://github.com`).

## Git config parsing

Herald reads `.git/config` for remote detection during [init](init.md).

- Simple keys (`user.email`, `core.bare`) are resolved from `[section]` blocks.
- Subsection keys (`remote.origin.url`) are resolved from `[section "subsection"]` blocks.
- Section names are case-insensitive (`USER.EMAIL` matches `[user]`).
- Subsection names are case-sensitive (`remote.Origin.url` does not match `[remote "origin"]`).
- Comment lines (`#`, `;`) are ignored.
- Multiple subsections are resolved independently.
- Missing keys or sections return `Nothing`.

## Acceptance criteria

### Kind parsing
1. `notable` defaults to `true` when omitted.
2. Explicit `notable: false` is parsed correctly.
3. `description` is parsed when present, `Nothing` when omitted.

### Config loading
4. Missing `projects` or `kinds` produces a parse error.
5. Config with `version-file` project loads successfully.
6. Config with both `cabal-file` and `version-file` on one project fails early with a clear error.

### Version source parsing
7. `cabal-file` only parses to `Just (CabalFile ...)`.
8. `version-file` only parses to `Just (VersionFile ...)`.
9. Neither field parses to `Nothing`.
10. Both fields produce a parse error mentioning both names.

### Serialisation roundtrips
11. `CabalFile` survives encode/decode.
12. `VersionFile` survives encode/decode; output contains `version-file:` key.
13. `Nothing` version source survives encode/decode.
14. `notable: true` is omitted from output; roundtrips correctly.
15. `notable: false` is present in output; roundtrips correctly.
16. `description: Nothing` roundtrips correctly.
17. `description: Just "..."` roundtrips correctly.

### Git URL normalisation
18. SSH URL with `.git` is normalised to HTTPS.
19. SSH URL without `.git` is normalised to HTTPS. **Gap:** no test.
20. HTTPS URL with `.git` is normalised (`.git` stripped). **Gap:** no test.
21. HTTPS URL without `.git` passes through.
22. Bare slug is expanded to GitHub HTTPS URL.
23. Trailing slash is stripped.
24. Unrecognised URL passes through unchanged.
25. SSH without colon, SSH with slash, HTTPS with no path all return `Nothing`.

### Git config parsing
26. Simple section.key lookups work.
27. Subsection keys (`remote.origin.url`) are resolved.
28. Missing key or section returns `Nothing`.
29. Section names are case-insensitive.
30. Subsection names are case-sensitive.
31. Comment lines are ignored.
32. Multiple subsections are resolved independently.
