#!/usr/bin/env bash
export TART_HOME="$TMPDIR/tart"
stratosphere-vm-image clean
test -d "$TART_HOME/vms/stratosphere-clean-26-5"
test -f "$TART_HOME/stratosphere-provisioning/stratosphere-clean-26-5.json"
cp -R "$TART_HOME" before
stratosphere-vm-image clean
diff -r before "$TART_HOME"
stratosphere-vm-image prepared
test -d "$TART_HOME/vms/stratosphere-prepared-26-5"
printf '%s\n' --cpu 4 --memory 4096 --display 1280x800pt --display-refit >settings
diff settings "$TART_HOME/vms/stratosphere-prepared-26-5/settings"
grep -Fx "$IMAGE_SOURCE" "$TART_HOME/vms/stratosphere-clean-26-5/source"
jq -e '.guestUser == "admin"' \
  "$TART_HOME/stratosphere-provisioning/stratosphere-prepared-26-5.json"
export TART_HOME="$TMPDIR/unmanaged"
mkdir -p "$TART_HOME/vms/stratosphere-clean-26-5"
cp -R "$TART_HOME" unmanaged-before
if stratosphere-vm-image clean; then
  echo 'unmanaged image accepted' >&2
  exit 1
fi
diff -r unmanaged-before "$TART_HOME"
export TART_HOME="$TMPDIR/conflicting"
mkdir -p "$TART_HOME/vms/stratosphere-clean-26-5" "$TART_HOME/stratosphere-provisioning"
echo '{}' >"$TART_HOME/stratosphere-provisioning/stratosphere-clean-26-5.json"
cp -R "$TART_HOME" conflict-before
if stratosphere-vm-image clean; then
  echo 'conflict accepted' >&2
  exit 1
fi
diff -r conflict-before "$TART_HOME"
export TART_HOME="$TMPDIR/interrupted"
mkdir -p "$TART_HOME"
touch "$TART_HOME/fail-set"
if stratosphere-vm-image clean; then
  echo 'failed configuration accepted' >&2
  exit 1
fi
test -d "$TART_HOME/vms/stratosphere-clean-26-5"
test ! -f "$TART_HOME/stratosphere-provisioning/stratosphere-clean-26-5.json"
rm "$TART_HOME/fail-set"
cp -R "$TART_HOME" interrupted-before
if stratosphere-vm-image clean; then
  echo 'interrupted image accepted' >&2
  exit 1
fi
diff -r interrupted-before "$TART_HOME"
export TART_HOME="$TMPDIR/terminated"
mkdir -p "$TART_HOME"
touch "$TART_HOME/interrupt-set"
if stratosphere-vm-image clean; then
  echo 'terminated image setup accepted' >&2
  exit 1
fi
test -d "$TART_HOME/vms/stratosphere-clean-26-5"
test ! -f "$TART_HOME/stratosphere-provisioning/stratosphere-clean-26-5.json"
rm "$TART_HOME/interrupt-set"
cp -R "$TART_HOME" terminated-before
if stratosphere-vm-image clean; then exit 1; fi
diff -r terminated-before "$TART_HOME"
export TART_HOME="$TMPDIR/invalid"
if stratosphere-vm-image other; then exit 1; fi
test ! -e "$TART_HOME"
if stratosphere-vm-image clean extra; then exit 1; fi
test ! -e "$TART_HOME"
export TART_HOME="$TMPDIR/bad-list"
mkdir -p "$TART_HOME/vms"
touch "$TART_HOME/bad-list"
cp -R "$TART_HOME" bad-list-before
if stratosphere-vm-image clean; then
  echo 'invalid image listing accepted' >&2
  exit 1
