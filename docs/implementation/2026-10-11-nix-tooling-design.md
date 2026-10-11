# Nix tooling and declarative VM preparation

Guest provisioning and the current command/data names are revised by the [VM provisioning design](2026-10-11-vm-provisioning-design.md). The earlier interface and qualification descriptions below are historical.

Approved on 2026-10-11: retain only necessary tooling logic, put declarations and composition in Nix, and use generated Bash only for effects Nix cannot perform. Nix is the sole build/tooling interface; the standalone Xcode route and repository Python scripts/tests are removed. Xcode remains available for native editing/previews and separately provisioned future UI testing.

## Authority

NFR-01 requires reproducible Nix/Swift builds. NFR-08 requires identity/permission-aware signing; this development tooling still does not establish release signing. NFR-09 and the testing approach require isolated desktop effects, truthful evidence, bounded cleanup, and explicit preparation. No product concepts, requirements, or product DOT diagrams change.

## Structure

- Nix declares native products, Info.plist data, pinned toolchain, package build/check/install phases, and development commands. Small generated shell entrypoints build the working tree, assemble bundles and optionally sign using an existing identity/keychain.
- Nix declares image source by immutable OCI digest, local names, CPU/RAM/display settings, and preparation recipe. `vm-prepare` explicitly downloads/configures missing images and records the applied specification. Repeated preparation reuses matching state and rejects conflicting existing state; it never replaces personal/unmanaged prepared images. Explicit adoption accepts an existing image only after its original provenance and current CPU/RAM/display settings match the declaration. Clean and prepared display settings are declared separately to preserve fixed pixels versus interactive point sizing/refitting. Mutable images/receipts stay under the selected Tart home, defaulting to `.local/tart`.
- E2E commands preserve isolated hosted/guest execution, GUI-session launch, stable signed artifact paths, bounded readiness/probe/cleanup, fresh evidence directories, build provenance, and deletion of owned clones only. No implicit image downloads or credential/permission setup.
- Documentation validation retains local links, heading anchors, stable IDs, and Graphviz parsing without Python.
- Behavioral checks cover preparation reuse/conflicts, bundle/signing failure cleanup, and E2E interruption/failure isolation. Python-specific scaffolding is discarded.

## Interface

Keep `build`, `test`, `stories`, `stories-packaged`, `docs`, `e2e-native`, and `e2e-vm`. Add `vm-prepare`. Keep only necessary selectors: development configuration/signing options, E2E profile/artifact/evidence/SSH inputs, and a VM profile selector. Secrets remain outside the Nix store. Shell scripts use declared pinned dependencies; structured metadata uses jq and native plist tools.

## Verification

Run pinned source builds/tests and behavioral checks with `nix flake check`, working-tree `nix run .#test`/`.#build`/`.#docs`, and direnv loading. Deterministic fakes establish wrapper behavior only. Preserve existing preparation/evidence and document any unverified live VM behavior explicitly.

## Naming and adoption revision — 2026-10-11

The canonical Nix package is `stratosphere`, with `default` pointing to the same derivation. The workflow is `CI` in `ci.yml`, package implementation is `nix/package.nix`, current evidence is `development-verification.md`, and the catalog section is `STORIES`. Dated foundation plans and Apple Foundation framework references keep their historical/native meanings.

The user authorized adopting existing images without rebuilding them. `vm-prepare --adopt PROFILE PROVENANCE.json` records a matching declaration after checking source/storage identity and current settings. It does not download, clone, modify guest configuration, or grant/verify permissions. The term preparation still describes base-image configuration; fully automated guest provisioning/permission management remains a separate, unimplemented capability.
