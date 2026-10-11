# UI design and animation process

Agreed on 2026-10-08: use a Storybook-style native component catalog to develop and review Stratosphere's UI. Previewing and refining interactions is central to achieving a polished result.

This document governs the development workflow. [Product requirements](functional-requirements.md), [concepts](concepts.md), and [decisions](decision-map.md) remain authoritative for product behavior. The catalog is planned tooling, not existing infrastructure. Build targets, source layout, commands, dependencies, and implementation sequence remain for implementation planning.

## Native catalog

Use SwiftUI for interface components and motion, with AppKit where desktop panels, window behavior, and native integration require it. The catalog renders the same components as the production UI; improvements carry into the app without maintaining a second implementation.

Adopt Storybook's model of named, isolated examples rather than requiring the web Storybook runtime. The standalone native catalog is the main review surface. Xcode previews provide quick component-level iteration, drawing from the same story definitions and fixtures. Browser mockups may help compare early visual directions, but their materials and motion are approximations requiring native review.

Desktop-specific stories also run in actual native panels so placement, focus, dismissal, pointer transitions, and Liquid Glass can be judged in their intended environment.

## Story contents

A story describes:

- A stable name identifying the component or interaction and its scenario.
- Synthetic workspace, window, notification, or history data and an initial state.
- Relevant environment settings, such as dimensions, appearance, or accessibility preferences.
- Optional replay steps and expected visible outcomes and actions.

Use reproducible fixtures without live personal app data. Simulated daemon responses supply success, delay, failure, and partial-result cases. Record requested actions for inspection; production actions continue to use the public daemon API. The catalog must not introduce UI-owned domain behavior or settle unresolved transport details.

Stories cover individual components and complete user interactions. Representative examples include:

| Story                               | Review focus                                                                                                                    |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Rail / Compact / Busy               | Density, badges, selection, and long names.                                                                                     |
| Rail / Compact to Full              | Expansion, continuity, and interrupted motion.                                                                                  |
| Hover preview / Deep tree           | Arbitrary nesting, scrolling, pointer transitions, and passive inspection.                                                      |
| Overview / Timeline                 | Historical previews, actual timestamps, and explicit selective restore.                                                         |
| Layout / Free-centered drag         | Centering on show/resize/display placement; positional drag selects free, while resize/manager positioning preserves the group. |
| Operation / Partial failure         | Progress, truthful results, nonblocking status, and retry/resume behavior.                                                      |
| Operation / Permanent purge         | Explicit confirmation bound to daemon preflight.                                                                                |
| Operation / Overlap and stalled app | Pending requests, cancellation, replanning, and responsive unrelated work.                                                      |

Include empty, crowded, unavailable, and failure states where relevant. Display scenarios exercise one shared rail configuration, not per-display overrides.

## Review controls

The catalog provides a searchable story sidebar, an interactive canvas, controls for scenario inputs and appearance, and an action log. Animation scenarios support reset, replay, repeat, and slower playback, with tunable timing and spring parameters where applicable. Variants use the same scenario for meaningful comparison.

Define shared typography, spacing, icons, materials, selection treatment, and motion parameters. Changes to these shared choices should be reviewed across representative stories.

## Animation review

Review full interaction sequences, not only finished states. Important motion has a replayable scenario, including rapid input and interruption where applicable:

- Enter a hover target, then leave before its preview finishes appearing.
- Move from the rail into its preview and dismiss it through normal interaction.
- Reverse an expansion while it is in progress.
- Receive a state update or notification during a transition.
- Navigate repeatedly and verify that obsolete animations do not accumulate.

Prefer restrained, interruptible motion that communicates continuity. Functional actions should not wait for decorative animation to finish. Honor configured animation settings and review reduced-motion and reduced-transparency variants.

Workspace switching remains instant by default. Animating Stratosphere's own views does not establish the feasibility of animating external application windows; backend mechanisms require separate real-macOS validation. Numerical timing and performance budgets are not selected by this document.

## Development and verification

Every UI feature or behavior change arrives with representative stories. Every important animation arrives with a replayable interaction scenario. Update affected stories alongside the production component.

Use the stories to review design variants, refine the chosen interaction, and check regressions. Screenshot comparisons help detect appearance changes; interaction checks verify outcomes and requested actions; recordings and hands-on review assess motion. A screenshot alone cannot verify animation quality, focus behavior, or private-API feasibility.

Final review uses real supported macOS configurations, including relevant wallpapers, display scales and refresh rates, light/dark appearance, accessibility settings, and keyboard/pointer interaction. Record the scenario and environment when reporting verification. Simulated responses cannot establish integration or backend feasibility.

## Product trace

| Authority                                                                                                                                                                     | Constraint on stories and review                                                                                          |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| [C-11](concepts.md#c-11--rail-and-overview), [FR-41–FR-45](functional-requirements.md#rail-overview-and-appearance)                                                           | Shared rail configuration, passive interactive previews, whole-tree overview, and correct space reservation.              |
| [FR-38–FR-40](functional-requirements.md#history-and-undo)                                                                                                                    | Timeline inspection is separate from explicit restoration; Undo and interrupted-operation Resume have distinct semantics. |
| [FR-47](functional-requirements.md#rail-overview-and-appearance), [FR-63](functional-requirements.md#configuration-and-ricing)                                                | Restrained Liquid Glass, configurable motion, and instant switching by default.                                           |
| [FR-52–FR-55](functional-requirements.md#api-and-execution)                                                                                                                   | Thin-client actions, daemon preflight, progress, partial results, and explicit resume.                                    |
| [NFR-01](non-functional-requirements.md#nfr-01--platform-and-native-integration), [NFR-03](non-functional-requirements.md#nfr-03--ax-hang-containment-and-responsiveness)     | Native macOS presentation and responsive UI independent of stalled app calls.                                             |
| [NFR-09](non-functional-requirements.md#nfr-09--verification-and-compatibility-lifecycle), [NFR-10](non-functional-requirements.md#nfr-10--documentation-and-maintainability) | Real-OS verification, synthetic deterministic data, and distinct UI/domain responsibilities.                              |
