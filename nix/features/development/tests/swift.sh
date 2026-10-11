#!/usr/bin/env bash
if [[ " $* " == *' --show-bin-path '* ]]; then printf '%s\n' "$FAKE_BINARIES"; fi
