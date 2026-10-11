{
  stdenv,
  swift,
  swiftpm,
  apple-sdk_26,
  darwinMinVersionHook,
}:
# The pinned package omits the upstream launcher for Darwin Swift Testing bundles.
stdenv.mkDerivation {
  pname = "swiftpm-with-testing-helper";
  inherit (swiftpm) version;
  src = swiftpm.src;
  nativeBuildInputs = [ swift ];
  buildInputs = [
    apple-sdk_26
    (darwinMinVersionHook "26.0")
  ];
  buildPhase = ''
    export CLANG_MODULE_CACHE_PATH="$TMPDIR/clang-cache"
    swiftc -parse-as-library -O Sources/swiftpm-testing-helper/Entrypoint.swift -o swiftpm-testing-helper
  '';
  installPhase = ''
    mkdir -p "$out"
    cp -R ${swiftpm}/. "$out/"
    chmod u+w "$out" "$out/bin"
    mkdir -p "$out/libexec/swift/pm"
    cp swiftpm-testing-helper "$out/libexec/swift/pm/"
  '';
  inherit (swiftpm) meta;
}
