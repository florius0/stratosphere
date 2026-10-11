#!/usr/bin/env bash
if [[ $* == 'list-keychains -d user' ]]; then
  printf '    "/original keychain"\n    "/second keychain"\n'
else
  printf '%s\n' "$*" >>"$SIGN_LOG"
fi
