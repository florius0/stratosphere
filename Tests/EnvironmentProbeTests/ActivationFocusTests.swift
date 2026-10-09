import AppKit
import Testing
@testable import EnvironmentProbe

@MainActor struct ActivationFocusTests {
    @Test func activationRequiresExactOwnedProcessInBothObservations() {
        #expect(!FixtureActivation.matches(owner: 0, system: 0, workspace: 0))
        #expect(!FixtureActivation.matches(owner: 42, system: 42, workspace: 7))
        #expect(!FixtureActivation.matches(owner: 42, system: nil, workspace: 42))
        #expect(FixtureActivation.matches(owner: 42, system: 42, workspace: 42))
    }
    @Test func inactiveAppMustBecomeActiveBeforeRaise() throws {
        var activated = false, reads = 0, effects: [String] = []
        try FixtureActivation.focus(activate: { activated = true; effects.append("activate"); return .success }, isActive: {
            reads += 1
            return activated && reads >= 3
        }, raise: { #expect(activated && reads >= 3); effects.append("raise"); return .success })
        #expect(effects == ["activate", "raise"])
    }
    @Test func activeAppRaisesWithoutQueuedReactivationOrFocusAttributeWrites() throws {
        var effects: [String] = []
        try FixtureActivation.focus(activate: { effects.append("activate"); return .success }, isActive: { true }, raise: { effects.append("raise"); return .success })
        #expect(effects == ["raise"])
    }
    @Test func blockedActivationCannotRaiseWindow() {
        var raised = false
        #expect(throws: ProbeFailure.self) {
            try FixtureActivation.focus(activate: { .success }, isActive: { false }, raise: { raised = true; return .success }, timeout: 0)
        }
        #expect(!raised)
    }
}
