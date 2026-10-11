#!/usr/bin/env bash
adopt=false provenance=""
if [[ $# == 3 && $1 == --adopt ]]; then
  adopt=true
  profile=$2
  provenance=$3
elif [[ $# == 1 ]]; then
  profile=$1
else
  echo "Usage: stratosphere-vm-image [clean|prepared] or stratosphere-vm-image --adopt [clean|prepared] PROVENANCE.json" >&2
  exit 2
fi
selected=$(jq -ce --arg profile "$profile" '.profiles[$profile] // error("Select clean or prepared")' "$STRATOSPHERE_IMAGE_CONFIG")
image=$(jq -r '.name' <<<"$selected")
expected=$(jq -r '.receipt' <<<"$selected")
display=$(jq -r '.display' <<<"$selected")
unit=$(jq -r '.displayUnit' <<<"$selected")
refit=$(jq -r '.displayRefit' <<<"$selected")
source_key=$(jq -r '.sourceKey' <<<"$selected")
source=$(jq -r '.source' "$STRATOSPHERE_IMAGE_CONFIG")
cpu=$(jq -r '.cpu' "$STRATOSPHERE_IMAGE_CONFIG")
memory=$(jq -r '.memory' "$STRATOSPHERE_IMAGE_CONFIG")
memory_bytes=$(jq -r '.memoryBytes' "$STRATOSPHERE_IMAGE_CONFIG")
width=$(jq -r '.displaySize.width' "$STRATOSPHERE_IMAGE_CONFIG")
height=$(jq -r '.displaySize.height' "$STRATOSPHERE_IMAGE_CONFIG")
export TART_HOME="${TART_HOME:-$PWD/.local/tart}"
receipt="$TART_HOME/stratosphere-provisioning/$image.json"
lock="$TART_HOME/.stratosphere-provisioning-lock"
acquire_lock() {
  if ! mkdir "$lock"; then
    echo "Provisioning is locked; inspect $lock before retrying." >&2
    exit 1
  fi
  trap 'rm -f "$lock/receipt.json"; rmdir "$lock"' EXIT
}
record_spec() {
  mkdir -p "$(dirname "$receipt")"
  cp "$expected" "$lock/receipt.json"
  mv "$lock/receipt.json" "$receipt"
}
images=$(tart list --format json)
exists=$(jq -r --arg image "$image" -f "$STRATOSPHERE_IMAGE_EXISTS_QUERY" <<<"$images")
if [[ $exists == true ]]; then
  if [[ -f $receipt ]] && cmp -s "$expected" "$receipt"; then
    echo "Reusing matching image: $image"
  elif [[ -e $receipt ]]; then
    echo "Refusing conflicting image specification: $image" >&2
    exit 1
  elif [[ $adopt == true ]]; then
    [[ -f $provenance && -f "$TART_HOME/vms/$image/config.json" ]] || {
      echo 'Adoption requires original provenance and the existing Tart configuration' >&2
      exit 1
    }
    home=$(cd "$TART_HOME" && pwd -P)
    jq -e --arg source "$source" --arg image "$image" --arg key "$source_key" --arg home "$home" \
      -f "$STRATOSPHERE_ADOPT_SOURCE_QUERY" \
      "$provenance" >/dev/null || {
      echo 'Recorded image source does not match the declared image/storage' >&2
      exit 1
    }
    jq -e --argjson cpu "$cpu" --argjson memory "$memory_bytes" \
      --argjson width "$width" --argjson height "$height" \
      --arg unit "$unit" --argjson refit "$refit" \
      -f "$STRATOSPHERE_ADOPT_SETTINGS_QUERY" \
      "$TART_HOME/vms/$image/config.json" >/dev/null || {
      echo 'Existing VM settings do not match the declaration; adoption changes no VM settings' >&2
      exit 1
    }
    acquire_lock
    [[ ! -e $receipt ]] || {
      echo 'Specification appeared during adoption; retry explicitly' >&2
      exit 1
    }
    record_spec
    echo "Adopted existing image: $image"
  else
    echo "Refusing existing unmanaged image: $image. Adopt it with its original provenance record." >&2
    exit 1
  fi
else
  [[ $adopt == false ]] || {
    echo 'Cannot adopt a missing image' >&2
    exit 1
  }
  if [[ -e $receipt ]]; then
    echo "Refusing orphaned provisioning receipt: $receipt" >&2
    exit 1
  fi
  mkdir -p "$TART_HOME"
  acquire_lock
  images=$(tart list --format json)
  exists=$(jq -r --arg image "$image" -f "$STRATOSPHERE_IMAGE_EXISTS_QUERY" <<<"$images")
  if [[ $exists == true ]]; then
    echo "Image appeared during provisioning; refusing changes: $image" >&2
    exit 1
  fi
  tart clone "$source" "$image"
  refit_flag=--no-display-refit
  if [[ $refit == true ]]; then refit_flag=--display-refit; fi
  tart set "$image" --cpu "$cpu" --memory "$memory" --display "$display" "$refit_flag"
  record_spec
  echo "Configured image: $image"
fi
echo "Image specification recorded. Guest permission grants are managed separately."
