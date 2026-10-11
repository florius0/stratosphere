{ pkgs }:
let
  makeProbes =
    { build, probe }:
    pkgs.writeShellApplication {
      name = "stratosphere-ci-probes";
      runtimeEnv = {
        STRATOSPHERE_CI_BUILD = build;
        STRATOSPHERE_CI_PROBE = probe;
      };
      text = builtins.readFile ./scripts/probes.sh;
    };
  environment = pkgs.writeShellApplication {
    name = "stratosphere-ci-environment";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./scripts/environment.sh;
  };
in
{
  inherit makeProbes environment;
  tests = import ./tests.nix { inherit pkgs makeProbes; };
}
