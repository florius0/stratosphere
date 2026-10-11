#!/usr/bin/env bash
command=$1
shift
case "$command" in
sysctl) cat "$TEST_STATE/model" ;;
id) echo 0 ;;
base64) "$COREUTILS_BASE64" --decode ;;
dscl)
  if [[ $2 == -read ]]; then
    case "$4" in
    NFSHomeDirectory) echo "NFSHomeDirectory: $TEST_HOME" ;;
    UserShell)
      printf 'UserShell: '
      cat "$TEST_STATE/shell"
      ;;
    UniqueID) echo 'UniqueID: 501' ;;
    PrimaryGroupID) echo 'PrimaryGroupID: 20' ;;
    esac
  else
    echo /bin/zsh >"$TEST_STATE/shell"
    echo shell >>"$TEST_STATE/effects"
  fi
  ;;
sysadminctl)
  [[ ! -e "$TEST_STATE/fail-login" ]] || exit 1
  [[ $* == *"-password runtime-password"* ]]
  [[ $* == *"-adminUser admin -adminPassword runtime-password"* ]]
  [[ ! -e "$TEST_STATE/no-login-effect" ]] || exit 0
  echo admin >"$TEST_STATE/login"
  echo autologin >>"$TEST_STATE/effects"
  ;;
defaults)
  if [[ $1 == -currentHost ]]; then shift; fi
  verb=$1
  key=$3
  file="$TEST_STATE/$key"
  [[ $key != autoLoginUser ]] || file="$TEST_STATE/login"
  if [[ $verb == read ]]; then
    cat "$file"
  else
    [[ ! -e "$TEST_STATE/no-default-effect" ]] || exit 0
    echo "$5" >"$file"
    echo defaults >>"$TEST_STATE/effects"
  fi
  ;;
sudo)
  [[ $1 != -H ]] || shift
  shift 2
  exec "$@"
  ;;
launchctl)
  if [[ $1 == print ]]; then
    [[ -e "$TEST_STATE/ssh" ]]
  else
    touch "$TEST_STATE/ssh"
    echo ssh >>"$TEST_STATE/effects"
  fi
  ;;
pmset)
  if [[ $1 == -g ]]; then
    cat "$TEST_STATE/power"
  else
    printf ' sleep 0\n displaysleep 0\n' >"$TEST_STATE/power"
    echo sleep >>"$TEST_STATE/effects"
  fi
  ;;
chown) echo chown >>"$TEST_STATE/effects" ;;
stat)
  if [[ $2 == '%u:%g' ]]; then
    echo '501:20'
  else "$COREUTILS_STAT" -c '%a' "$3"; fi
  ;;
*)
  echo "Unknown native boundary" >&2
  exit 1
  ;;
esac
