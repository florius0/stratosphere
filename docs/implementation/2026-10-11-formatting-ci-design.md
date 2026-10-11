# Project-wide formatting and Nix-owned CI

Status: approved on 2026-10-11, extending the Nix composition discussion.

## Authority and scope

NFR-01 requires reproducible Nix/Swift tooling; NFR-09 requires truthful verification and isolated desktop effects; NFR-10 requires maintainable boundaries. This tooling change does not revise product behavior or product DOT diagrams. Nix remains the sole composition and command interface, without Just, mission-control, or a custom dispatcher.

## Formatting

Use a pinned treefmt-nix flake-parts module alongside scoped feature-module auto-imports. Expose the same formatter wrapper through `formatter.aarch64-darwin` (`nix fmt`) and `apps.aarch64-darwin.format` (`nix run .#format`). Select nixfmt for Nix, swift-format for Swift, clang-format for the existing Objective-C bridge and header, Prettier for Markdown/YAML/JSON, shfmt for standalone shell files, and Taplo for TOML. Verify Swift formatter compatibility with the pinned Swift 6.2 toolchain before adopting its version.

Use explicit file patterns and exclude `.local`, `.build`, `.swiftpm`, `.direnv`, generated artifacts and external sources. Include hidden tracked configuration such as `.github` and `.envrc` where appropriate. Preserve Markdown prose wrapping and DOT layout; DOT syntax remains covered by documentation checks. Inline shell strings receive Nix formatting only; shell formatting applies to extracted script files.

Formatting writes working-tree files. A formatting flake check uses the same settings against the Git-backed source snapshot and fails on differences without modifying the checkout. A second formatting pass must produce no changes. Apply the initial formatting normalization as a separately reviewable change, preserving existing staged and unstaged user work.

## CI interface

Expose `nix run .#ci-check` for deterministic CI verification: source build/tests, tooling behavior checks, snapshot formatting and actual repository documentation/DOT validation. Add actual documentation validation as a source-snapshot check alongside the documentation-validator fixture suite; they verify different things.

Expose `nix run .#ci-environment` to collect Xcode/SDK/macOS evidence at the existing `.local/ci` paths. Expose `nix run .#ci-probes` to build release artifacts with the existing ad-hoc signing policy and run the hosted native qualification at `.local/ci/qualification`. This command must reject execution outside the existing authorized hosted environment before building or launching probe artifacts. Local VM qualification remains the separate explicit E2E command.

The GitHub workflow retains events, permissions, runner selection, timeouts, concurrency, checkout, Nix installation and artifact upload. Its execution steps invoke these Nix commands without inline build, formatting, evidence-collection or probe recipes. Deterministic and environment-probe jobs retain their dependency and failure semantics. Formatting checks never fix files in CI.

## Verification and migration

Evaluate all outputs and explicitly realize the declared check outputs. Validate formatting rejection on intentionally unformatted fixtures, formatter idempotency, exclusion of mutable VM storage, actual documentation failure propagation, and hosted-profile rejection before probe side effects. Run working-tree Swift/tooling checks and documentation validation after normalization. Confirm workflow commands and artifact paths agree with the Nix entrypoints. Record cached outputs distinctly from freshly executed tests; hosted qualification remains unverified until run on the supported hosted macOS configuration.

Implement this as part of the flake-parts refactor, avoiding a temporary second formatter configuration. Prefer treefmt-nix over a hand-written formatter loop: it provides one declared formatter configuration and the standard formatter/check outputs. CI orchestration remains small Nix-owned wrappers over the existing commands and checks.
