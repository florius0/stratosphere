# Project Foundation Implementation Plan

> **For agentic workers:** Use subagent-driven-development for the domain, catalog, and environment-probe tasks, with task review and final review. The approved user instruction authorizes continuous execution.

**Goal:** Provide a buildable native foundation and truthful isolated-test tooling.

**Architecture:** One Swift package separates domain values, shared UI, and executable entrypoints. One bundle assembler is reused by development and CI. Nix wrappers and Tart orchestration launch the same native qualification probe.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Swift Testing, Python standard library for tooling, Nix, Tart, GitHub Actions.

## Global Constraints

- macOS 26+ Apple Silicon only; SIP-enabled core.
- Synthetic fixtures; no deterministic tests depend on personal apps/data.
- Desktop-mutating tests run only on hosted runners or disposable guests.
- Shared production UI components and reproducible/replayable stories.
- Keep Q-01–Q-13 mechanisms unresolved outside explicitly implemented domain rules.
- Preserve the existing uncommitted product documents; do not include them in foundation commits.
- Treat missing environment capabilities as setup failure, never an empty success.

## Task 1: Domain and Swift tests

**Files:** `Package.swift`, `Sources/Domain/*.swift`, `Tests/DomainTests/*.swift`.

**Interfaces:** A value-based `WorkspaceTree` provides node/window ownership mutations and `resolveActivation(target:displays:main:)`; returned placement references durable node IDs, not AX objects. Concrete type names are chosen within Domain and consumed only after this task's review. References: C-01–C-04; FR-01–FR-06, FR-14.

- [ ] Write tests for leaf wrapping transferring windows/layout/binding; unique sibling names including Unicode/case collisions; no double ownership; direct-descendant binding after ancestor activation; remembered/recency/order selection and display fallback collisions.
- [ ] Run `swift test --filter DomainTests`, observe missing behavior, then implement minimal value-based rules.
- [ ] Run the domain suite and review whether each test catches a realistic invariant violation.

## Task 2: Native catalog

**Files:** `Sources/UI/*.swift`, `Sources/StoryCatalog/*.swift`, `Tests/UITests/*.swift`.

**Interfaces:** UI uses independently constructed presentation fixtures and records requested actions without a live daemon. StoryCatalog renders those same views in a native app and panel. References: FR-41–FR-47, FR-54; design-process.md.

- [ ] Write tests for story replay/action state before implementing those transitions.
- [ ] Add busy compact/full rail, deep tree, partial-failure and interruptible expansion stories with reset/replay, searchable selection, appearance controls, and action log.
- [ ] Build catalog; inspect native UI on the host without starting window management.

## Task 3: Build, bundles, and Nix

**Files:** `Tools/build.py`, `Tools/bundle.py`, `Tools/check-docs.py`, `Packaging/*.plist`, `flake.nix`, `flake.lock`, `nix/*.nix`, `README.md`, `.gitignore`.

**Interfaces:** `python3 Tools/build.py build|test|stories|qualify` is the common development wrapper. `build` writes `.local/build/*.app` and a probe executable. `qualify` delegates to the isolated entrypoint, and `stories` launches only the catalog.

- [ ] Prove Swift 6 and SDK 26 compilation; record selected compiler and SDK. Investigate a pinned Nix source build and retain explicit unqualified status if unavailable.
- [ ] Assemble bundles containing Info.plist, executable, resources and optional signing; inspect metadata and Mach-O dependencies.
- [ ] Add lockfile and Nix wrappers for development, checks, build, stories, native and VM qualification.
- [ ] Execute actual supported entrypoints; do not report evaluation as a successful source build.

## Task 4: Isolated environment probes and orchestration

**Files:** `Sources/FixtureApp/*.swift`, `Sources/EnvironmentProbe/*.swift`, `E2E/*.py`, `Tests/ToolTests/*.py`, `.github/workflows/*.yml`, `docs/implementation/environment-setup.md`.

**Interfaces:** `EnvironmentProbe --profile hosted|guest --fixture PATH --output PATH` produces structured environment/results JSON and a nonzero exit for missing requirements. `E2E/native.py` enforces the isolated profile and invokes the probe. `E2E/vm.py` accepts a configured prepared image and guest GUI account; clones, transfers, collects, and cleans up.

- [ ] Write wrapper tests proving absent isolation is refused and owned guest teardown occurs on failure.
- [ ] Add real AppKit fixture and AX/display probe; compile without mutating the host desktop.
- [ ] Implement bounded guest lifecycle and qualification workflow; preserve result/log artifacts on failure.
- [ ] Attempt isolated qualification when prerequisites exist; retain a concrete pending checklist for daemon/watchdog, grant survival, and hardware evidence.

## Task 5: Review and evidence

**Files:** `docs/implementation/foundation-verification.md`, `README.md`, this plan.

- [ ] Run Swift tests, tooling tests, builds, Nix checks applicable to selected tooling, documentation link/ID checks, and Graphviz parsing.
- [ ] Inspect artifacts and native stories; review the final changes for invariants, truthful qualification, cleanup, and preservation of product authority.
- [ ] Record passed and unavailable checks separately; update task status to reflect actual results.
