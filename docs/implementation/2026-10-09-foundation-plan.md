# Project Foundation Implementation Plan

> **For agentic workers:** Use subagent-driven-development for the domain, catalog, and environment-probe tasks, with task review and final review. The approved user instruction authorizes continuous execution.

**Goal:** Provide a buildable native foundation and truthful isolated-test tooling.

**Architecture:** One Swift package separates domain values, shared UI, and executable entrypoints. One bundle assembler is reused by development and CI. Nix wrappers and Tart orchestration launch the same native qualification probe.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Swift Testing, Python standard library for tooling, Nix, Tart, GitHub Actions.

## Global Constraints

- macOS 26+ Apple Silicon only; SIP-enabled core.
- Synthetic fixtures; no deterministic tests depend on personal apps/data.
- Desktop-mutating tests run only on hosted runners or disposable test VMs.
- Shared production UI components and reproducible/replayable stories.
- Keep Q-01–Q-13 mechanisms unresolved outside explicitly implemented domain rules.
- Preserve the existing uncommitted product documents; do not include them in foundation commits.
- Treat missing environment capabilities as setup failure, never an empty success.

## Task 1: Domain and Swift tests

**Files:** `Package.swift`, `Sources/Domain/*.swift`, `Tests/DomainTests/*.swift`.

**Interfaces:** A value-based `WorkspaceTree` provides node/window ownership mutations and `resolveActivation(target:displays:main:)`; returned placement references durable node IDs, not AX objects. Concrete type names are chosen within Domain and consumed only after this task's review. References: C-01–C-04; FR-01–FR-06, FR-14.

- [x] Write tests for leaf wrapping transferring windows/layout/binding; unique sibling names including Unicode/case collisions; no double ownership; direct-descendant binding after ancestor activation; remembered/recency/order selection and display fallback collisions.
- [x] Run `swift test --filter DomainTests`, observe missing behavior, then implement minimal value-based rules.
- [x] Run the domain suite and review whether each test catches a realistic invariant violation.

## Task 2: Native catalog

**Files:** `Sources/UI/*.swift`, `Sources/StoryCatalog/*.swift`, `Tests/UITests/*.swift`.

**Interfaces:** UI uses independently constructed presentation fixtures and records requested actions without a live daemon. StoryCatalog renders those same views in a native app and panel. References: FR-41–FR-47, FR-54; design-process.md.

- [x] Write tests for story replay/action state before implementing those transitions.
- [x] Add busy compact/full rail, deep tree, partial-failure and interruptible expansion stories with reset/replay, searchable selection, appearance controls, and action log.
- [x] Build catalog; inspect native UI on the host without starting window management.

## Task 3: Build, bundles, and Nix

**Files:** `Tools/build.py`, `Tools/bundle.py`, `Tools/check-docs.py`, `Packaging/*.plist`, `flake.nix`, `flake.lock`, `nix/*.nix`, `README.md`, `.gitignore`.

**Interfaces:** `python3 Tools/build.py build|test|stories|qualify` is the common development wrapper. `build` writes `.local/build/*.app` and a probe executable. `qualify` delegates to the isolated entrypoint, and `stories` launches only the catalog.

- [x] Prove Swift 6 and SDK 26 compilation; record selected compiler and SDK. Investigate a pinned Nix source build and retain explicit unqualified status if unavailable.
- [x] Assemble bundles containing Info.plist, executable, resources and optional signing; inspect metadata and Mach-O dependencies.
- [x] Add lockfile and Nix wrappers for development, checks, build, stories, native and VM qualification.
- [x] Execute actual supported entrypoints; do not report evaluation as a successful source build.

## Task 4: Isolated environment probes and orchestration

**Files:** `Sources/FixtureApp/*.swift`, `Sources/EnvironmentProbe/*.swift`, `E2E/*.py`, `Tests/ToolTests/*.py`, `.github/workflows/*.yml`, `docs/implementation/environment-setup.md`.

**Interfaces:** `EnvironmentProbe --profile hosted|guest --fixture PATH --output PATH` produces structured environment/results JSON and a nonzero exit for missing requirements. `E2E/native.py` enforces the isolated profile and invokes the probe. `E2E/vm.py` accepts a configured prepared image and test VM user account; clones, transfers, collects, and cleans up.

- [x] Write wrapper tests proving absent isolation is refused and owned test VM teardown occurs on failure.
- [x] Add real AppKit fixture and AX/display probe; compile without mutating the host desktop.
- [x] Implement bounded test VM lifecycle and qualification workflow; preserve result/log artifacts on failure.
- [x] Attempt isolated qualification when prerequisites exist; retain a concrete pending checklist for daemon/watchdog, grant survival, and hardware evidence.

## Task 5: Review and evidence

**Files:** `docs/implementation/foundation-verification.md`, `README.md`, this plan.

- [x] Run Swift tests, tooling tests, builds, Nix checks applicable to selected tooling, documentation link/ID checks, and Graphviz parsing.
- [x] Inspect artifacts and native stories; review the final changes for invariants, truthful qualification, cleanup, and preservation of product authority.
- [x] Record passed and unavailable checks separately; update task status to reflect actual results.

## Execution result

Implemented and reviewed the native code/build foundation. Initial pinned Nix and Xcode checks passed 45 Swift Testing tests and 20 Python tooling tests. Follow-up runtime-only, signing and native boundary fixes now pass 79 Swift tests and 36 Python tests on both toolchains. Native catalog and packaged artifacts were inspected; exact evidence and remaining limits are in [foundation verification](foundation-verification.md).

The initial prerequisite inspection found no prepared Tart image, dedicated test VM key, configured Git remote or persistent signing identity. After the host user freed storage and approved a dedicated test identity, a SIP-enabled macOS 26.5 test VM was prepared, signed artifacts installed at stable paths, and Accessibility granted. Interactive Retina scaling is saved and visually confirmed. Actual disposable runs demonstrated rebuilt-probe grant survival, partial native window/display/focus checks, and complete baseline restoration/owned-clone teardown in the documented runs.

The complete normal signed local probe passed on 2026-10-10 at `20398a2`, including both windows, main-display change, removal/reconnect identity, full baseline/focus restoration and owned clone teardown. Evidence and the explicit activation-readiness revision are recorded in foundation verification. The prepared test VM is open for interactive use with the qualified tools; stop it before automated cloning. Hosted qualification awaits the user's manual push. Checkmarks above record implemented tooling and executed checks; they do not establish unexecuted product or release gates.
