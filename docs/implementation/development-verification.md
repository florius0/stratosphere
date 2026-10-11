# Development verification

Tooling was revised on 2026-10-11: `Tools/` and `E2E/` were first renamed, then repository Python tooling was replaced by the [Nix tooling design](2026-10-11-nix-tooling-design.md). Historical commands/results below describe their original invocations. The [feature-module revision](2026-10-11-feature-modules-plan.md) moved current constructors, tests and scripts to `nix/features/`; dated records retain their original locations unless explicitly updated.

Evidence is recorded for this setup on 2026-10-09. Product behavior and release evidence remain governed by [the testing approach](../testing-approach.md).

## Environment

The development host reports macOS 26.5 (25F71), Apple Silicon, Xcode 26.6 (17F113), Apple Swift 6.3.3 and SDK 26.5; SIP is enabled. The pinned Nix environment resolves Swift 6.2.4, SDK 26.5 and Tart 2.37.0. Both toolchains were verified against the same package. At initial inspection no valid code-signing identity was available; the first artifacts were ad-hoc signed for build inspection. A dedicated local test identity was subsequently created with the host user's approval, as recorded below.

## Executed checks

- Domain: 23 Swift Testing tests pass, including recursive tree/binding/selection and ownership invariants. Test-first stub failures were observed before implementation. Scoped review approved both specification compliance and quality.
- `nix flake check --print-build-logs`: exit 0. The pinned source derivation compiled all native products and ran 45 Swift Testing tests in seven suites. Its independent tooling check ran 20 Python tests. These include output freshness, interruption/timeout, launch failure, passing-probe/failed-teardown reporting, and owned clone cleanup. No desktop-mutating tests run in the build sandbox.
- `python3 Tools/build.py test`: exit 0 using Xcode Swift 6.3.3. The same 45 Swift tests and 20 Python tests passed; documentation checks ran afterward.
- `python3 Tools/build.py build --configuration release --sign-identity -`: exit 0. Both app bundles and the probe executable assembled successfully. `codesign --verify --strict` accepted the ad-hoc signed artifacts; this does not establish persistent TCC identity or release signing.
- `otool -L` inspection of all three Nix-built products found only system dependencies, with no external Nix store libraries. The catalog's Mach-O deployment metadata reports minimum macOS 26.0 and SDK 26.5; both bundle plists declare minimum 26.0.
- Native and VM wrapper tests use synthetic temporary executables and files, including a fake Tart/SSH boundary. They prove wrapper behavior, not VM feasibility. Both wrappers reject existing output directories and report cleanup failure as a failed run.
- The native process-owner tests and separate harmless subprocess experiments verified inherited process-group ownership, TERM/KILL bounds, and outer-group cleanup after timeout or probe termination. No real fixture app was launched for those tests. Native refusal/CLI checks also returned expected nonzero results without AX/display observations.
- Documentation links, anchors and stable product references were checked; all three DOT summaries parsed with Graphviz.
- Native catalog launched on the host using synthetic data. Canvas sizing, panel bounds, presentation inputs and independent hover state were corrected following scoped reviews. Final canvas inspection showed an unclipped footer and the expected simulated action/result state. Native panels opened without changing the catalog's focused search field in the initial inspection. Full pointer pass-through, interrupted spring geometry, focus behavior across other apps, display scales and accessibility variants still need hands-on review; deterministic story tests do not establish those desktop properties. Local screenshot evidence is in `.local/evidence/catalog-final.png`.
- Pinned development shell evaluated and launched: Swift 6.2.4, Tart 2.37.0, Python 3.14.7 and SDK settings are available.
- Domain, catalog, tooling and native probe reviews passed after their fixes; whole-foundation review passed after correcting the signed-artifact selection in the test VM instructions. No open actionable source-review findings remain.

