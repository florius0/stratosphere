# Nix tooling implementation plan

**Goal:** Replace repository Python tooling with focused Nix declarations and generated Bash, and declare VM images/preparation.

**Architecture:** Nix modules expose packages, apps, and behavioral check derivations. The flake composes these modules and the pinned native development environment. Bash handles mutable host/guest effects, while Nix owns product/image configuration.

**Constraints:** macOS 26+, Apple Silicon, SIP-enabled evidence remains separate. Preserve existing images, credentials, permission grants, and user product-document edits. No broad process termination, implicit downloads, or new option framework.

- [x] Build/artifacts: declare native app metadata in `nix/artifacts.nix`; share assembly with `nix/package.nix` and development builds. Use generated build/test/stories commands, pinned shell/toolchain, optional existing signing identity/keychain, and truthful metadata. Behavioral checks exercise failed signing and complete bundle assembly.
- [x] VM preparation: create `nix/vm-images.nix` with digest-pinned source/specification, idempotent explicit prepare command, specification receipts, and fake-Tart checks for missing/matching/conflicting images. Preserve existing unmanaged images.
- [x] E2E: create `nix/e2e.nix` with bounded native/VM wrappers, isolation preflight, fresh evidence, metadata filtering, GUI-domain launch, stable artifact paths, and owned cleanup; check failure/interruption behavior with synthetic boundaries.
- [x] Documentation: create `nix/docs.nix` with a Python-free validator and link/anchor/ID/DOT regression checks.
- [x] Integrate: compose modules in `flake.nix`, remove repository Python files and Python-only tests, update README/AGENTS/CI/environment instructions and verification records. Keep historical evidence distinguishable from new checks.
- [x] Verify: `nix flake check --print-build-logs`, `nix run .#test`, `nix run .#build`, `nix run .#docs`, direnv, and review final diffs. Report runtime qualifications separately.

Execution is in the current checkout so the existing authorized changes and uncommitted product documents remain available. No commits or separate worktree are needed for this tooling replacement.

## Follow-up: names and existing-image adoption

- [x] Rename the workflow to CI, the package implementation to `nix/package.nix`, the canonical package to `stratosphere`, current verification to `development-verification.md`, and the catalog section to STORIES. Update live links while preserving historical plans and Apple framework names.
- [x] Declare per-profile display settings, add explicit provenance/settings-checked adoption, verify that mismatches are refused and image files are preserved, adopt both existing local images, and verify subsequent reuse.
