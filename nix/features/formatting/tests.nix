{ pkgs, formatter }:
pkgs.runCommand "stratosphere-formatting-behavior" {
  nativeBuildInputs = [
    formatter
    pkgs.git
    pkgs.coreutils
  ];
} (builtins.readFile ./tests/run.sh)