The pinned nixpkgs SwiftPM initially lacked the Darwin Swift Testing launcher. `nix/features/toolchain/swiftpm.nix` (originally `nix/swiftpm.nix`) builds the matching, unmodified upstream `Sources/swiftpm-testing-helper/Entrypoint.swift` from SwiftPM 6.2.4 and includes it with that package. The suites explicitly disable XCTest because they use Swift Testing; future XCTest/XCUITest requires separately provisioned Xcode. Xcode-only preview macros were replaced with shared `PreviewProvider` definitions. Nix's Clang wrapper still emits target/minimum-version warnings for SwiftPM invocations; the native products' observed deployment metadata meets the 26.0 floor.

## Not yet qualified

Initial setup had no test VM image, SSH key or signing identity. After the host user freed storage and approved a dedicated test identity, the following preparation was executed on 2026-10-09:

- Downloaded the official macOS 26.5 vanilla image pinned to `sha256:e12d678b248f3122e276fa64632970a8e1c6dc60ff6738d21fe9bfa5ea58f426` into `.local/tart`. Its reported disk capacity is 50 GB, with about 27 GB in the base image; APFS clones share unchanged data.
- Booted a prepared clone with four CPUs, 4096 MiB RAM, a fixed 1280×800 display and display refitting disabled. Actual observations: macOS 26.5, build 25F71, VirtualMac2,1, arm64, SIP enabled and active GUI login UID 501.
- Verified dedicated-key SSH access for test VM user `admin`; only the public SSH key was installed in the test VM. The host user's home and signing keys were not mounted or copied.
- Re-enabled Gatekeeper in the prepared test VM; the vendor image initially reported assessments disabled. The host's Gatekeeper settings were not changed.
- Created the approved local test signing identity in `.local/signing/test.keychain-db`, with host-user trust limited to code signing. Signed all three artifacts and verified their signatures. The host user's original keychain search list was restored. This is development signing, not Developer ID/notarized distribution.
- The Nix-managed Tart bundle could not be materialized because of a store permissions error. For this preparation, the official Tart 2.37.0 archive was extracted under `.local/tools`; its SHA-256 exactly matched the pinned nixpkgs input. The same signed app bundle executable was used, without modifying host Nix permissions.
- A separate runtime inspection found no Xcode or Command Line Tools installation. The probe runs in the test VM user's GUI launch domain. After the host user enabled Accessibility, signed rebuilt probes repeatedly observed that grant in fresh disposable clones. This demonstrates the development probe's stable-path/signature grant across these builds and clones; installed-product onboarding and signed release updates remain separate.
- Interactive scaling was corrected with point-based sizing and automatic display fitting. The test VM reports a 2× backing scale after restart, and the host user confirmed the image is sharp. The wrapper explicitly disables fitting on each disposable clone before boot.
- The normal signed probe at `edb35c1` independently observed both fixture windows at their requested AX/native geometry, with actual keyboard focus, on a 1440×900 1× monitor to the left and a 1280×800 logical / 2560×1600 pixel Retina monitor above. Main-display change, removal and reconnect UUID matching passed; configuration of the reconnected handle then failed. The complete original display state and prior focus were restored, and the wrapper discarded its owned clone.
- Diagnostics proved the creating process retained stale CoreGraphics mode/ID/configuration information: it reported old IDs `[1,2,3]` while a fresh observer saw `[1,2,4]`; mirror configuration of new ID 4 failed with CGError 1001. The harness now uses bounded, guarded fresh processes for real display observations and configuration, with actual active-state checks, validated requests, transaction cancellation and independent postconditions. Descriptor/expected values are never used as observations.
- Full normal runs at `5e13a7d` and `022a3b4` reached the initial verified extended topology but failed focus activation: first a system AX `cannotComplete` response, then an activation deadline. Both restored baseline displays/focus and discarded the clone. The latest diagnostic (`f4edacb`) compares parent and fresh-process focus state before cleanup; it has compiled and passed scoped review but has not run signed yet.
- On 2026-10-10, the diagnostic release compilation succeeded, but signing failed with `errSecInternalComponent`. The host's Security service reports `In dark wake, no UI possible`. Normal host wake/unlock is required before the next signed run; no host wake, lock-policy change or permission workaround was performed.

