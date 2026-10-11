#!/usr/bin/env bash
command="${!#}"
case "$command" in
'sudo -n true') exit 0 ;;
'sudo -n /bin/bash '*)
  cat >"$PACKET"
  [[ ${FAIL_GUEST:-} != 1 ]] || exit 7
  echo ready
  ;;
'id -un')
  [[ " $* " == *' IdentitiesOnly=yes '* ]] || exit 7
  [[ ${FAIL_KEY:-} != 1 ]] || exit 7
  echo admin
  ;;
'uid='*) [[ ${FAIL_GUI:-} != 1 ]] || exit 7 ;;
'rm -f '*) exit 0 ;;
*)
  echo 'Unexpected remote operation' >&2
  exit 1
  ;;
esac
