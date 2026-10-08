# Project foundation design

Approved through the setup proposal and the user's “Do that” instruction on 2026-10-09. This is implementation design, not a revision of product scope.

## Scope

Create a SwiftPM-first macOS 26 Apple Silicon project with working domain tests, shared native UI stories, explicit app assembly, Nix entrypoints, and isolated-environment qualification probes. Build only targets with implemented behavior. A window-management daemon, its public transport, full persistence, and watchdogs follow in separate designs; their names are not empty executable promises in this foundation.

The initial domain implements durable workspace/window identities, derived leaf status, populated-leaf wrapping, single ownership, sibling name validation, and activation-scoped binding resolution (C-01–C-04; FR-01–FR-06, FR-14). Selection resolves remembered leaves, then recency, then child order, and display collisions by recency. Direct focus starts resolution at its target. It does not implement global navigation operations or app effects.

## Build and packaging

One root package owns libraries and native executables. Use Swift 6 language mode and a macOS 26 deployment floor. Start with Domain, UI, StoryCatalog, FixtureApp, and EnvironmentProbe. Xcode can open the package for development; an Xcode UI-testing project is added with the first actual UI automation suite.

Use one explicit bundle assembler for product resources and helper bundles. Development signing uses an explicitly selected persistent local identity; unsigned build artifacts may be assembled for checks, but cannot establish TCC identity/grant survival. Official distribution signing/notarization remains a release operation (NFR-08; FR-69–FR-71). Builds must not include a dependency on the developer's Nix store in delivered binaries.

Pin supporting Nix tools and expose development, build, deterministic-check, story, native-qualification, and VM-qualification entrypoints. Qualify the compiler and SDK before claiming a reproducible source build. If nixpkgs' compiler cannot compile the required Swift 6/macOS 26 SDK combination, use a version-checked external Xcode toolchain for an explicitly impure development wrapper and keep reproducible source packaging unqualified. Do not silently change the language or platform floor. Pin prepared VM images separately from Nix.

## Native catalog

The catalog uses shared SwiftUI/AppKit UI views with synthetic presentation data. Initial stories include a crowded rail, deep workspace preview, nonblocking partial failure, and compact/full interrupted expansion. Search, scenario selection, reset/replay, appearance/accessibility controls, and an action log form its review surface. Native panel stories exercise hover/dismissal/focus rather than only rendering in a canvas. No story starts management of the personal desktop (FR-41–FR-47; docs/design-process.md).

## Qualification probes

A fixture app supplies real predictable AppKit windows without personal content. A native probe verifies the active GUI session, actual macOS/build/architecture/SIP, available AX grants, cross-process discovery and geometry readback, and extended virtual-monitor topology. Mutating probes require an explicit isolated environment profile: hosted CI or a disposable guest. The probe never treats missing permission or private-symbol support as success.

The local wrapper clones an explicitly configured stopped Tart image, boots it, transfers app/probe artifacts, invokes the same native entrypoint in the guest's active GUI login, collects results, and discards the clone with bounded cleanup. Image preparation and persistent signing grants are documented separately. Prepared and clean images stay distinct. A GitHub workflow runs deterministic checks and qualification probes on macos-26; actual job execution depends on repository hosting being configured.

These probes are infrastructure evidence, not daemon E2E or a complete environment qualification. The remaining daemon-failure/app-stall/watchdog scenario, installed-product grant survival, unattended host controller, real app integrations, and physical desktop review stay visibly unqualified (docs/testing-approach.md; Q-01–Q-06). Reliable ChatGPT restoration remains a release gate.

## Verification

Write meaningful domain tests before implementation; run Swift Testing with synthetic data. Build native artifacts and inspect bundle metadata and dependencies. Exercise wrapper refusal and cleanup with controlled test inputs. Parse all DOT documents with Graphviz and validate documentation links and stable IDs. Record concrete executed commands and outcomes, including unavailable prerequisites. Host inspection and catalog review are permitted; live AX/display mutations run only in an isolated test OS.

No transport framing, filesystem event algorithm, concurrency attribution mechanism, or backend is selected by this setup (Q-09, Q-10, Q-13; D-02).