The follow-up code removes developer-tool queries from the runtime probe, forwards bounded host build metadata, installs tools at stable paths across runs, and supports a separate signing keychain during builds. The metadata/stable-path and subsequent native-fix reviews passed, with their actual checks retained locally. The final deterministic totals are recorded below. Local preparation, signing and permission-check evidence lives under `.local/vm-preparation` and `.local/signing` and is excluded from Git.

No Git remote is configured; the user will push manually. Hosted qualification has not run.

Final checks on `f4edacb`: `nix flake check --print-build-logs` and `python3 Tools/build.py test` both exited 0, each running 77 Swift Testing tests in 17 suites and 36 Python tooling tests. Documentation links, stable references and all DOT summaries passed. The latest release compilation also succeeded before the dark-wake signing failure. Scoped reviews have no open actionable source findings; cumulative focus-experiment evidence remains explicitly limited to its observed sequence.

## Qualified local probe on 2026-10-10

The normal signed probe at `20398a2` passed in a fresh disposable clone of the prepared macOS 26.5 (25F71), arm64, SIP-enabled image. Both `qualification.json` and the outer `run.json` report `passed`; there are no probe or VM teardown errors. Evidence is retained in `.local/results/vm-normal-activation-2026-10-10`, alongside all earlier failed/diagnostic runs.

Actual observations verified two real AppKit windows through AX and independent fixture/CoreGraphics readbacks, including geometry, keyboard focus and monitor membership before and after reconnect. The extended topology included 1440×900 at 1× to the left and 1280×800 logical / 2560×1600 pixels at 2× above. Main-display change, removal, reconnect identity, full baseline mode/identity/origin/main restoration and prior application focus all passed. The owned test VM clone was stopped and deleted.

The final activation barrier uses the exact live owned application, its native active state, foreground PID and app-scoped AXFrontmost. It establishes activation before AXRaise; the final system-wide AX focused application, app focused window, native key window, geometry and display checks remain required after raising. Read-order diagnostics showed that the premature system-wide query could fail immediately even while those activation signals agreed. No private focus shortcut, fixed delay or fixture-side focus command was used.

Both final toolchain checks exited 0: pinned Nix and Xcode each ran 79 Swift tests in 17 suites and 36 Python tooling tests. Scoped source reviews passed, including failure-category preservation; the cumulative focus diagnostic remains exploratory evidence rather than standalone action proof. The release artifacts were signed with the approved local test identity. Their strict signatures and the restored host keychain search list were verified.

The prepared test VM was reopened with automatic display fitting; its actual backing scale remains 2×. The qualified signed probe/fixture were installed at the stable paths. Stop this interactive prepared VM before cloning it for automated runs. The earlier signing block cleared after normal host wake and approved keychain access; host lock settings were not changed.

Hosted qualification has not run. This passing local probe is partial environment qualification; daemon/watchdog recovery, AX stalls, installed-product behavior, input/capture, real integrations, physical hardware and optional host CI remain unqualified. A compiled private adapter is not proof of feasibility. The current implementation has no daemon/watchdog implementation and cannot establish app-stall/crash recovery. Installed startup, real integrations, hardware behavior and the optional idle controller remain separate work.

The setup preserves all product-document edits that existed before implementation. They remain outside foundation commits; repository hosting must include that documentation separately before CI can check it.

## Nix development tooling revision — 2026-10-11

In the first tooling revision, renamed the tooling directories to `tools/` and `e2e/`. Working-tree `nix run .#build`, `.#test`, and `.#stories` now enter the default pinned development shell; the former packaged catalog launcher is `.#stories-packaged`. `.envrc` loads that shell through direnv. Tart remains in the default development shell for interactive VM management. Only the VM app wrapper directly adds Tart as a runtime dependency.

