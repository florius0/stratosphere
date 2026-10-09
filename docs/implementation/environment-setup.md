# Isolated environment preparation

The [testing approach](../testing-approach.md) is authoritative. This foundation supplies real fixture/display/AX probes and a disposable test VM wrapper. It does not yet qualify daemon/watchdog recovery or installed-product behavior.

Use **host**, **host user**, **test VM**, and **test VM user** as defined in [the testing terminology](../testing-approach.md#terminology). The host user builds/signs artifacts and coordinates the run; the test VM user runs the copied programs in the test VM's GUI session.

## Images and storage

Use `nix develop` for the pinned Tart executable. Set `TART_HOME` to a writable image location outside the Nix store; the wrapper defaults to `.local/tart`. Use an external APFS disk when local capacity cannot comfortably hold the stopped base image, clone changes, logs and free host headroom. Do not mount the host user's home, keychain, or working checkout into the test VM.

Prepare a macOS 26 Apple Silicon image using an official Tart image or Apple's installer. Record its immutable source identity, actual macOS/build, SIP state, preparation recipe and signing identity in a manifest beside the image. Keep it stopped before cloning. The wrapper accepts only a local prepared-image name, not a mutable registry tag.

```sh
export TART_HOME=/absolute/path/to/stratosphere-vms
tart list
tart run stratosphere-prepared
```

In the test VM, create a dedicated test VM user with automatic GUI login and enable SSH for that user. Install only the public half of a dedicated test VM SSH key; keep the private half with the host user on the host. Do not include CI registrations or integration-account credentials in reusable images. These preparation steps use System Settings and the test VM user's account configuration.

## Build identity and permissions

Choose a persistent development-only signing identity and stable test VM installation path. The build wrapper accepts `--sign-identity` or `STRATOSPHERE_SIGN_IDENTITY`; it never creates/imports a certificate or changes keychains implicitly. An ad-hoc signed or unsigned build is suitable for build inspection, but does not prove permission-grant survival.

```sh
python3 Tools/build.py build --configuration release \
  --sign-identity 'Your persistent development identity'
```

Grant Accessibility through System Settings to the process that actually performs AX work, using the installed probe from this signed build. Confirm the launched probe's capability rather than assuming Terminal/SSH grants apply. Preserve its signature during transfer. Keep a second clean image without product grants for future permission/onboarding scenarios.

The VM wrapper launches the probe through `launchctl bootstrap gui/<test-vm-user-uid>` only after verifying that GUI domain exists. SSH supplies transfer/orchestration, not evidence of desktop readiness. The probe checks the live session and permissions again. Its fixture stays in the probe's owned process tree. Missing GUI readiness, AX permission, SIP-enabled core, or private virtual-display capability fails setup.

## Run and evidence

```sh
nix run .#e2e-vm -- --image stratosphere-prepared \
  --artifacts .local/build \
  --tart-home /absolute/path/to/stratosphere-vms \
  --ssh-key /absolute/path/to/test-vm-key \
  --output .local/results/qualification
```

Each run creates a unique clone and unique test VM paths. The wrapper bounds clone/boot/SSH/probe/teardown, streams partial logs out, collects structured results, and stops/deletes only the owned clone. A keyboard interruption discards the run; rerun the whole probe in a fresh test VM. This is interactive local testing; the optional idle-time CI host controller is not implemented.

The explicit `--artifacts .local/build` selects the persistently signed artifacts from the preceding build step. Omitting it selects Nix's unsigned store artifacts; those require separate controlled-launch permission qualification and do not inherit the prepared development identity.

Choose a new `--output` directory on each invocation. Existing directories are refused. `run.json` describes the current orchestration outcome, and `qualification.json` is retained only as actual probe evidence; a successful probe followed by failed cleanup is still a failed run.

The hosted workflow uses its fresh GitHub runner directly, with an explicit hosted profile. It starts normally packaged processes under the controlled launch chain and verifies their own grants. It has no nested VM or permission bypass. Setup failures remain failed checks.

## Qualification still required

- Demonstrate the same probe on a fresh hosted runner and prepared SIP-enabled test VM; retain both result sets.
- Test development signing/grant survival across changed builds and image clones at stable installation paths. The current disposable-run paths alone do not establish that evidence.
- Add the real daemon, app AX-stall fixture, independent watchdog and baseline-recovery scenario.
- Add clean/prepared installed-product startup, permission revocation and signed update scenarios.
- Qualify unattended admission/activity detection, host-controller termination, and return-to-work interruption before optional host CI.
- Validate physical reconnect identity, gestures, appearance and app integrations on supported hardware. ChatGPT reliable conversation/draft/fresh-context restoration remains a release gate (FR-29).

See [the verification record](foundation-verification.md) for checks actually executed in this checkout.
