{ pkgs }:
let
  package = pkgs.writeShellApplication {
    name = "stratosphere-docs";
    runtimeInputs = [
      pkgs.lychee
      pkgs.graphviz
      pkgs.findutils
      pkgs.gawk
    ];
    runtimeEnv.STRATOSPHERE_REFERENCES_QUERY = ./queries/references.awk;
    text = builtins.readFile ./scripts/check.sh;
  };
in
{
  inherit package;
  tests = import ./tests.nix { inherit pkgs package; };
  app = {
    type = "app";
    program = "${package}/bin/stratosphere-docs";
  };
}