- `nix flake check --print-build-logs`: exit 0; the source derivation built and assembled artifacts, passed 79 Swift Testing tests in 17 suites, and the tooling derivation passed 36 Python tests.
- `nix run .#test`: exit 0; 79 Swift tests, 36 Python tests, and working-tree documentation/DOT checks passed with pinned Swift 6.2.4/SDK 26.5. Cleared the previous Swift scratch build before switching from Xcode to the pinned compiler; initial attempts found mixed-toolchain manifest/linker failures.
- `nix run .#build`: exit 0; assembled the catalog, fixture app, and probe in `.local/build`.
- `nix run .#docs`: exit 0; links, anchors, product references, and DOT parsing passed.
- `nix run .#stories -- --help`: exit 0; verified entrypoint construction and argument forwarding. Catalog GUI launch and appearance were not reviewed for this tooling revision.
- `direnv exec .` verified existing pinned compiler/SDK paths and `SWIFT_EXEC`; `.envrc` was allowed locally, and `.direnv/` is ignored.

The original default shell could not load because an invalid leftover Tart store entry failed cleanup at `tart.app` with `Operation not permitted`. macOS logs showed an App Management authorization failure attributed to Determinate Nix's daemon. The user removed that invalid store entry using `sudo` and granted the Nix daemon App Management permission; Tart 2.37.0 subsequently ran successfully. This was a local environment repair, not a product or package patch. No VM or desktop-mutating qualification scenarios ran for this revision.

## Nix-owned tooling and VM specifications — 2026-10-11

The [approved design](2026-10-11-nix-tooling-design.md) replaces repository Python tooling and Python-specific tests with focused Nix modules. Nix declares native artifacts, metadata, image sources/settings, checks and command composition; generated Bash performs necessary runtime effects. The standalone Xcode build route is removed. Xcode remains a native editing/preview tool and separately provisioned future UI-test dependency.

Executed verification:

- `nix flake check --print-build-logs`: exit 0. Six check derivations cover the pinned source build (79 Swift Testing tests in 17 suites), artifact metadata/signing search-list restoration, artifact publication rollback, offline documentation validation, VM preparation state and interruption, and E2E wrapper isolation/metadata/deadlines/owned cleanup. Synthetic boundary tests do not establish macOS private-API or live VM feasibility.
- `nix run .#test`: exit 0, running 79 Swift tests, the Nix tooling checks and working-tree documentation checks. `nix run .#docs`: exit 0; local links/fragments, stable IDs and DOT syntax passed across 18 Markdown files before this verification-record update.
- `nix run .#build -- --configuration release --sign-identity -`: exit 0. Release bundles/probe assembled; `codesign --verify --strict` accepted all three ad-hoc signatures and `plutil -lint` accepted both app manifests. This does not establish persistent development grants or distribution identity.
- `nix run .#stories -- --configuration release --sign-identity -`: exit 0, built and opened the native catalog. This tooling change did not review component appearance.
- `direnv exec .` confirmed pinned Swift/swiftc, Tart 2.37.0, and `TART_HOME` pointing at this checkout's existing `.local/tart`.
- Real `vm-prepare clean` inventory/preflight refused the existing unmanaged image before cloning/downloading. Both pre-existing VM images were preserved. New managed preparation and the ported E2E wrappers were tested with synthetic boundaries; no new real image download or live E2E run occurred during this revision.

During investigation, initial filesystem-path flake evaluations attempted to import ignored `.local` data, including VM disks, and were interrupted. One returned an unsupported `control.sock` type error. Subsequent evaluations exclusively used Git-backed sources. The disk audit found no retained imported `.local/tart` store source, only the original clean/prepared images, and approximately 69 GiB free at final checks. No broad garbage collection or VM deletion was performed. Avoid `path:.` and plain filesystem `builtins.getFlake` calls against this checkout.

The native daemon, integrations and recovery/release gates remain unimplemented or separately unqualified as described above. No new product/backend capability is claimed by this tooling port.

## Canonical names and existing-image adoption — 2026-10-11

The workflow is now CI (`.github/workflows/ci.yml`), the Nix package is `stratosphere-0.1.0` exposed as `packages.aarch64-darwin.stratosphere` and `default`, the package implementation at that revision was `nix/package.nix` (now `nix/features/package/package.nix`), this current record is `development-verification.md`, and the catalog story-list heading is STORIES. Historical dated foundation documents and Apple Foundation imports/framework declarations remain unchanged.

