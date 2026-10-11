# Hosted probe evidence policy

Approved on 2026-10-12 after run 38162207293 reported SIP disabled on the GitHub-hosted macOS 26 ARM64 runner. Build/signing succeeded; the prior SIP gate stopped the probe before AX/display work.

## Design and implementation plan

Preserve NFR-01 and D-23: core compatibility requires SIP-enabled evidence. Hosted probes may exercise the same AX/display scenarios with explicitly observed disabled SIP, producing supplemental regression evidence. Guest probes still require enabled SIP. Unknown/custom SIP state or a failed observation remains a setup failure in either profile. Never change SIP in a test wrapper.

1. Add deterministic policy tests for enabled/disabled/unknown/custom states and failed observations.
2. Apply the policy before GUI/AX/display work and publish `sip_enabled_core_evidence` in the report. A false value means a passing probe does not establish SIP-enabled compatibility.
3. Print the probe log and SIP evidence classification in the native wrapper, retaining failure exit codes and uploaded evidence.
4. Revise the testing approach and decision evidence explicitly. The same desktop scenarios run in a SIP-enabled local VM; additional hosted-unavailable cases remain VM obligations. Missing permissions/capabilities and assertion failures continue to fail hosted setup/tests; no blanket skips or automatic green fallback.
5. Run pinned deterministic tests, documentation/DOT validation, formatting and flake checks. A new hosted run must establish actual AX/display availability; deterministic tests cannot establish it. No daemon E2E, runner controller or new permission provisioning is introduced.

The hosted job remains required for its declared coverage. Local VM availability does not block ordinary PR checks, but absence of required SIP-enabled/release evidence blocks a compatibility claim or release. Record exact environment versions separately.
