{
  description = "Stratosphere native macOS project foundation";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/39ad350a0602fa0a58a544344e3e9187526ea45c";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = package: nixpkgs.lib.getName package == "tart";
      };
      swiftpm = pkgs.callPackage ./nix/swiftpm.nix { };
      foundation = pkgs.callPackage ./nix/foundation.nix {
        inherit swiftpm;
        src = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            let
              name = baseNameOf path;
              relative = pkgs.lib.removePrefix "${toString ./.}/" (toString path);
              top = builtins.head (pkgs.lib.splitString "/" relative);
            in toString path == toString ./. || (
              builtins.elem top [ "Package.swift" "Sources" "Tests" "Tools" "E2E" ]
              && !(builtins.elem name [ ".local" ".build" ".swiftpm" "__pycache__" ".DS_Store" ])
            );
        };
      };
      developmentApp = name: command: {
        type = "app";
        meta.description = name;
        program = "${pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ pkgs.python3 pkgs.graphviz pkgs.tart ];
          text = ''
            if [[ ! -f Package.swift ]]; then
              echo "Run this command from the Stratosphere repository root." >&2
              exit 2
            fi
            ${command}
          '';
        }}/bin/${name}";
      };
    in {
      packages.${system} = { inherit foundation; default = foundation; };
      checks.${system} = {
        source-build = foundation;
        tooling = pkgs.runCommand "stratosphere-tooling-checks" {
          nativeBuildInputs = [ pkgs.python3 pkgs.graphviz ];
          src = foundation.src;
        } ''
          cp -R "$src" source
          chmod -R u+w source
          cd source
          python3 -m unittest discover -s Tests/ToolTests
          touch "$out"
        '';
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.swift swiftpm pkgs.python3 pkgs.graphviz pkgs.tart ];
        buildInputs = [ pkgs.apple-sdk_26 (pkgs.darwinMinVersionHook "26.0") ];
        STRATOSPHERE_SWIFT = "${pkgs.swift}/bin/swift";
        STRATOSPHERE_SDK = "${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
      };
      apps.${system} = {
        build = developmentApp "stratosphere-build" "exec python3 Tools/build.py build \"$@\"";
        test = developmentApp "stratosphere-test" "exec python3 Tools/build.py test \"$@\"";
        docs = developmentApp "stratosphere-docs" "exec python3 Tools/check-docs.py \"$@\"";
        stories = {
          type = "app";
          meta.description = "Open the native Stratosphere story catalog";
          program = "${pkgs.writeShellScript "stratosphere-stories" ''
            exec /usr/bin/open "${foundation}/Applications/StoryCatalog.app" "$@"
          ''}";
        };
        e2e-native = developmentApp "stratosphere-e2e-native" "exec python3 E2E/native.py --artifacts ${foundation}/Applications \"$@\"";
        e2e-vm = developmentApp "stratosphere-e2e-vm" "exec python3 E2E/vm.py --artifacts ${foundation}/Applications \"$@\"";
      };
    };
}
