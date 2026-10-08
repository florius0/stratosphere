{ lib, stdenv, swift, swiftpm, python3, apple-sdk_26, darwinMinVersionHook, src }:
stdenv.mkDerivation {
  pname = "stratosphere-foundation";
  version = "0.1.0";
  inherit src;
  nativeBuildInputs = [ swift swiftpm python3 ];
  buildInputs = [ apple-sdk_26 (darwinMinVersionHook "26.0") ];
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
    python3 Tools/bundle.py "$binaries/StoryCatalog" "$out/Applications/StoryCatalog.app" --identifier dev.stratosphere.catalog --name StoryCatalog
    python3 Tools/bundle.py "$binaries/FixtureApp" "$out/Applications/FixtureApp.app" --identifier dev.stratosphere.fixture --name FixtureApp
    cp "$binaries/EnvironmentProbe" "$out/Applications/EnvironmentProbe"
    cat > "$out/Applications/toolchain.json" <<EOF
    {"compiler":"Swift ${swift.version}","sdk":"${apple-sdk_26.version}","sourceRevision":"${src}"}
    EOF
    ln -s "$out/Applications/EnvironmentProbe" "$out/bin/stratosphere-environment-probe"
    runHook postInstall
  '';
  meta = {
    description = "Native story catalog and isolated-environment probes for Stratosphere";
    platforms = [ "aarch64-darwin" ];
  };
}
