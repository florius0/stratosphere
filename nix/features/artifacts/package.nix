{ pkgs }:
let
  apps = {
    StoryCatalog = {
      identifier = "dev.stratosphere.catalog";
      icon = ../../../Assets/AppIcons/PlanetSunlit.icns;
    };
    FixtureApp = {
      identifier = "dev.stratosphere.fixture";
    };
  };
  plists = pkgs.lib.mapAttrs (
    name: app:
    pkgs.writeText "${name}-Info.plist" ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>${name}</string>
        <key>CFBundleIdentifier</key><string>${app.identifier}</string>
        <key>CFBundleName</key><string>${name}</string>
        <key>CFBundleDisplayName</key><string>${name}</string>
        ${pkgs.lib.optionalString (
          app ? icon
        ) "<key>CFBundleIconFile</key><string>Stratosphere.icns</string>"}
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleShortVersionString</key><string>0.1.0</string>
        <key>CFBundleVersion</key><string>1</string>
        <key>LSMinimumSystemVersion</key><string>26.0</string>
        <key>NSHighResolutionCapable</key><true/>
        <key>NSPrincipalClass</key><string>NSApplication</string>
      </dict></plist>
    ''
  ) apps;
  executables = [ "EnvironmentProbe" ];
  specification = pkgs.writeText "artifacts.json" (
    builtins.toJSON {
      apps = pkgs.lib.mapAttrs (
        name: app:
        app
        // {
          plist = plists.${name};
          resources = pkgs.lib.optionalAttrs (app ? icon) { "Stratosphere.icns" = app.icon; };
        }
      ) apps;
      inherit executables;
      signables = (map (name: "${name}.app") (builtins.attrNames apps)) ++ executables;
      publications =
        (map (name: "${name}.app") (builtins.attrNames apps)) ++ executables ++ [ "toolchain.json" ];
    }
  );
  assembler = pkgs.writeShellApplication {
    name = "stratosphere-assemble";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    runtimeEnv.STRATOSPHERE_ARTIFACT_SPEC = specification;
    text = builtins.readFile ./scripts/assemble.sh;
  };
  mkSigner =
    {
      security ? "/usr/bin/security",
      codesign ? "/usr/bin/codesign",
    }:
    pkgs.writeShellApplication {
      name = "stratosphere-sign";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jq
      ];
      runtimeEnv = {
        STRATOSPHERE_SECURITY = security;
        STRATOSPHERE_CODESIGN = codesign;
      };
      text = builtins.readFile ./scripts/sign.sh;
    };
in
{
  inherit
    apps
    plists
    specification
    assembler
    mkSigner
    ;
  signer = mkSigner { };
}
