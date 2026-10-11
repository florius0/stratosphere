{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem = { config, pkgs, ... }: {
    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        nixfmt.enable = true;
        swift-format.enable = true;
        clang-format = {
          enable = true;
          includes = [
            "*.m"
            "*.h"
          ];
        };
        prettier = {
          enable = true;
          includes = [
            "*.md"
            "*.yml"
            "*.yaml"
            "*.json"
          ];
          settings.proseWrap = "preserve";
        };
        shfmt = {
          enable = true;
          includes = [
            "*.sh"
            ".envrc"
          ];
          indent_size = 2;
        };
        taplo.enable = true;
      };
      settings.global.excludes = [
        ".local/*"
        ".build/*"
        ".swiftpm/*"
        ".direnv/*"
        "result"
        "result-*"
        "vendor/*"
        "*.dot"
        "flake.lock"
      ];
    };
    apps.format = {
      program = config.treefmt.build.wrapper;
      meta.description = "Format project sources and configuration";
    };
    checks.formatting-behavior = pkgs.callPackage ../features/formatting/tests.nix {
      formatter = config.treefmt.build.wrapper;
    };
  };
}
