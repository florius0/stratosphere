#!/usr/bin/env bash
set -euo pipefail
profile= artifacts="${STRATOSPHERE_ARTIFACTS:-$PWD/.local/build}" output="" image="${STRATOSPHERE_VM_IMAGE:-}" key="${STRATOSPHERE_SSH_KEY:-}"
while (($#)); do
  case "$1" in
  --profile | --artifacts | --output | --image | --ssh-key)
    (($# >= 2)) || {
      echo "Missing value for $1" >&2
      exit 2
    }
    case "$1" in --profile) profile=$2 ;; --artifacts) artifacts=$2 ;; --output) output=$2 ;; --image) image=$2 ;; --ssh-key) key=$2 ;; esac
    shift 2
    ;;
  *)
    echo "Unknown argument: $1" >&2
    exit 2
    ;;
  esac
done
run=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
output=${output:-$PWD/.local/results/$run}
mkdir -p "$(dirname "$output")"
mkdir "$output" || {
  echo 'Choose a fresh output directory' >&2
  exit 2
}
output=$(cd "$output" && pwd)
status=setup-failed code=2 error="" probe_status="" probe_code=null timed_out=false cleanup_errors='[]' owned_pid=""
bounded() { timeout --kill-after=5s "$@"; }
stop_owned() {
  if [[ -n $owned_pid ]]; then
    kill -TERM -- "-$owned_pid" 2>/dev/null || true
    for ((i = 0; i < 5; i++)); do
      kill -0 -- "-$owned_pid" 2>/dev/null || break
      sleep 1
    done
    kill -KILL -- "-$owned_pid" 2>/dev/null || true
    for ((i = 0; i < 5; i++)); do
      kill -0 "$owned_pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$owned_pid" 2>/dev/null; then
      cleanup_errors=$(jq -c '. + ["Owned process did not stop"]' <<<"$cleanup_errors")
      owned_pid=""
      return 1
    fi
    wait "$owned_pid" 2>/dev/null || true
    owned_pid=""
  fi
}
cleanup() { stop_owned; }
finish() {
  trap - EXIT INT TERM
  cleanup || { cleanup_errors=$(jq -c '. + ["Cleanup failed"]' <<<"$cleanup_errors"); }
  if [[ $cleanup_errors != '[]' ]]; then
    status=failed
    code=2
  fi
  jq -n --arg status "$status" --arg profile "$profile" --arg error "$error" --arg probeStatus "$probe_status" --arg image "$image" --arg run "$run" --argjson exitCode "$code" --argjson probeExitCode "$probe_code" --argjson timedOut "$timed_out" --argjson cleanupErrors "$cleanup_errors" '{status:$status,profile:$profile,error:$error,probeStatus:$probeStatus,image:$image,run:$run,exitCode:$exitCode,probeExitCode:$probeExitCode,timedOut:$timedOut,cleanupErrors:$cleanupErrors}' >"$output/run.json"
  echo "Qualification evidence: $output"
  exit "$code"
}
fail() {
  error=$1
  exit 2
}
trap 'error="Runtime step failed with status $?"' ERR
trap finish EXIT
trap 'status=interrupted; code=130; error="Run interrupted"; exit 130' INT
trap 'status=interrupted; code=143; error="Run terminated"; exit 143' TERM
probe_timeout=${STRATOSPHERE_PROBE_TIMEOUT:-120}
ready_timeout=${STRATOSPHERE_READY_TIMEOUT:-180}
[[ $probe_timeout =~ ^[1-9][0-9]*$ && $ready_timeout =~ ^[1-9][0-9]*$ ]] || fail 'Deadlines must be positive seconds'
artifacts=$(cd "$artifacts" && pwd) || fail 'Artifacts directory unavailable'
[[ -f "$artifacts/EnvironmentProbe" && -d "$artifacts/FixtureApp.app" ]] || fail 'Build native artifacts first'
metadata='{}'
if [[ -e "$artifacts/toolchain.json" ]]; then
  metadata='{"compiler":null}'
  if [[ $(wc -c <"$artifacts/toolchain.json") -le 32768 ]] && iconv -f UTF-8 -t UTF-16LE "$artifacts/toolchain.json" >/dev/null 2>&1; then
    metadata=$(jq -ce -f "$STRATOSPHERE_METADATA_QUERY" "$artifacts/toolchain.json" 2>/dev/null) || metadata='{"compiler":null}'
    [[ $(printf %s "$metadata" | wc -c) -le 32768 ]] || metadata='{"compiler":null}'
  fi
fi
export STRATOSPHERE_BUILD_METADATA="$metadata"
unset STRATOSPHERE_SOURCE_REVISION
revision=$(jq -r '.sourceRevision // empty' <<<"$metadata")
if [[ -n $revision ]]; then export STRATOSPHERE_SOURCE_REVISION="$revision"; fi
result() {
  [[ -f "$output/qualification.json" ]] || fail 'Probe produced no qualification result'
  probe_status=$(jq -er 'if type == "object" then .status | select(type == "string") else empty end' "$output/qualification.json") || fail 'Malformed probe result'
  status=$probe_status
  if [[ $probe_status == passed && $probe_code == 0 ]]; then code=0; else
    code=2
    [[ $status != passed ]] || status=failed
  fi
}
