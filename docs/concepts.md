# Concepts

See [overview](overview.md) for authority and [functional requirements](functional-requirements.md) for behavior. [concepts.dot](concepts.dot) summarizes these relationships.

## C-01 — Workspace tree

A workspace is a durable, UUID-identified node with a display name, optional monitor binding, sibling ordering metadata, saved selection, and retained state. Nesting depth is not fixed at two. A **leaf** has no workspace children; a **parent** has children. Leaf/parent status is derived from tree structure, never an independently stored type. A top-level workspace is commonly called a **project**, but uses the same node model.

Only leaves directly own windows. Adding children to a populated leaf wraps its windows and layout into a generated child, transfers its saved monitor binding to that child, and leaves the original node as an unbound parent. The resulting parent can subsequently be explicitly bound. Removing the last child leaves an empty leaf by definition. The generated-child naming policy is not yet specified.

Names are Unicode-normalized and case-insensitively unique among siblings. Different projects can each contain `Development`. Name-based directories mirror hierarchy; UUIDs preserve identity through rename and reparenting.

## C-02 — Display binding and effective placement

Any workspace may bind to a physical display, symbolic `main`, or no display. Normally monitor bindings belong to leaves; parents remain unbound, with explicit parent bindings available as a grouping override. Defaults: leaves bind to `main`; parents are unbound. `main` follows macOS main-display settings. Unresolved physical bindings resolve to the main display without erasing the saved binding.

Resolve activation bindings from the explicit focus target downward: a bound node overrides descendant bindings for that activation; an unbound node does not. Ancestor overrides from an earlier activation do not persist over later direct focus of a descendant. Direct focus uses the target's own saved binding and resolves its subtree afresh. For example, activating a left-bound parent places its right-bound child on the left, while later directly focusing that child uses the right monitor. Only the explicitly focused node determines switching scope. Resolving children does not recursively trigger new switching operations. A leaf resolves to itself for child selection.

## C-03 — Visible scope and selection

The **visible scope** is the subtree currently eligible for display; the **active project** is its top-level ancestor. At most one leaf is visible per display. An unbound focus target replaces the global visible scope with its subtree and blanks displays that have no selected leaf. An unbound leaf appears on the main display and blanks the others.

A bound target switches its monitor within the current hierarchy. Focusing outside the current project first activates the target project. Focusing outside a narrower visible scope but inside the project expands the scope to the lowest common ancestor; compatible selections on other displays remain visible. This prevents simultaneous unrelated top-level hierarchies.

Moving the active project itself beneath an unarchived destination preserves its current visible scope and focus, while its new top-level ancestor becomes the active project; the destination's other branches are not revealed (FR-13). Archived sources/destinations reject reparenting until explicitly unarchived (FR-12). Successfully merging the active project into another destination follows the previously focused window, or its absorbing destination window, into that destination; if unavailable, use the destination's selection/focus fallback (FR-24).

Each ancestor remembers selected descendant leaves per display and its last focused descendant window. Selection fallback is remembered selection, descendant recency, then child order. Archived subtrees are ineligible. Display-fallback collisions use the most recently focused leaf.

## C-04 — Window identity and application context

A durable **managed window** represents saved application context, membership, history, and placement. It has exactly one leaf owner. A live macOS window handle is an ephemeral binding, not durable identity.

For single-window apps, separate managed contexts belong to individual leaves, including different leaves within the same project. Multiple contexts can share one live window over time, but only one context per app is live. When multiple visible leaves request that app's contexts, focusing a leaf requests its context even if another app receives keyboard focus; the swap must not steal that focus. Other simultaneously requested contexts are unavailable placeholders. An integration captures outgoing state and restores incoming state. This is context switching, not generic window cloning.

A native macOS tab group is one managed window and one layout slot. Its tabs can appear as presentation children. Browser tabs, native window tabs, and i3 tabbed containers are distinct concepts.

## C-05 — Lifecycle and presence

**Visible/hidden** describes presentation; **loaded** describes live resources; **closed** records closure. Hiding leaves resources loaded. Automatic unloading is excluded. Workspace close recursively captures/releases resources; focus/open restores only leaves selected to become visible.

