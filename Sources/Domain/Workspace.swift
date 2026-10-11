import Foundation

public enum DisplayBinding: Hashable, Sendable {
  case main
  case physical(String)
}

public enum WindowGroup: Sendable { case tiled, free, freeCentered }
public enum TiledEngine: Sendable { case bsp, i3 }

public struct LeafLayout: Equatable, Sendable {
  public var engine: TiledEngine
  public internal(set) var groups: [UUID: WindowGroup]
  public init(engine: TiledEngine = .bsp) {
    self.engine = engine
    groups = [:]
  }
}

public struct WorkspaceNode: Equatable, Sendable {
  public let id: UUID
  public internal(set) var name: String
  public internal(set) var parent: UUID?
  public internal(set) var children: [UUID] = []
  public internal(set) var binding: DisplayBinding?
  public internal(set) var layout: LeafLayout? = LeafLayout()
  public internal(set) var archived = false
  public internal(set) var lastFocus: UInt64 = 0
  public internal(set) var remembered: [String: UUID] = [:]
  public var isLeaf: Bool { children.isEmpty }
  public var windows: Set<UUID> { Set(layout?.groups.keys.map { $0 } ?? []) }
}

public struct GeneratedChild: Sendable {
  public let name: String
  public let id: UUID
  public init(name: String, id: UUID = UUID()) {
    self.name = name
    self.id = id
  }
}

public enum ActivationScope: Equatable, Sendable {
  case global
  case display(String)
}

public struct Activation: Equatable, Sendable {
  public let target: UUID
  public let scope: ActivationScope
  public let placements: [String: UUID]
  public let blankDisplays: Set<String>
}

public enum TreeError: Error, Equatable {
  case missingWorkspace(UUID)
  case duplicateIdentity(UUID)
  case duplicateName(String)
  case wrappingChildRequired
  case notLeaf(UUID)
  case windowAlreadyOwned(UUID)
  case missingWindow(UUID)
  case invalidSelection(UUID)
  case invalidDisplays
  case archivedWorkspace(UUID)
  case populatedLeaf(UUID)
  case cycle
}
