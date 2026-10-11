#!/bin/sh
sleep 60 &
printf '%s' "$!" >"$PROBE_MARKER"
wait
