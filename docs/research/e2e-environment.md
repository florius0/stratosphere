# E2E execution environment investigation

Researched on 2026-10-08. The execution approach was adopted on 2026-10-09 and refined with Nix in the [testing approach](../testing-approach.md), which governs the workflow. This investigation preserves supporting evidence and its limits. Adoption does not mean an implemented test system or passed platform acceptance checks.

## Recommended approach

Use one native Swift test harness against real Stratosphere processes and real macOS windows. Run it directly in GitHub's disposable `macos-26` Apple Silicon runner. Run the same harness inside a disposable Tart macOS VM for local development and optional CI on the host. Create additional monitors inside the test operating system with a small `CGVirtualDisplay` helper, independent of the VM launcher.

GitHub remains the required CI provider. The host supplies optional extended runs; its availability never blocks ordinary pull-request checks. Desktop-mutating tests never run in the host user's login session. Ordinary deterministic tests and the native UI story catalog can run on the host without starting the manager against the host desktop.

| Environment         | Execution boundary                                           | Reset                                                      | Intended work                                                                    |
| ------------------- | ------------------------------------------------------------ | ---------------------------------------------------------- | -------------------------------------------------------------------------------- |
| GitHub-hosted CI    | Existing runner OS and GUI session; no nested VM             | Fresh runner for each job; scenario cleanup within the job | Required deterministic tests and core native E2E after environment qualification |
| Local development   | Disposable Tart test VM with an active GUI login             | Clone a stopped prepared image; discard after the run      | The same E2E suite, focused reruns, debugging, and interactive inspection        |
| Host as CI capacity | One ephemeral GitHub runner inside a disposable Tart test VM | One job per runner/test VM, then discard                   | Optional stress, integration, compatibility, and release-environment checks      |

This is test infrastructure. It does not select Stratosphere's native/virtual workspace backend, change application lifecycle rules, or introduce a runtime product compatibility policy.

## Evidence and its limits

### GitHub provides a suitable starting environment