fi
diff -r bad-list-before "$TART_HOME"
export TART_HOME="$TMPDIR/fail-list"
mkdir -p "$TART_HOME/vms"
touch "$TART_HOME/fail-list"
cp -R "$TART_HOME" fail-list-before
if stratosphere-vm-image clean; then exit 1; fi
diff -r fail-list-before "$TART_HOME"
export TART_HOME="$TMPDIR/fail-clone"
mkdir -p "$TART_HOME/vms"
touch "$TART_HOME/fail-clone"
if stratosphere-vm-image clean; then exit 1; fi
test ! -f "$TART_HOME/stratosphere-provisioning/stratosphere-clean-26-5.json"
test -d "$TART_HOME/vms/stratosphere-clean-26-5"
export TART_HOME="$TMPDIR/orphan"
mkdir -p "$TART_HOME/vms" "$TART_HOME/stratosphere-provisioning"
echo '{}' >"$TART_HOME/stratosphere-provisioning/stratosphere-clean-26-5.json"
cp -R "$TART_HOME" orphan-before
if stratosphere-vm-image clean; then exit 1; fi
diff -r orphan-before "$TART_HOME"
export TART_HOME="$TMPDIR/locked"
mkdir -p "$TART_HOME/vms" "$TART_HOME/.stratosphere-provisioning-lock"
cp -R "$TART_HOME" locked-before
if stratosphere-vm-image clean; then exit 1; fi
diff -r locked-before "$TART_HOME"
mkdir "$TMPDIR/default"
cd "$TMPDIR/default"
unset TART_HOME
stratosphere-vm-image clean
test -f .local/tart/stratosphere-provisioning/stratosphere-clean-26-5.json
export TART_HOME="$TMPDIR/adopt"
mkdir -p "$TART_HOME/vms/stratosphere-clean-26-5"
printf 'existing disk' >"$TART_HOME/vms/stratosphere-clean-26-5/disk.img"
cat >"$TART_HOME/vms/stratosphere-clean-26-5/config.json" <<'CONFIG'
{"os":"darwin","arch":"arm64","cpuCount":4,"memorySize":4294967296,"display":{"width":1280,"height":800},"displayRefit":false}
CONFIG
jq -n --arg source "$IMAGE_SOURCE" --arg home "$TART_HOME" \
  '{image:$source,localBase:"stratosphere-clean-26-5",prepared:"stratosphere-prepared-26-5",tartHome:$home,downloadComplete:true}' >provenance.json
cp -R "$TART_HOME/vms" existing-vms
stratosphere-vm-image --adopt clean "$PWD/provenance.json"
diff -r existing-vms "$TART_HOME/vms"
jq -e '.source != null and .name == "stratosphere-clean-26-5" and .displayRefit == false' \
  "$TART_HOME/stratosphere-provisioning/stratosphere-clean-26-5.json"
stratosphere-vm-image clean
diff -r existing-vms "$TART_HOME/vms"
export TART_HOME="$TMPDIR/adopt-wrong-source"
mkdir -p "$TART_HOME/vms/stratosphere-clean-26-5"
cp existing-vms/stratosphere-clean-26-5/* "$TART_HOME/vms/stratosphere-clean-26-5/"
jq --arg home "$TART_HOME" '.tartHome=$home | .image="wrong-source"' provenance.json >wrong-provenance.json
if stratosphere-vm-image --adopt clean "$PWD/wrong-provenance.json"; then
  echo 'Unverified source adopted'
  exit 1
fi
test ! -e "$TART_HOME/stratosphere-provisioning"
diff -r existing-vms "$TART_HOME/vms"
jq --arg home "$TART_HOME" '.tartHome=$home' provenance.json >correct-provenance.json
jq '.cpuCount=2' "$TART_HOME/vms/stratosphere-clean-26-5/config.json" >changed.json
cp changed.json "$TART_HOME/vms/stratosphere-clean-26-5/config.json"
if stratosphere-vm-image --adopt clean "$PWD/correct-provenance.json"; then
  echo 'Mismatched settings adopted'
  exit 1
fi
test ! -e "$TART_HOME/stratosphere-provisioning"
cmp changed.json "$TART_HOME/vms/stratosphere-clean-26-5/config.json"
touch "$out"
