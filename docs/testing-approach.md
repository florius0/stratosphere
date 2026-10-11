# Testing approach

Agreed on 2026-10-09: use one native E2E suite directly on GitHub-hosted macOS runners and inside disposable Tart VMs for local development and optional CI on the host. Nix manages the tool environment and execution wrappers; prepared macOS images supply the isolated desktop and its system state.

This document governs the testing workflow. [Product requirements](functional-requirements.md), [non-functional requirements](non-functional-requirements.md), and [decisions](decision-map.md) remain authoritative for product behavior. The current implementation provides build targets, deterministic tests, native UI stories, and isolated native/VM probe entrypoints. A signed local probe passed in a disposable SIP-enabled macOS 26.5 Apple Silicon VM on 2026-10-10; hosted qualification has not run. The daemon, integrations, persistence engine, recovery watchdogs, and optional idle-time CI controller remain unimplemented. See the [development verification record](implementation/development-verification.md) for executed checks and qualification limits, and the [environment investigation](research/e2e-environment.md) for supporting research.

## Terminology

Use these terms throughout the testing workflow:

| Term         | Meaning                                                                                                             |
| ------------ | ------------------------------------------------------------------------------------------------------------------- |
| Host         | The physical Mac running Tart and the local development tools.                                                      |
| Host user    | The macOS account on the host that runs those tools; its desktop, home and keychain stay outside test VM execution. |
| Test VM      | The isolated macOS virtual machine used for desktop-mutating tests.                                                 |
| Test VM user | The dedicated macOS account inside the test VM, with its own GUI login, files and permission grants.                |

The host user builds and signs artifacts on the host. Tests run as the test VM user inside a disposable test VM.

## Execution environments

| Environment       | Execution                                                                       | Reset and purpose                                                                                                                     |
| ----------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| GitHub-hosted CI  | Native suite in an Apple Silicon `macos-26` runner's GUI session; no nested VM. | Fresh runner per job; required PR checks after qualification.                                                                         |
| Local development | Build on the host; run inside a disposable Tart test VM.                        | Clone a stopped prepared image, transfer artifacts, collect results, then discard. Support focused reruns and interactive inspection. |
| Host as a runner  | One-job GitHub self-hosted runner inside a disposable Tart test VM.             | Optional extended tests admitted during idle time; the host user's desktop stays outside the execution boundary.                      |

Scenario logic, fixtures, assertions, and result format are common to all three. Launch, permission preparation, and reset differ explicitly. GitHub remains the required CI provider; the host's availability does not block ordinary PR checks.

Desktop-mutating tests run only in the hosted runner or test VM. Deterministic tests and the [native story catalog](design-process.md) may run on the host without starting the manager against the host user's desktop.

Use macOS 26+ on Apple Silicon. Record actual macOS/build, architecture, runner or test VM image identity, Xcode/SDK, signing identity, integration versions, and source revision. A major-version runner label is not an exact OS-version pin. Establish SIP-enabled core behavior explicitly; success on a differently configured runner is not that evidence.

## Test layers and observability

| Layer                             | What it proves                                                                                                                                 |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Deterministic tests               | Tree/binding invariants, layouts, protocol, persistence, reconciliation, preflight, partial operations, history, and Undo with synthetic data. |
| Native E2E                        | Actual daemon, rail, watchdogs, backend adapters, persistence, and integrations interacting with real macOS windows.                           |
| UI stories and interaction checks | Component presentation, requested actions, focus/dismissal behavior, and replayable interrupted motion.                                        |
| Real-app and release validation   | Declared restoration fidelity, installed-product behavior, signing/permissions, and exact compatibility evidence.                              |
| Hardware validation               | Physical display connections, gestures, sleep/wake, refresh rates, and appearance under supported desktop conditions.                          |

Fixture applications create predictable real AppKit windows, native tabs/full-screen cases, and deliberate failure conditions. They may expose a fixture control channel; they do not replace AX or CoreGraphics with fakes. Keep production components and normal permission/preflight behavior in the E2E path.

Drive management scenarios through the public daemon API/CLI. Check independent observations of geometry, focus, display membership, visibility, and durable state rather than only successful API responses. Exercise rail, hotkey, and mouse actions through actual interaction. Catalog stories with simulated daemon responses remain UI tests, not daemon E2E.

## Launch profiles and permissions

**Controlled launch** starts real packaged daemon, rail, and watchdog executables through a qualified test launch chain. This is the initial hosted-CI profile. Verify required capabilities in every process that performs the work. Observe permission inheritance; avoid detaching into an unqualified context. This profile proves management/recovery behavior, not normal login registration or onboarding.

**Installed product** uses normal app startup, login registration, permissions, signing, and update/recovery behavior. Run it in prepared or clean test VMs, and on hosted CI only after qualifying that exact path. Controlled-launch results cannot replace installed-product release evidence.

