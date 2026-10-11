{ ... }:
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      system,
      ...
    }:
    let
      ci = import ../features/ci/package.nix { inherit pkgs; };
      checks = map (name: ".#checks.${system}.${name}") (builtins.attrNames config.checks);
      check = pkgs.writeShellApplication {
        name = "stratosphere-ci-check";
        runtimeInputs = [ pkgs.nix ];
        text = ''
          [[ -f flake.nix ]] || { echo 'Run from the Stratosphere repository root' >&2; exit 2; }
          exec nix build --no-link --print-build-logs ${lib.escapeShellArgs checks} "$@"
        '';
      };
      probes = ci.makeProbes {
        build = config.apps.build.program;
        probe = config.apps.e2e-native.program;
      };
    in
    {
      apps = {
        ci-check = {
          program = lib.getExe check;
          meta.description = "Run all deterministic CI checks";
        };
        ci-environment = {
          program = lib.getExe ci.environment;
          meta.description = "Record CI toolchain and OS evidence";
        };
        ci-probes = {
          program = lib.getExe probes;
          meta.description = "Run hosted macOS environment qualification";
        };
      };
      checks.ci-boundaries = ci.tests;
    };
}
