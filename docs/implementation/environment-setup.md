# Isolated environment provisioning

The [testing approach](../testing-approach.md) is authoritative. The current implementation supplies real fixture/display/AX probes and a disposable test VM wrapper. It does not yet qualify daemon/watchdog recovery or installed-product behavior.

Use **host**, **host user**, **test VM**, and **test VM user** as defined in [the testing terminology](../testing-approach.md#terminology). The host user builds/signs artifacts and coordinates the run; the test VM user runs the copied programs in the test VM's GUI session.

## Images and storage

Use `nix develop` for the pinned Tart executable. Set `TART_HOME` to a writable image location outside the Nix store; the development shell, provisioning command and E2E wrapper default to `.local/tart`. Use an external APFS disk when local capacity cannot comfortably hold the stopped base image, clone changes, logs and free host headroom. Do not mount the host user's home, keychain, or working checkout into the test VM.

The [image specification](../../nix/features/vm/images/package.nix) pins the OCI source by digest and declares image names, CPU, memory, display settings and guest user. [Guest configuration](../../nix/features/vm/guest/package.nix) declares the existing account, shell, SSH access, automatic login and idle settings. Run `nix run .#vm-provisioning -- prepared` explicitly to configure the image and its guest. Missing images are downloaded only through this explicit command. Image receipts live under `$TART_HOME/stratosphere-provisioning/`; matching images are reused, while conflicting, unmanaged, interrupted or orphaned state requires explicit resolution. The `.stratosphere-provisioning-lock` serializes provisioning operations.

Adopt an existing image with `nix run .#vm-provisioning -- --adopt prepared .local/vm-provisioning/provisioning.json`. Adoption verifies the source/storage record, CPU/RAM and display settings, then records the image receipt without downloading, cloning, changing settings or provisioning the guest. Run the prepared command afterward for guest configuration. The retained prepared image has passed guest provisioning. The local clean image was deleted; recreate it on demand with `nix run .#vm-provisioning -- clean` for future onboarding scenarios. Clean provisioning configures only the image and never runs automatically.

Prepared guest provisioning boots the stopped managed template in place and checks the pinned vanilla image's existing `admin` account and passwordless sudo. It configures the declared shell, preserves existing authorized keys while adding the dedicated public key, verifies SSH service and automatic login, and sets screensaver idle time, sleep and display sleep to zero. It does not reset the password or create another user. The controller verifies key-based SSH and the active console user's GUI domain, then shuts down only the boot it started. Per-run logs and results live under `.local/vm-provisioning/runs/`; success writes `<image>.guest.json` beside the image receipt.

The SSH private key defaults to `.local/vm-provisioning/test-vm-key` and is generated only if missing; the retained key is preserved. Select another key with `STRATOSPHERE_SSH_KEY`. The password file defaults to `.local/vm-provisioning/guest-password`, initially containing the vendor's public `admin` bootstrap password; `STRATOSPHERE_VM_PASSWORD_FILE` selects a runtime file for an existing different password. Private credentials stay outside the Nix store. Only the public key is installed in the guest. Do not include CI registrations or integration-account credentials in reusable images.

Provisioning does not change Gatekeeper, SIP, TCC or MDM settings and installs no Nix, Xcode, SDK or guest agent. The upstream vanilla image already includes its own security/settings choices; recording provisioning success is not new Accessibility or product-permission qualification. Keep signing identities and required System Settings grants separate, and record actual OS/build, SIP state and observed permissions. Stop the image before cloning; E2E accepts a local image name rather than a mutable registry tag.

```sh
export TART_HOME=/absolute/path/to/stratosphere-vms
tart list
tart run stratosphere-prepared-26-5
```

Use the existing provisioned test VM account for interactive inspection. Guest provisioning, image downloads and account changes never run implicitly through direnv, tests or E2E.

## Display scaling for interactive use

For a sharp, readable test VM window, use point-based sizing and enable automatic display fitting on the stopped prepared image:

```sh
tart set stratosphere-prepared-26-5 --display 1280x800pt --display-refit
tart run stratosphere-prepared-26-5
```

[Tart's display fitting](https://raw.githubusercontent.com/openai/tart/2.37.0/Sources/tart/Commands/Run.swift) lets the test VM follow the window size and the host display's Retina density. The local preparation was checked at a 2× backing scale and visually confirmed by the host user. Selecting a larger 1× resolution alone can make controls smaller; enlarging a fixed low-resolution desktop can make it blurry.

Desktop qualification must disable display refitting in its disposable test VM so resizing a host window cannot change the asserted topology. Keep the interactive setting on the prepared image separate from the run's fixed display configuration.

## Build identity and permissions

Choose a persistent development-only signing identity and stable test VM installation path. The build wrapper accepts `--sign-identity` or `STRATOSPHERE_SIGN_IDENTITY`; it never creates/imports a certificate or changes keychains implicitly. An ad-hoc signed or unsigned build is suitable for build inspection, but does not prove permission-grant survival.

When an existing test identity is in a separate keychain, select it with `--sign-keychain` or `STRATOSPHERE_SIGN_KEYCHAIN`. The wrapper temporarily includes that keychain in the host user's search list only during signing, and restores the original list afterward, including on failure. It does not unlock keychains or create trust settings. Test signing keys stay on the host and are not copied into the test VM.

```sh
nix run .#build -- --configuration release \
  --sign-identity 'Your persistent development identity'
```

Grant Accessibility through System Settings to the process that actually performs AX work, using the installed probe from this signed build. Confirm the launched probe's capability rather than assuming Terminal/SSH grants apply. Preserve its signature during transfer. Recreate the optional clean image without product grants when future permission/onboarding scenarios require it.

The VM wrapper launches the probe through `launchctl bootstrap gui/<test-vm-user-uid>` only after verifying that GUI domain exists. SSH supplies transfer/orchestration, not evidence of desktop readiness. The probe checks the live session and permissions again. Its fixture stays in the probe's owned process tree. Missing GUI readiness, AX permission, SIP-enabled core, or private virtual-display capability fails setup.

Install and grant access at the stable paths used by the wrapper:

- `/Users/<test VM user>/.local/stratosphere-test-tools/EnvironmentProbe`
- `/Users/<test VM user>/.local/stratosphere-test-tools/FixtureApp.app`

Each disposable clone uses those same tool paths. Results, logs and the GUI launch job remain in separate per-run directories. The wrapper replaces only its own fixture bundle inside the clone before copying a changed build, preserving the signed host source and avoiding stale bundle resources.

The initial test VM needs no Xcode, SDK or Nix installation when running these self-contained artifacts. The wrappers forward bounded build metadata from the host's `toolchain.json`; the probe records it separately from the test VM's observed OS/build and never invokes developer tools there. Missing or malformed build metadata is marked unavailable or invalid, rather than pretending the test VM has the host's toolchain. Later Xcode-managed UI tests may use a separate image profile.

## Run and evidence

```sh
nix run .#e2e-vm -- --profile prepared \
  --artifacts .local/build \
  --ssh-key /absolute/path/to/test-vm-key \
  --output .local/results/qualification
```

Each run creates a unique clone and unique test VM paths. The wrapper bounds clone/boot/SSH/probe/teardown, streams partial logs out, collects structured results, and stops/deletes only the owned clone. A keyboard interruption discards the run; rerun the whole probe in a fresh test VM. This is interactive local testing; the optional idle-time CI host controller is not implemented.

The explicit `--artifacts .local/build` selects the persistently signed artifacts from the preceding build step. The wrapper also defaults to `.local/build`. Selecting packaged unsigned artifacts requires separate controlled-launch permission qualification and does not inherit the prepared development identity.

Choose a new `--output` directory on each invocation. Existing directories are refused. `run.json` describes the current orchestration outcome, and `qualification.json` is retained only as actual probe evidence; a successful probe followed by failed cleanup is still a failed run.

The hosted workflow uses its fresh GitHub runner directly, with an explicit hosted profile. It starts normally packaged processes under the controlled launch chain and verifies their own grants. It has no nested VM or permission bypass. Setup failures remain failed checks.

## Qualification still required

- Demonstrate the same probe on a fresh hosted runner. The local SIP-enabled test VM probe passed on 2026-10-10; retain both environment result sets when hosted evidence is available.
- Test development signing/grant survival across changed builds and image clones at stable installation paths. The local development probe has retained its grant across the tested rebuilt artifacts and clones at these paths; this does not qualify installed-product onboarding or release updates.
- Add the real daemon, app AX-stall fixture, independent watchdog and baseline-recovery scenario.
- Add clean/prepared installed-product startup, permission revocation and signed update scenarios.
- Qualify unattended admission/activity detection, host-controller termination, and return-to-work interruption before optional host CI.
- Validate physical reconnect identity, gestures, appearance and app integrations on supported hardware. ChatGPT reliable conversation/draft/fresh-context restoration remains a release gate (FR-29).

See [the verification record](development-verification.md) for checks actually executed in this checkout.
