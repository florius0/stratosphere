# Foundation verification

Evidence is recorded for this setup on 2026-10-09. Product behavior and release evidence remain governed by [the testing approach](../testing-approach.md).

## Environment

The development host reports macOS 26.5 (25F71), Apple Silicon, Xcode 26.6 (17F113), Apple Swift 6.3.3 and SDK 26.5; SIP is enabled. The pinned Nix environment resolves Swift 6.2.4, SDK 26.5 and Tart 2.37.0. Both toolchains were verified against the same package. No valid code-signing identities were available; development artifacts were ad-hoc signed for build inspection.

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

The pinned nixpkgs SwiftPM initially lacked the Darwin Swift Testing launcher. `nix/swiftpm.nix` builds the matching, unmodified upstream `Sources/swiftpm-testing-helper/Entrypoint.swift` from SwiftPM 6.2.4 and includes it with that package. The suites explicitly disable XCTest because they use Swift Testing; future XCTest/XCUITest requires separately provisioned Xcode. Xcode-only preview macros were replaced with shared `PreviewProvider` definitions. Nix's Clang wrapper still emits target/minimum-version warnings for SwiftPM invocations; the native products' observed deployment metadata meets the 26.0 floor.

## Not yet qualified

Initial setup had no test VM image, SSH key or signing identity. After the host user freed storage and approved a dedicated test identity, the following preparation was executed on 2026-10-09:

- Downloaded the official macOS 26.5 vanilla image pinned to `sha256:e12d678b248f3122e276fa64632970a8e1c6dc60ff6738d21fe9bfa5ea58f426` into `.local/tart`. Its reported disk capacity is 50 GB, with about 27 GB in the base image; APFS clones share unchanged data.
- Booted a prepared clone with four CPUs, 4096 MiB RAM, a fixed 1280×800 display and display refitting disabled. Actual observations: macOS 26.5, build 25F71, VirtualMac2,1, arm64, SIP enabled and active GUI login UID 501.
- Verified dedicated-key SSH access for test VM user `admin`; only the public SSH key was installed in the test VM. The host user's home and signing keys were not mounted or copied.
- Re-enabled Gatekeeper in the prepared test VM; the vendor image initially reported assessments disabled. The host's Gatekeeper settings were not changed.
- Created the approved local test signing identity in `.local/signing/test.keychain-db`, with host-user trust limited to code signing. Signed all three artifacts and verified their signatures. The host user's original keychain search list was restored. This is development signing, not Developer ID/notarized distribution.
- The Nix-managed Tart bundle could not be materialized because of a store permissions error. For this preparation, the official Tart 2.37.0 archive was extracted under `.local/tools`; its SHA-256 exactly matched the pinned nixpkgs input. The same signed app bundle executable was used, without modifying host Nix permissions.
- A separate runtime inspection found no Xcode or Command Line Tools installation. The actual probe ran through the test VM user's GUI launch domain, observed an active console session and AX access denied, then returned `setup-failed` with no fixture/display observations. Accessibility approval is the current prerequisite; no private-display feasibility or grant-survival claim is made from this check.

The follow-up code removes developer-tool queries from the runtime probe, forwards bounded host build metadata, installs tools at stable paths across runs, and supports a separate signing keychain during builds. The metadata/stable-path reviews passed; 48 Swift tests and 34 Python tooling tests pass on the host after these changes. Local preparation, signing and permission-check evidence lives under `.local/vm-preparation` and `.local/signing` and is excluded from Git.

No Git remote is configured; the user will push manually. Hosted qualification has not run.

Actual test VM/hosted AX mutation, virtual-display topology/identity, permission-grant survival and desktop cleanup remain unqualified. A compiled private adapter is not proof of feasibility. The foundation has no daemon/watchdog implementation and cannot establish app-stall/crash recovery. Installed startup, real integrations, hardware behavior and the optional idle controller remain separate work.

The setup preserves all product-document edits that existed before implementation. They remain outside foundation commits; repository hosting must include that documentation separately before CI can check it.
