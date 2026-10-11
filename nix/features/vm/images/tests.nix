{
  pkgs,
  spec,
  makePackage,
}:
let
  fakeTart = pkgs.writeShellApplication {
    name = "tart";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = builtins.readFile ./tests/fake-tart.sh;
  };
  testedPackage = makePackage fakeTart;
in
pkgs.runCommand "vm-image-behavior" {
  nativeBuildInputs = [
    testedPackage
    pkgs.jq
    pkgs.coreutils
  ];
  IMAGE_SOURCE = spec.source;
} (builtins.readFile ./tests/run.sh)
