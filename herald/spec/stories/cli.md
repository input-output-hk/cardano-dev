# Global CLI options

Covers command-line options that apply at the top level, before a subcommand is chosen.

## Behaviour

- `-c`, `--config FILE` selects the config file to load (default `.herald.yml`).
  See [config](config.md) for how the file is loaded and parsed.
- `--version` prints herald's own version and exits, without requiring a subcommand
  or a valid `.herald.yml`.
  This is distinct from `batch`'s own `-v`/`--version A.B.C.D` option, which sets the
  version of the package being released - see [batch](batch.md#version-computation).

## Acceptance criteria

1. `herald --version` prints herald's version and exits successfully, without a subcommand.
2. `herald --version` succeeds even when no `.herald.yml` config file is present.
