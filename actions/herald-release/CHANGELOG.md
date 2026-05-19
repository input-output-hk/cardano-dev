## 0.0.1.0 -- 2026-05-19

- Make the release action idempotent across re-runs: reset release branch to the default branch with explicit start-point, force-push branch and tag, reuse existing open PR instead of creating duplicates, and fail hard on existing tags.
  (feature)
  [PR 33](https://github.com/input-output-hk/cardano-dev/pull/33)

- Add action outputs (pr-url, pr-number, version, tag) and GHA annotation for release summary.
  (feature)
  [PR 31](https://github.com/input-output-hk/cardano-dev/pull/31)

- Add herald-release action for automated release PR creation with changelog batching, version bumping, and commit signing instructions.
  (feature)
  [PR 28](https://github.com/input-output-hk/cardano-dev/pull/28)

