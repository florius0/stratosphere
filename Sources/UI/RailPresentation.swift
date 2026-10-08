public struct RailProjectPresentation: Identifiable, Sendable {
    public let project: WorkspacePresentation
    public let active: Bool
    public let path: [String]
    public let windows: [String]
    public var id: String { project.id }
    public init(project: WorkspacePresentation, active: Bool, path: [String], windows: [String]) {
        self.project = project; self.active = active; self.path = path; self.windows = windows
    }
}

public enum RailPresentation {
    public static func rows(projects: [WorkspacePresentation], selected: String) -> [RailProjectPresentation] {
        projects.map { project in
            let path = path(to: selected, in: project)
            return RailProjectPresentation(project: project, active: path != nil,
                                           path: path?.dropFirst().map(\.name) ?? [], windows: path?.last?.windows ?? [])
        }
    }

    private static func path(to id: String, in workspace: WorkspacePresentation) -> [WorkspacePresentation]? {
        if workspace.id == id { return [workspace] }
        for child in workspace.children {
            if let path = path(to: id, in: child) { return [workspace] + path }
        }
        return nil
    }
}
