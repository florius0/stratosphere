# Stratosphere

A native macOS window manager and persistent project-context manager. Product authority starts at [the overview](docs/overview.md).

This checkout contains the current development implementation: a workspace domain model, shared native UI components and story catalog, build/bundle tooling, and isolated-environment probes. It does not yet contain a working window-management daemon, public socket API, persistence engine, integrations, or recovery watchdogs.

## Development

Requires Apple Silicon and macOS 26+. The Nix lockfile pins Swift 6.2.4, SDK 26.5, Graphviz, jq, documentation-checking tools and Tart. Xcode supplies native editing/previews and separately provisioned UI-testing tools.

Run these commands from the repository root; each selects the pinned Swift compiler and SDK without first entering a development shell:

```sh
nix run .#test                  # Swift + tooling behavior + documentation checks
nix run .#build                 # Build and assemble working-tree artifacts
nix run .#stories               # Rebuild and open the working-tree catalog
nix fmt                        # Format project sources and configuration
```

Outputs and caches stay in `.local/`. Pass helper options after `--`, for example `nix run .#build -- --configuration release`. For an existing identity in a separate keychain, add `--sign-identity NAME --sign-keychain /absolute/path/to/keychain`. The host user's original keychain search list is restored after signing. Identity creation, keychain unlocking and trust approval are separate setup actions.

For interactive development, use `nix develop` or enable direnv. Install direnv and optionally nix-direnv, enable the direnv hook in your shell (for zsh, `eval "$(direnv hook zsh)"` in `~/.zshrc`), then run `direnv allow` once in this checkout. The committed `.envrc` loads the default flake development shell automatically; `.direnv/` is ignored. nix-direnv adds caching for faster reloads. The default development shell also includes Tart for interactive VM management.

Nix is the tooling interface. Modules under `nix/` declare native artifacts, metadata, checks, VM specifications, and command composition. Nix packages feature-local `.sh` scripts for build, signing, launch and VM runtime effects. Static product/VM specifications and metadata stay in Nix; generated JSON and explicit runtime environment values connect them to the scripts. Xcode remains available for editing/previews; there is no separate Xcode build wrapper. Development caches are separated by the pinned compiler version.

Flake-parts composes automatically imported feature modules under `nix/modules/`. Each feature owns its app/package/check outputs: toolchain, artifacts, packaged source, development, documentation, formatting, CI, and VM images/guest/provisioning/E2E. There is no catch-all wiring module. Constructors, tests and existing scripts are grouped by feature under `nix/features/` and imported explicitly; they are never auto-imported as modules.

Shared implementation values use per-system module arguments (`toolchain`, `artifacts`, `docs`, `vmImages`, `vmGuest`), named explicitly by consuming modules. Features register their existing working-tree behavior checks through the internal `stratosphere.toolingChecks` option. This keeps `nix run .#test` separate from snapshot formatting/source checks; `ci-check` runs every public check, including the independently exposed VM guest check. The development shell is constructed directly from the shared toolchain, formatter and interactive tools. No separate task runner is required.

Runtime implementations live in each feature’s `scripts/` directory, with shared helpers scoped to development or E2E. Documentation queries live in `.awk` files; structured VM queries use `.jq` files. Behavioral tests and synthetic command fixtures live under `tests/`, with Nix declaring dependencies and check registration. Both packaged and working-tree builds use the same manifest-driven bundle assembler. The portable guest script is generated from its native template and requires no guest Nix installation.

`nix fmt` and `nix run .#format` use the same pinned treefmt configuration: nixfmt for Nix, swift-format for Swift, clang-format for the Objective-C bridge, Prettier for Markdown/YAML/JSON, shfmt for standalone shell files and `.envrc`, and Taplo for TOML. Markdown prose wrapping is preserved; DOT diagrams remain under documentation validation. Mutable `.local` VM storage, build caches and generated artifacts are excluded. `nix run .#format -- --no-cache --fail-on-change` checks the working tree; CI checks the Git-backed source snapshot without changing your checkout.

GitHub Actions supplies runners, checkout, Nix installation and artifact uploads; execution recipes live in Nix:

```sh
nix run .#ci-check              # All deterministic checks, including formatting and docs
nix run .#ci-environment        # Record Xcode/SDK/macOS evidence in .local/ci
nix run .#ci-probes             # Hosted-only build/signing and environment qualification
```

`ci-check` explicitly realizes every declared check output, including source build/tests, tooling behavior, formatting, and actual repository documentation/DOT checks. Documentation-validator fixture tests remain separate. `ci-probes` refuses physical-host and self-hosted execution before any build/probe action; use the explicit VM E2E command for local qualification.

```sh
nix flake check                # Pinned source build/tests + tooling behavior checks
nix run .#docs                 # Check working-tree documentation
nix build .#stratosphere       # Packaged development artifacts
nix run .#stories-packaged      # Open the Nix-built catalog
```

The source derivation builds and tests the package with pinned tools. `result/Applications` contains the catalog, fixture app and native probe. These are development artifacts, not a signed distribution of the complete product. The development commands operate on current working-tree files; `nix build`/`nix flake check` verify the flake source snapshot.

The flake also builds SwiftPM's matching upstream macOS test-bundle helper, which the pinned nixpkgs package omits. The deterministic suite uses Swift Testing; future XCTest/XCUITest suites use separately provisioned Xcode.

