{ pkgs, makeProbes }:
let
  effect = pkgs.writeShellApplication {
    name = "ci-effect";
    text = ''touch "$CI_EFFECT"'';
  };
  probes = makeProbes {
    build = "${effect}/bin/ci-effect";
    probe = "${effect}/bin/ci-effect";
  };
  failedBuild = pkgs.writeShellApplication {
    name = "ci-failed-build";
    text = "exit 7";
  };
  failedProbes = makeProbes {
    build = "${failedBuild}/bin/ci-failed-build";
    probe = "${effect}/bin/ci-effect";
  };
in
pkgs.runCommand "stratosphere-ci-boundaries" {
  CI_PROBES = "${probes}/bin/stratosphere-ci-probes";
  FAILED_PROBES = "${failedProbes}/bin/stratosphere-ci-probes";
} (builtins.readFile ./tests/run.sh)
