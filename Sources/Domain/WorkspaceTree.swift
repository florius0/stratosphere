import Foundation

public struct WorkspaceTree: Equatable, Sendable {
  public private(set) var nodes: [UUID: WorkspaceNode] = [:]
  public private(set) var roots: [UUID] = []
  public private(set) var owners: [UUID: UUID] = [:]
  private var focusSequence: UInt64 = 0
  public init() {}

  /// A populated leaf requires caller-supplied child metadata; naming policy remains undecided.
  @discardableResult
  public mutating func addWorkspace(
    name: String, parent: UUID? = nil,
    binding: DisplayBinding? = .main,
    id: UUID = UUID(), wrappingChild: GeneratedChild? = nil
  ) throws -> UUID {
    guard nodes[id] == nil else { throw TreeError.duplicateIdentity(id) }
    try validateName(name, parent: parent)
    try validateWrapping(parent: parent, incomingName: name, incomingID: id, child: wrappingChild)
    prepareParent(parent, wrappingChild: wrappingChild)
    nodes[id] = WorkspaceNode(id: id, name: normalized(name), parent: parent, binding: binding)
    if let parent { nodes[parent]?.children.append(id) } else { roots.append(id) }
    return id
  }

  public mutating func rename(_ id: UUID, to name: String) throws {
    let node = try workspace(id)
    try validateName(name, parent: node.parent, excluding: id)
    let displayName = normalized(name)
    nodes[id]?.name = displayName
  }

  public mutating func setBinding(_ binding: DisplayBinding?, for id: UUID) throws {
    _ = try workspace(id)
    nodes[id]?.binding = binding
  }

  public mutating func setEngine(_ engine: TiledEngine, for id: UUID) throws {
    _ = try leaf(id)
    nodes[id]?.layout?.engine = engine
  }

  public mutating func addWindow(_ window: UUID, to leaf: UUID, group: WindowGroup = .tiled) throws
  {
    _ = try self.leaf(leaf)
    guard owners[window] == nil else { throw TreeError.windowAlreadyOwned(window) }
    nodes[leaf]?.layout?.groups[window] = group
    owners[window] = leaf
  }

  public mutating func transferWindow(_ window: UUID, to leaf: UUID) throws {
    _ = try self.leaf(leaf)
    guard let previous = owners[window], let group = nodes[previous]?.layout?.groups[window] else {
      throw TreeError.missingWindow(window)
    }
    guard previous != leaf else { return }
    nodes[previous]?.layout?.groups.removeValue(forKey: window)
    nodes[leaf]?.layout?.groups[window] = group
    owners[window] = leaf
  }

  /// Changes parentage only. Active-project and visible-scope updates belong to navigation.
  public mutating func reparent(_ id: UUID, to parent: UUID?, wrappingChild: GeneratedChild? = nil)
    throws
  {
    let node = try workspace(id)
    if let parent {
      _ = try workspace(parent)
      guard !isDescendant(parent, of: id) else { throw TreeError.cycle }
    }
    guard parent != node.parent else { return }
    try validateName(node.name, parent: parent, excluding: id)
    try validateWrapping(
      parent: parent, incomingName: node.name, incomingID: id, child: wrappingChild)
    prepareParent(parent, wrappingChild: wrappingChild)
    detach(id, from: node.parent)
    nodes[id]?.parent = parent
    if let parent { nodes[parent]?.children.append(id) } else { roots.append(id) }
  }

  public mutating func removeEmptyLeaf(_ id: UUID) throws {
    let node = try leaf(id)
    guard node.windows.isEmpty else { throw TreeError.populatedLeaf(id) }
    detach(id, from: node.parent)
    nodes.removeValue(forKey: id)
  }

  public mutating func setArchived(_ archived: Bool, for id: UUID) throws {
    _ = try workspace(id)
    nodes[id]?.archived = archived
  }

  public mutating func remember(_ leaf: UUID, for ancestor: UUID, display: String) throws {
    _ = try workspace(ancestor)
    guard let node = nodes[leaf], node.isLeaf, isDescendant(leaf, of: ancestor) else {
      throw TreeError.invalidSelection(leaf)
    }
    nodes[ancestor]?.remembered[display] = leaf
  }

  public mutating func recordFocus(_ leaf: UUID, display: String) throws {
    _ = try self.leaf(leaf)
    guard !hasArchivedAncestor(leaf) else { throw TreeError.archivedWorkspace(leaf) }
    focusSequence += 1
    var current: UUID? = leaf
    while let id = current {
      nodes[id]?.lastFocus = focusSequence
      nodes[id]?.remembered[display] = leaf
      current = nodes[id]?.parent
    }
  }

