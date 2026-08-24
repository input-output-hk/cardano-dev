## 0.2.0.0 -- 2026-08-24

- Bumping a project's version in a .cabal file no longer reformats the file, preserving the original column alignment, CRLF line endings, and the presence or absence of a final trailing newline.
  (bugfix)
  [PR 44](https://github.com/input-output-hk/cardano-dev/pull/44)

- Added a top-level `herald --version` option that prints herald's own version and exits, independent of the `batch` subcommand's existing `-v`/`--version` option.
  (feature)
  [PR 44](https://github.com/input-output-hk/cardano-dev/pull/44)

- The batch command now requires choosing either --version or the new --auto-version flag instead of silently guessing the version when neither is given.
  (breaking)
  [PR 44](https://github.com/input-output-hk/cardano-dev/pull/44)

- Added a --dry-run option to the batch command that previews the version, per-fragment changelog inclusion, and the rendered changelog section without writing or deleting anything.
  (feature)
  [PR 44](https://github.com/input-output-hk/cardano-dev/pull/44)

## 0.1.2.0 -- 2026-07-28

- Add per-project changes-dir support. Each project in .herald.yml can declare its own changes-dir, which is scanned alongside the global directory. Fragments in a per-project directory infer their project from the directory, making the project field optional for both file and diff validation. No two changes-dir values may be the same or nest inside each other, including between per-project and global directories.
  (feature)
  [PR 39](https://github.com/input-output-hk/cardano-dev/pull/39)

## 0.1.1.0 -- 2026-05-19

- Add version-file support documentation and extract command to CLI reference.
  (feature)
  [PR 28](https://github.com/input-output-hk/cardano-dev/pull/28)

