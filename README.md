# cardano-dev
Scripts for developing on cardano

## Nix usage
Theres an app in the flake for every script in `scripts/` directory.
You can view them using `nix flake show github:input-output-hk/cardano-dev`.
The scripts can be run using `nix run` e.g.:
```bash
# execute scripts/tag.sh script
nix run 'github:input-output-hk/cardano-dev#tag'
```
