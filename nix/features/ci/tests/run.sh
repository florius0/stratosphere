#!/usr/bin/env bash
export CI_EFFECT="$TMPDIR/effect"
unset GITHUB_ACTIONS RUNNER_OS RUNNER_ENVIRONMENT
if "$CI_PROBES" >result.log 2>&1; then
  echo 'Host accepted for CI probes' >&2
  exit 1
fi
grep -q 'GitHub-hosted macOS runner' result.log
test ! -e "$CI_EFFECT"
export GITHUB_ACTIONS=true RUNNER_OS=macOS RUNNER_ENVIRONMENT=self-hosted
if "$CI_PROBES" >result.log 2>&1; then
  echo 'Self-hosted runner accepted for CI probes' >&2
  exit 1
fi
test ! -e "$CI_EFFECT"
export RUNNER_ENVIRONMENT=github-hosted
"$CI_PROBES"
test -e "$CI_EFFECT"
rm "$CI_EFFECT"
status=0
"$FAILED_PROBES" || status=$?
test "$status" = 7
test ! -e "$CI_EFFECT"
touch "$out"
