# Nix feature modules

Approved on 2026-10-11: finish the feature split discussed after the formatting/CI implementation. Trace: NFR-01, NFR-09, NFR-10. This reorganizes tooling without changing product requirements or DOT summaries.

## Design

Remove the catch-all `core.nix`. Automatically imported modules own toolchain, artifacts, packaged source, development, documentation, formatting, CI, and VM images/guest/provisioning/E2E. Put explicitly imported constructors, tests and existing scripts under corresponding `nix/features` directories. Import-tree scans only `nix/modules`.

Use per-system module arguments for shared implementation values: `toolchain`, `artifacts`, `docs`, `vmImages`, and `vmGuest`. Their producers each have one owner; consumers name dependencies in their module argument lists and pass them explicitly to constructors. Standard flake outputs remain the public interface. A typed internal `stratosphere.toolingChecks` option lets features contribute the existing working-tree tooling checks without including snapshot formatting/source checks or forming dependency cycles. CI continues to realize every standard check.

Construct the development shell directly from the toolchain, formatter and existing interactive dependencies. Remove the shell from the command constructor. Preserve runtime scripts, existing command names, pinned inputs, artifact paths, and the source filter. Expose the already-transitive VM guest check independently. The broader shell extraction remains separate work.

## Execution and verification

- [x] Record existing app/package/check identities and staged contents before edits.
- [x] Move constructors/tests/scripts into feature directories and fix explicit relative references.
- [x] Replace `core.nix` with independent modules; inject VM guest configuration into provisioning and build the shell directly.
- [x] Update current documentation and relative links, preserving historical descriptions.
- [x] Format and evaluate outputs. Compare identities: existing build/tooling/probe outputs should be identical; only documentation/formatting snapshot checks should change, plus the separately exposed guest check.
- [x] Run `ci-check`, `nix flake check`, working-tree tests, docs and formatter idempotency. Review the scoped change and verify existing staged contents remain intact. Do not run desktop-mutating probes.
