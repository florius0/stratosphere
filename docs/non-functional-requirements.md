# Non-functional requirements

See [functional requirements](functional-requirements.md), [decision map](decision-map.md), and [overview](overview.md). Numerical performance budgets not explicitly agreed are open, not inferred from the word “instant.”

## NFR-01 — Platform and native integration

Target macOS 26+ and Apple Silicon only, in Swift. Use Nix for reproducible builds and native Home Manager configuration. Core window/workspace behavior must operate with SIP enabled. Private APIs are permitted throughout the product; optional ricing may have different SIP requirements. Liquid Glass/native macOS presentation is the default.

Backend selection is a developer compile-time decision, based on feasibility. macOS compatibility is validated in development/release lifecycle, not through an automatic runtime feature-disable policy. Basic permission/error diagnostics remain required and are not the same as adaptive OS compatibility handling (FR-67, FR-71).

## NFR-02 — Shared-state consistency and execution

Use globally ordered planning/commits for mutable authoritative state and per-client action sequencing. External AX, integration, and shell work must not hold the global mutation queue. Revalidate relevant state before issuing side effects and committing asynchronous results; record actual effects even when intent has become stale, then replan instead of adopting stale results as current state. Never assume app side effects are transactional or rollback-capable.

Only concrete conflicting app-effect steps or steps awaiting a required live-window identity wait/replan. Pending operations/launchers do not lock whole workspaces/windows; other clients, including CLI processes invoked by shells, retain their own sequencing and may plan/commit state through the short mutation queue. Later correlation and placement use current ownership/state. Valid external edits supersede unissued conflicting work; newer genuine app activity supersedes pending reconciliation for the affected item, without treating manager-generated events as new activity (FR-57, FR-75–FR-77). Coordination and attribution mechanisms remain open (Q-13).

Navigation/resizing must not accumulate unbounded hotkey-repeat work. Fine-grained resource locks are deferred until measured need; client execution queues do not imply concurrent unsynchronized state mutation (D-18).

## NFR-03 — AX hang containment and responsiveness

Use dedicated per-application AX threads/run loops as baseline, following AeroSpace's actual model. Confine that app's AX objects, operations, and subscriptions to its worker. Blocking app calls must not freeze daemon/UI/recovery heartbeat or healthy-app work. Cooperative cancellation is not assumed to interrupt an in-flight AX call.

Switching proceeds for responsive apps while affected stalled windows may temporarily remain visible with diagnostics and later retries. Test hang scenarios; add restartable helper-process isolation only if evidence requires it. Per-window threads are not a requirement. Instant/no-animation switching is the default, with configurable animation; latency targets need definition (Q-05).

Side-effect steps blocked by stalled app work expose nonblocking status and cancellation, then replan when the app responds; other clients' planning/state commits continue (FR-78). Routine operations must not acquire modal confirmation gates because of documented fidelity limits; preflight and required persistence still precede unsafe effects (FR-54).

## NFR-04 — Crash and hang recovery

Recovery must not depend on the failed daemon or rail. Persist recovery baseline before moving/hiding managed windows. Independent monitoring handles unexpected exit and heartbeat stalls, restores surviving window geometry and Dock settings first, then bounded restart. Preserve explicit shutdown intent so watchdogs do not restart intentionally stopped components.

“Immediate” recovery is required behavior, but numerical detection/recovery bounds and guarantees when the target app's AX service itself is hung remain research questions. The rail watchdog must coexist with manager recovery without restart races (FR-64–FR-66, Q-04).

## NFR-05 — Durability and storage safety

Persist versioned readable JSON and durable UUIDs; external name-based paths are intentionally part of the interface. Use atomic replacement for individual daemon-written files and recoverable intent/progress records for multi-file/external operations. Preserve pre-operation history, partial completion, and captured state. Storage errors must not turn unavailable state into empty state or permit unsafe closure.

Accept valid external replacements immediately without CAS/approval workflows, applying overlap and activity precedence under FR-76–FR-77. Preserve malformed evidence and last readable state. Safely distinguish own writes, external replacement, rename/move, deletion, and copy. Backup restoration can involve temporarily incomplete trees; debounce/reconciliation details must be specified before implementation (Q-09).

