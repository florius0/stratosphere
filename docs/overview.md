# Stratosphere

Stratosphere is a standalone macOS window manager and persistent project-context manager. It combines an arbitrarily nested workspace tree, window layouts, application-state integrations, a Dock replacement rail, and a Mission Control replacement with history browsing.

The initial design was agreed through an interview completed on 2026-10-08. Subsequent agreed revisions are recorded in the decision map. This documentation describes the new product, not the earlier implementation experiment. Implementation planning is a separate task.

## Authority and document structure

These documents supersede the experimental implementation, its contract, handoffs, and mockups wherever they conflict. Existing source, if reintroduced, is evidence of mechanisms only, not product authority.

| Document                                                      | Purpose                                                                             |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| [Concepts](concepts.md)                                       | Domain vocabulary, relationships, and invariants (`C-*`).                           |
| [Concept diagram](concepts.dot)                               | Summarized domain relationships using the same concept IDs.                         |
| [Feature map](feature-map.md)                                 | Product capabilities, dependencies, and scope (`F-*`).                              |
| [Feature diagram](feature-map.dot)                            | Summarized capability/dependency map.                                               |
| [Functional requirements](functional-requirements.md)         | Observable behavior, including failure paths (`FR-*`).                              |
| [Non-functional requirements](non-functional-requirements.md) | Reliability, durability, platform, packaging, and execution constraints (`NFR-*`).  |
| [Decision map](decision-map.md)                               | Agreed decisions, rationale, consequences, and open questions (`D-*`, `Q-*`).       |
| [Decision diagram](decision-map.dot)                          | Decision dependencies and unresolved feasibility.                                   |
| [Design process](design-process.md)                           | Agreed UI development and animation-review workflow using a native story catalog.   |
| [Testing approach](testing-approach.md)                       | Agreed testing workflow for hosted CI, disposable local VMs, idle-time CI, and Nix. |

Markdown is authoritative. DOT diagrams summarize it and must not introduce requirements. IDs are stable: retain IDs when editing and do not reuse removed IDs. Cross-links name the relevant IDs. Requirements specify outcomes; decisions explain choices; concepts define terms; feature maps organize capabilities.

An **agreed** rule is product scope. A **proposed mechanism** is not an implementation commitment. An **open question** requires research or a later design decision. In particular, private-API availability is not proof that a normally signed process can invoke it with SIP enabled.

## Product scope

- Workspaces are arbitrary-depth tree nodes. Leaves own windows and app contexts; parents organize them. Monitor bindings normally belong to leaves; parents default to unbound and may be explicitly bound as a grouping override. Direct focus uses the target's binding; ancestor overrides apply during activation (D-03, FR-04).
- Hidden workspaces remain loaded. Manual recursive closure captures state; focus/open restores only selected visible leaves.
- Built-in integrations cover generic macOS windows, Safari, Chrome, VS Code, user-configured zmx/Ghostty launchers, and ChatGPT leaf contexts. Single-window apps keep separate contexts per leaf with one live per app; the focused leaf wins among visible contexts without stealing keyboard focus (D-12, FR-29).
- A Liquid Glass rail provides workspace navigation, notifications, application launchers, folders, and previews. A global overview provides tree navigation and selective history restoration.
- Every UI action uses the public daemon API and is available through CLI/IPC. Configuration is TOML with a native Nix Home Manager module and writable UI overrides.
- Ordinary actions run without confirmation prompts. The daemon preflights internally, captures before-state, and preserves history/Undo where supported. Documented integration limits are accepted during normal use; unexpected failures stop unsafe steps with nonblocking status and recovery actions. Permanent purge requires explicit confirmation (D-11, FR-54).
- State is readable JSON in a name-based filesystem tree. External edits, renames, moves, deletions, and copies have live semantics.
- Distribution includes a self-contained app with UI, daemon, CLI, and recovery helpers, plus direct-download, Homebrew, and Nix channels.

## Platform and feasibility

Target macOS 26+ on Apple Silicon only. Core behavior must work with SIP enabled. Private APIs are permitted. Native Spaces are preferred if they satisfy the requirements; otherwise use virtual workspaces. Developers choose the backend at compile time, not users.

Native Spaces discovery/control, native full-screen preservation/navigation (including the virtual backend), ChatGPT conversation and draft preservation, notification-action replay, green-button interaction, and AX-hang/recovery behavior require validation. See [open questions](decision-map.md#open-questions-and-proposed-mechanisms). Reliable ChatGPT context switching is an explicit release requirement. VS Code fidelity may be reduced after implementation research; CLI control is preferred.

## Explicit exclusions and deferrals

Automatic unloading, multiple tiled groups per leaf, third-party integration processes, runtime/user backend selection, competing-window-manager detection, and adaptive runtime handling of private-API breakage are outside initial scope. Fine-grained mutation locks are deferred until measurements justify them. A standalone shared/global-window exception was proposed but not accepted; single-window apps instead use saved leaf contexts.

No implementation roadmap is defined here. Numerical defaults and unresolved details must be checked against the decision map rather than inferred from examples.

## Command design

The [accepted command catalog](command-catalog.md) defines the resource-first CLI/action surface, selectors, arguments, defaults, results, and recovery paths (D-30, FR-79). It refines the product interface while preserving accepted invariants and unresolved mechanism/feasibility questions.

## Development workflow research

[E2E execution environment investigation](research/e2e-environment.md) records the evidence and feasibility limits behind the [agreed testing approach](testing-approach.md). The workflow is selected; macOS-specific mechanisms still require the documented acceptance checks before implementation relies on them.
