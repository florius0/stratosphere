#!/usr/bin/env bash
mkdir -p .local/ci
/usr/bin/xcodebuild -version >.local/ci/xcode.txt
/usr/bin/xcrun --show-sdk-version >.local/ci/sdk.txt
/usr/bin/sw_vers >.local/ci/macos.txt
