{ self, ... }:
{
  perSystem =
    {
      pkgs,
      toolchain,
      artifacts,
      ...
    }:
    let
      package = pkgs.callPackage ../features/package/package.nix {
        inherit artifacts;
        inherit (toolchain) swiftpm;
        src = pkgs.lib.cleanSourceWith {
          src = self;
          filter =
            path: type:
            let
              name = baseNameOf path;
              relative = pkgs.lib.removePrefix "${toString self}/" (toString path);
              top = builtins.head (pkgs.lib.splitString "/" relative);
            in
            toString path == toString self
            || (
              builtins.elem top [
                "Package.swift"
                "Sources"
                "Tests"
              ]
              && !(builtins.elem name [
                ".local"
                ".build"
                ".swiftpm"
                "__pycache__"
                ".DS_Store"
              ])
            );
        };
      };
    in
    {
      packages = {
        stratosphere = package;
        default = package;
      };
      checks.source-build = package;
      apps.stories-packaged = {
        meta.description = "Open the packaged native story catalog";
        program = "${pkgs.writeShellScript "stratosphere-stories-packaged" ''
          exec /usr/bin/open "${package}/Applications/StoryCatalog.app" "$@"
        ''}";
      };
    };
}
