#!/usr/bin/env bash
mkdir -p artifacts/FixtureApp.app
cp "$E2E_FIXTURES/probe-success.sh" artifacts/EnvironmentProbe
chmod u+w,+x artifacts/EnvironmentProbe
export PROBE_MARKER="$PWD/launched"
unset GITHUB_ACTIONS RUNNER_OS RUNNER_ENVIRONMENT
if "$NATIVE_RUNNER" --profile hosted --artifacts "$PWD/artifacts" --output "$PWD/refused"; then exit 1; fi
test ! -e "$PROBE_MARKER"
jq -e '.status == "setup-failed"' refused/run.json
test ! -e refused/qualification.json
export GITHUB_ACTIONS=true RUNNER_OS=macOS RUNNER_ENVIRONMENT=github-hosted
"$NATIVE_RUNNER" --profile hosted --artifacts "$PWD/artifacts" --output "$PWD/passed"
jq -e '.status == "passed" and .exitCode == 0' passed/run.json
if "$NATIVE_RUNNER" --profile hosted --artifacts "$PWD/artifacts" --output "$PWD/passed"; then exit 1; fi
jq -e '.status == "passed"' passed/run.json
cat >artifacts/toolchain.json <<'JSON'
{"compiler":"Swift","sourceRevision":"test-revision","secret":"must-not-leak"}
JSON
cp "$E2E_FIXTURES/probe-failure.sh" artifacts/EnvironmentProbe
if "$NATIVE_RUNNER" --profile hosted --artifacts "$PWD/artifacts" --output "$PWD/nonzero"; then exit 1; fi
jq -e '.status == "failed" and .probeExitCode == 7' nonzero/run.json
jq -e '.compiler == "Swift" and .sourceRevision == "test-revision" and (has("secret")|not)' "$PROBE_MARKER"
printf '[]' >artifacts/toolchain.json
if "$NATIVE_RUNNER" --profile hosted --artifacts "$PWD/artifacts" --output "$PWD/malformed"; then exit 1; fi
jq -e '. == {compiler:null}' "$PROBE_MARKER"
printf '{"compiler":"\377"}' >artifacts/toolchain.json
if "$NATIVE_RUNNER" --profile hosted --artifacts "$PWD/artifacts" --output "$PWD/invalid-utf8"; then exit 1; fi
jq -e '. == {compiler:null}' "$PROBE_MARKER"
jq -n '{compiler:("é" * 3000)}' >artifacts/toolchain.json
if "$NATIVE_RUNNER" --profile hosted --artifacts "$PWD/artifacts" --output "$PWD/oversized-field"; then exit 1; fi
jq -e '. == {compiler:null}' "$PROBE_MARKER"
cp "$E2E_FIXTURES/probe-stall.sh" artifacts/EnvironmentProbe
export STRATOSPHERE_PROBE_TIMEOUT=1
if "$NATIVE_RUNNER" --profile hosted --artifacts "$PWD/artifacts" --output "$PWD/timeout"; then exit 1; fi
jq -e '.timedOut and .exitCode != 0' timeout/run.json
if kill -0 "$(cat "$PROBE_MARKER")" 2>/dev/null; then
  echo 'Probe child leaked'
  exit 1
fi
export STRATOSPHERE_PROBE_TIMEOUT=60
"$NATIVE_RUNNER" --profile hosted --artifacts "$PWD/artifacts" --output "$PWD/interrupted" &
runner=$!
for i in $(seq 1 50); do
  test -f interrupted/probe.log && break
  sleep 0.1
done
sleep 0.2
kill -TERM "$runner"
wait "$runner" && exit 1
jq -e '.status == "interrupted" and .exitCode == 143' interrupted/run.json
if kill -0 "$(cat "$PROBE_MARKER")" 2>/dev/null; then
  echo 'Interrupted child leaked'
  exit 1
fi
mkdir fake-bin
cp "$E2E_FIXTURES/tart-clone-failure.sh" fake-bin/tart
chmod u+w,+x fake-bin/tart
export PATH="$PWD/fake-bin:$PATH" TART_COMMANDS="$PWD/tart-commands"
touch dedicated-key
if "$VM_RUNNER" --image prepared-baseline --ssh-key "$PWD/dedicated-key" --artifacts "$PWD/artifacts" --output "$PWD/clone-failed"; then exit 1; fi
jq -e '.status == "setup-failed" and .cleanupErrors == []' clone-failed/run.json
test "$(wc -l <"$TART_COMMANDS")" = 4
! grep -E '^delete prepared-baseline$|^set prepared-baseline' "$TART_COMMANDS"
grep -E '^delete stratosphere-test-' "$TART_COMMANDS"
cp "$E2E_FIXTURES/tart-cleanup-failure.sh" fake-bin/tart
export SSH_COMMANDS="$PWD/ssh-commands"
if "$FAKE_VM_RUNNER" --image prepared-baseline --ssh-key "$PWD/dedicated-key" --artifacts "$PWD/artifacts" --output "$PWD/cleanup-failed"; then exit 1; fi
jq -e '.status == "failed" and .exitCode != 0 and .probeStatus == "passed" and (.cleanupErrors|length) > 0' cleanup-failed/run.json
jq -e '.status == "passed"' cleanup-failed/qualification.json
grep 'launchctl bootstrap gui/501 ' "$SSH_COMMANDS"
grep '/.local/stratosphere-test-tools/FixtureApp.app' "$SSH_COMMANDS"
! grep -E '^delete prepared-baseline$|^set prepared-baseline' "$TART_COMMANDS"
cp "$E2E_FIXTURES/tart-stall.sh" fake-bin/tart
"$VM_RUNNER" --image prepared-baseline --ssh-key "$PWD/dedicated-key" --artifacts "$PWD/artifacts" --output "$PWD/vm-interrupted" &
runner=$!
for i in $(seq 1 50); do
  test -f vm-interrupted/tart.log && break
  sleep 0.1
done
sleep 0.2
kill -TERM "$runner"
wait "$runner" && exit 1
jq -e '.status == "interrupted" and .cleanupErrors == []' vm-interrupted/run.json
! grep -E '^delete prepared-baseline$|^set prepared-baseline' "$TART_COMMANDS"
touch "$out"
