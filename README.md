# cardano-dev

Development tools and reusable CI components for the Cardano ecosystem.

## Herald

Changelog and release automation for PVP-versioned projects.
Herald replaces manual PR-description-based changelog workflows with file-based changelog fragments.
See [herald/README.md](herald/README.md) for full documentation.

```bash
nix run github:input-output-hk/cardano-dev#herald -- --help
```

## Reusable GitHub Actions

| Action | Description |
|--------|-------------|
| [`herald-validate`](actions/herald-validate/action.yml) | Validate changelog fragments on PRs ([example](actions/herald-validate/example.yml)) |
| [`herald-release`](actions/herald-release/action.yml) | Batch fragments, bump version, open a release PR ([example](actions/herald-release/example.yml)) |
| [`cabal-cache`](actions/cabal-cache/action.yml) | Cache and restore Cabal dependencies |
| [`grpc-deps`](actions/grpc-deps/action.yml) | Install gRPC system dependencies (Linux, macOS, Windows) |

## Nix scripts

There is an app in the flake for every script with a file name ending with `.sh` in `scripts/` directory.
You can view them using `nix flake show github:input-output-hk/cardano-dev`.

```bash
# execute scripts/tag.sh script
nix run 'github:input-output-hk/cardano-dev#tag'
```
