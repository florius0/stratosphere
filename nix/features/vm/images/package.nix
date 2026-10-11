{ pkgs }:
let
  spec = {
    version = 1;
    source = "ghcr.io/cirruslabs/macos-tahoe-vanilla@sha256:e12d678b248f3122e276fa64632970a8e1c6dc60ff6738d21fe9bfa5ea58f426";
    cpu = 4;
    memory = 4096;
    displaySize = {
      width = 1280;
      height = 800;
    };
    guestUser = "admin";
    profiles = {
      clean = {
        name = "stratosphere-clean-26-5";
        displayUnit = "px";
        displayRefit = false;
      };
      prepared = {
        name = "stratosphere-prepared-26-5";
        displayUnit = "pt";
        displayRefit = true;
      };
    };
  };
  display =
    settings:
    "${toString spec.displaySize.width}x${toString spec.displaySize.height}${
      pkgs.lib.optionalString (settings.displayUnit == "pt") "pt"
    }";
  receipts = pkgs.lib.mapAttrs (
    profile: settings:
    pkgs.writeText "vm-${profile}-spec.json" (
      builtins.toJSON {
        inherit profile;
        inherit (spec)
          version
          source
          cpu
          memory
          guestUser
          ;
        inherit (settings) name displayRefit;
        display = display settings;
      }
    )
  ) spec.profiles;
  configuration = pkgs.writeText "vm-images.json" (
    builtins.toJSON (
      spec
      // {
        memoryBytes = spec.memory * 1024 * 1024;
        profiles = pkgs.lib.mapAttrs (
          profile: settings:
          settings
          // {
            receipt = receipts.${profile};
            display = display settings;
            sourceKey = if profile == "clean" then "localBase" else "prepared";
          }
        ) spec.profiles;
      }
    )
  );
  makePackage =
    tart:
    pkgs.writeShellApplication {
      name = "stratosphere-vm-image";
      runtimeInputs = [
        tart
        pkgs.coreutils
        pkgs.jq
      ];
      runtimeEnv = {
        STRATOSPHERE_IMAGE_CONFIG = configuration;
        STRATOSPHERE_IMAGE_EXISTS_QUERY = ./queries/exists.jq;
        STRATOSPHERE_ADOPT_SOURCE_QUERY = ./queries/adopt-source.jq;
        STRATOSPHERE_ADOPT_SETTINGS_QUERY = ./queries/adopt-settings.jq;
      };
      text = builtins.readFile ./scripts/image.sh;
    };
in
{
  inherit spec configuration makePackage;
  package = makePackage pkgs.tart;
  tests = import ./tests.nix { inherit pkgs spec makePackage; };
}
