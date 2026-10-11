{
  pkgs,
  sdk,
  artifacts,
  docs,
  tooling,
  swift ? pkgs.swift,
  fileTools ? pkgs.coreutils,
}:
let
  toolchain = pkgs.writeText "toolchain.json" (
    builtins.toJSON {
      compiler = "Swift ${swift.version}";
      sdk = pkgs.apple-sdk_26.version;
    }
  );
  runner =
    action:
    pkgs.writeShellApplication {
      name = "stratosphere-${action}-run";
      runtimeInputs = [
        pkgs.jq
        pkgs.git
        fileTools
      ];
      runtimeEnv = {
        STRATOSPHERE_DEVELOPMENT_COMMON = ./scripts/common.sh;
        STRATOSPHERE_SWIFT = "${swift}/bin/swift";
        STRATOSPHERE_SWIFT_VERSION = swift.version;
        STRATOSPHERE_SDK = sdk;
      }
      // (
        if action == "test" then
          {
            STRATOSPHERE_TOOLING_CHECKS = tooling;
            STRATOSPHERE_DOCS = "${docs.package}/bin/stratosphere-docs";
          }
        else
          {
            STRATOSPHERE_ASSEMBLER = "${artifacts.assembler}/bin/stratosphere-assemble";
            STRATOSPHERE_ARTIFACT_SPEC = artifacts.specification;
            STRATOSPHERE_SIGNER = "${artifacts.signer}/bin/stratosphere-sign";
            STRATOSPHERE_TOOLCHAIN = toolchain;
          }
      );
      extraShellCheckFlags = [
        "-x"
        "-P"
        "${./scripts}"
      ];
      text =
        builtins.readFile (if action == "test" then ./scripts/test.sh else ./scripts/build.sh)
        + pkgs.lib.optionalString (action == "stories") ''
          /usr/bin/open "$output/StoryCatalog.app"
        '';
    };
  app = action: {
    type = "app";
    program = "${
      pkgs.writeShellApplication {
        name = "stratosphere-${action}";
        text = ''exec ${pkgs.nix}/bin/nix develop --command ${runner action}/bin/stratosphere-${action}-run "$@"'';
      }
    }/bin/stratosphere-${action}";
  };
in
{
  inherit runner;
  apps = pkgs.lib.genAttrs [ "build" "test" "stories" ] app;
}
