# Nix declarations and standalone runtime scripts

Approved on 2026-10-12 following the runtime-script investigation. Trace: NFR-01, NFR-08, NFR-09, NFR-10. Nix remains the sole command/composition interface; product requirements and DOT summaries do not change.

Nix owns dependencies, executable paths, native product/VM/guest specifications, generated configuration and check registration. Standalone feature-local scripts own argument parsing, runtime filesystem/signing/process effects, SSH, deadlines and cleanup. Preserve single-controller traps and ownership; do not introduce a global shell framework or separate task runner. Runtime credentials remain outside the store. The guest script remains portable to the prepared native macOS guest without Nix or extra tools.

- [x] Save current implementation/index and use the existing behavioral checks as refactor coverage.
- [x] Artifacts: declare the bundle/executable/publication manifest, package shared assemble/sign scripts, and update both source and working-tree builds to call the assembler.
- [x] Development: separate build/test scripts with shared Swift setup; preserve command options, caches, rollback and catalog launch behavior.
- [x] Documentation: extract check script and stable-ID AWK query, plus tests and fixtures.
- [x] VM images: keep specifications/receipts in Nix, pass profile JSON to the reconciliation script, extract adoption queries and fake-Tart tests.
- [x] Provisioning/guest: extract native guest template and host controller; pass fixed settings safely from Nix while retaining runtime credentials and independent cleanup.
- [x] E2E: extract native/VM/common scripts and queries, separate all fixtures/tests, replace recursive self-import and modified `pkgs` with explicit transport arguments.
- [x] Extract remaining substantial test bodies/fixtures across features; retain short derivation phases/wrappers/stubs inline. Package scripts with syntax/ShellCheck validation and existing shfmt coverage.
- [x] Run all declared checks, working-tree tests/build, documentation and formatter idempotency. Review the final boundaries and preserve staged user contents. Synthetic tests establish refactor behavior only; do not run live desktop/VM qualification implicitly.