  /// Resolves the explicit target subtree without changing focus, bindings, or current visibility.
  public func resolveActivation(target: UUID, displays: Set<String>, main: String) throws
    -> Activation
  {
    let targetNode = try workspace(target)
    guard displays.contains(main) else { throw TreeError.invalidDisplays }
    guard !hasArchivedAncestor(target) else { throw TreeError.archivedWorkspace(target) }
    let candidates = activationCandidates(target: target, main: main)
    var desiredSelections: [(String, UUID)] = []
    var processed: Set<String> = []
    for (display, _) in candidates where processed.insert(display).inserted {
      let eligible = candidates.filter { $0.0 == display }.map { $0.1 }
      let selected: UUID
      if let remembered = targetNode.remembered[display], eligible.contains(remembered) {
        selected = remembered
      } else {
        selected = mostRecent(eligible)
      }
      desiredSelections.append((display, selected))
    }
    // Select each intended display before resolving disconnect collisions by leaf recency.
    var placements: [String: UUID] = [:]
    for (desired, selected) in desiredSelections {
      let actual = displays.contains(desired) ? desired : main
      if let previous = placements[actual] {
        if nodes[selected]!.lastFocus > nodes[previous]!.lastFocus { placements[actual] = selected }
      } else {
        placements[actual] = selected
      }
    }
    let scope: ActivationScope
    if let binding = targetNode.binding {
      let desired = displayID(binding, main: main)
      scope = .display(displays.contains(desired) ? desired : main)
    } else {
      scope = .global
    }
    return Activation(
      target: target, scope: scope, placements: placements,
      blankDisplays: scope == .global ? displays.subtracting(placements.keys) : [])
  }

  private func activationCandidates(target: UUID, main: String) -> [(String, UUID)] {
    var pending: [(UUID, DisplayBinding?)] = [(target, nil)]
    var candidates: [(String, UUID)] = []
    while let (id, inherited) = pending.popLast(), let node = nodes[id] {
      guard !node.archived else { continue }
      let effective = inherited ?? node.binding
      if node.isLeaf {
        candidates.append((displayID(effective ?? .main, main: main), id))
      } else {
        for child in node.children.reversed() { pending.append((child, effective)) }
      }
    }
    return candidates
  }

  private func displayID(_ binding: DisplayBinding, main: String) -> String {
    switch binding {
    case .main: main
    case .physical(let id): id
    }
  }

  private func mostRecent(_ candidates: [UUID]) -> UUID {
    candidates.dropFirst().reduce(candidates[0]) { previous, candidate in
      nodes[candidate]!.lastFocus > nodes[previous]!.lastFocus ? candidate : previous
    }
  }

  private func workspace(_ id: UUID) throws -> WorkspaceNode {
    guard let node = nodes[id] else { throw TreeError.missingWorkspace(id) }
    return node
  }

  private func leaf(_ id: UUID) throws -> WorkspaceNode {
    let node = try workspace(id)
    guard node.isLeaf else { throw TreeError.notLeaf(id) }
    return node
  }

  private func normalized(_ name: String) -> String { name.precomposedStringWithCanonicalMapping }
  private func nameKey(_ name: String) -> String {
    normalized(name).folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
  }

  private func validateName(_ name: String, parent: UUID?, excluding id: UUID? = nil) throws {
    let siblings: [UUID]
    if let parent { siblings = try workspace(parent).children } else { siblings = roots }
    if siblings.contains(where: {
      $0 != id && nodes[$0].map { nameKey($0.name) == nameKey(name) } == true
    }) {
      throw TreeError.duplicateName(name)
    }
  }

  private func validateWrapping(
    parent: UUID?, incomingName: String, incomingID: UUID,
    child: GeneratedChild?
  ) throws {
    guard let parent, let node = nodes[parent], node.isLeaf, !node.windows.isEmpty else { return }
    guard let child else { throw TreeError.wrappingChildRequired }
    guard nodes[child.id] == nil, child.id != incomingID else {
      throw TreeError.duplicateIdentity(child.id)
    }
    guard nameKey(child.name) != nameKey(incomingName) else {
      throw TreeError.duplicateName(child.name)
    }
  }

  private mutating func prepareParent(_ parent: UUID?, wrappingChild: GeneratedChild?) {
    guard let parent, let original = nodes[parent], original.isLeaf else { return }
    if !original.windows.isEmpty, let child = wrappingChild {
      var generated = WorkspaceNode(
        id: child.id, name: normalized(child.name), parent: parent,
        binding: original.binding, layout: original.layout)
      generated.lastFocus = original.lastFocus
      nodes[child.id] = generated
      nodes[parent]?.children = [child.id]
      for window in original.windows { owners[window] = child.id }
    }
    nodes[parent]?.layout = nil
    nodes[parent]?.binding = nil
  }

  private mutating func detach(_ id: UUID, from parent: UUID?) {
    if let parent {
      nodes[parent]?.children.removeAll { $0 == id }
      if nodes[parent]?.isLeaf == true { nodes[parent]?.layout = LeafLayout() }
    } else {
      roots.removeAll { $0 == id }
    }
  }

  private func isDescendant(_ id: UUID, of ancestor: UUID) -> Bool {
    var current: UUID? = id
    while let candidate = current {
      if candidate == ancestor { return true }
      current = nodes[candidate]?.parent
    }
    return false
  }

  private func hasArchivedAncestor(_ id: UUID) -> Bool {
    var current: UUID? = id
    while let candidate = current, let node = nodes[candidate] {
      if node.archived { return true }
      current = node.parent
    }
    return false
  }
}
