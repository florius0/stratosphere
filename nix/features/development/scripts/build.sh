#!/usr/bin/env bash
# shellcheck source=common.sh
source "$STRATOSPHERE_DEVELOPMENT_COMMON"
prepare_swift build "$@"
"${command[@]}"
mapfile -t products < <(jq -r '.publications[]' "$STRATOSPHERE_ARTIFACT_SPEC")
binaries=$("${command[@]}" --show-bin-path)
stage=$(mktemp -d "$output/.artifacts-XXXXXX")
published=() backups=() committed=false
cleanup() {
  local result=$?
  trap - EXIT
  local restore_failed=false
  if [[ $committed == false ]]; then
    for product in "${published[@]}"; do rm -rf "${output:?}/${product:?}"; done
    for product in "${backups[@]}"; do
      mv "$stage/previous-$product" "$output/$product" || {
        result=1
        restore_failed=true
      }
    done
  fi
  if [[ $restore_failed == true ]]; then
    echo "Artifact recovery needed; previous files retained in $stage" >&2
  else
    rm -rf "$stage"
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$STRATOSPHERE_ASSEMBLER" "$binaries" "$stage"
revision=$(git rev-parse HEAD)
if [[ -n $(git status --porcelain) ]]; then revision+="-dirty"; fi
jq --arg revision "$revision" --arg macOS "$(/usr/bin/sw_vers -productVersion)" \
  '. + {sourceRevision:$revision,macOS:$macOS}' "$STRATOSPHERE_TOOLCHAIN" >"$stage/toolchain.json"
if [[ -n $identity ]]; then
  mapfile -t signables < <(jq -r '.signables[]' "$STRATOSPHERE_ARTIFACT_SPEC")
  signed=()
  for product in "${signables[@]}"; do signed+=("$stage/$product"); done
  "$STRATOSPHERE_SIGNER" "$identity" "$keychain" "${signed[@]}"
fi
for product in "${products[@]}"; do
  if [[ -L "$output/$product" ]]; then
    echo "Refusing symlink: $output/$product" >&2
    exit 2
  fi
done
for product in "${products[@]}"; do
  if [[ -e "$output/$product" ]]; then
    mv "$output/$product" "$stage/previous-$product"
    backups+=("$product")
  fi
  mv "$stage/$product" "$output/$product"
  published+=("$product")
done
committed=true
echo "Artifacts: $output"
