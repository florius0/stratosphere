{ pkgs, makeRunners }:
let
  fakeRemote = pkgs.symlinkJoin {
    name = "fake-guest-transport";
    paths = [
      (pkgs.writeShellScriptBin "ssh" (builtins.readFile ./tests/ssh.sh))
      (pkgs.writeShellScriptBin "scp" "exit 0")
    ];
  };
  runners = makeRunners { };
  fakeRunners = makeRunners { remote = fakeRemote; };
in
pkgs.runCommand "e2e-wrapper-behavior" {
  nativeBuildInputs = [
    pkgs.bash
    pkgs.coreutils
    pkgs.jq
    pkgs.openssh
    pkgs.libiconv
    pkgs.gnused
    pkgs.gnugrep
  ];
  NATIVE_RUNNER = "${runners.native}/bin/e2e-native";
  VM_RUNNER = "${runners.vm}/bin/e2e-vm";
  FAKE_VM_RUNNER = "${fakeRunners.vm}/bin/e2e-vm";
  E2E_FIXTURES = ./tests;
} (builtins.readFile ./tests/run.sh)
