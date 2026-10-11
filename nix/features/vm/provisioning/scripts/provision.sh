#!/usr/bin/env bash
"$STRATOSPHERE_VM_IMAGE_TOOL" "$@"
if [[ $1 == --adopt || $1 == clean ]]; then exit 0; fi
image="$STRATOSPHERE_PREPARED_IMAGE"
user=$(jq -r '.guestUser' "$STRATOSPHERE_PROVISIONING_CONFIG")
bootstrap_user=$(jq -r '.bootstrap.user' "$STRATOSPHERE_PROVISIONING_CONFIG")
bootstrap_password=$(jq -r '.bootstrap.initialPassword' "$STRATOSPHERE_PROVISIONING_CONFIG")
export TART_HOME="${TART_HOME:-$PWD/.local/tart}"
data="$PWD/.local/vm-provisioning"
key="${STRATOSPHERE_SSH_KEY:-$data/test-vm-key}"
password_file="${STRATOSPHERE_VM_PASSWORD_FILE:-$data/guest-password}"
prepare_credentials() {
  umask 077
  mkdir -p "$data"
  if [[ ! -e $key ]]; then
    mkdir -p "$(dirname "$key")"
    ssh-keygen -q -t ed25519 -N "" -f "$key"
  fi
  public_key=$(ssh-keygen -y -P "" -f "$key")
  if [[ ! -e $password_file ]]; then
    if [[ -n ${STRATOSPHERE_VM_PASSWORD_FILE:-} ]]; then
      echo 'Guest password file not found' >&2
      exit 2
    fi
    printf '%s\n' "$bootstrap_password" >"$password_file"
  fi
  [[ -f $password_file && ! -L $password_file ]] || {
    echo 'Use a regular guest password file' >&2
    exit 2
  }
}
prepare_credentials
run=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
output="$data/runs/$run"
mkdir -p "$output"
lock="$TART_HOME/.stratosphere-provisioning-lock"
mkdir "$lock" || {
  echo 'Another provisioning operation owns the lock' >&2
  exit 2
}
boot_pid="" booted=false outcome=failed
bounded() { timeout --kill-after=5s "$@"; }
stop_boot() {
  local result=0
  if [[ $booted == true && -n $boot_pid ]] && kill -0 "$boot_pid" 2>/dev/null; then
    bounded 15 tart stop "$image" >>"$output/tart.log" 2>&1 || result=1
    booted=false
  fi
  if [[ -n $boot_pid ]]; then
    kill -TERM -- "-$boot_pid" 2>/dev/null || true
    for ((i = 0; i < 50; i++)); do
      kill -0 "$boot_pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$boot_pid" 2>/dev/null; then
      kill -KILL -- "-$boot_pid" 2>/dev/null || true
      for ((i = 0; i < 50; i++)); do
        kill -0 "$boot_pid" 2>/dev/null || break
        sleep 0.1
      done
    fi
    if kill -0 "$boot_pid" 2>/dev/null; then
      echo 'Owned VM process did not stop' >&2
      result=1
    else
      wait "$boot_pid" 2>/dev/null || true
    fi
    boot_pid=""
  fi
  return "$result"
}
finish() {
  local result=$? staged="$TART_HOME/stratosphere-provisioning/.guest-$run.tmp"
  trap - EXIT INT TERM
  set +e
  if ! stop_boot; then result=1; fi
  if ((result != 0)); then outcome=failed; fi
  if ((result == 130 || result == 143)); then outcome=interrupted; fi
  write_result() {
    jq -n --arg status "$outcome" --arg image "$image" --argjson exitCode "$result" \
      --slurpfile configuration "$STRATOSPHERE_GUEST_RECIPE" '{status:$status,image:$image,exitCode:$exitCode,configuration:$configuration[0],permissions:"not-managed"}' >"$output/run.json"
  }
  if ! write_result; then
    result=1
    outcome=failed
  fi
  if [[ $outcome == passed ]] && ! cp "$output/run.json" "$staged"; then
    result=1
    outcome=failed
  fi
  if ! rmdir "$lock"; then
    result=1
    outcome=failed
  fi
  if [[ $outcome == passed ]]; then
    receipt="$TART_HOME/stratosphere-provisioning/$image.guest.json"
    if [[ -d $receipt || -L $receipt ]] || ! mv "$staged" "$receipt"; then
      result=1
      outcome=failed
    fi
  fi
  if [[ $outcome != passed ]]; then
    rm -f "$staged"
    write_result || echo 'Could not persist provisioning failure evidence' >&2
  fi
  echo "Provisioning evidence: $output"
  exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
inventory=$(bounded 15 tart list --format json)
jq -e --arg image "$image" 'type == "array" and any(.[]; .Source == "local" and .Name == $image and .Running == false)' <<<"$inventory" >/dev/null || {
  echo 'Stop the prepared template before provisioning' >&2
  exit 2
}
connection=(-F /dev/null -i "$key" -o IdentitiesOnly=yes -o IdentityAgent=none -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$output/known_hosts" -o "PreferredAuthentications=publickey,password")
address=""
destination=""
boot() {
  set -m
  tart run --no-graphics "$image" >>"$output/tart.log" 2>&1 &
  boot_pid=$!
  booted=false
  local deadline=$((SECONDS + STRATOSPHERE_READY_TIMEOUT))
  while ((SECONDS < deadline)); do
    kill -0 "$boot_pid" 2>/dev/null || {
      echo 'VM stopped before readiness' >&2
      return 1
    }
    address=$(bounded 10 tart ip "$image" 2>/dev/null) || address=""
    if [[ $address =~ ^[0-9a-fA-F:.]+$ ]]; then
      destination="${bootstrap_user}@$address"
      if bounded 15 sshpass -f "$password_file" ssh "${connection[@]}" "$destination" 'sudo -n true' >>"$output/ssh.log" 2>&1; then
        kill -0 "$boot_pid" 2>/dev/null || {
          echo 'Owned VM launcher exited during readiness' >&2
          return 1
        }
        booted=true
        return 0
      fi
    fi
    sleep 1
  done
  echo 'Guest SSH readiness deadline exceeded' >&2
  return 1
}
boot
apply_guest() {
  bounded 30 sshpass -f "$password_file" scp "${connection[@]}" "$STRATOSPHERE_GUEST_SCRIPT" "$destination:/tmp/stratosphere-provisioning-$run.sh" >>"$output/ssh.log" 2>&1
  {
    head -n 1 "$password_file" | tr -d '\n' | base64 --wrap=0
    printf '\n'
    printf '%s' "$public_key" | base64 --wrap=0
    printf '\n'
  } | bounded 45 sshpass -f "$password_file" ssh "${connection[@]}" "$destination" \
    "sudo -n /bin/bash /tmp/stratosphere-provisioning-$run.sh" >"$output/guest.log" 2>&1
  message=$(tail -n 1 "$output/guest.log")
  [[ $message == ready || $message == reboot-required ]] || {
    echo 'Guest did not verify its configuration' >&2
    exit 1
  }
  if [[ $message == reboot-required ]]; then
    stop_boot
    boot
  fi
}
apply_guest
verify_guest() {
  destination="$user@$address"
  bounded 15 ssh "${connection[@]}" -o BatchMode=yes "$destination" 'id -un' >"$output/user.txt"
  [[ $(cat "$output/user.txt") == "$user" ]] || {
    echo 'Guest user verification failed' >&2
    exit 1
  }
  deadline=$((SECONDS + STRATOSPHERE_READY_TIMEOUT))
  gui_ready=false
  while ((SECONDS < deadline)); do
    # SSH evaluates these variables in the guest shell.
    # shellcheck disable=SC2016
    if bounded 15 ssh "${connection[@]}" -o BatchMode=yes "$destination" \
      'uid=$(id -u); test "$(stat -f %u /dev/console)" = "$uid" && launchctl print "gui/$uid" >/dev/null' >>"$output/ssh.log" 2>&1; then
      gui_ready=true
      break
    fi
    sleep 1
  done
  [[ $gui_ready == true ]] || {
    echo 'Guest GUI readiness deadline exceeded' >&2
    exit 1
  }
}
verify_guest
bounded 15 ssh "${connection[@]}" -o BatchMode=yes "$destination" \
  "rm -f /tmp/stratosphere-provisioning-$run.sh" >>"$output/ssh.log" 2>&1
kill -0 "$boot_pid" 2>/dev/null || {
  echo 'Owned VM launcher exited during provisioning' >&2
  exit 1
}
outcome=passed
