{
  pkgs,
  images,
  guest,
}:
let
  recipe = pkgs.writeText "vm-guest-configuration.json" (builtins.toJSON guest.configuration);
  makePackage =
    {
      tart,
      remote ? pkgs.openssh,
      credentialHelper ? pkgs.sshpass,
      imagePackage ? images.package,
      readyTimeout ? 180,
    }:
    let
      configuration = pkgs.writeText "vm-provisioning.json" (
        builtins.toJSON {
          guestUser = guest.configuration.user;
          bootstrap = {
            user = "admin";
            initialPassword = "admin";
          };
        }
      );
    in
    pkgs.writeShellApplication {
      name = "vm-provisioning";
      runtimeInputs = [
        tart
        remote
        credentialHelper
        pkgs.openssh
        pkgs.coreutils
        pkgs.jq
      ];
      runtimeEnv = {
        STRATOSPHERE_VM_IMAGE_TOOL = "${imagePackage}/bin/stratosphere-vm-image";
        STRATOSPHERE_PREPARED_IMAGE = images.spec.profiles.prepared.name;
        STRATOSPHERE_PROVISIONING_CONFIG = configuration;
        STRATOSPHERE_GUEST_RECIPE = recipe;
        STRATOSPHERE_GUEST_SCRIPT = guest.script;
        STRATOSPHERE_READY_TIMEOUT = toString readyTimeout;
      };
      text = builtins.readFile ./scripts/provision.sh;
    };
  package = makePackage { tart = pkgs.tart; };
in
{
  inherit makePackage guest package;
  app = {
    type = "app";
    program = "${package}/bin/vm-provisioning";
  };
  tests = import ./tests.nix {
    inherit pkgs makePackage;
    guestChecks = guest.tests;
  };
}
