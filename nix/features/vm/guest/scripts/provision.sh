#!/bin/bash
set -euo pipefail
case "$(@sysctl@ -n hw.model)" in
VirtualMac*) ;;
*)
  echo "Guest provisioning requires a VirtualMac." >&2
  exit 1
  ;;
esac
[[ "$(@id@ -u)" == 0 ]] || {
  echo "Guest provisioning requires root." >&2
  exit 1
}
umask 077
IFS= read -r encodedPassword
IFS= read -r encodedKey
password=$(printf '%s' "$encodedPassword" | @base64@ -D 2>/dev/null) || {
  echo "Invalid password input." >&2
  exit 1
}
publicKey=$(printf '%s' "$encodedKey" | @base64@ -D 2>/dev/null) || {
  echo "Invalid public key input." >&2
  exit 1
}
unset encodedPassword encodedKey
[[ -n $password ]] || {
  echo "A guest login password is required." >&2
  exit 1
}
case "$publicKey" in
ssh-ed25519\ * | ssh-rsa\ * | ecdsa-sha2-*\ *) ;;
*)
  echo "An SSH public key is required." >&2
  exit 1
  ;;
esac
[[ $publicKey != *$'\n'* && $publicKey != *$'\r'* ]] || {
  echo "The public key must contain one line." >&2
  exit 1
}
read -r keyType keyBody _ <<<"$publicKey"
[[ -n $keyBody ]] || {
  echo "The public key must include its key body." >&2
  exit 1
}
user="@user@"
home="@home@"
record="/Users/$user"
actualHome=$(@dscl@ . -read "$record" NFSHomeDirectory | @awk@ '{print $2}')
[[ $actualHome == "$home" && -d $home ]] || {
  echo "The declared guest account/home must already exist." >&2
  exit 1
}
shell=$(@dscl@ . -read "$record" UserShell | @awk@ '{print $2}')
if [[ $shell != @shell@ ]]; then
  @dscl@ . -create "$record" UserShell @shell@
fi
[[ "$(@dscl@ . -read "$record" UserShell | @awk@ '{print $2}')" == @shell@ ]]
uid=$(@dscl@ . -read "$record" UniqueID | @awk@ '{print $2}')
gid=$(@dscl@ . -read "$record" PrimaryGroupID | @awk@ '{print $2}')
[[ $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ ]]
sshDirectory="$home/.ssh"
authorized="$sshDirectory/authorized_keys"
[[ ! -L $sshDirectory && ! -L $authorized ]] || {
  echo "SSH configuration must not be symlinked." >&2
  exit 1
}
@mkdir@ -p "$sshDirectory"
: >>"$authorized"
keyFile=$(@mktemp@ "$sshDirectory/.authorized_keys.XXXXXX")
trap '@rm@ -f "$keyFile"' EXIT
@awk@ -v keyType="$keyType" -v keyBody="$keyBody" '
  $1 == keyType && $2 == keyBody { if (seen++) next }
  { print }
' "$authorized" >"$keyFile"
if ! @cmp@ -s "$authorized" "$keyFile"; then
  @mv@ "$keyFile" "$authorized"
fi
@rm@ -f "$keyFile"
trap - EXIT
key_exists() {
  @awk@ -v keyType="$keyType" -v keyBody="$keyBody" '
    $1 == keyType && $2 == keyBody { found = 1 }
    END { exit !found }
  ' "$authorized"
}
if ! key_exists; then
  printf '\n%s\n' "$publicKey" >>"$authorized"
fi
@chown@ "$uid:$gid" "$sshDirectory" "$authorized"
@chmod@ 700 "$sshDirectory"
@chmod@ 600 "$authorized"
key_exists
[[ "$(@stat@ -f '%u:%g' "$authorized")" == "$uid:$gid" && "$(@stat@ -f '%u:%g' "$sshDirectory")" == "$uid:$gid" ]]
[[ "$(@stat@ -f '%Lp' "$authorized")" == 600 && "$(@stat@ -f '%Lp' "$sshDirectory")" == 700 ]]
if ! @launchctl@ print system/com.openssh.sshd >/dev/null 2>&1; then
  @launchctl@ enable system/com.openssh.sshd
  @launchctl@ bootstrap system /System/Library/LaunchDaemons/ssh.plist
fi
@launchctl@ print system/com.openssh.sshd >/dev/null
outcome=ready
login=$(@defaults@ read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true)
if [[ $login != "@autoLoginUser@" ]]; then
  if ! @sysadminctl@ -adminUser "$user" -adminPassword "$password" \
    -autologin set -userName "@autoLoginUser@" -password "$password" >/dev/null 2>&1; then
    echo "Automatic GUI login configuration failed." >&2
    exit 1
  fi
  outcome=reboot-required
fi
unset password
[[ "$(@defaults@ read /Library/Preferences/com.apple.loginwindow autoLoginUser)" == "@autoLoginUser@" ]] || {
  echo "Automatic GUI login readback failed." >&2
  exit 1
}
idle=$(@sudo@ -H -u "$user" @defaults@ -currentHost read com.apple.screensaver idleTime 2>/dev/null || true)
if [[ $idle != @screensaverIdleTime@ ]]; then
  @sudo@ -H -u "$user" @defaults@ -currentHost write com.apple.screensaver idleTime -int @screensaverIdleTime@
fi
[[ "$(@sudo@ -H -u "$user" @defaults@ -currentHost read com.apple.screensaver idleTime)" == @screensaverIdleTime@ ]]
power_matches() {
  @awk@ -v sleep=@sleep@ -v displaySleep=@displaySleep@ '
    $1 == "sleep" { sleepCount++; if ($2 != sleep) mismatch = 1 }
    $1 == "displaysleep" { displayCount++; if ($2 != displaySleep) mismatch = 1 }
    END { exit (!sleepCount || !displayCount || mismatch) }
  ' <<<"$power"
}
power=$(@pmset@ -g custom)
if ! power_matches; then
  @pmset@ -a sleep @sleep@ displaysleep @displaySleep@
fi
power=$(@pmset@ -g custom)
power_matches
echo "$outcome"
