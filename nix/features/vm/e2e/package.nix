{ pkgs, vmSpec }:
let
  configuration = pkgs.writeText "vm-e2e.json" (
    builtins.toJSON (
      vmSpec
      // {
        launchAgent = {
          RunAtLoad = true;
          EnvironmentVariables.STRATOSPHERE_GUEST = "1";
        };
      }
    )
  );
  makeRunners =
    {
      remote ? pkgs.openssh,
    }:
    let
      dependencies = [
        pkgs.bash
        pkgs.coreutils
        pkgs.jq
        remote
        pkgs.libiconv
        pkgs.gnused
        pkgs.gnugrep
      ];
      makeRunner =
        name: script:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = dependencies;
          runtimeEnv = {
            STRATOSPHERE_E2E_COMMON = ./scripts/common.sh;
            STRATOSPHERE_VM_CONFIG = configuration;
            STRATOSPHERE_METADATA_QUERY = ./queries/metadata.jq;
            STRATOSPHERE_AGENT_QUERY = ./queries/agent.jq;
          };
          extraShellCheckFlags = [
            "-x"
            "-P"
            "${./scripts}"
          ];
          text = builtins.readFile script;
        };
    in
    {
      native = makeRunner "e2e-native" ./scripts/native.sh;
      vm = makeRunner "e2e-vm" ./scripts/vm.sh;
    };
  runners = makeRunners { };
  vmLauncher = pkgs.writeShellApplication {
    name = "e2e-vm-launch";
    runtimeInputs = [ pkgs.tart ];
    text = ''exec ${runners.vm}/bin/e2e-vm "$@"'';
  };
in
{
  inherit makeRunners;
  inherit (runners) native vm;
  nativeApp = {
    type = "app";
    program = "${runners.native}/bin/e2e-native";
  };
  vmApp = {
    type = "app";
    program = "${vmLauncher}/bin/e2e-vm-launch";
  };
  tests = import ./tests.nix { inherit pkgs makeRunners; };
}
