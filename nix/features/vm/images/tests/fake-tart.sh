#!/usr/bin/env bash
mkdir -p "$TART_HOME/vms"
case "$1" in
list)
  if [[ -e "$TART_HOME/bad-list" ]]; then
    echo '{}'
    exit 0
  fi
  [[ ! -e "$TART_HOME/fail-list" ]] || exit 9
  for path in "$TART_HOME"/vms/*; do
    [[ -d $path ]] || continue
    jq -n --arg name "$(basename "$path")" '{Source:"local",Name:$name}'
  done | jq -s .
  ;;
clone)
  mkdir "$TART_HOME/vms/$3"
  [[ ! -e "$TART_HOME/fail-clone" ]] || exit 9
  printf '%s\n' "$2" >"$TART_HOME/vms/$3/source"
  ;;
set)
  [[ -d "$TART_HOME/vms/$2" ]]
  [[ ! -e "$TART_HOME/fail-set" ]] || exit 9
  if [[ -e "$TART_HOME/interrupt-set" ]]; then
    kill -TERM "$PPID"
    exit 143
  fi
  image="$2"
  shift 2
  printf '%s\n' "$@" >"$TART_HOME/vms/$image/settings"
  ;;
*) exit 8 ;;
esac
