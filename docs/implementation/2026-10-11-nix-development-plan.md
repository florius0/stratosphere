# Nix development commands and lowercase tooling

The tooling sections are historical and superseded by the approved [Nix tooling design](2026-10-11-nix-tooling-design.md); recorded product and verification obligations remain in force.

**Goal:** Keep the Python helpers while making Nix the primary development interface and enabling direnv.

**Authority:** NFR-01 requires Swift and reproducible Nix builds; NFR-09 and the testing approach require truthful verification evidence. This changes development tooling only, with no product requirement or DOT changes.

**Approved design:** Working-tree build, test, and stories commands enter the default development shell through `nix develop --command`, selecting its complete compiler, SDK, and linker environment. The shell explicitly pins `SWIFT_EXEC` so SwiftPM does not select Xcode internally. Packaged stories remain available as `stories-packaged`. Rename `Tools` to `tools` and `E2E` to `e2e`, including callers, tests, source filtering, CI, and documentation. Keep recorded historical verification commands intact and annotate the path revision.

## Implementation and verification

- [x] Rename directories and update live path references without changing Python behavior.
- [x] Share pinned compiler/SDK values between the development shell and Nix development apps; keep documentation and E2E apps lightweight. Keep Tart in the default development shell for interactive VM management, as requested. Only the VM app wrapper directly adds Tart as a runtime dependency.
- [x] Make `stories` rebuild and launch the working tree; move the existing packaged launcher to `stories-packaged`.
- [x] Add `.envrc` with `use flake`, ignore `.direnv/`, and document shell setup and initial `direnv allow`.
- [x] Update README, environment setup, and CI descriptions for pinned development commands.
- [x] Run Python tooling tests, documentation checks, Nix checks, working-tree test/build commands, and inspect launcher scripts. Verify direnv loading if available. Do not run desktop-mutating probes.

Existing uncommitted product documents remain the user's work. No commits or changes to global shell configuration are required.
