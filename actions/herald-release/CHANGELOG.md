## 0.0.2.0 -- 2026-07-28

- Fix the release action never adding the changelog fragment for the next cycle: its check for an already existing fragment always matched, so the step always skipped.
  The step no longer assumes fragments live in `.changes/`, so it works with per-project changes directories.
  Fix the signing instructions in the release PR creating a tag without a message, which left `git tag` waiting for an editor and failing when the message was empty.
  (bugfix)
  [PR 42](https://github.com/input-output-hk/cardano-dev/pull/42)

- Optionally include CHaP PR submission instructions in the release PR body. When chap-instructions is enabled and the project has a cabal-file, the PR body shows copy-paste commands for creating the CHaP PR after signing.
  (feature)
  [PR 40](https://github.com/input-output-hk/cardano-dev/pull/40)

- Improve release action resilience: skip tag creation (deferred to signing), make release fragment idempotent on re-runs, add set -euo pipefail to PR body generation, and use explicit push targets.
  (bugfix)
  [PR 40](https://github.com/input-output-hk/cardano-dev/pull/40)

- Show who triggered the release in the PR body. The action reads GITHUB_ACTOR from the runner environment and adds "Triggered by @USERNAME" at the top of the PR description.
  (feature)
  [PR 40](https://github.com/input-output-hk/cardano-dev/pull/40)

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

