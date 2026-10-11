#!/usr/bin/env bash
# shellcheck source=common.sh
source "$STRATOSPHERE_DEVELOPMENT_COMMON"
prepare_swift test "$@"
"${command[@]}"
test -e "$STRATOSPHERE_TOOLING_CHECKS"
"$STRATOSPHERE_DOCS"