Directly closing a window, including through app termination or crash, records it as closed. It remains closed during workspace reopening until explicitly reopened. Windows released by workspace closure are eligible for restoration when their leaf is selected. Minimized windows remain open but do not consume a tile; selecting them restores them. Archive excludes a closed subtree from ordinary navigation until explicitly restored. Trash is recoverable deletion, with a 30-day default retention.

An archived subtree is sealed for operational interaction until explicitly unarchived. Workspace/window transfers in or out, reparenting an archived node, merge, and app-state restoration are rejected before side effects with an unarchive-required result. There is no implicit unarchive or close-and-insert path. Passive inspection, history preview, and backup remain available (FR-12–FR-14).

Permanent purge removes a Trash entry and unreferenced semantic data. Data still required by current state, retained snapshots, or eligible Undo survives under its existing retention rules, including pinned snapshots; history/Undo may therefore still restore the item within declared fidelity. Purge preflight makes that scope explicit. Erasing retained history would require a separately specified explicit action (FR-12, FR-37, FR-54).

## C-06 — Layout groups and engine state

Layout groups are leaf properties, not nodes in the workspace hierarchy. A leaf has one tiled group using BSP or i3-like, plus free and free-centered groups. Each window belongs to one group. Engine-specific trees reference window IDs and do not own semantic membership.

The leaf coordinator allocates display space; the tiled engine arranges its windows and floating groups overlay it. Switching BSP/i3 affects the whole tiled group and retains engine-specific state. The i3-like engine supports horizontal/vertical splits, tabbed containers, and stacked containers. Headers are configurable.

Free preserves manual window placement. While in free-centered, a window stays centered within usable display space when shown, resized, or placed on another display. A deliberate positional drag switches it to free and preserves the position the user chose. Position changes accompanying resize or Stratosphere's centering do not trigger that switch. Making a tiled window floating still requires an explicit action/modifier (FR-15, FR-17).

Native full-screen preserves leaf ownership and mode across workspace switches. Presenting the window again keeps it in native full-screen; normal focus/selection still chooses which window is presented. Explicit full-screen exit restores the prior group. Backend mechanisms, especially virtual-backend coexistence with native Spaces, require validation (FR-20, Q-01).

## C-07 — Integration and fidelity

An **integration** owns app-specific capture, restoration, matching, compatible merge, independent cloning where supported, presentation children, and actions. Initial integrations are built-in only. Generic macOS behavior can provide focus/geometry fallback without replacing richer saved payloads.

Fidelity is declared per window: **reliable**, **best effort**, or **unavailable**. Integration evidence decides safe matches and merge compatibility. Ambiguous matches require explicit resolution unless independent restoration is supported. Fidelity is a stated guarantee for captured fields, not a promise to reproduce process memory.

Brief integration documentation explains restoration limits. Normal use accepts those limits, including best-effort/unavailable restoration, without confirmation prompts. History/Undo protects structural changes where supported; saved app state restores only the integration's declared fields. Unexpected capture/restoration failures stop affected unsafe steps and expose nonblocking status with Retry or an explicit recovery action (FR-54).

## C-08 — Current state, history, and previews

**Current state** follows ordinary user/application activity. **History** contains immutable snapshots at meaningful boundaries. Workspace snapshots include subtree structure, layouts, and window-state references; window snapshots can be restored individually.

Valid external edits immediately become desired state and supersede conflicting operation steps not yet issued. Newer genuine user/app activity supersedes pending reconciliation for the affected item while unrelated reconciliation continues. Events caused by Stratosphere itself do not count as new activity. Already-issued effects remain recorded; reconciliation follows the latest desired state (FR-76–FR-77).

The overview timeline reconstructs a preview from each item's latest snapshot at or before a selected time; it is not an atomic global checkpoint. Restoration is selective and explicit. Screenshots are separate persisted preview assets, enabled by default except for private windows. They are not restoration state.

