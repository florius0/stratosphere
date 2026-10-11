{
  pkgs,
  sdk,
  artifacts,
  docs,
}:
let
  compiler = pkgs.writeShellApplication {
    name = "swift";
    text = (builtins.readFile ./tests/swift.sh);
  };
  signer = pkgs.writeShellScriptBin "stratosphere-sign" "exit 7";
  development = import ./package.nix {
    inherit pkgs;
    swift = compiler // {
      version = pkgs.swift.version;
    };
    fileTools = pkgs.symlinkJoin {
      name = "fake-file-tools";
      paths = [
        failingMove
        pkgs.coreutils
      ];
    };
    inherit sdk docs;
    artifacts = artifacts // {
      inherit signer;
    };
    tooling = pkgs.writeText "checked" "";
  };
  runner = development.runner "build";
  failingMove = pkgs.writeShellApplication {
    name = "mv";
    runtimeEnv.REAL_MOVE = "${pkgs.coreutils}/bin/mv";
    text = builtins.readFile ./tests/move.sh;
  };
in
pkgs.runCommand "stratosphere-development-checks" {
  BUILD_RUNNER = "${runner}/bin/stratosphere-build-run";
  FAILING_MOVE_BIN = "${failingMove}/bin";
  nativeBuildInputs = [
    pkgs.git
    pkgs.jq
    pkgs.coreutils
  ];
} (builtins.readFile ./tests/run.sh)