Use Git-backed flake commands from this checkout. Plain `path:.` references and `builtins.getFlake` filesystem paths can import ignored `.local` data, including large VM disks. Nix's Git-flake source includes tracked files. Include the pre-existing untracked product docs in your own documentation commit before using a fresh checkout or CI. The setup commits preserve their original edits. `nix run .#docs` checks the current working tree's links, anchors, product IDs and DOT summaries.

## Native stories

Open the package in Xcode for editing and previews, or launch the standalone catalog. It includes busy rails, a deep hover preview, partial failure, and interruptible expansion. The components and fixtures are shared. Actions are logged rather than sent to a live manager. The hover story includes actual nonactivating native panels.

Stories and deterministic tests can run on the host user's desktop. Desktop-mutating probes cannot.

## VM provisioning

[`nix/features/vm/images/package.nix`](nix/features/vm/images/package.nix) declares the digest-pinned macOS base image and profile settings. [`nix/features/vm/guest/package.nix`](nix/features/vm/guest/package.nix) declares guest settings, and [`nix/features/vm/provisioning/package.nix`](nix/features/vm/provisioning/package.nix) coordinates their application. Provisioning is explicit:

```sh
nix run .#vm-provisioning -- prepared
```

For a missing profile, Tart explicitly downloads and configures the declared image in `.local/tart`, or `TART_HOME`. The development shell and direnv select the same storage. Matching images are reused; unmanaged images, changed specifications, incomplete provisioning and stale locks require explicit resolution and are preserved.

The prepared profile boots the stopped managed image in place, configures its existing `admin` account, installs the dedicated SSH public key while retaining other keys, and sets SSH, automatic GUI login and idle settings. It verifies key-based SSH and the active console user's GUI domain, then stops its own boot. The pinned vanilla image supplies bootstrap SSH and passwordless sudo. No Nix, Xcode, SDK or guest agent is installed in the test VM. Provisioning does not reset passwords, create users, or change Gatekeeper, SIP, TCC or MDM settings.

Host data stays in `.local/vm-provisioning`: `test-vm-key` is reused or generated if missing, and `guest-password` initially contains the vendor's public bootstrap password. `STRATOSPHERE_SSH_KEY` and `STRATOSPHERE_VM_PASSWORD_FILE` select runtime files; private credentials stay outside the Nix store. Image receipts and successful guest receipts (`<image>.guest.json`) live under `$TART_HOME/stratosphere-provisioning/`; logs and results are separate per run.

Existing images can be adopted using their original source record:

```sh
nix run .#vm-provisioning -- --adopt prepared .local/vm-provisioning/provisioning.json
```

Adoption checks recorded source/storage and current CPU, memory and display settings, then writes the image receipt. It does not clone, download, change VM settings or provision the guest. The retained prepared image has passed guest provisioning. The local clean image was deleted; its optional declaration remains available through `nix run .#vm-provisioning -- clean` for future onboarding scenarios. That command downloads/configures the image only, and it never runs automatically. The clean profile uses fixed pixel sizing without display refitting; prepared uses point sizing with display refitting.

Guest provisioning establishes SSH and GUI readiness for the observed run. Persistent signing and Accessibility grants remain separate [environment setup](docs/implementation/environment-setup.md); provisioning does not establish new permission qualification. Entering direnv, running tests and E2E commands never provision images automatically.

## Isolated macOS qualification

```sh
nix run .#e2e-vm -- --profile prepared \
  --artifacts .local/build \
  --ssh-key /absolute/path/to/test-vm-key
```

This requires a prepared, stopped local Tart image with automatic GUI login, dedicated SSH access, and qualified AX permissions. See [environment provisioning](docs/implementation/environment-setup.md). The wrapper selects a stopped local image from the declared profile, never downloads images implicitly, clones before running, executes in the test VM's GUI launch domain, collects results, and discards only its own clone.

Build `.local/build` with your persistent signing identity for this prepared test VM route. The E2E entrypoints default to `.local/build`; `--artifacts` can select a different build explicitly. Use a persistent signing identity for permission-grant survival. Packaged unsigned artifacts need their own qualified controlled-launch permissions.

The initial test VM runs the host-built artifacts without Xcode, an SDK or Nix. Host build metadata is forwarded separately from the test VM's observed runtime OS. Tools use stable installation paths across clones; each run's evidence stays separate.

The native entrypoint also runs directly on GitHub-hosted macOS runners:

```sh
nix run .#e2e-native -- --profile hosted
```

It verifies the hosted context, and both entrypoints fail visibly for missing prerequisites. The [CI workflow](.github/workflows/ci.yml) runs deterministic checks and environment probes; it has not run until repository hosting is configured. Environment probes are partial infrastructure qualification, not daemon E2E.

Every invocation requires a new output directory. `run.json` records the current wrapper outcome; `qualification.json` exists only when the actual probe produced evidence. Reusing a directory is refused so an old passing result cannot stand in for a new run.

## Design and evidence

- [Approved foundation design](docs/implementation/2026-10-09-foundation-design.md)
- [Implementation plan](docs/implementation/2026-10-09-foundation-plan.md)
- [Nix tooling design](docs/implementation/2026-10-11-nix-tooling-design.md)
- [Verification record](docs/implementation/development-verification.md)
- [Agreed testing approach](docs/testing-approach.md)
- [Native design process](docs/design-process.md)
