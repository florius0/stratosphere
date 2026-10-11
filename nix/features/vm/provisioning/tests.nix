{
  pkgs,
  makePackage,
  guestChecks,
}:
let
  imagePackage = pkgs.writeShellScriptBin "stratosphere-vm-image" "exit 0";
  credentialHelper = pkgs.writeShellScriptBin "sshpass" ''shift 2; exec "$@"'';
  tart = pkgs.writeShellScriptBin "tart" (builtins.readFile ./tests/tart.sh);
  remote = pkgs.symlinkJoin {
    name = "fake-provisioning-remote";
    paths = [
      (pkgs.writeShellScriptBin "ssh" (builtins.readFile ./tests/ssh.sh))
      (pkgs.writeShellScriptBin "scp" "exit 0")
    ];
  };
  runner = makePackage {
    inherit
      tart
      remote
      credentialHelper
      imagePackage
      ;
    readyTimeout = 2;
  };
in
pkgs.runCommand "vm-provisioning-behavior" {
  GUEST_CHECKS = guestChecks;
  nativeBuildInputs = [
    runner
    pkgs.jq
    pkgs.coreutils
  ];
} (builtins.readFile ./tests/run.sh)
