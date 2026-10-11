#!/bin/sh
printf '%s\n' "$*" >>"$TART_COMMANDS"
case "$1" in
list) printf '[{"Source":"local","Name":"prepared-baseline","Running":false}]' ;;
ip) echo 192.0.2.10 ;;
run) sleep 60 ;;
delete) exit 9 ;;
esac
