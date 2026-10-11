{ ... }:
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      toolchain,
      artifacts,
      docs,
      ...
    }:
    let
      tooling = pkgs.runCommand "stratosphere-tooling-checks" { } ''
        ${lib.concatMapStringsSep "\n" (check: "test -e ${check}") (
          builtins.attrValues config.stratosphere.toolingChecks
        )}
        touch "$out"
      '';
      development = import ../features/development/package.nix {
        inherit
          pkgs
          artifacts
          docs
          tooling
          ;
        inherit (toolchain) sdk;
      };
      check = import ../features/development/tests.nix {
        inherit pkgs artifacts docs;
        inherit (toolchain) sdk;
      };
    in
    {
      options.stratosphere.toolingChecks = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.package;
        default = { };
        internal = true;
        description = "Tooling behavior checks required by working-tree tests";
      };
      config = {
        apps = development.apps;
        checks.development = check;
        stratosphere.toolingChecks.development = check;
        devShells.default = pkgs.mkShell (
          toolchain.environment
          // {
            packages = [
              pkgs.swift
              toolchain.swiftpm
              pkgs.graphviz
              pkgs.tart
              pkgs.jq
              config.treefmt.build.wrapper
            ];
            inherit (toolchain) buildInputs;
            shellHook = ''export TART_HOME="''${TART_HOME:-$PWD/.local/tart}"'';
          }
        );
      };
    };
}