Provision a test VM with active automatic GUI login, a stable development-only signing identity, stable bundle IDs/installation paths, and required grants made through System Settings. Verify grants survive changed builds and cloning. Recreate an optional separate clean test VM without product grants when onboarding/permission scenarios require it; ordinary development does not retain that extra disk. Distributed Developer ID builds retain their original signatures.

SSH transfers and orchestration are allowed, but GUI work executes in the test VM's active login session. Changing Unix user or starting a system service is insufficient. If the host user's keychain or the test VM user's GUI session is unavailable, capacity stays unavailable; do not weaken the host's lock policy for CI.

## Multiple displays

Create additional monitors inside the test macOS using a private `CGVirtualDisplay` helper. The current implementation provides this common mechanism for hosted and test VM environments. Apple's VM graphics configuration exposes one display; do not assume additional VM attachments. The signed local probe verified extended virtual displays, differing densities, main-display changes, removal/reconnect, and baseline restoration on macOS 26.5 Apple Silicon with SIP enabled. Hosted support and other supported configurations remain qualification gates; see the [verification record](implementation/development-verification.md#qualified-local-probe-on-2026-10-10).

Cover single-display and two-display extended desktops in the core suite, with three-display cases in extended runs. Include different dimensions/densities, monitors above/left of main, main-display changes, removal, and reconnect. Verify observed topology before assertions and disable automatic VM display refitting. Include the original runner/VM display in the topology; keep test monitors extended rather than mirrored.

Exercise ancestor binding precedence, selected leaves, blanking unoccupied monitors, window transfer, fallback, and one shared rail configuration. Check actual durable monitor identity on reconnect; numeric live handles are not persistent identity. If virtual monitors cannot reproduce stable reconnect identity, retain real-hardware validation and report the virtual case as unqualified.

Assertions run inside the test OS; a separate host window for every display is optional. Captures or test VM screen sharing support inspection. Virtual monitors do not prove cable/EDID, physical gesture, or hardware timing behavior.

## Nix and image management

Pin the Nix environment and prepared macOS image separately. Nix declares digest-pinned sources, CPU/RAM/display settings, guest configuration and provisioning receipts alongside tools, build outputs and execution wrappers. Explicit `vm-provisioning` configures missing images and the prepared image's existing account, SSH public key, automatic login and idle settings. Runtime credential files remain outside the store. Key-based SSH and the active console user's GUI domain are verified before a successful guest receipt is recorded. Signing and permission grants remain separate; provisioning does not change Gatekeeper, SIP, TCC or MDM. Tart manages mutable disks, boot and disposable clones. Store working disks and results outside the immutable Nix store.

