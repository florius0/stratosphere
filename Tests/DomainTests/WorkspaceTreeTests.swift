import Foundation
import Testing
import Domain

@Suite struct DomainTests {
    @Test func wrappingTransfersWindowsLayoutAndBinding() throws {
        var tree = WorkspaceTree()
        let project = try tree.addWorkspace(name: "Project", binding: .physical("right"))
        let tiled = UUID(), floating = UUID()
        try tree.addWindow(tiled, to: project)
        try tree.addWindow(floating, to: project, group: .freeCentered)
        try tree.setEngine(.i3, for: project)
        let priorLayout = tree.nodes[project]?.layout
        let wrapped = GeneratedChild(name: "Original")
        let added = try tree.addWorkspace(name: "New", parent: project, wrappingChild: wrapped)
        #expect(tree.nodes[project]?.isLeaf == false)
        #expect(tree.nodes[project]?.binding == nil)
        #expect(tree.nodes[project]?.layout == nil)
        #expect(tree.nodes[project]?.windows == [])
        #expect(tree.nodes[project]?.children == [wrapped.id, added])
        #expect(tree.nodes[wrapped.id]?.layout == priorLayout)
        #expect(tree.nodes[wrapped.id]?.binding == .physical("right"))
        #expect(tree.owners[tiled] == wrapped.id)
        #expect(tree.owners[floating] == wrapped.id)
        #expect(tree.nodes[wrapped.id]?.parent == project)
    }

