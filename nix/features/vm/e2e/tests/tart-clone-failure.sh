#!/bin/sh
printf '%s\n' "$*" >>"$TART_COMMANDS"
case "$1" in list) printf '[{"Source":"local","Name":"prepared-baseline","Running":false}]' ;; clone) exit 4 ;; delete) test "$2" != prepared-baseline || exit 99 ;; esac
