#!/usr/bin/env bash
if [[ ${FAIL_MOVE:-} == 1 && $1 == */.artifacts-*/FixtureApp.app && $2 == */FixtureApp.app ]]; then exit 8; fi
exec "$REAL_MOVE" "$@"
