#!/usr/bin/env bash
prepare_swift() {
  local action=$1
  shift
  configuration=debug
  identity="${STRATOSPHERE_SIGN_IDENTITY:-}"
  keychain="${STRATOSPHERE_SIGN_KEYCHAIN:-}"
  while (($#)); do
    case "$1" in
    --configuration | --sign-identity | --sign-keychain)
      (($# >= 2)) || {
        echo "Missing value for $1" >&2
        exit 2
      }
      case "$1" in
      --configuration) configuration=$2 ;;
      --sign-identity) identity=$2 ;;
      --sign-keychain) keychain=$2 ;;
      esac
      shift 2
      ;;
    *)
      echo 'Supported options: --configuration debug|release, --sign-identity NAME, --sign-keychain PATH' >&2
      exit 2
      ;;
    esac
  done
  [[ $configuration == debug || $configuration == release ]] || exit 2
  [[ -z $keychain || -n $identity ]] || {
    echo 'A keychain requires a signing identity' >&2
    exit 2
  }
  [[ -f Package.swift ]] || {
    echo 'Run from the Stratosphere repository root' >&2
    exit 2
  }
  output="$PWD/.local/build"
  mkdir -p "$output"
  export SDKROOT="$STRATOSPHERE_SDK"
  export MACOSX_DEPLOYMENT_TARGET=26.0
  export CLANG_MODULE_CACHE_PATH="$output/cache/clang"
  export SWIFT_MODULECACHE_PATH="$output/cache/swift"
  command=("$STRATOSPHERE_SWIFT" "$action"
    --package-path "$PWD" --scratch-path "$output/swift-$STRATOSPHERE_SWIFT_VERSION"
    --cache-path "$output/cache/packages" --config-path "$output/cache/config"
    --security-path "$output/cache/security" --disable-sandbox -c "$configuration")
  if [[ $action == test ]]; then command+=(--disable-xctest); fi
}
