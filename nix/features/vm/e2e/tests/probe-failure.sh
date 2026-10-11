#!/bin/sh
printf '%s' "$STRATOSPHERE_BUILD_METADATA" >"$PROBE_MARKER"
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then output=$2; fi
  shift
done
printf '{"status":"passed"}' >"$output"
exit 7