- Adoption behavioral checks passed for matching provenance/settings, preservation of an existing disk/configuration, refusal of a mismatched source or changed configuration, and subsequent normal reuse.
- Both real existing images were adopted from `.local/vm-preparation/preparation.json`. The declared clean profile preserves 1280×800 pixels with display refitting off; prepared preserves 1280×800 points with refitting on. Both use four CPUs and 4096 MiB RAM.
- Configuration SHA-256 checks before/after adoption matched for both images. Subsequent `vm-prepare clean` and `vm-prepare prepared` reported reuse. No download, clone, guest mutation or new permission qualification occurred.
- `nix flake check --print-build-logs`: exit 0 after the renames/adoption changes, including the source build and all 79 Swift tests. The catalog caption change compiled with the shared production catalog; its appearance was not separately inspected for this caption-only revision.

The explicit adoption command writes the Nix specification receipt after validating recorded source/storage identity and observed Tart settings. It trusts the original source record; it does not attest the full contents of a mutated VM disk. Prior live permission/GUI qualification remains recorded separately. Fully automated guest provisioning/permissions is not implemented by this revision.

## Declarative guest provisioning — 2026-10-11

The user authorized Nix-owned guest provisioning excluding MDM and permission management. The [design](2026-10-11-vm-provisioning-design.md) and [plan](2026-10-11-vm-provisioning-plan.md) record the scope. The public command is `nix run .#vm-provisioning -- prepared`; image-only setup/adoption is an internal step. Active data moved from `.local/vm-preparation` to `.local/vm-provisioning`, the source record is `provisioning.json`, and image/guest receipts use `$TART_HOME/stratosphere-provisioning/`. Original historical commands above retain their original names.

Nix declares the existing image-provided admin account/home/shell, its authorized public key, automatic login target, no idle screensaver, and no idle sleep/display sleep. The generated guest script rejects physical-host execution before mutations, preserves unrelated/restricted SSH keys and existing passwords, and verifies native command readbacks. No guest Nix, Xcode, SDK or extra guest agent is installed. No Gatekeeper, SIP, TCC, Accessibility or MDM configuration is changed.

Executed evidence:

- Guest native-boundary checks passed for physical-host refusal, account/shell/key ownership/modes, preservation of unrelated/restricted keys, duplicate-key identity normalization, authenticated autologin failure/readback, no secret output, and every power profile.
- Host-controller checks passed for repeatable setup, dedicated-key-only authentication, failed guest/GUI stages, failed VM launch without stopping another boot, forced owned cleanup after stop failure, and truthful failure evidence when receipt persistence is denied. Prior success records survive failed provisioning.
- Real provisioning completed three times on the retained prepared image. First run: `.local/vm-provisioning/runs/2f9350ba085df217ef3d6d576186cf1f`; final-script runs: `19ce7c2d7ab3828a4f5c9ce7e0d81f41` and `4310ad195d7b6c23266268029393be9b`. Each returned exit 0, verified key-based SSH plus the actual console user's GUI launch domain, and stopped its owned VM boot. The final recipe receipt reports `passed`, admin automatic login, `/Users/admin`, `/bin/zsh`, zero screensaver/sleep/display-sleep timers, and permissions `not-managed`.
- The final recipe repeated successfully after key identity normalization. It reused the existing dedicated private key and the adopted image; no new image download or clone occurred, and the removed clean image stayed absent.
- `nix flake check --print-build-logs`: exit 0 with the new image and provisioning checks; the unchanged pinned source build remains the previously verified 79 Swift tests. The final read-only review has no remaining material findings.

This verifies provisioning on the retained macOS template, not a fresh image rebuild or new permission qualification. Bootstrap password fallback and actual changes from disabled autologin were covered through synthetic/native-helper checks and documented upstream contracts; the retained template already supplied SSH and automatic login. Signing/Accessibility qualification and installed-product/recovery gates remain separate.

## Project formatting and Nix-owned CI — 2026-10-11