Nixpkgs packages Tart while preserving its app bundle/provisioning profile. It also packages Apple SDKs, including SDK 26; compiler/SDK selection belongs in implementation planning. Full Xcode/UI-testing tools are separately provisioned and recorded. The Nix lockfile does not pin macOS, GUI login, permissions, signing keychains, or external Xcode. [Tart package](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ta/tart/package.nix), [Darwin tooling](https://nixos.org/manual/nixpkgs/unstable/#sec-darwin)

Prefer a small runtime test VM receiving self-contained app, harness, and fixture bundles built on the host. Installing Nix in the test VM is optional. If artifacts reference store dependencies, install Nix once in the prepared test VM and transfer complete closures with `nix copy`; an executable alone is insufficient. An Xcode-equipped profile serves suites needing development/UI-testing tools in the test VM. [Closure transfer](https://nix.dev/manual/nix/2.32/command-ref/new-cli/nix3-copy)

| Implemented entrypoint                                          | Responsibility                                                                                                                                 |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `nix develop`                                                   | Provide pinned development tools and the selected writable Tart home.                                                                          |
| `nix run .#vm-provisioning -- prepared`                         | Explicitly configure the declared image and guest; verify dedicated SSH and active GUI login, retain per-run evidence and stop the owned boot. |
| `nix run .#vm-provisioning -- clean`                            | Recreate the optional image on demand for onboarding; configure image settings only.                                                           |
| `nix run .#vm-provisioning -- --adopt prepared PROVENANCE.json` | Verify existing image provenance/settings and record its image receipt without guest changes.                                                  |
| `nix flake check`                                               | Evaluate/build deterministic, cacheable checks.                                                                                                |
| `nix run .#e2e-vm`                                              | Clone an explicitly prepared, stopped local Tart image, run the native qualification probe, collect results, and discard the owned clone.      |
| `nix run .#e2e-native`                                          | Run the native qualification probe in an explicitly isolated hosted or test VM environment.                                                    |

These entrypoints are provided by the project flake. See [development commands](../README.md#development) and [environment provisioning](implementation/environment-setup.md) for usage and prerequisites. The native and VM entrypoints currently run infrastructure probes, not daemon E2E; product scenarios will follow their implementations. Live GUI tests execute at runtime outside the Nix build sandbox, with fresh qualification, rather than treating a cached derivation as current desktop evidence.

Version images by macOS/build, immutable image identity, provisioning recipe, signing identity, and fixture/app versions. Cache a stopped prepared image for copy-on-write clones. Provisioning uses `.local/vm-provisioning` for credentials and evidence and `$TART_HOME/stratosphere-provisioning` for image/guest receipts. It never runs automatically through direnv, tests or E2E. Keep runner registrations and integration credentials out of reusable/shared images; use dedicated app test accounts and explicit integration profiles. Measure suite resource use before increasing test VM CPU/RAM or admitting capacity.

## Isolation, cleanup, and results

Run one desktop-mutating scenario at a time per GUI session. Parallelism requires independent jobs or test VMs. Give scenarios separate config, state/history, socket, recovery, screenshots, and notification-output paths through supported configuration; changing `HOME` is not user isolation.

Record baseline Dock/geometry and fixture/display state before management. Cleanup uses explicit Stratosphere shutdown followed by scenario-owned process/window cleanup. Track identities; avoid broad app-name termination. Failure to restore baseline prevents desktop reuse. Independent host orchestration bounds teardown and discards stuck test VMs. Enable login startup only for relevant scenarios.

Missing GUI session, denied required AX access, wrong topology, or unavailable display capability fails setup visibly. Required checks cannot silently skip scenarios, substitute fakes, or pass with no windows. Deliberate permission-loss scenarios assert diagnostics/degradation separately.

Preserve environment metadata, scenario/commit identity, process/watchdog logs, operation results, sanitized state/recovery records, and topology. Capture visual evidence when available without requiring it for textual diagnostics. Separate product failures, setup failures, and user interruptions. Setup may receive one fresh-environment retry with both results retained; do not retry assertion failures into a green result.

## Idle-time CI on the host

A trusted host controller admits work; workflow code and the ephemeral runner execute only in the test VM. Select an approved commit that passed hosted checks, prepare the test VM, register a one-job runner with a unique label, and dispatch its optional workflow. Keep runner-administration credentials on the host. Do not expose the host user's home, keychain, or checkout to the CI test VM.

Configurable initial policy: 15 minutes without physical user input, external power, resource headroom, no local interactive test run, and at most one test VM. Observe host activity independently of input generated inside the test VM. Do not wake the Mac or unlock its desktop for CI.

When the host user returns, stop admission and cancel the optional job. Allow up to 30 seconds for collection/cleanup, then stop/discard the test VM. Report interruption and retry the whole scenario in a fresh test VM later. Do not transparently pause AX calls, watchdog deadlines, or destructive product operations. These are infrastructure defaults, not product latency requirements.

Dispatch when ready, bound runner/dispatch races, and cancel unmatched runs rather than leave an indefinite queue. Preserve runner logs and partial results outside the test VM during execution. Restrict jobs on the host to approved branches/workflows; ordinary fork PRs use hosted runners. Local interactive execution takes priority. [GitHub ephemeral runner lifecycle](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)

## Qualification and release gates

Before treating the workflow as working infrastructure, demonstrate on a fresh hosted runner and a SIP-enabled macOS 26 Apple Silicon test VM:

1. Two extended virtual monitors with verified arrangement, density/modes, main-display changes, removal/reconnect, and real fixture windows occupying both.
2. Actual cross-process AX discovery, focus, move/resize, and observation from the process doing the work; qualify input/capture and helper launch paths too.
3. A minimal real daemon scenario through the same native entrypoint, including daemon failure, an app AX stall, independent recovery, and baseline restoration.
4. Signing/grant survival across changed builds and clones, plus clean/prepared installed-product startup and permission-loss cases.
5. Unattended GUI readiness, activity detection unaffected by test VM input, return-to-work cancellation, and recovery/diagnostics after controller termination.

If hosted qualification fails, required CI reports it. Correct or explicitly revise the environment approach; do not quietly move required PR checks to the host or disable SIP to claim core compatibility.

Release evidence is broader than PR checks: exact supported macOS/integration versions, signed installed-product behavior, physical desktop conditions, and account-dependent restoration. Reliable ChatGPT conversation/draft/fresh-context restoration remains a release gate. Optional runner availability does not waive required evidence.

## Product trace

| Authority                                 | Testing obligation                                                                       |
| ----------------------------------------- | ---------------------------------------------------------------------------------------- |
| C-02/C-03; FR-03/FR-06/FR-13; FR-41/FR-45 | Real bindings, scope, fallback/reconnect, and shared rails.                              |
| FR-22–FR-29; Q-02                         | Actual integration fidelity and reliable ChatGPT contexts.                               |
| FR-52–FR-57; NFR-02                       | Public actions, preflight, ordering, partial operations, and explicit resume.            |
| FR-64–FR-68; NFR-03/NFR-04; Q-04          | Actual AX stalls, independent watchdogs, and desktop/Dock recovery.                      |
| FR-69–FR-71; NFR-08                       | Installed startup, stable identity, signed distribution, and updates.                    |
| NFR-01/NFR-09/NFR-10; D-02/D-25           | Supported-platform/SIP evidence; real private-API validation; separate backend decision. |

No product requirements or product DOT summaries change by adopting this workflow.
