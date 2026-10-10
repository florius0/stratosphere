import AppKit
import Testing
@testable import EnvironmentProbe

@MainActor struct ActivationFocusTests {
    @Test func activationRequiresLiveOwnerAndAllThreeActualSignals() {
        #expect(!FixtureActivation.matches(owner: 0, live: true, nativeActive: true, workspace: 0, appFrontmost: true))
        #expect(!FixtureActivation.matches(owner: 42, live: false, nativeActive: true, workspace: 42, appFrontmost: true))
        #expect(!FixtureActivation.matches(owner: 42, live: true, nativeActive: false, workspace: 42, appFrontmost: true))
        #expect(!FixtureActivation.matches(owner: 42, live: true, nativeActive: true, workspace: 7, appFrontmost: true))
        #expect(!FixtureActivation.matches(owner: 42, live: true, nativeActive: true, workspace: 42, appFrontmost: false))
        #expect(FixtureActivation.matches(owner: 42, live: true, nativeActive: true, workspace: 42, appFrontmost: true))
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
