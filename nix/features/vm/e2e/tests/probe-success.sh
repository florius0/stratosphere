#!/bin/sh
touch "$PROBE_MARKER"
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then output=$2; fi
  shift
done
printf '{"status":"passed"}' >"$output"
