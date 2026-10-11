#!/usr/bin/env bash
# shellcheck source=common.sh
source "$STRATOSPHERE_E2E_COMMON"
case "$profile" in
hosted) [[ ${GITHUB_ACTIONS:-} == true && ${RUNNER_OS:-} == macOS && ${RUNNER_ENVIRONMENT:-} == github-hosted ]] || fail 'Hosted profile requires a GitHub-hosted macOS runner' ;;
guest) [[ ${STRATOSPHERE_GUEST:-} == 1 && $(/usr/sbin/sysctl -n hw.model) == VirtualMac* ]] || fail 'Guest profile requires a marked VirtualMac' ;;
*) fail 'Select hosted or guest profile' ;;
esac
deadline=$probe_timeout
set -m
timeout --kill-after=5s "$deadline" "$artifacts/EnvironmentProbe" --profile "$profile" --fixture "$artifacts/FixtureApp.app" --output "$output/qualification.json" >"$output/probe.log" 2>&1 &
owned_pid=$!
probe_code=0
wait "$owned_pid" || probe_code=$?
stop_owned
if [[ $probe_code == 124 || $probe_code == 137 ]]; then
  timed_out=true
  fail 'Probe exceeded deadline'
fi
cat "$output/probe.log"
if [[ -f "$output/qualification.json" ]]; then
  jq -r 'if .sip_enabled_core_evidence == false then "SIP disabled: supplemental hosted regression evidence only; SIP-enabled VM qualification remains required." elif .sip_enabled_core_evidence == true then "SIP enabled: core environment evidence." else "SIP qualification unavailable; inspect qualification.json." end' "$output/qualification.json"
fi
result
