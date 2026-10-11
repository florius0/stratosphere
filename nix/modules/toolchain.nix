{ inputs, ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      sdk = "${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
    in
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = package: lib.getName package == "tart";
      };
      _module.args.toolchain = {
        swiftpm = pkgs.callPackage ../features/toolchain/swiftpm.nix { };
        inherit sdk;
        buildInputs = [
          pkgs.apple-sdk_26
          (pkgs.darwinMinVersionHook "26.0")
        ];
        environment = {
          SWIFT_EXEC = "${pkgs.swift}/bin/swiftc";
          STRATOSPHERE_SWIFT = "${pkgs.swift}/bin/swift";
          STRATOSPHERE_SDK = sdk;
        };
      };
    };
}