Individual window restoration keeps its managed identity and current leaf owner while restoring captured state in that leaf; structural Undo handles its own transfer. Subtree restoration preserves the selected node's own identity/name/parent. Captured descendants moved elsewhere and captured windows transferred to other leaves return as their original identities with UUID/history and restore captured contents, subject to safe integration matching/restoration. Affected archived sources/destinations require explicit Unarchive before restoration or transfer steps (FR-12). Unrelated contents at former locations remain untouched; before-state includes original placement/ownership and state for structural Undo (FR-23, FR-39).

Portable workspace backups include retained semantic history and structural Undo with required state references (FR-34). Retained snapshots, including pinned workspace snapshots, and eligible Undo remain complete under retention: referenced state required for restoration must survive expiry of its independent item history and purge of its Trash entry. Purge/cleanup may reclaim data only after all current-state, retained-snapshot, and eligible-Undo references to it are released (FR-37). This preserves captured fields, not state outside the integration's declared guarantees.

## C-09 — Operation, preflight, and action

An **operation** is durable daemon-owned work with an ID, progress, partial results, and retry/resume. It survives client disconnection. Crash-interrupted work requires explicit resumption.

A **preflight** internally identifies affected resources, checks invariants and required capture/persistence, and preserves before-state before side effects. Ordinary actions proceed within documented integration limits without confirmation. Permanent purge requires explicit confirmation bound to a daemon preflight token; changed affected state/risks require fresh consent. Explicit force accepts current purge risks but cannot bypass invariants or required durability checks. External state edits reconcile without confirmation (FR-54).

Overlap waiting applies to concrete conflicting side-effect steps or steps requiring an unidentified live window. A pending operation/launcher does not lock a whole workspace/window: other clients may plan and commit state through the short mutation queue. Waiting steps replan against latest state; for example, live-window correlation after launch uses the window's current leaf owner. A stalled call leaves dependent steps pending with visible blocked status and cancellation. App recovery replans those steps; daemon-crash interruption requires explicit Resume (FR-75–FR-78). Coordination mechanisms remain open (Q-13).

An **action** is executable configuration shared by hooks, hotkeys, and launchers. Its shell form requires `shell`, with optional `name` and `async` (default false), matching FR-59. Per-client execution queues preserve sequences; a CLI process invoked by a shell has its own client queue. Globally ordered mutation commits protect shared state. External work does not hold the mutation queue.

## C-10 — Workspace order

Sibling lists place pinned nodes first in manual order, then unpinned nodes by recency. Focusing a leaf updates recency along its ancestor path. Presentation ordering never changes parentage.

`WorkspaceOrder(w)` is a circular traversal of eligible leaves respecting those sibling lists, excluding `w` when it is a leaf. For a parent it begins after the entire subtree and includes that subtree's leaves after wrapping. Navigation uses a stable snapshot for its sequence. Post-close fallback additionally excludes the closed subtree.

## C-11 — Rail and overview

The **rail** is a thin daemon client replacing the Dock. It shows global launchers, workspace tree, windows, integration children, notification attribution, separators, filesystem stacks, and launcher folders. Each display shows a rail with shared configuration and highlights its visible leaf. There are no per-display configuration overrides.

The **overview** replaces the Mission Control interaction with the entire logical tree and history timeline. A compact rail hover opens an interactive tree preview; preview alone never focuses, restores, or changes recency.

## C-12 — Notification materialized view

The rail's notification store is a separately persisted materialized view of Apple's retained notifications. It mirrors source removals and is stale when source access is unavailable. Attribution maps notifications to saved/live windows and workspaces; ambiguity falls back to the app's most recently focused window. The app's actual chosen window wins on activation.

Notification content, click observation, and action replay are separate capabilities. Database observation does not by itself establish click semantics or a callable original action.

## C-13 — Recovery and compatibility

Recovery records preserve pre-management geometry and first-observed geometry for later windows. A watchdog restores surviving windows and Dock settings after manager crash/hang, without undoing deliberate app changes or recreating closed windows. A rail watchdog restarts enabled UI independently.

Backend selection and supported private mechanisms are compile-time/development decisions. Releases publish tested macOS/app versions; no runtime private-feature auto-disable policy is specified.
