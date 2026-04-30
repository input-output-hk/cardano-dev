{
  description = "A list of useful scripts for cardano-node development";
  inputs = {
    systems.url = "github:nix-systems/default";
    haskellNix.url = "github:carbolymer/haskell.nix/remove-deprecated-pie-hardening";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    iohkNix.url = "github:input-output-hk/iohk-nix";
    utils.url = "github:numtide/flake-utils";
    utils.inputs.systems.follows = "systems";
  };

  outputs =
    {
      nixpkgs,
      haskellNix,
      iohkNix,
      utils,
      ...
    }@inputs:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          inherit (haskellNix) config;
          overlays = [ haskellNix.overlay ];
        };

        # list of all scripts (without .sh suffix)
        scripts =
          with pkgs.lib;
          map (removeSuffix ".sh") (
            filter (hasSuffix ".sh") (builtins.attrNames (builtins.readDir ./scripts))
          );

        # wrap a shell script, adding programs to its PATH
        wrap =
          {
            paths ? [ ],
            vars ? { },
            file ? null,
            script ? null,
            name ? "wrap",
          }:
          assert file != null || script != null || abort "wrap needs 'file' or 'script' argument";
          let
            set =
              with pkgs.lib;
              n: v:
              "--set ${escapeShellArg (escapeShellArg n)} " + "'\"'${escapeShellArg (escapeShellArg v)}'\"'";
            args =
              (map (p: "--prefix PATH : ${p}/bin") paths) ++ (pkgs.lib.attrValues (pkgs.lib.mapAttrs set vars));
          in
          pkgs.runCommand name
            {
              f = if file == null then pkgs.lib.writeScript name script else file;
              buildInputs = [ pkgs.makeWrapper ];
            }
            ''
              makeWrapper "$f" "$out" ${toString args}
            '';

        # create an app for a script name
        mkScriptApp = scriptName: {
          type = "app";
          program =
            (wrap {
              name = scriptName;
              paths = with pkgs; [
                git
                gh
                jq
                yq-go
              ];
              file = ./scripts/${scriptName}.sh;
            }).outPath;
        };

        inherit (pkgs) lib;

        # herald — haskell.nix project
        heraldProject = pkgs.haskell-nix.cabalProject' {
          src = ./herald;
          compiler-nix-name = ghcVersion;
          crossPlatforms =
            p:
            lib.optionals (system == "x86_64-linux") [
              p.ucrt64
              p.musl64
              p.aarch64-multiplatform-musl
            ]
            ++ lib.optionals (system == "aarch64-linux") [ p.aarch64-multiplatform-musl ];
          modules = [
            (
              { lib, pkgs, ... }:
              lib.mkIf pkgs.stdenv.hostPlatform.isWindows {
                packages.basement.configureFlags = [ "--hsc2hs-option=--cflag=-Wno-int-conversion" ];
              }
            )
          ];
        };

        heraldExe = heraldProject.hsPkgs.herald.components.exes.herald;
        heraldTestExe = heraldProject.hsPkgs.herald.components.tests.herald-test;
        heraldE2eExe = heraldProject.hsPkgs.herald.components.tests.herald-test-e2e;

        # Best available exe for the current system:
        # Linux gets a static musl build (minimal closure), macOS gets dynamic.
        heraldPlatformExe =
          if system == "x86_64-linux" then
            heraldProject.projectCross.musl64.hsPkgs.herald.components.exes.herald
          else if system == "aarch64-linux" then
            heraldProject.projectCross.aarch64-multiplatform-musl.hsPkgs.herald.components.exes.herald
          else
            heraldExe;

        ghcVersion = "ghc9122";

        # Pinned tool versions shared between devShell and CI lint check
        toolVersions = {
          cabal = "latest";
          fourmolu = "0.18.0.0";
          hlint = "3.10";
          cabal-gild = "1.7.0.1";
        };

        heraldRelease =
          lib.optionalAttrs (system == "x86_64-linux") {
            x86_64-linux = heraldProject.projectCross.musl64.hsPkgs.herald.components.exes.herald;
            aarch64-linux =
              heraldProject.projectCross.aarch64-multiplatform-musl.hsPkgs.herald.components.exes.herald;
            x86_64-windows = heraldProject.projectCross.ucrt64.hsPkgs.herald.components.exes.herald;
          }
          // lib.optionalAttrs (system == "aarch64-linux") {
            aarch64-linux =
              heraldProject.projectCross.aarch64-multiplatform-musl.hsPkgs.herald.components.exes.herald;
          }
          // lib.optionalAttrs (system == "aarch64-darwin") {
            ${system} = heraldExe;
          };
        checks =
          let
            locale =
              if pkgs.stdenv.hostPlatform.isDarwin then "en_US.UTF-8" else "C.UTF-8";

          in
          {
            test =
              pkgs.runCommand "herald-test"
                {
                  LANG = locale;
                  LC_ALL = locale;
                }
                ''
                  ${heraldTestExe}/bin/herald-test
                  touch $out
                '';
            e2e =
              pkgs.runCommand "herald-e2e"
                {
                  LANG = locale;
                  LC_ALL = locale;
                  nativeBuildInputs = [ pkgs.git ];
                }
                ''
                  export HOME=$TMPDIR
                  git config --global user.email "test@test.com"
                  git config --global user.name "Test"
                  ${heraldE2eExe}/bin/herald-test-e2e
                  touch $out
                '';
          lint =
            let
              fourmolu = pkgs.haskell-nix.tool ghcVersion "fourmolu" toolVersions.fourmolu;
              hlint = pkgs.haskell-nix.tool ghcVersion "hlint" toolVersions.hlint;
              cabal-gild = pkgs.haskell-nix.tool ghcVersion "cabal-gild" toolVersions.cabal-gild;
            in
            pkgs.runCommand "herald-lint"
              {
                nativeBuildInputs = [
                  fourmolu
                  hlint
                  cabal-gild
                  pkgs.diffutils
                ];
                src = ./herald;
              }
              ''
                cd $src
                fourmolu --mode check src/ test/ app/ test-e2e/
                hlint src/ test/ app/ test-e2e/
                cabal-gild --input herald.cabal > $TMPDIR/formatted.cabal
                diff -u herald.cabal $TMPDIR/formatted.cabal
                touch $out
              '';
        };
      in
      {
        # create an app for every script in `scripts` directory, plus herald
        apps = pkgs.lib.foldl' (acc: s: acc // { ${s} = mkScriptApp s; }) {
          herald = {
            type = "app";
            program = "${heraldPlatformExe}/bin/herald";
          };
          herald-dy = {
            type = "app";
            program = "${heraldExe}/bin/herald";
          };
        } scripts;
        packages = {
          herald = heraldPlatformExe;
        }
        // heraldRelease;
        devShells = {
          herald = heraldProject.shellFor {
            tools = toolVersions;
            # Skip cross-compilation deps in the dev shell
            crossPlatforms = _: [ ];
            shellHook = ''
              export LANG="en_US.UTF-8"
            '' + lib.optionalString
              (pkgs.glibcLocales != null && pkgs.stdenv.hostPlatform.libc == "glibc") ''
              export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"
            '';
          };
        };
        inherit checks;
        hydraJobs = pkgs.callPackages iohkNix.utils.ciJobsAggregates {
          ciJobs = {
            herald = {
              inherit (heraldProject.hsPkgs.herald.components) library;
              exe = heraldExe;
              static = heraldPlatformExe;
              tests = heraldTestExe;
              e2e = heraldE2eExe;
            }
            // lib.optionalAttrs (heraldRelease != { }) {
              release = heraldRelease;
            };
            inherit checks;
            revision = pkgs.writeText "revision" (inputs.self.rev or "dirty");
          }
          // lib.optionalAttrs (system == "x86_64-linux") {
            windows =
              let
                windowsProject = heraldProject.projectCross.ucrt64;
              in
              {
                inherit (windowsProject.hsPkgs.herald.components) library;
                inherit (windowsProject.hsPkgs.herald.components.exes) herald;
                inherit (windowsProject.hsPkgs.herald.components.tests) herald-test;
              };
          };
        };
        formatter = pkgs.nixfmt;
      }
    );

  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys = [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
    allow-import-from-derivation = true;
  };
}