GitHub documents `macos-26` as Apple Silicon and does not support nested virtualization on its ARM64 macOS runners. Its current standard runner specification is three CPUs, 7 GB RAM, and 14 GB available SSD storage. Keep tests small and execute desktop scenarios serially within each job. Record actual OS/build, architecture, image version, Xcode, and app versions; the major-version label does not pin an exact patch release. [Runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

The macOS 26 ARM64 image recipe invokes automatic GUI-login and TCC provisioning scripts. The login script establishes an unlocked graphical login. The TCC script seeds Accessibility and screen-capture grants for the hosted runner agent, shell, and other tools. These are stronger evidence than assuming all hosted Macs are unusably headless. They are image preparation details, not a guarantee for every separately launched app or helper. [Image recipe](https://github.com/actions/runner-images/blob/main/images/macos/templates/macOS-26.arm64.anka.pkr.hcl), [GUI login preparation](https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-autologin.sh), [Permission preparation](https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-tccdb-macos.sh)

GitHub also enables developer mode and Xcode automation mode. Xcode automation permission alone does not prove that Stratosphere's daemon can manipulate another application's windows. [Machine preparation](https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-machine.sh)

### Multiple monitors belong inside macOS

Apple's installed Xcode 26.6 SDK states that `VZMacGraphicsDeviceConfiguration.displays` supports a maximum of one display. Do not plan multiple VM display attachments from that array's plural name. Tart's configuration similarly has a single display entry. [Apple API](https://developer.apple.com/documentation/virtualization/vzmacgraphicsdeviceconfiguration/displays), [Tart configuration source](https://github.com/cirruslabs/tart/blob/main/Sources/tart/VMConfig.swift)

Use private CoreGraphics virtual-display objects inside the test VM or hosted runner instead. Chromium's macOS test helper creates multiple virtual displays, controls resolution/density, and observes addition/removal. It documents distinct serial-number requirements and removal workarounds. Its current availability check excludes headless environments, so that helper is evidence of a mechanism, not a drop-in guarantee for hosted CI. [Chromium helper](https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm)

A Chromium change records successful virtual-display testing in a macOS 14 Intel VM; that does not validate macOS 26 Apple Silicon. Another application's CI helper targets headless virtual displays, while its compatibility workflow disables that step on its macOS 26 leg. That is mixed evidence, and makes live qualification mandatory. [Historical VM result](https://chromium.googlesource.com/chromium/src/+/3ff212147268d3723faf8678b946c4d7d483c9aa), [cmux display helper](https://github.com/manaflow-ai/cmux/blob/main/scripts/create-virtual-display.m), [cmux compatibility workflow](https://github.com/manaflow-ai/cmux/blob/main/.github/workflows/ci-macos-compat.yml)

### VM reset is practical

Tart provides Apple Silicon macOS test VMs, configurable CPU/RAM/display dimensions, and read-only directory sharing. Its prepared-image workflow supports automatic test VM GUI login. Local APFS clones use copy-on-write; test VM memory and boot costs remain. Use a cached stopped image, not a new macOS installation for each run. [Tart setup](https://tart.run/quick-start/), [Clone implementation explanation](https://github.com/cirruslabs/tart/discussions/292)

Tart reports a host user's login-keychain requirement on recent macOS. The idle controller must handle a locked/unavailable keychain as unavailable capacity rather than prompting during normal work. Do not change the host user's login or screen-lock policy to make CI work. [Tart FAQ](https://tart.run/faq/)

### Permissions depend on identity and launch path

Apple documents stable signing identity, responsible-code attribution, and how daemonization can break that relationship. It recommends VM reset for reliable TCC testing. Those observations justify separate controlled-launch and installed-product profiles, but do not themselves prove Accessibility inheritance on the hosted runner. [Apple permission guidance](https://developer.apple.com/forums/thread/678819)

Use persistent development-only signing identity and stable bundle IDs/installation paths for the prepared local test VM. Grant required permissions once through System Settings while preparing the test VM, then clone it. Keep a separate clean test VM image without product grants for onboarding/revocation scenarios. Test Developer ID releases without re-signing them as development builds. Apple recommends a fresh VM for testing the actual quarantined/notarized installation path. [Code identity requirements](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html), [Notarized-product testing](https://developer.apple.com/forums/thread/130560)

## Harness and test boundaries

The runner-facing entrypoint executes native scenarios in its current isolated test OS. A local wrapper creates the test VM, transfers inputs, starts that entrypoint in the test VM's GUI login session, retrieves results, and removes the test VM. Neither test logic nor expected outcomes depend on GitHub versus Tart. Exact build targets, source layout, executable names, transport details, and commands remain for implementation planning.

| Component                 | Responsibility                                                                                           | Dependencies                                                                        |
| ------------------------- | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Environment launcher      | Supply an isolated macOS desktop, identify the run, and retrieve results                                 | GitHub runner or Tart; test VM GUI-session bootstrap                                |
| Environment qualification | Prove session, permissions, display capabilities, and actual OS/signing conditions before a suite starts | Native OS calls and a controlled fixture application                                |
| Display helper            | Create, configure, remove, and observe test monitors                                                     | CoreGraphics private creation adapter and public display configuration/observation  |
| Fixture applications      | Expose predictable real windows and deliberate failure conditions without personal data                  | AppKit, native tabs/full-screen where relevant, a fixture-only control channel      |
| Scenario driver           | Execute public daemon/CLI actions and real UI input, then assert observable outcomes                     | Actual daemon API, OS observations, fixtures; XCUITest for rail/catalog interaction |
| Result collector          | Preserve logs, state, environment manifest, and available visual evidence                                | Test processes, fixture observations, existing screenshot permission                |
| Idle controller           | Admit and interrupt optional jobs on the host                                                            | Host activity/power/resource observations and GitHub runner lifecycle               |

Keep the real daemon, layout, persistence, backend adapter, integrations under test, rail, and watchdogs in the execution path. Synthetic applications supply real macOS windows; they do not replace AX or CoreGraphics with fakes. Do not add a test switch that bypasses permission checks or substitutes a fake OS backend and call the resulting run E2E.

Drive most scenarios through the public daemon API/CLI for reproducibility. Check independent native results: fixture-observed window geometry/presence, focus, display membership, and on-disk durable state. Test rail/hotkey/mouse actions with actual UI/input separately so direct API calls do not masquerade as UI coverage. Reuse synthetic story fixtures from [the native catalog workflow](../design-process.md) for UI scenarios without substituting catalog responses for daemon E2E.

## Two execution profiles

**Controlled launch** runs real packaged daemon/rail/watchdog executables under the qualified test launch chain. Avoid detaching them into a different permission context. This is the first hosted-CI target; verify permissions in each process that actually performs privileged work. It exercises management behavior and independent recovery, but does not certify normal login installation or permission onboarding.

**Installed product** uses normal app startup, login registration, signing, permissions, and update/recovery behavior. It runs in prepared or clean disposable test VMs, as appropriate, and on a hosted runner only if that exact launch path qualifies. A controlled-launch result cannot satisfy an installed-product scenario. Product process/lifecycle design remains a separate implementation decision.

Local test VMs have active automatic GUI login and use a user-session bootstrap for GUI work. SSH transfers and orchestration are allowed; changing the Unix user or starting a system service is not evidence of joining the required GUI session. Detect a missing or locked test VM session before launching the manager.

## Multi-display scenarios

Start with one display and two-display extended desktops; add a three-display topology to extended runs. Use intentionally different dimensions/densities to catch pixel/point confusion. Configure relative origins, including a monitor above/left of main, and verify the actual arrangement before assertions. Disable automatic VM display refitting for deterministic scenarios.

Test leaf monitor bindings, ancestor overrides, global switches blanking unoccupied displays, shared rail configuration and usable-area reservation, main-display reassignment, window transfer, display removal fallback, and subsequent reconnect. These exercise C-02/C-03, FR-03/FR-06/FR-13, and FR-41/FR-45.

Use distinct descriptor identities for simultaneously connected monitors. For reconnect scenarios, reuse the logical monitor's descriptor and verify the actual durable display identity reported by macOS; do not equate a newly allocated numeric display handle with physical identity. If the virtual mechanism cannot reproduce stable reconnect identity, report that case as unqualified and retain real-hardware coverage of the requirement.

Keep the VM/runner's original display as a known baseline. Include it in the recorded topology rather than pretending it vanished. Do not mirror virtual monitors as part of the baseline test setup. Wait for observable display/window convergence with bounds, not a fixed sleep followed by an optimistic assertion.

The helper need not render each display into its own VM-host window. Assertions run inside the test VM; interactive debugging can use test VM screen sharing or per-display captures. Visual access to every test VM display is a convenience to validate, not a prerequisite for window-placement assertions.

Virtual monitors cover macOS's window/display handling, not cable/EDID behavior, hardware sleep/wake, physical gestures, or high-refresh appearance. Those stay in explicit hardware validation and the published compatibility matrix.

## State reset, ordering, and failures

Allow one desktop-mutating scenario at a time per GUI session. Parallelize using independent hosted jobs or separate test VMs rather than multiple managers sharing one desktop. Deterministic suites may run concurrently elsewhere.

Each scenario gets its own configuration, semantic state, history, runtime socket, recovery records, screenshots, and notification-output paths. Use explicit supported path configuration when the implementation defines it; do not change `HOME` to imitate a second user. Disable test VM login startup for ordinary scenarios, enabling it only for startup tests. Test actions still use daemon preflight and confirmation semantics.

Before each scenario, verify no prior test manager remains, establish the expected windows/displays, and record baseline Dock/geometry. Cleanup uses explicit Stratosphere shutdown, then scenario-owned fixture/process cleanup. Kill only processes created by the harness, using tracked identity rather than a broad app-name match. Host orchestration independently bounds teardown and discards a stuck test VM. Failure to restore the baseline prevents reuse of that desktop.

A missing GUI session, AX denial, incorrect topology, or unavailable required display mechanism fails qualification. Required CI fails with a setup diagnostic; it does not silently skip the scenario, replace it with a fake, or return success with an empty window list. Permission-denied tests are deliberate separate scenarios with expected degraded diagnostics.

Capture environment metadata, suite/scenario/commit identity, daemon/watchdog/fixture logs, operation results, sanitized state and recovery records, and display topology. Attach screenshots/recordings when available; their failure must not block textual diagnostics. Distinguish product failure, environment failure, and user-preempted execution. Retry environment provisioning once from a fresh environment; preserve the first result. Do not retry product assertion failures into a green result.

## Optional CI during idle time

Run a small trusted controller on the host. Workflow code and the self-hosted runner execute only inside the test VM. The controller selects an approved commit that has passed hosted checks, prepares a test VM, registers a one-job runner with a unique label, and dispatches the optional workflow to that label. A repository runner-registration credential stays on the host; the test VM receives only its runner registration/session credentials and normal job credentials. Do not mount the host user's home, keychain, or working checkout into the CI test VM.

GitHub supports one-job ephemeral runners and labels, and queues jobs until a matching runner is available; queued self-hosted jobs expire after 24 hours. For this small deployment, dispatch only after the test VM is ready rather than create an indefinite backlog every night. Bound a startup/dispatch race and cancel an unmatched optional run; never route it to a different machine implicitly. [Runner lifecycle](https://docs.github.com/en/actions/reference/runners/self-hosted-runners), [Runner labels](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/use-in-a-workflow)

Recommended configurable admission policy: 15 minutes without physical user input, external power, healthy memory/CPU headroom, no local interactive test run, and at most one test VM. Observe host physical activity rather than input generated inside the test VM. The SDK exposes `HIDIdleTime`; its behavior under injected test VM events needs qualification. Inability to establish reliable host-idle state means no admission. Do not wake the Mac or unlock the host user's desktop to obtain capacity.

Recommended return-to-work policy: host user activity stops admission and cancels the active optional job. Allow up to 30 seconds for result collection and test VM cleanup, then stop/discard the test VM. Report it as interrupted, preserving diagnostics already transferred; retry the whole scenario in a new test VM during a later idle period. Do not attempt transparent pause/resume of AX calls, watchdog deadlines, or an interrupted destructive operation. These timing values are infrastructure defaults for review, not new product responsiveness guarantees.

Keep runner logs and partial results outside the disposable test VM as the run proceeds. Restrict workflows on the host to approved branches/jobs; ordinary fork pull requests stay on GitHub-hosted runners. Local interactive runs take priority and do not inherit the idle controller's admission/preemption policy.

## Development tools and images

Nix pins Tart, supporting tools, dependencies, build outputs, and execution wrappers. Nixpkgs also packages Apple SDKs, including SDK 26. Full Xcode/UI-testing tools, macOS, GUI login, permissions, and signing keychains are separately prepared and recorded. Pin the Nix environment and test VM image independently. See the [agreed Nix workflow](../testing-approach.md#nix-and-image-management) for runtime E2E entrypoints and optional test VM closure transfer. No SwiftPM layout or implemented project build contract is selected by this investigation.

Cache a small runtime test VM image and transfer locally built artifacts into it for frequent E2E iteration. Use a separate Xcode-equipped test VM profile only when a suite needs development tools there. The native scenario driver can be a prebuilt artifact; XCUITest scenarios may need the Xcode-equipped profile. Start evaluation with Tart's default two CPUs/4 GB RAM and raise resources only after measuring the suites; admit CI test VMs only while maintaining host headroom.

Version prepared images by macOS/build, image identity/digest, signing identity, fixture/integration versions, and preparation recipe. Never bake runner registrations or personal integration accounts into a reusable image. Keep integration test credentials out of shared/public base images. Account-dependent tests use dedicated test data/accounts and an explicitly credentialed integration profile.

## Coverage and release evidence

| Suite                                                                   | GitHub required checks                                  | Local test VM / optional host CI                         | Additional evidence                                       |
| ----------------------------------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------- |
| Domain, layout, protocol, storage invariants                            | Yes; deterministic synthetic data                       | Same tests for reproduction                              | Does not establish OS feasibility                         |
| Real windows, AX discovery/mutation, switching, native tabs/full-screen | Core after controlled-launch qualification              | Same suite, broader cases                                | Record actual backend and OS conditions                   |
| Multi-display placement and rails                                       | Required cases after display qualification              | Same display helper and topology cases                   | Physical reconnect identity/hardware behavior separately  |
| App AX stalls, daemon/rail crashes, independent recovery                | Bounded fixture cases after qualification               | Stress/repetition and installed-product cases            | Verify desktop/Dock results, not just restarted PIDs      |
| Catalog/rail UI and input                                               | Qualified XCUITest/native interaction cases             | Interactive review and recordings                        | Wallpaper/materials/motion/gestures on supported hardware |
| Safari/Chrome and other real-app restoration                            | Account-free qualified subset                           | Dedicated integration profiles                           | Exact app versions and fidelity evidence                  |
| ChatGPT conversation/draft/fresh contexts                               | Only after actual integration and account qualification | Dedicated integration profile; release evidence required | Reliable restoration remains a release gate               |
| First-run grants, revocation, login, signed updates                     | Only if installed-product path qualifies                | Prepared/clean test VMs; required release validation     | Developer ID/notarization and SIP evidence                |

Hosted PR checks do not replace release gates. The host's optional capacity can produce release evidence, but absence or preemption of required release evidence blocks release. Virtual or deterministic tests do not waive hardware-dependent validation.

## Alternatives considered

| Alternative                                                      | Assessment                                                                                                                                                                                                                                                                                                                                                                                                             |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Second user with fast user switching or a remote virtual desktop | Lighter and worth retaining as a manual diagnostic option. Apple documents a remote virtual desktop without interrupting the console user, but it shares the OS and complicates reset, failure containment, and display/session assumptions. It offers less parity with disposable hosted CI. [Apple remote desktop](https://support.apple.com/guide/remote-desktop/choose-how-to-control-and-observe-apd4f46319e/mac) |
| Tart VM for every environment                                    | Good local isolation, but nested virtualization is unsupported on the target GitHub runners. Use the hosted runner as the existing isolation boundary.                                                                                                                                                                                                                                                                 |
| One harness with native-hosted and test VM launchers             | Recommended. Scenario logic and real OS adapters stay common; environment provision/reset and permission preparation differ explicitly.                                                                                                                                                                                                                                                                                |

## Acceptance checks before adoption as working infrastructure

These are the first implementation research deliverable, before building a large suite. They are not checks already performed here.

1. On a fresh `macos-26` ARM64 hosted runner and a SIP-enabled macOS 26 ARM64 Tart test VM, create two extended virtual monitors, set arrangement/main display, change resolution/density, remove/re-add, and verify observed topology and identity. Check fixture windows can occupy both monitors; do not substitute two video streams from a single display.
2. Launch a normally signed controlled process through the proposed chain. From the process that will perform AX work, discover, focus, move, resize, and observe a separate fixture application's window. Verify actual mutation/readback, input delivery, and available captures. Check any detached watchdog/rail/helper separately.
3. Run a minimal real daemon/fixture scenario through the same native entrypoint on hosted CI and the test VM. Force daemon exit and an app AX stall; verify independent recovery, healthy-app responsiveness, and baseline restoration. Backend-specific research questions remain separate.
4. In prepared and clean test VMs, prove development-grant survival across two changed builds and image cloning, normal installed-product startup, permission loss diagnostics, and signing identity attribution. Test the real distributed artifact separately when it exists.
5. Prove unattended test VM GUI readiness, host keychain handling, activity detection unaffected by test VM input, return-to-work cancellation, log survival, and cleanup after forced host-controller termination. Measure boot/reset/resource costs before setting admission budgets beyond the recommended initial defaults.

If a hosted capability fails, required CI reports that limitation. Investigate a supported launch/configuration correction; do not silently move mandatory checks to the host, disable SIP to claim core compatibility, or rename simulated tests E2E. Hosted breadth remains conditional until qualified. This is the material feasibility limit on the recommended architecture.

## Verification performed in this investigation

Read authoritative project documents, inspected the installed SDK declarations, and researched the primary sources linked above. Read-only local checks reported macOS 26.5 (25F71), ARM64, Xcode 26.6 (17F113), and SIP enabled. Tart was not found on the current command path. This checkout has no commits, configured Git remote, or implemented build/test infrastructure.

No GitHub Actions job, VM, virtual-display mutation, Accessibility mutation, permission change, runner registration, or personal-app test was performed. These findings finalize the recommended execution boundaries and qualification policy, not proof that the acceptance checks have passed.

## Product requirement trace

- [NFR-01](../non-functional-requirements.md#nfr-01--platform-and-native-integration), D-23/D-29: macOS 26+, Apple Silicon, Swift, and SIP-enabled core evidence.
- [NFR-03/NFR-04](../non-functional-requirements.md#nfr-03--ax-hang-containment-and-responsiveness), [FR-64–FR-68](../functional-requirements.md#recovery-process-lifecycle-and-release), Q-04: actual AX containment, independent recovery, and interruption cases.
- [NFR-08](../non-functional-requirements.md#nfr-08--distribution-and-identity), FR-69–FR-71: stable identity, installed-product tests, and distribution evidence.
- [NFR-09/NFR-10](../non-functional-requirements.md#nfr-09--verification-and-compatibility-lifecycle): exact environment evidence, synthetic deterministic data, and responsibility boundaries.
- [C-02/C-03](../concepts.md#c-02--display-binding-and-effective-placement), FR-03/FR-06/FR-13, [FR-41–FR-45](../functional-requirements.md#rail-overview-and-appearance): display topology, bindings, scope, and shared rails.
- [FR-22–FR-29](../functional-requirements.md#integrations-and-merge), Q-02: real integration evidence and the ChatGPT release gate.
- [D-02/D-25/D-26](../decision-map.md#agreed-decisions), Q-01/Q-03/Q-06: preserve unresolved backend/notification/gesture/private-API mechanisms; test-environment checks do not decide them.

No product Markdown or DOT requirements are revised by this investigation.
