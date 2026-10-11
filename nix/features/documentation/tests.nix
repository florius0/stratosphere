{ pkgs, package }:
pkgs.runCommand "stratosphere-docs-tests" {
  nativeBuildInputs = [ package ];
  DOC_FIXTURES = ./tests;
} (builtins.readFile ./tests/run.sh)
