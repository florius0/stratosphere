#!/usr/bin/env bash
mkdir -p workspace/binaries workspace/.local/build
cd workspace
git init -q
git -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm fixture
touch Package.swift
export FAKE_BINARIES="$PWD/binaries"
printf 'new catalog' >binaries/StoryCatalog
printf 'new fixture' >binaries/FixtureApp
printf 'new probe' >binaries/EnvironmentProbe
for product in StoryCatalog.app FixtureApp.app EnvironmentProbe toolchain.json; do
  printf 'old artifact' >".local/build/$product"
done
cp -R .local/build expected
if "$BUILD_RUNNER" --sign-identity test; then
  echo 'Signing failure accepted'
  exit 1
fi
diff -r expected .local/build
rm .local/build/FixtureApp.app
ln -s "$PWD/expected/FixtureApp.app" .local/build/FixtureApp.app
cp -R .local/build linked
if "$BUILD_RUNNER"; then
  echo 'Symlink accepted'
  exit 1
fi
diff -r linked .local/build
rm .local/build/FixtureApp.app
cp expected/FixtureApp.app .local/build/FixtureApp.app
export PATH="$FAILING_MOVE_BIN:$PATH" FAIL_MOVE=1
if "$BUILD_RUNNER"; then
  echo 'Publication failure accepted'
  exit 1
fi
diff -r expected .local/build
unset FAIL_MOVE
"$BUILD_RUNNER"
cmp binaries/StoryCatalog .local/build/StoryCatalog.app/Contents/MacOS/StoryCatalog
cmp binaries/EnvironmentProbe .local/build/EnvironmentProbe
jq -e '.compiler != null and .sdk != null and .sourceRevision != null' .local/build/toolchain.json
touch "$out"
