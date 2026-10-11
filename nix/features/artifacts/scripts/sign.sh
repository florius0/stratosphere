#!/usr/bin/env bash
identity=$1
keychain=$2
shift 2
original=()
restore=false
cleanup() {
  local result=$?
  trap - EXIT
  if [[ $restore == true ]]; then
    "$STRATOSPHERE_SECURITY" list-keychains -d user -s "${original[@]}" || result=1
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
args=(--force --options runtime --sign "$identity")
if [[ -n $keychain ]]; then
  [[ -f $keychain ]] || {
    echo "Signing keychain not found: $keychain" >&2
    exit 2
  }
  keychain=$(cd "$(dirname "$keychain")" && printf '%s/%s' "$PWD" "$(basename "$keychain")")
  listed=$("$STRATOSPHERE_SECURITY" list-keychains -d user)
  decoded=$(jq -Rrs 'split("\n") | .[] | select(test("\\S")) | fromjson' <<<"$listed")
  if [[ -n $decoded ]]; then mapfile -t original <<<"$decoded"; fi
  present=false
  for item in "${original[@]}"; do if [[ $item == "$keychain" ]]; then present=true; fi; done
  if [[ $present == false ]]; then
    restore=true
    "$STRATOSPHERE_SECURITY" list-keychains -d user -s "$keychain" "${original[@]}"
  fi
  args+=(--keychain "$keychain")
fi
for artifact in "$@"; do
  if [[ -f $artifact ]]; then
    "$STRATOSPHERE_CODESIGN" "${args[@]}" --identifier dev.stratosphere.environment-probe "$artifact"
  else
    "$STRATOSPHERE_CODESIGN" "${args[@]}" "$artifact"
  fi
done
