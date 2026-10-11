#!/bin/sh
printf '%s\n' "$*" >>"$TART_COMMANDS"
case "$1" in
list) printf '[{"Source":"local","Name":"prepared-baseline","Running":false}]' ;;
ip) exit 1 ;;
run) sleep 60 ;;
esac
