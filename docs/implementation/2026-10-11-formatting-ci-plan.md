# Formatting and CI implementation plan

Approved design: [formatting and CI](2026-10-11-formatting-ci-design.md).

Goal: one pinned project formatter and Nix-owned CI entrypoints. Trace: NFR-01, NFR-09, NFR-10. Work in the existing checkout, preserving user changes and the index; do not commit unrelated staged work.

- [x] Add behavioral checks for formatter rejection/idempotency/exclusions and hosted-probe refusal before any build or probe effects. Confirm the requested format command is absent before implementation.
- [x] Add pinned flake-parts, import-tree and treefmt-nix inputs. Auto-import only `nix/modules`; migrate current outputs into a feature module without changing existing runtime semantics.
- [x] Configure nixfmt, swift-format, Prettier, shfmt and Taplo in one treefmt module. Export its wrapper through `nix fmt`, `.#format`, and the development shell. Exclude mutable/generated data and preserve prose wrapping.
- [x] Add actual source-snapshot documentation validation. Package CI commands for deterministic check realization, environment evidence collection and hosted-only probes. Keep fake CI boundaries in tests.
- [x] Replace workflow execution recipes with the three Nix commands, retaining runner policy and artifact handling. Document interfaces and formatting policy.
- [x] Apply formatting as a separately recorded normalization, inspect the diff, verify idempotency and meaningful failure cases, run all declared checks, working-tree tests and documentation checks. Record cached checks separately from live execution; do not run desktop probes on the host.

Use existing Nix behavioral-check conventions. Do not introduce a command dispatcher, Just, mission-control, broad runtime-script refactor, or new product behavior. Inspect the final scoped change for unnecessary glue and dependency cycles.
