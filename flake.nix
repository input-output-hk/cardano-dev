{
  description = "A list of useful scripts for cardano-node development";
  inputs = {
    systems.url = "github:nix-systems/default";
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    utils.inputs.systems.follows = "systems";
  };

  outputs = { nixpkgs, utils, haskellNix, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          inherit (haskellNix) config;
        };
        # list of all scripts (without .sh suffix)
        scripts = with builtins;
          map (pkgs.lib.removeSuffix ".sh") (attrNames (readDir ./scripts));
        # create an app for a script name
        mkScriptApp = scriptName: {
          type = "app";
          program = pkgs.lib.getExe ((pkgs.writeScriptBin scriptName
            (builtins.readFile ./scripts/${scriptName}.sh)).overrideAttrs
            (old: {
              buildCommand = ''
                ${old.buildCommand}
                 patchShebangs $out'';
              buildInputs = with pkgs; [ git gh jq yq-go ];
            }));
        };
      in {
        # create an app for every script in `scripts` directory
        apps = pkgs.lib.foldl' (acc: s: acc // { ${s} = mkScriptApp s; }) { }
          scripts;

        formatter = nixpkgs.legacyPackages.${system}.nixfmt;
      });

  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys =
      [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
    allow-import-from-derivation = true;
  };
}
