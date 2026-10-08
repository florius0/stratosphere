import Foundation
import Testing
@testable import UI

@Suite("Catalog interaction state")
@MainActor
struct CatalogSessionTests {
    // Removing the distinction between hover inspection and explicit focus breaks these assertions.
    @Test func hoverIsPassiveAndCrossingIntoPreviewKeepsItVisible() {
        let session = CatalogSession(story: .deepPreview)
        let initialSelection = session.selectedWorkspace
        session.canvasHover.enter(.rail)
        #expect(session.canvasHover.visible)
        session.canvasHover.leave(.rail)
        let departure = session.canvasHover.generation
        session.canvasHover.enter(.preview)
        session.canvasHover.dismiss(generation: departure)
        #expect(session.canvasHover.visible)
        #expect(session.selectedWorkspace == initialSelection)
        #expect(session.actions.isEmpty)
        session.send(.focus("research"))
        #expect(session.actions == [.focus("research")])
        #expect(session.selectedWorkspace == "research")
    }

    @Test func pointerDepartureDismissesButNeverRequestsAnAction() {
        let session = CatalogSession(story: .deepPreview)
        session.canvasHover.enter(.rail)
        #expect(session.canvasHover.visible)
        session.canvasHover.leave(.rail)
        session.canvasHover.dismiss(generation: session.canvasHover.generation)
        #expect(!session.canvasHover.visible)
        #expect(session.actions.isEmpty)
    }

    // Retry must not imply all work completed or replay already successful steps.
    @Test func retryPreservesPartialResultUntilResponse() {
        let session = CatalogSession(story: .partialFailure)
        session.send(.retry)
        #expect(session.operation == .retrying)
        #expect(session.completedSteps == 2)
        #expect(session.actions == [.retry("notes")])
        session.send(.retry)
        #expect(session.actions.count == 1)
        session.send(.retrySucceeded)
        #expect(session.operation == .complete)
        #expect(session.completedSteps == 3)
    }

    // A reset or a newer replay must invalidate steps queued by an older replay.
    @Test func staleReplayCannotChangeResetOrNewStory() {
        let session = CatalogSession(story: .interruptedExpansion)
        let first = session.beginReplay()
        session.replayStep(0, generation: first)
        #expect(session.expanded)
        session.reset()
        session.replayStep(1, generation: first)
        #expect(!session.expanded)
        #expect(session.actions.isEmpty)
        let second = session.beginReplay()
        session.select(.partialFailure)
        session.replayStep(0, generation: second)
        #expect(session.operation == .partialFailure)
        #expect(session.actions.isEmpty)
    }

    @Test func replayReversesExpansionThenAcceptsNewInput() {
        let session = CatalogSession(story: .interruptedExpansion)
        let generation = session.beginReplay()
        session.replayStep(0, generation: generation)
        #expect(session.expanded)
        session.replayStep(1, generation: generation)
        #expect(!session.expanded)
        session.replayStep(2, generation: generation)
        #expect(session.expanded)
        session.send(.setExpanded(false))
        #expect(!session.expanded)
        #expect(session.actions.isEmpty)
    }

    @Test func searchFindsNestedScenarioAndSelectionResetsTransientState() {
        let session = CatalogSession(story: .partialFailure)
        session.send(.retry)
        let results = StoryDefinition.matching("  DEEP TREE ")
        #expect(results.map(\.id) == [.deepPreview])
        session.select(.busyFull)
        #expect(session.actions.isEmpty)
        #expect(session.operation == .idle)
        #expect(session.expanded)
    }
}

@Suite("Independent hover surfaces and rail content")
@MainActor
struct PresentationReviewTests {
    @Test func replayFeedsBothSurfacesAndResetDismissesBoth() {
        let session = CatalogSession(story: .deepPreview)
        let generation = session.beginReplay()
        session.replayStep(0, generation: generation)
        #expect(session.canvasHover.visible)
        #expect(session.nativeHover.visible)
        session.reset()
        #expect(!session.canvasHover.visible)
        #expect(!session.nativeHover.visible)
        session.replayStep(1, generation: generation)
        #expect(!session.canvasHover.visible)
        #expect(!session.nativeHover.visible)
        #expect(session.actions.isEmpty)
    }

    @Test func nativeOutsideClickPreservesCanvasHover() {
        let session = CatalogSession(story: .deepPreview)
        let canvas = session.canvasHover
        let native = session.nativeHover
        native.enter(.rail)
        native.leave(.rail)
        native.enter(.preview)
        canvas.enter(.rail)
        native.close()
        #expect(!native.visible)
        #expect(canvas.visible)
        canvas.leave(.rail)
        let departure = canvas.generation
        canvas.enter(.preview)
        canvas.dismiss(generation: departure)
        #expect(canvas.visible)
    }

    @Test func oldDismissalCannotDismissReopenedNativePreview() {
        let hover = PreviewHover()
        hover.enter(.rail)
        hover.leave(.rail)
        let obsolete = hover.generation
        hover.close()
        hover.enter(.rail)
        hover.dismiss(generation: obsolete)
        #expect(hover.visible)
        hover.leave(.rail)
        hover.dismiss(generation: hover.generation)
        #expect(!hover.visible)
    }

    @Test func fullRailFollowsSuppliedSelectionAndNeverInventsFixtureRows() throws {
        let projects: [WorkspacePresentation] = [
            .init(id: "studio", name: "A real project", children: [
                .init(id: "notes", name: "Notes", windows: ["Trip notes"]),
                .init(id: "build", name: "Build", children: [
                    .init(id: "editor", name: "Editor", windows: ["Main.swift", "Build log"])
                ])
            ]),
            .init(id: "other", name: "Other", windows: ["Unrelated window"])
        ]
        let first = try #require(RailPresentation.rows(projects: projects, selected: "notes").first)
        #expect(first.active)
        #expect(first.path == ["Notes"])
        #expect(first.windows == ["Trip notes"])
        let changed = RailPresentation.rows(projects: projects, selected: "editor")
        let active = try #require(changed.first)
        #expect(active.path == ["Build", "Editor"])
        #expect(active.windows == ["Main.swift", "Build log"])
        #expect(changed.last?.active == false)
        #expect(changed.last?.windows == [])
        let noSelection = RailPresentation.rows(projects: projects, selected: "missing")
        #expect(noSelection.allSatisfy { !$0.active && $0.path.isEmpty && $0.windows.isEmpty })
    }
}

@Suite("Rail pointer bounds")
struct RailPointerBoundsTests {
    @Test func emptyHostSpaceIsOutsideRenderedRailDuringReversal() {
        let host = CGRect(x: 100, y: 200, width: 324, height: 614)
        let compact = RailPointerBounds.frame(host: host, renderedSize: CGSize(width: 66, height: 590), inset: 12)
        #expect(!compact.contains(CGPoint(x: 200, y: 400)))
        #expect(compact.contains(CGPoint(x: 370, y: 400)))
        let intermediate = RailPointerBounds.frame(host: host, renderedSize: CGSize(width: 128, height: 590), inset: 12)
        #expect(!intermediate.contains(CGPoint(x: 270, y: 400)))
        #expect(intermediate.contains(CGPoint(x: 300, y: 400)))
        #expect(intermediate.maxX == compact.maxX)
        let full = RailPointerBounds.frame(host: host, renderedSize: CGSize(width: 252, height: 590), inset: 12)
        #expect(full.contains(CGPoint(x: 200, y: 400)))
        #expect(!full.contains(CGPoint(x: 200, y: 205)))
    }
}
