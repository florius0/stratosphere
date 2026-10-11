#!/usr/bin/env bash
test -e "$GUEST_CHECKS"
mkdir -p workspace/.local/tart/stratosphere-provisioning
cd workspace
export TART_HOME="$PWD/.local/tart"
export VM_COMMANDS="$PWD/commands" VM_PID="$PWD/pid" PACKET="$PWD/packet"
vm-provisioning prepared >output.log 2>&1
jq -e '.status == "passed" and .permissions == "not-managed"' "$TART_HOME/stratosphere-provisioning/stratosphere-prepared-26-5.guest.json"
test -s .local/vm-provisioning/test-vm-key
test -s "$PACKET"
if grep -E '^clone |^delete ' "$VM_COMMANDS"; then
  echo 'Unexpected image clone/deletion'
  exit 1
fi
if kill -0 "$(cat "$VM_PID")" 2>/dev/null; then
  echo 'Owned boot leaked'
  exit 1
fi
before=$(sha256sum .local/vm-provisioning/test-vm-key)
vm-provisioning prepared >>output.log 2>&1
test "$before" = "$(sha256sum .local/vm-provisioning/test-vm-key)"
cp "$TART_HOME/stratosphere-provisioning/stratosphere-prepared-26-5.guest.json" previous.json
export FAIL_GUEST=1
if vm-provisioning prepared >>output.log 2>&1; then
  echo 'Guest failure accepted'
  exit 1
fi
cmp previous.json "$TART_HOME/stratosphere-provisioning/stratosphere-prepared-26-5.guest.json"
if kill -0 "$(cat "$VM_PID")" 2>/dev/null; then
  echo 'Failed provisioning boot leaked'
  exit 1
fi
unset FAIL_GUEST
export FAIL_GUI=1
if vm-provisioning prepared >>output.log 2>&1; then
  echo 'Missing GUI accepted'
  exit 1
fi
cmp previous.json "$TART_HOME/stratosphere-provisioning/stratosphere-prepared-26-5.guest.json"
unset FAIL_GUI
export FAIL_STOP=1
if vm-provisioning prepared >>output.log 2>&1; then
  echo 'Cleanup failure accepted'
  exit 1
fi
if kill -0 "$(cat "$VM_PID")" 2>/dev/null; then
  kill -TERM "$(cat "$VM_PID")" 2>/dev/null || true
  echo 'Cleanup failure leaked owned boot'
  exit 1
fi
cmp previous.json "$TART_HOME/stratosphere-provisioning/stratosphere-prepared-26-5.guest.json"
unset FAIL_STOP
stop_count=$(grep -c '^stop ' "$VM_COMMANDS")
export FAIL_START=1
if vm-provisioning prepared >>output.log 2>&1; then
  echo 'Failed launcher accepted'
  exit 1
fi
test "$stop_count" = "$(grep -c '^stop ' "$VM_COMMANDS")" || {
  echo 'Failed launcher stopped an unowned VM'
  exit 1
}
unset FAIL_START
touch checkpoint
sleep 0.1
chmod a-w "$TART_HOME/stratosphere-provisioning"
if vm-provisioning prepared >>output.log 2>&1; then
  echo 'Receipt publication failure accepted'
  exit 1
fi
chmod u+w "$TART_HOME/stratosphere-provisioning"
result=$(find .local/vm-provisioning/runs -name run.json -newer checkpoint)
jq -e '.status == "failed" and .exitCode != 0' "$result"
cmp previous.json "$TART_HOME/stratosphere-provisioning/stratosphere-prepared-26-5.guest.json"
touch "$out"