Implemented the [approved design](2026-10-11-formatting-ci-design.md): pinned flake-parts/import-tree composition, a scoped `nix/modules` import tree, and treefmt-nix formatting through `nix fmt` and `nix run .#format`. Swift and swift-format both resolve to 6.2.4. Formatting covers Nix, Swift, the Objective-C bridge/header, Markdown/YAML/JSON, standalone shell scripts including `.envrc`, and TOML; mutable VM storage, caches and generated artifacts are excluded. Initial normalization changed 69 files. A pre-format snapshot and formatting-only patch are retained locally under `.local/formatting-ci`; existing staged contents were verified unchanged. No UI behavior or diagram layout changes were intended or visually qualified.

GitHub Actions now calls `ci-check`, `ci-environment` and `ci-probes`. Runner policy, events, timeouts, permissions and artifact uploads remain workflow concerns. `ci-check` explicitly realizes all 11 declared check outputs, including actual source-snapshot documentation validation separate from validator fixtures. The hosted probe command checks its environment before release build/signing or probe execution. No additional task runner or dispatcher was introduced.

Executed verification:

- `nix run .#ci-check`: exit 0. The normalized release source built freshly and passed all 79 Swift Testing tests in 17 suites. Source-snapshot documentation and formatting checks executed; the six existing tooling checks reused their cached outputs. New formatter and CI boundary checks were separately built and passed.
- `nix run .#test`: exit 0; the normalized working tree rebuilt with the pinned tools and passed all 79 Swift tests plus tooling dependencies and documentation validation.
- `nix flake check --print-build-logs`: exit 0. Final formatter fixtures and CI boundary checks executed, including build-failure propagation without launching the probe. Existing apps still produce their pre-existing missing-description warnings.
- `nix fmt -- --no-cache --fail-on-change`: exit 0 with zero changed files after normalization. Formatter fixtures cover every configured source type, hidden workflow files, `.envrc`, ignored nested VM/cache paths and preserved Markdown prose wrapping.
- Separate temporary Git-backed source snapshots with a broken Markdown link or an unformatted Nix file were both rejected by their actual documentation/formatting check derivations. The production checkout was not changed by these negative checks.
- `nix run .#docs`: exit 0; 22 Markdown files, local fragments/product references and DOT summaries passed.
- `nix run .#ci-environment`: exit 0, recording Xcode 26.6 (17F113), SDK 26.5 and macOS 26.5 (25F71). The actual `ci-probes` entrypoint rejected this host before runtime build/probe actions; synthetic checks also reject self-hosted runner signals.
- Read-only review found no substantive correctness issues. The final change was checked for whitespace errors and unnecessary glue.

Hosted qualification has not run. No live VM provisioning or desktop-mutating probe ran for this change. Cached wrapper checks and synthetic boundaries do not establish private-API, installed-product, permission-grant or recovery feasibility. The earlier qualification limits remain in force.

## Independent Nix feature modules — 2026-10-12

Completed the [feature-module split](2026-10-11-feature-modules-plan.md) approved on 2026-10-11. Removed `nix/modules/core.nix`. Toolchain, artifacts, source packaging, development, documentation, formatting, CI and VM images/guest/provisioning/E2E each register their own outputs. Constructors, tests and existing scripts are grouped under `nix/features/`; only `nix/modules/` is auto-imported. Shared implementation values use named per-system arguments. Features contribute the original six working-tree tooling checks through a typed internal option, without pulling snapshot checks into that command.

The development shell is constructed directly from the toolchain and tools, with no `overrideAttrs` composition. Provisioning receives the guest implementation explicitly. The existing transitive guest test is also exposed as `checks.aarch64-darwin.vm-guest`, making 12 public checks. Runtime scripts, pinned inputs, public command names, source filters and artifact paths retain their previous behavior. Current source packaging is `nix/features/package/package.nix`, with the matching SwiftPM helper at `nix/features/toolchain/swiftpm.nix`.

Executed verification:

