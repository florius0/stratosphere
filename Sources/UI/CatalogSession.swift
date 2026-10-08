import Foundation
import Observation

/// Presentation fixtures and requested actions only; these are not daemon wire types.
public enum StoryID: String, CaseIterable, Identifiable, Sendable {
    case busyCompact = "rail-compact-busy"
    case busyFull = "rail-full-busy"
    case deepPreview = "hover-deep-tree"
    case partialFailure = "operation-partial-failure"
    case interruptedExpansion = "rail-interrupted-expansion"
    public var id: String { rawValue }
}

public struct StoryDefinition: Identifiable, Sendable {
    public let id: StoryID
    public let title: String
    public let detail: String
    public static let all: [Self] = [
        .init(id: .busyCompact, title: "Rail / Compact / Busy", detail: "Crowded projects, long names, badges and launchers."),
        .init(id: .busyFull, title: "Rail / Full / Busy", detail: "Active paths, windows and project expansion."),
        .init(id: .deepPreview, title: "Hover preview / Deep tree", detail: "Passive inspection, nested scrolling and native panel handoff."),
        .init(id: .partialFailure, title: "Operation / Partial failure", detail: "Two completed steps, one preserved failure and explicit Retry."),
        .init(id: .interruptedExpansion, title: "Rail / Compact to Full", detail: "Reverse expansion in progress; keep accepting rapid input.")
    ]
    public static func matching(_ query: String) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { query.isEmpty || "\($0.title) \($0.detail)".localizedCaseInsensitiveContains(query) }
    }
}

public enum PointerRegion: Sendable, Hashable { case rail, preview }
public enum PresentationAction: Equatable, Sendable {
    case focus(String), retry(String)
    public var description: String {
        switch self {
        case .focus(let id): "Focus workspace · \(id)"
        case .retry(let id): "Retry failed step · \(id)"
        }
    }
}
public enum StoryEvent: Sendable {
    case focus(String), retry, retrySucceeded, setExpanded(Bool)
}
public enum OperationPresentation: Equatable, Sendable { case idle, partialFailure, retrying, complete }

@MainActor @Observable
public final class CatalogSession {
    public let canvasHover = PreviewHover()
    public let nativeHover = PreviewHover()
    public private(set) var story: StoryID
    public private(set) var selectedWorkspace = PresentationFixtures.initialSelection
    public private(set) var expanded = false
    public private(set) var operation: OperationPresentation = .idle
    public private(set) var completedSteps = 0
    public private(set) var actions: [PresentationAction] = []
    public private(set) var replayGeneration = 0
    public var expandedNodes = PresentationFixtures.initialExpandedNodes

    public init(story: StoryID = .busyCompact) {
        self.story = story
        reset()
    }

    public func send(_ event: StoryEvent) {
        switch event {
        case .focus(let id):
            selectedWorkspace = id
            actions.append(.focus(id))
        case .retry:
            guard operation == .partialFailure else { return }
            operation = .retrying
            actions.append(.retry("notes"))
        case .retrySucceeded:
            guard operation == .retrying else { return }
            operation = .complete
            completedSteps = 3
        case .setExpanded(let value): expanded = value
        }
    }

    public func beginReplay() -> Int {
        reset()
        return replayGeneration
    }

    public var replayStepCount: Int {
        switch story {
        case .interruptedExpansion: 3
        case .deepPreview: 4
        case .partialFailure: 2
        case .busyCompact, .busyFull: 2
        }
    }

    public func replayStep(_ step: Int, generation: Int) {
        guard generation == replayGeneration else { return }
        switch story {
        case .interruptedExpansion:
            send(.setExpanded(step != 1))
        case .deepPreview:
            for hover in [canvasHover, nativeHover] {
                switch step {
                case 0: hover.enter(.rail)
                case 1:
                    hover.leave(.rail)
                    hover.enter(.preview)
                case 2:
                    hover.leave(.preview)
                    hover.dismiss(generation: hover.generation)
                default: hover.enter(.rail)
                }
            }
        case .partialFailure:
            send(step == 0 ? .retry : .retrySucceeded)
        case .busyCompact, .busyFull:
            send(.setExpanded(step == 0))
        }
    }

    public func reset() {
        replayGeneration += 1
        selectedWorkspace = PresentationFixtures.initialSelection
        expanded = story == .busyFull
        canvasHover.close()
        nativeHover.close()
        actions.removeAll()
        operation = story == .partialFailure ? .partialFailure : .idle
        completedSteps = story == .partialFailure ? 2 : 0
        expandedNodes = PresentationFixtures.initialExpandedNodes
    }

    public func select(_ story: StoryID) {
        self.story = story
        reset()
    }
}
