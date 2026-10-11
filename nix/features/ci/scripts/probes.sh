#!/usr/bin/env bash
if [[ ${GITHUB_ACTIONS:-} != true || ${RUNNER_OS:-} != macOS || ${RUNNER_ENVIRONMENT:-} != github-hosted ]]; then
  echo 'CI probes require a GitHub-hosted macOS runner' >&2
  exit 2
fi
"$STRATOSPHERE_CI_BUILD" --configuration release --sign-identity -
exec "$STRATOSPHERE_CI_PROBE" --profile hosted --output .local/ci/qualification
