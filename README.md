# Stratosphere

A native macOS window manager and persistent project-context manager. Product authority starts at [the overview](docs/overview.md).

This checkout contains the initial development foundation: a workspace domain model, shared native UI components and story catalog, build/bundle tooling, and isolated-environment probes. It does not yet contain a working window-management daemon, public socket API, persistence engine, integrations, or recovery watchdogs.

## Development

Requires Apple Silicon and macOS 26+. The Nix lockfile pins Swift 6.2.4, SDK 26.5, Python, Graphviz and Tart. Xcode supplies native IDE/previews and the separate Apple-toolchain development build.

```sh
nix develop
python3 Tools/build.py test
python3 Tools/build.py build
python3 Tools/build.py stories
```

The development shell selects the pinned Swift compiler/SDK. Outside that shell, these Python commands select the active Xcode toolchain and verify Swift 6+/SDK 26+. Both routes use the same package and bundle assembler. Outputs and caches stay in `.local/`.

```sh
nix flake check
nix run .#docs
nix build .#foundation
nix run .#stories
```

The source derivation builds and tests the package with pinned tools. `result/Applications` contains the catalog, fixture app and native probe. These are foundation artifacts, not a signed distribution of the complete product. `nix run .#build` and `nix run .#test` use the external Xcode development toolchain; use `nix build`/`nix flake check` for pinned source evidence.

The flake also builds SwiftPM's matching upstream macOS test-bundle helper, which the pinned nixpkgs package omits. The deterministic suite uses Swift Testing; future XCTest/XCUITest suites use separately provisioned Xcode.

Nix's Git-flake source includes tracked files. Include the pre-existing untracked product docs in your own documentation commit before using a fresh checkout or CI. The setup commits preserve their original edits. `nix run .#docs` checks the current working tree's links, anchors, product IDs and DOT summaries.

## Native stories

Open the package in Xcode for editing and previews, or launch the standalone catalog. It includes busy rails, a deep hover preview, partial failure, and interruptible expansion. The components and fixtures are shared. Actions are logged rather than sent to a live manager. The hover story includes actual nonactivating native panels.

Stories and deterministic tests can run on the host user's desktop. Desktop-mutating probes cannot.

## Isolated macOS qualification

```sh
nix run .#e2e-vm -- --image stratosphere-prepared \
  --artifacts .local/build \
  --ssh-key /absolute/path/to/test-vm-key
```

This requires a prepared, stopped local Tart image with automatic GUI login, dedicated SSH access, and qualified AX permissions. See [environment preparation](docs/implementation/environment-setup.md). The wrapper never downloads an image implicitly, clones before running, executes in the test VM's GUI launch domain, collects results, and discards only its own clone.

Build `.local/build` with your persistent signing identity for this prepared test VM route. Without `--artifacts`, the Nix entrypoints use the unsigned store build, which needs its own qualified controlled-launch permissions; it cannot establish persistent development-grant survival.

The native entrypoint also runs directly on GitHub-hosted macOS runners:

```sh
python3 E2E/native.py --profile hosted
```

It verifies the hosted context, and both entrypoints fail visibly for missing prerequisites. The [foundation workflow](.github/workflows/foundation.yml) runs deterministic checks and environment probes; it has not run until repository hosting is configured. Environment probes are partial infrastructure qualification, not daemon E2E.

Every invocation requires a new output directory. `run.json` records the current wrapper outcome; `qualification.json` exists only when the actual probe produced evidence. Reusing a directory is refused so an old passing result cannot stand in for a new run.

## Design and evidence

- [Approved foundation design](docs/implementation/2026-10-09-foundation-design.md)
- [Implementation plan](docs/implementation/2026-10-09-foundation-plan.md)
- [Verification record](docs/implementation/foundation-verification.md)
- [Agreed testing approach](docs/testing-approach.md)
- [Native design process](docs/design-process.md)