    @Test func missingWrappingMetadataLeavesTreeUnchanged() throws {
        var tree = WorkspaceTree()
        let project = try tree.addWorkspace(name: "Project")
        try tree.addWindow(UUID(), to: project)
        let before = tree
        #expect(throws: TreeError.wrappingChildRequired) {
            try tree.addWorkspace(name: "Child", parent: project)
        }
        #expect(tree == before)
    }

    @Test func conflictingGeneratedChildFailsAtomically() throws {
        var tree = WorkspaceTree()
        let project = try tree.addWorkspace(name: "Project")
        try tree.addWindow(UUID(), to: project)
        let before = tree
        #expect(throws: TreeError.duplicateName("child")) {
            try tree.addWorkspace(name: "Child", parent: project, wrappingChild: GeneratedChild(name: "child"))
        }
        #expect(tree == before)
    }

    @Test func leavesDeriveFromChildrenAtArbitraryDepth() throws {
        var tree = WorkspaceTree()
        let root = try tree.addWorkspace(name: "Root")
        var parent = root
        for index in 0..<128 { parent = try tree.addWorkspace(name: "Level \(index)", parent: parent) }
        #expect(tree.nodes[root]?.isLeaf == false)
        #expect(tree.nodes[root]?.binding == nil)
        #expect(tree.nodes[parent]?.isLeaf == true)
        #expect(tree.nodes[parent]?.binding == .main)
        let nextParent = try #require(tree.nodes[parent]?.parent)
        try tree.removeEmptyLeaf(parent)
        #expect(tree.nodes[nextParent]?.isLeaf == true)
        #expect(tree.nodes[nextParent]?.layout != nil)
    }

    @Test(arguments: [("Development", "DEVELOPMENT"), ("Café", "Cafe\u{301}"), ("Straße", "STRASSE")])
    func siblingNamesRejectCaseAndUnicodeCollisions(names: (String, String)) throws {
        var tree = WorkspaceTree()
        let root = try tree.addWorkspace(name: "Root")
        try tree.addWorkspace(name: names.0, parent: root)
        let before = tree
        #expect(throws: TreeError.duplicateName(names.1)) { try tree.addWorkspace(name: names.1, parent: root) }
        #expect(tree == before)
    }

    @Test func namesNormalizeAndIdentitySurvivesRenameAndMove() throws {
        var tree = WorkspaceTree()
        let first = try tree.addWorkspace(name: "One"), second = try tree.addWorkspace(name: "Two")
        let child = try tree.addWorkspace(name: "Cafe\u{301}", parent: first)
        try tree.addWorkspace(name: "Café", parent: second)
        #expect(tree.nodes[child]?.name == "Café")
        #expect(throws: TreeError.duplicateName("Café")) { try tree.reparent(child, to: second) }
        try tree.rename(child, to: "Work")
        try tree.reparent(child, to: second)
        #expect(tree.nodes[child]?.id == child)
        #expect(tree.nodes[child]?.parent == second)
        #expect(tree.nodes[first]?.isLeaf == true)
        #expect(tree.nodes[second]?.children.contains(child) == true)
        let before = tree
        #expect(throws: TreeError.duplicateName("CAFÉ")) { try tree.rename(child, to: "CAFÉ") }
        #expect(tree == before)
    }

    @Test func duplicateUUIDAndCyclicMoveFailAtomically() throws {
        var tree = WorkspaceTree()
        let root = try tree.addWorkspace(name: "Root")
        let child = try tree.addWorkspace(name: "Child", parent: root)
        let before = tree
        #expect(throws: TreeError.duplicateIdentity(root)) { try tree.addWorkspace(name: "Other", id: root) }
        #expect(throws: TreeError.cycle) { try tree.reparent(root, to: child) }
        #expect(tree == before)
    }

    @Test func ordinaryWindowsHaveOneOwnerAndTransferPreservesGroup() throws {
        var tree = WorkspaceTree()
        let one = try tree.addWorkspace(name: "One"), two = try tree.addWorkspace(name: "Two")
        let window = UUID()
        try tree.addWindow(window, to: one, group: .free)
        let before = tree
        #expect(throws: TreeError.windowAlreadyOwned(window)) { try tree.addWindow(window, to: two) }
        #expect(tree == before)
        try tree.transferWindow(window, to: two)
        #expect(tree.nodes[one]?.windows == [])
        #expect(tree.nodes[two]?.windows == [window])
        #expect(tree.nodes[two]?.layout?.groups[window] == .free)
        #expect(tree.owners[window] == two)
        try tree.transferWindow(window, to: two)
        #expect(tree.nodes[two]?.windows == [window])
    }

    @Test func parentCannotOwnWindowsAndFailedTransferPreservesOwner() throws {
        var tree = WorkspaceTree()
        let parent = try tree.addWorkspace(name: "Parent")
        let child = try tree.addWorkspace(name: "Child", parent: parent)
        let window = UUID()
        try tree.addWindow(window, to: child)
        let before = tree
        #expect(throws: TreeError.notLeaf(parent)) { try tree.addWindow(UUID(), to: parent) }
        #expect(throws: TreeError.notLeaf(parent)) { try tree.transferWindow(window, to: parent) }
        #expect(tree == before)
    }

    @Test func ancestorBindingOverridesOnlyItsActivation() throws {
        var tree = WorkspaceTree()
        let parent = try tree.addWorkspace(name: "Parent")
        let child = try tree.addWorkspace(name: "Child", parent: parent, binding: .physical("right"))
        try tree.setBinding(.physical("left"), for: parent)
        let together = try tree.resolveActivation(target: parent, displays: ["left", "right"], main: "left")
        #expect(together.placements == ["left": child])
        #expect(together.scope == .display("left"))
        let direct = try tree.resolveActivation(target: child, displays: ["left", "right"], main: "left")
        #expect(direct.placements == ["right": child])
        #expect(direct.scope == .display("right"))
        #expect(tree.nodes[child]?.binding == .physical("right"))
    }

    @Test func unboundTargetDeterminesGlobalScopeDespiteBoundChildren() throws {
        var tree = WorkspaceTree()
        let parent = try tree.addWorkspace(name: "Parent")
        let left = try tree.addWorkspace(name: "Left", parent: parent, binding: .physical("left"))
        let right = try tree.addWorkspace(name: "Right", parent: parent, binding: .physical("right"))
        let activation = try tree.resolveActivation(target: parent, displays: ["left", "right", "extra"], main: "left")
        #expect(activation.scope == .global)
        #expect(activation.placements == ["left": left, "right": right])
        #expect(activation.blankDisplays == ["extra"])
        let before = tree
        _ = try tree.resolveActivation(target: parent, displays: ["left", "right"], main: "left")
        #expect(tree == before)
    }

    @Test func unboundLeafUsesMainAndBlanksOthers() throws {
        var tree = WorkspaceTree()
        let leaf = try tree.addWorkspace(name: "Leaf", binding: nil)
        let activation = try tree.resolveActivation(target: leaf, displays: ["left", "right"], main: "right")
        #expect(activation.placements == ["right": leaf])
        #expect(activation.blankDisplays == ["left"])
        #expect(activation.scope == .global)
    }

    @Test func selectionUsesChildOrderThenRecencyThenRemembered() throws {
        var tree = WorkspaceTree()
        let parent = try tree.addWorkspace(name: "Parent")
        let first = try tree.addWorkspace(name: "First", parent: parent)
        let second = try tree.addWorkspace(name: "Second", parent: parent)
        #expect(try tree.resolveActivation(target: parent, displays: ["main"], main: "main").placements == ["main": first])
        try tree.recordFocus(second, display: "main")
        try tree.remember(first, for: parent, display: "main")
        #expect(try tree.resolveActivation(target: parent, displays: ["main"], main: "main").placements == ["main": first])
        try tree.setArchived(true, for: first)
        #expect(try tree.resolveActivation(target: parent, displays: ["main"], main: "main").placements == ["main": second])
        #expect(tree.nodes[parent]?.lastFocus == tree.nodes[second]?.lastFocus)
    }

    @Test func descendantRecencyWinsWhenRememberedLeafLeavesSubtree() throws {
        var tree = WorkspaceTree()
        let parent = try tree.addWorkspace(name: "Parent"), outside = try tree.addWorkspace(name: "Outside")
        let first = try tree.addWorkspace(name: "First", parent: parent)
        let recent = try tree.addWorkspace(name: "Recent", parent: parent)
        let remembered = try tree.addWorkspace(name: "Remembered", parent: parent)
        try tree.recordFocus(recent, display: "main")
        try tree.remember(remembered, for: parent, display: "main")
        try tree.reparent(remembered, to: outside)
        #expect(try tree.resolveActivation(target: parent, displays: ["main"], main: "main").placements == ["main": recent])
        #expect(tree.nodes[first]?.lastFocus == 0)
    }

    @Test func selectionRemembersLeavesAtEveryAncestor() throws {
        var tree = WorkspaceTree()
        let root = try tree.addWorkspace(name: "Root")
        let branch = try tree.addWorkspace(name: "Branch", parent: root)
        let first = try tree.addWorkspace(name: "First", parent: branch)
        let second = try tree.addWorkspace(name: "Second", parent: branch)
        try tree.recordFocus(second, display: "left")
        #expect(tree.nodes[root]?.remembered["left"] == second)
        #expect(tree.nodes[branch]?.remembered["left"] == second)
        try tree.remember(first, for: branch, display: "main")
        #expect(try tree.resolveActivation(target: branch, displays: ["main"], main: "main").placements == ["main": first])
    }

    @Test func missingDisplayCollisionUsesMRUAndReconnectionRetainsIntent() throws {
        var tree = WorkspaceTree()
        let root = try tree.addWorkspace(name: "Root")
        let mainLeaf = try tree.addWorkspace(name: "Main", parent: root)
        let absent = try tree.addWorkspace(name: "Absent", parent: root, binding: .physical("right"))
        try tree.recordFocus(mainLeaf, display: "left")
        try tree.recordFocus(absent, display: "right")
        try tree.remember(mainLeaf, for: root, display: "left")
        let disconnected = try tree.resolveActivation(target: root, displays: ["left"], main: "left")
        #expect(disconnected.placements == ["left": absent])
        #expect(tree.nodes[absent]?.binding == .physical("right"))
        let reconnected = try tree.resolveActivation(target: root, displays: ["left", "right"], main: "left")
        #expect(reconnected.placements == ["left": mainLeaf, "right": absent])
    }

    @Test func symbolicMainFollowsMainSettingWithoutChangingSavedBinding() throws {
        var tree = WorkspaceTree()
        let leaf = try tree.addWorkspace(name: "Leaf")
        #expect(try tree.resolveActivation(target: leaf, displays: ["left", "right"], main: "left").placements == ["left": leaf])
        #expect(try tree.resolveActivation(target: leaf, displays: ["left", "right"], main: "right").placements == ["right": leaf])
        #expect(tree.nodes[leaf]?.binding == .main)
    }

    @Test func archivedAncestorExcludesItsEntireSubtree() throws {
        var tree = WorkspaceTree()
        let root = try tree.addWorkspace(name: "Root")
        let branch = try tree.addWorkspace(name: "Branch", parent: root)
        let leaf = try tree.addWorkspace(name: "Leaf", parent: branch)
        try tree.setArchived(true, for: branch)
        #expect(try tree.resolveActivation(target: root, displays: ["main"], main: "main").placements.isEmpty)
        #expect(throws: TreeError.archivedWorkspace(leaf)) {
            try tree.resolveActivation(target: leaf, displays: ["main"], main: "main")
        }
    }

    @Test func invalidTopologyAndRememberedSelectionAreRejected() throws {
        var tree = WorkspaceTree()
        let root = try tree.addWorkspace(name: "Root"), outside = try tree.addWorkspace(name: "Outside")
        let leaf = try tree.addWorkspace(name: "Leaf", parent: root)
        #expect(throws: TreeError.invalidDisplays) { try tree.resolveActivation(target: root, displays: [], main: "main") }
        #expect(throws: TreeError.invalidSelection(outside)) { try tree.remember(outside, for: root, display: "main") }
        #expect(throws: TreeError.notLeaf(root)) { try tree.recordFocus(root, display: "main") }
        #expect(tree.nodes[leaf]?.lastFocus == 0)
    }

    @Test func populatedLeafRemovalCannotDiscardWindowOwnership() throws {
        var tree = WorkspaceTree()
        let leaf = try tree.addWorkspace(name: "Leaf")
        let window = UUID()
        try tree.addWindow(window, to: leaf)
        let before = tree
        #expect(throws: TreeError.populatedLeaf(leaf)) { try tree.removeEmptyLeaf(leaf) }
        #expect(tree == before)
        #expect(tree.owners[window] == leaf)
    }

    @Test func reparentIntoPopulatedLeafWrapsItsExistingContents() throws {
        var tree = WorkspaceTree()
        let source = try tree.addWorkspace(name: "Source")
        let destination = try tree.addWorkspace(name: "Destination", binding: .physical("right"))
        let window = UUID()
        try tree.addWindow(window, to: destination, group: .freeCentered)
        let before = tree
        #expect(throws: TreeError.wrappingChildRequired) { try tree.reparent(source, to: destination) }
        #expect(tree == before)
        let child = GeneratedChild(name: "Existing")
        try tree.reparent(source, to: destination, wrappingChild: child)
        #expect(tree.nodes[destination]?.children == [child.id, source])
        #expect(tree.nodes[destination]?.binding == nil)
        #expect(tree.nodes[child.id]?.binding == .physical("right"))
        #expect(tree.nodes[child.id]?.layout?.groups[window] == .freeCentered)
        #expect(tree.owners[window] == child.id)
        #expect(tree.roots == [destination])
    }

    @Test func firstBoundAncestorOverridesEveryDeeperBinding() throws {
        var tree = WorkspaceTree()
        let root = try tree.addWorkspace(name: "Root")
        let branch = try tree.addWorkspace(name: "Branch", parent: root)
        let middle = try tree.addWorkspace(name: "Middle", parent: branch)
        let leaf = try tree.addWorkspace(name: "Leaf", parent: middle, binding: .physical("right"))
        try tree.setBinding(.physical("left"), for: branch)
        try tree.setBinding(.physical("right"), for: middle)
        #expect(try tree.resolveActivation(target: root, displays: ["left", "right"], main: "left").placements == ["left": leaf])
        #expect(try tree.resolveActivation(target: middle, displays: ["left", "right"], main: "left").placements == ["right": leaf])
    }

    @Test func rememberedLeafOnAnotherDisplayDoesNotOverrideBinding() throws {
        var tree = WorkspaceTree()
        let root = try tree.addWorkspace(name: "Root")
        let left = try tree.addWorkspace(name: "Left", parent: root, binding: .physical("left"))
        let right = try tree.addWorkspace(name: "Right", parent: root, binding: .physical("right"))
        try tree.remember(right, for: root, display: "left")
        #expect(try tree.resolveActivation(target: root, displays: ["left", "right"], main: "left").placements == ["left": left, "right": right])
    }
}
