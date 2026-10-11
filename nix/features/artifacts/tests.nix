{ pkgs }:
let
  artifacts = import ./package.nix { inherit pkgs; };
  security = pkgs.writeShellScript "fake-security" (builtins.readFile ./tests/security.sh);
  codesign = pkgs.writeShellScript "fake-codesign" (builtins.readFile ./tests/codesign.sh);
  signer = artifacts.mkSigner { inherit security codesign; };
in
pkgs.runCommand "stratosphere-artifact-checks" {
  TEST_ICON = ../../../Assets/AppIcons/PlanetSunlit.icns;
  ASSEMBLER = "${artifacts.assembler}/bin/stratosphere-assemble";
  SIGNER = "${signer}/bin/stratosphere-sign";
  GREP = "${pkgs.gnugrep}/bin/grep";
  nativeBuildInputs = [ pkgs.jq ];
} (builtins.readFile ./tests/run.sh)
