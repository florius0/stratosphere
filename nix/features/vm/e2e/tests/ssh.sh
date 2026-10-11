#!/usr/bin/env bash
command="${@: -1}"
printf '%s\n' "$command" >>"$SSH_COMMANDS"
case "$command" in
'id -u '*) echo 501 ;;
*'launchctl print gui/501/dev.stratosphere.qualification.'*) echo 'last exit code = 0' ;;
*'/qualification.json '*) echo '{"status":"passed"}' ;;
esac
