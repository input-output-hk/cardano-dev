{
  description = "A list of useful scripts for cardano-node development";
  inputs = {
    systems.url = "github:nix-systems/default";
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    utils.inputs.systems.follows = "systems";
  };

  outputs = { nixpkgs, utils, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # list of all scripts (without .sh suffix)
        scripts = with pkgs.lib;
          map (removeSuffix ".sh") (filter (hasSuffix ".sh")
            (builtins.attrNames (builtins.readDir ./scripts)));

        # wrap a shell script, adding programs to its PATH
        wrap = { paths ? [ ], vars ? { }, file ? null, script ? null
          , name ? "wrap" }:
          assert file != null || script != null
            || abort "wrap needs 'file' or 'script' argument";
          let
            set = with pkgs.lib;
              n: v:
              "--set ${escapeShellArg (escapeShellArg n)} "
              + "'\"'${escapeShellArg (escapeShellArg v)}'\"'";
            args = (map (p: "--prefix PATH : ${p}/bin") paths)
              ++ (pkgs.lib.attrValues (pkgs.lib.mapAttrs set vars));
          in pkgs.runCommand name {
            f = if file == null then pkgs.lib.writeScript name script else file;
            buildInputs = [ pkgs.makeWrapper ];
          } ''
            makeWrapper "$f" "$out" ${toString args}
          '';

        # create an app for a script name
        mkScriptApp = scriptName: {
          type = "app";
          program = (wrap {
            name = scriptName;
            paths = with pkgs; [ git gh jq yq-go ];
            file = ./scripts/${scriptName}.sh;
          }).outPath;
        };
      in {
        # create an app for every script in `scripts` directory
        apps = pkgs.lib.foldl' (acc: s: acc // { ${s} = mkScriptApp s; }) { }
          scripts;
        formatter = pkgs.nixfmt-classic;
      });

  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys =
      [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
    allow-import-from-derivation = true;
  };
}
