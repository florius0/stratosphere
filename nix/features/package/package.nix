{
  lib,
  stdenv,
  swift,
  swiftpm,
  apple-sdk_26,
  darwinMinVersionHook,
  artifacts,
  src,
}:
stdenv.mkDerivation {
  pname = "stratosphere";
  version = "0.1.0";
  inherit src;
  nativeBuildInputs = [
    swift
    swiftpm
  ];
  buildInputs = [
    apple-sdk_26
    (darwinMinVersionHook "26.0")
  ];
  strictDeps = true;
  doCheck = true;
  buildPhase = ''
    runHook preBuild
    export CLANG_MODULE_CACHE_PATH="$TMPDIR/clang-cache"
    export SWIFT_MODULECACHE_PATH="$TMPDIR/swift-cache"
    swift build -c release --disable-sandbox --cache-path "$TMPDIR/packages" --config-path "$TMPDIR/config" --security-path "$TMPDIR/security"
    runHook postBuild
  '';
  checkPhase = ''
    runHook preCheck
    swift test -c release --disable-xctest --disable-sandbox --cache-path "$TMPDIR/packages" --config-path "$TMPDIR/config" --security-path "$TMPDIR/security"
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    binaries=$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$TMPDIR/packages" --config-path "$TMPDIR/config" --security-path "$TMPDIR/security")
    mkdir -p "$out/Applications" "$out/bin"
    ${artifacts.assembler}/bin/stratosphere-assemble "$binaries" "$out/Applications"
    cp ${
      builtins.toFile "toolchain.json" (
        builtins.toJSON {
          compiler = "Swift ${swift.version}";
          sdk = apple-sdk_26.version;
          sourceRevision = toString src;
        }
      )
    } "$out/Applications/toolchain.json"
    ln -s "$out/Applications/EnvironmentProbe" "$out/bin/stratosphere-environment-probe"
    runHook postInstall
  '';
  meta = {
    description = "Native story catalog and isolated-environment probes for Stratosphere";
    platforms = [ "aarch64-darwin" ];
  };
}
