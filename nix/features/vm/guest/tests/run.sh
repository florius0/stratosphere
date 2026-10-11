#!/usr/bin/env bash
bash -n "$PRODUCTION_SCRIPT"
shellcheck "$PRODUCTION_SCRIPT"
if grep -q /nix/store "$PRODUCTION_SCRIPT"; then
  echo 'Guest script requires host Nix store paths' >&2
  exit 1
fi
export TEST_STATE="$TMPDIR/state" TEST_HOME="$TMPDIR/home"
mkdir -p "$TEST_STATE" "$TEST_HOME/.ssh"
echo Mac14,5 >"$TEST_STATE/model"
echo /bin/bash >"$TEST_STATE/shell"
echo admin >"$TEST_STATE/login"
echo unrelated-key >"$TEST_HOME/.ssh/authorized_keys"
printf '%s\n' ' sleep 1' ' displaysleep 1' >"$TEST_STATE/power"
touch "$TEST_STATE/ssh" "$TEST_STATE/effects"
printf '%s\n%s\n' "$(printf runtime-password | base64)" "$(printf 'ssh-ed25519 AAAAtest fixture' | base64)" >secrets
if bash "$GUEST_SCRIPT" <secrets >result 2>&1; then
  echo 'host accepted'
  exit 1
fi
test ! -s "$TEST_STATE/effects"
grep -Fx unrelated-key "$TEST_HOME/.ssh/authorized_keys"
echo VirtualMac2,1 >"$TEST_STATE/model"
echo other >"$TEST_STATE/login"
bash "$GUEST_SCRIPT" <secrets >result 2>&1
grep -Fx reboot-required result
grep -Fx unrelated-key "$TEST_HOME/.ssh/authorized_keys"
test "$(grep -c '^ssh-ed25519 AAAAtest fixture$' "$TEST_HOME/.ssh/authorized_keys")" = 1
test "$(stat -c '%a' "$TEST_HOME/.ssh/authorized_keys")" = 600
test "$(stat -c '%a' "$TEST_HOME/.ssh")" = 700
if grep -q runtime-password result; then exit 1; fi
if grep -q AAAAtest result; then exit 1; fi
cp "$TEST_HOME/.ssh/authorized_keys" before
bash "$GUEST_SCRIPT" <secrets >result 2>&1
grep -Fx ready result
diff before "$TEST_HOME/.ssh/authorized_keys"
test "$(grep -c '^autologin$' "$TEST_STATE/effects")" = 1
echo other >"$TEST_STATE/login"
touch "$TEST_STATE/fail-login"
if bash "$GUEST_SCRIPT" <secrets >result 2>&1; then
  echo 'failed login accepted'
  exit 1
fi
if grep -E '^(ready|reboot-required)$' result; then exit 1; fi
if grep -q runtime-password result; then exit 1; fi
rm "$TEST_STATE/fail-login"
touch "$TEST_STATE/no-login-effect"
if bash "$GUEST_SCRIPT" <secrets >result 2>&1; then
  echo 'missing login readback accepted'
  exit 1
fi
if grep -E '^(ready|reboot-required)$' result; then exit 1; fi
if grep -q runtime-password result; then exit 1; fi
rm "$TEST_STATE/no-login-effect"
echo admin >"$TEST_STATE/login"
echo 1200 >"$TEST_STATE/idleTime"
touch "$TEST_STATE/no-default-effect"
if bash "$GUEST_SCRIPT" <secrets >result 2>&1; then
  echo 'missing defaults readback accepted'
  exit 1
fi
if grep -E '^(ready|reboot-required)$' result; then exit 1; fi
rm "$TEST_STATE/no-default-effect"
echo 0 >"$TEST_STATE/idleTime"
printf ' sleep 0\n displaysleep 0\n sleep 10\n displaysleep 10\n' >"$TEST_STATE/power"
bash "$GUEST_SCRIPT" <secrets >result 2>&1
if grep -Eq 'sleep[[:space:]]+10' "$TEST_STATE/power"; then
  echo 'idle power profile unchanged'
  exit 1
fi
printf '%s\n' 'unrelated-key' 'ssh-ed25519 AAAAtest original-comment' \
  'ssh-ed25519 AAAAtest second-comment' 'restrict ssh-ed25519 AAAAtest restricted-comment' \
  'ssh-ed25519 OTHERkey unrelated-comment' >"$TEST_HOME/.ssh/authorized_keys"
bash "$GUEST_SCRIPT" <secrets >result 2>&1
test "$(grep -c '^ssh-ed25519 AAAAtest ' "$TEST_HOME/.ssh/authorized_keys")" = 1
grep -Fx 'ssh-ed25519 AAAAtest original-comment' "$TEST_HOME/.ssh/authorized_keys"
grep -Fx 'restrict ssh-ed25519 AAAAtest restricted-comment' "$TEST_HOME/.ssh/authorized_keys"
grep -Fx 'ssh-ed25519 OTHERkey unrelated-comment' "$TEST_HOME/.ssh/authorized_keys"
grep -Fx 'unrelated-key' "$TEST_HOME/.ssh/authorized_keys"
cp "$TEST_HOME/.ssh/authorized_keys" normalized-before
bash "$GUEST_SCRIPT" <secrets >result 2>&1
diff normalized-before "$TEST_HOME/.ssh/authorized_keys"
touch "$out"
