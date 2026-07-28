## 0.1.2.0 -- 2026-07-28

- Add per-project changes-dir support. Each project in .herald.yml can declare its own changes-dir, which is scanned alongside the global directory. Fragments in a per-project directory infer their project from the directory, making the project field optional for both file and diff validation. No two changes-dir values may be the same or nest inside each other, including between per-project and global directories.
  (feature)
  [PR 39](https://github.com/input-output-hk/cardano-dev/pull/39)

## 0.1.1.0 -- 2026-05-19

- Add version-file support documentation and extract command to CLI reference.
  (feature)
  [PR 28](https://github.com/input-output-hk/cardano-dev/pull/28)

