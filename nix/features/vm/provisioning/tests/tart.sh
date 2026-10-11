#!/usr/bin/env bash
printf '%s\n' "$*" >>"$VM_COMMANDS"
case "$1" in
list) printf '[{"Name":"stratosphere-prepared-26-5","Running":false,"Source":"local"}]' ;;
run)
  echo "$$" >"$VM_PID"
  [[ ${FAIL_START:-} != 1 ]] || exit 9
  sleep 60 &
  wait
  ;;
ip) echo 192.0.2.4 ;;
stop)
  if [[ ${FAIL_STOP:-} == 1 ]]; then exit 8; fi
  if [[ -f $VM_PID ]]; then kill -TERM "$(cat "$VM_PID")" 2>/dev/null || true; fi
  ;;
*)
  echo 'Unexpected image mutation' >&2
  exit 1
  ;;
esac