History and Undo survive restart within retention and are included in portable workspace backups (FR-34). Retained snapshots and eligible Undo must keep their required restoration references complete, including references whose independent item retention has expired or whose Trash entry has been purged (FR-12, FR-37). Cleanup must respect current reference/retention state and reclaim only unreferenced semantic data; purge must not leave retained snapshots incomplete. Revalidate restored Undo availability rather than assuming every backed-up record is executable. Notification view and previews are separate from semantic history/backups; live-window handles must never become durable identity.

## NFR-06 — Isolation and degradation

An unavailable integration/window, corrupt state document, missing optional permission, or partial operation failure must not stop unrelated workspaces. Report truthful fidelity and typed/structured failures rather than success with empty results. Preserve integration-owned payloads during generic fallback.

Unexpected failures stop affected unsafe steps and expose nonblocking status with Retry or an explicit recovery action; they do not automatically open confirmation dialogs. Required capture/persistence and identity checks cannot be bypassed to keep an operation moving. Documented integration limitations are accepted during normal use (FR-54).

Core Accessibility loss leaves diagnostics available and stops mutations. Persistence failure permits only safe operations not needing new records. App crashes mean user-closed windows, not supervision/relaunch. Failed application actions do not justify force-killing apps.

## NFR-07 — Local interface and privacy

Restrict Unix socket access to current user; verify client identity and keep runtime paths/private files appropriately protected. Specific framing, directory modes, handshake, event overflow, and protocol compatibility details require a fresh transport design rather than inheriting the experiment.

Keep notification content and screenshots in separate discoverable paths for Git/backup exclusion. Separation enables exclusion but is not encryption or automatic privacy. Default private/incognito capture is disabled. Read Apple's notification database without modifying it. Never interpret missing permission as an empty notification source and delete the cached view; mark it stale.

User-configured arbitrary Bash is an authorized local capability. Its environment, working directory, diagnostics, bounds, and restoration correlation contract need explicit specification. Do not silently replace it with an argv-only restriction (Q-08).

## NFR-08 — Distribution and identity

Distributed direct-download/Homebrew releases must be Developer ID signed and notarized with stable bundle identity. Validate private-API compatibility with distribution requirements. Official bundles are default for Nix; source builds use persistent local signing and do not inherit official notarization. Permission-grant survival across upgrades is required design intent.

Ship UI, daemon, CLI, and watchdogs/helpers in a self-contained app. Make CLI usable through all distribution channels. Upgrades preserve mutable data and recover desktop safely. Keep Nix-managed configuration/package paths separate from mutable workspace/runtime data.

## NFR-09 — Verification and compatibility lifecycle

Publish exact tested macOS and integration-app versions for each release. Verify real OS behavior for backend/import, private APIs, green-button interaction, gesture interception, native notification routing/replay, native tabs/full-screen, app-state capture, permission changes, and watchdog recovery. Mock tests alone cannot establish these contracts.

Deterministic model/protocol/storage tests should cover tree and binding invariants, selection and order snapshots, merge precedence, lifecycle/minimization, file events, internal preflight, purge-consent freshness, overlapping operations, superseded intent, genuine versus manager-generated activity, partial operations, restart/Undo, and integration failures. Do not require real personal app data in deterministic tests. Reliable ChatGPT conversation/draft restoration is a release gate; VS Code scope is intentionally revisitable.

## NFR-10 — Documentation and maintainability

Keep domain, layout engine, app integrations, OS/backend mechanisms, persistence, API, and UI responsibilities distinct. Isolate private/version-specific mechanisms behind internal adapters; this does not create a third-party plugin contract or runtime compatibility auto-disable requirement.

Update requirements/decisions/concepts and their DOT summaries when behavior changes. Preserve stable IDs and explicitly record revisions to prior decisions. Implementation plans must cite affected requirements and unresolved feasibility. No feature can be claimed complete from an unsupported private symbol or an unvalidated screenshot alone.
