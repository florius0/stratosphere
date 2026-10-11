#!/usr/bin/env bash
# shellcheck source=common.sh
source "$STRATOSPHERE_E2E_COMMON"
export TART_HOME="${TART_HOME:-$PWD/.local/tart}"
profile=${profile:-prepared}
profile_config=$(jq -ce --arg profile "$profile" '.profiles[$profile] // error("Select clean or prepared VM profile")' "$STRATOSPHERE_VM_CONFIG")
image="${image:-$(jq -r '.name' <<<"$profile_config")}"
user="${STRATOSPHERE_VM_USER:-$(jq -r '.guestUser' "$STRATOSPHERE_VM_CONFIG")}"
[[ $image =~ ^[a-zA-Z0-9_.-]+$ && $image != .* ]] || fail 'Select a prepared local Tart image'
[[ $user =~ ^[a-z_][a-z0-9_-]*$ && -f $key ]] || fail 'Dedicated SSH key and local guest user required'
command -v tart >/dev/null || fail 'Tart unavailable'
name="stratosphere-test-$run" clone_attempted=false address="" uid="" label="dev.stratosphere.qualification.$run"
# The common EXIT handler calls this replacement cleanup function.
# shellcheck disable=SC2329
cleanup() {
  if [[ -n $address && -n $uid ]]; then ssh_guest launchctl bootout "gui/$uid/$label" >>"$output/tart.log" 2>&1 || true; fi
  if [[ $clone_attempted == true ]]; then
    bounded 15 tart stop "$name" >>"$output/tart.log" 2>&1 || cleanup_errors='["Owned clone stop failed"]'
    stop_owned || true
    if ! bounded 30 tart delete "$name" >>"$output/tart.log" 2>&1; then cleanup_errors=$(jq -c '. + ["Owned clone deletion failed"]' <<<"$cleanup_errors"); fi
  fi
}
inventory=$(bounded 30 tart list --format json) || fail 'Prepared image inventory unavailable'
jq -e --arg image "$image" --arg clone "$name" 'type == "array" and any(.[]; .Source == "local" and .Name == $image and .Running == false) and all(.[]; .Name != $clone)' <<<"$inventory" >/dev/null || fail 'Select a stopped prepared local image; clone name must be unused'
clone_attempted=true

bounded 120 tart clone "$image" "$name" >"$output/tart.log" 2>&1 || fail 'Clone failed'
bounded 30 tart set "$name" --no-display-refit >>"$output/tart.log" 2>&1 || fail 'Display setup failed'
set -m
tart run --no-graphics "$name" >>"$output/tart.log" 2>&1 &
owned_pid=$!
deadline=$((SECONDS + ready_timeout))
while ((SECONDS < deadline)); do
  kill -0 "$owned_pid" 2>/dev/null || fail 'Tart exited before readiness'
  address=$(bounded 10 tart ip "$name" 2>/dev/null) || address=""
  [[ $address =~ ^[0-9a-fA-F:.]+$ ]] && break
  address=""
  sleep 1
done
[[ -n $address ]] || fail 'Guest networking deadline exceeded'
connection=(-i "$key" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$output/known_hosts")
destination="$user@$address"
ssh_guest() {
  local command="" word
  for word in "$@"; do
    printf -v word '%q' "$word"
    command+="$word "
  done
  bounded 15 ssh "${connection[@]}" "$destination" "$command"
}
while ((SECONDS < deadline)); do
  uid=$(ssh_guest id -u 2>/dev/null) || uid=""
  [[ $uid =~ ^[0-9]+$ ]] && break
  sleep 1
done
[[ $uid =~ ^[0-9]+$ ]] || fail 'Guest SSH deadline exceeded'
ssh_guest launchctl print "gui/$uid" >/dev/null || fail 'Guest GUI session unavailable'
remote="/Users/$user/.local/stratosphere-e2e/$run"
remote_tools="/Users/$user/.local/stratosphere-test-tools"
ssh_guest mkdir -p "$remote" "$remote_tools" || fail 'Guest directory setup failed'
ssh_guest rm -rf "$remote_tools/FixtureApp.app" || fail 'Guest fixture replacement failed'
bounded 60 scp "${connection[@]}" -r "$artifacts/FixtureApp.app" "$artifacts/EnvironmentProbe" "$destination:$remote_tools/" || fail 'Artifact transfer failed'
jq -n --arg label "$label" --arg tools "$remote_tools" --arg remote "$remote" --arg image "$image" --argjson metadata "$metadata" --slurpfile specification "$STRATOSPHERE_VM_CONFIG" -f "$STRATOSPHERE_AGENT_QUERY" >"$output/probe.plist"
/usr/bin/plutil -convert xml1 "$output/probe.plist" || fail 'Launch agent encoding failed'
bounded 30 scp "${connection[@]}" "$output/probe.plist" "$destination:$remote/probe.plist" || fail 'Launch agent transfer failed'
ssh_guest launchctl bootstrap "gui/$uid" "$remote/probe.plist" || fail 'Guest GUI launch failed'
deadline=$((SECONDS + probe_timeout))
while ((SECONDS < deadline)); do
  ssh_guest cat "$remote/probe.log" >"$output/probe.log" 2>&1 || true
  if ssh_guest test -f "$remote/qualification.json"; then
    ssh_guest cat "$remote/qualification.json" >"$output/qualification.json" || fail 'Result transfer failed'
    job=$(ssh_guest launchctl print "gui/$uid/$label") || fail 'Probe exit status unavailable'
    probe_code=$(sed -n 's/.*last exit code = \([0-9]*\).*/\1/p' <<<"$job")
    [[ $probe_code =~ ^[0-9]+$ ]] || {
      sleep 1
      continue
    }
    result
    exit "$code"
  fi
  sleep 1
done
timed_out=true
fail 'Guest qualification deadline exceeded'
