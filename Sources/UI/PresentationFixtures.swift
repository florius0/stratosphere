import SwiftUI

public struct WorkspacePresentation: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let symbol: String
    public let colorIndex: Int
    public let badge: Int
    public let windows: [String]
    public let children: [Self]
    public init(id: String, name: String, symbol: String = "folder", colorIndex: Int = 0, badge: Int = 0, windows: [String] = [], children: [Self] = []) {
        self.id = id; self.name = name; self.symbol = symbol; self.colorIndex = colorIndex
        self.badge = badge; self.windows = windows; self.children = children
    }
}

/// Entirely invented review content. No application state or desktop capture is read.
public enum PresentationFixtures {
    public static let initialSelection = "references"
    public static let initialExpandedNodes: Set<String> = ["studio", "work", "research", "field", "archive", "archive-2025", "archive-2025-q4"]
    public static let projects: [WorkspacePresentation] = [
        .init(id: "studio", name: "Studio", symbol: "square.stack.3d.up.fill", colorIndex: 0, badge: 3, children: [
            .init(id: "work", name: "Product", children: [
                .init(id: "research", name: "Research", children: [
                    .init(id: "references", name: "References", windows: ["Field notes · Notes", "Reference library · Safari"]),
                    .init(id: "field", name: "Field studies", children: [
                        .init(id: "coast", name: "Coastal habitats", children: [
                            .init(id: "transect", name: "Transect observations", windows: ["Tide log · Numbers", "Survey sketches · Preview"])
                        ])
                    ])
                ]),
                .init(id: "design", name: "Design", windows: ["Components · Sketch", "Design brief · Notes"]),
                .init(id: "engineering", name: "Engineering", windows: ["App · Code", "Development · Terminal"])
            ]),
            .init(id: "archive", name: "Archive", children: [
                .init(id: "archive-2025", name: "2025", children: [
                    .init(id: "archive-2025-q4", name: "Autumn", children: [
                        .init(id: "archive-review", name: "Review", windows: ["Summary · Pages"])
                    ])
                ])
            ])
        ]),
        .init(id: "atlas", name: "Atlas", symbol: "globe.americas.fill", colorIndex: 1, badge: 12, windows: ["Maps · Safari"]),
        .init(id: "garden", name: "Garden", symbol: "leaf.fill", colorIndex: 2, windows: ["Planting calendar · Calendar"]),
        .init(id: "reading", name: "Reading & ideas", symbol: "book.closed.fill", colorIndex: 3, badge: 2, windows: ["Reading list · Books"]),
        .init(id: "weekend", name: "Weekend explorations and photography", symbol: "camera.fill", colorIndex: 4, windows: ["Selects · Photos"]),
        .init(id: "music", name: "Music", symbol: "waveform", colorIndex: 5, windows: ["Session · Music"]),
        .init(id: "home", name: "Home", symbol: "house.fill", colorIndex: 6, windows: ["Household · Reminders"])
    ]
    public static let deepTree = projects[0]
    public static let colors: [Color] = [.blue, .indigo, .green, .orange, .pink, .purple, .teal]
}