- Captured and compared package/app/check store identities before and after the split. Both package outputs, the development shell, all runtime app paths except `ci-check`, and every existing build/tooling check are unchanged. `ci-check` changed only to include the newly exposed guest check; documentation and formatter snapshot derivations changed with the source tree. No existing outputs were removed.
- `nix run .#ci-check`: exit 0, realizing all 12 checks. Source-snapshot documentation and formatting checks executed; unchanged source-build and behavior outputs reused the previously verified cache.
- `nix run .#test`: exit 0. All 79 Swift Testing tests in 17 suites executed freshly using the directly composed shell; existing tooling outputs were reused, and working-tree documentation validation passed.
- `nix flake check --print-build-logs`: exit 0; output evaluation passed, with unchanged check outputs already available. Existing app-description and compiler-wrapper warnings remain unchanged.
- Documentation links were updated for relocated files. `nix run .#docs` validated 23 Markdown files, local fragments, stable IDs and all DOT summaries. Formatter checks reported zero changed files after formatting the new modules.
- Scoped read-only review found no material architecture/behavior issues. Historical/current path wording was clarified after review. Existing staged contents were verified unchanged, and whitespace checks passed.

No desktop-mutating probe, VM provisioning, hosted qualification or UI appearance review ran for this structural refactor. Existing environment/product qualification limits remain unchanged.

## Standalone runtime scripts — 2026-10-12

Implemented the [approved runtime extraction](2026-10-12-runtime-scripts-plan.md). Nix package constructors now declare dependencies, configuration and script packaging. Substantial production/test Bash lives in feature-local `.sh` files; documentation ID parsing is a separate AWK query, and VM inventory/adoption/metadata/launch-agent queries are named jq files. Shared development and E2E helpers stay in the caller’s process, preserving controller traps and owned state. Short derivation phases and wrappers/stubs remain inline.

Native product definitions generate an artifact manifest with app plists, executable names, signable/publication lists and optional resources. A shared packaged assembler serves both source and working-tree builds. VM profile selection consumes generated JSON instead of Nix-generated shell cases. The host provisioner receives fixed settings through generated data/environment paths, while credentials remain runtime files. The guest template retains `/bin/bash` and native paths, with a check rejecting host store references. Explicit E2E transport injection replaces the recursive package import and modified `pkgs`. Runtime scripts use pinned inputs or deliberate native macOS commands and receive Bash syntax/ShellCheck checks when packaged.

Concurrent app-icon work added the selected planet resource while assembly was being extracted. Both a special icon copy and the new generic resource copy initially ran, copying the read-only store file twice; the second overwrite failed with `Permission denied`. Removed the duplicate special copy, retaining the icon through the declarative resource manifest. Artifact tests verify the bundle icon key and bytes. Read-only copied test fixtures were made writable where scenarios deliberately replace or append to them.

Executed evidence:

- `nix run .#ci-check`: exit 0, realizing all 12 checks. Extracted artifact/signing restoration, publication rollback, docs-validator fixtures, VM image reuse/adoption/failure, portable guest behavior, provisioning cleanup/readiness, CI boundaries, formatter behavior and E2E interruption/deadline/metadata/owned-cleanup checks passed. The packaged source rebuilt, passed all 79 Swift tests in 17 suites, and completed installation with the icon.
- `nix run .#build -- --configuration release --sign-identity -`: exit 0. Working-tree assembly and ad-hoc signing passed; strict signature verification accepted both bundles and the probe, and the copied icon matched the selected source asset. No catalog GUI launch or appearance claim is implied by this check.
- `nix run .#test`: exit 0 through the extracted test script, with all 79 Swift tests and working-tree documentation validation.
- `nix flake check --print-build-logs`: exit 0. Final standard outputs evaluated and their declared checks were available; the explicit CI command established realization of every check. Existing compiler-wrapper/app-description and nested-Nix setting warnings remain separate from the resolved icon-copy failure.
- Formatting passed with zero changes after normalization. Documentation links/fragments/product IDs and DOT syntax passed across 24 Markdown files. Read-only review found no material extraction regressions, dependency cycles, guest runtime Nix dependency or import-from-derivation.
- Existing staged edits were preserved; concurrent user-owned icon assets were retained. Whitespace checks passed.

Synthetic fixtures establish controller/refactor behavior only. No live VM provisioning, hosted qualification, desktop-mutating probe or UI appearance review ran for this extraction. Existing product/integration/recovery qualification limits remain unchanged.
