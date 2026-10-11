#!/usr/bin/env bash
mkdir binaries assembled
printf 'catalog' >binaries/StoryCatalog
printf 'fixture' >binaries/FixtureApp
printf 'probe' >binaries/EnvironmentProbe
"$ASSEMBLER" "$PWD/binaries" "$PWD/assembled"
test -f assembled/StoryCatalog.app/Contents/MacOS/StoryCatalog || {
  echo 'FAIL: catalog was not assembled'
  exit 1
}
cmp binaries/StoryCatalog assembled/StoryCatalog.app/Contents/MacOS/StoryCatalog
test -x assembled/EnvironmentProbe
test -d assembled/FixtureApp.app/Contents/Resources
/usr/bin/plutil -lint assembled/StoryCatalog.app/Contents/Info.plist
/usr/bin/plutil -extract CFBundleIdentifier raw assembled/StoryCatalog.app/Contents/Info.plist | "$GREP" -Fx dev.stratosphere.catalog
/usr/bin/plutil -extract CFBundleIconFile raw assembled/StoryCatalog.app/Contents/Info.plist | "$GREP" -Fx Stratosphere.icns
cmp "$TEST_ICON" assembled/StoryCatalog.app/Contents/Resources/Stratosphere.icns
export SIGN_LOG="$PWD/sign.log"
touch 'test keychain'
if "$SIGNER" test "$PWD/test keychain" assembled/EnvironmentProbe; then
  echo 'FAIL: signing failure was ignored'
  exit 1
fi
test "$(tail -n 1 "$SIGN_LOG")" = 'list-keychains -d user -s /original keychain /second keychain' || {
  echo 'FAIL: original keychain search list was not restored'
  exit 1
}
touch "$out"
