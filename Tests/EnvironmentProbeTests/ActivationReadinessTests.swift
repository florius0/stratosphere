import AppKit
import Testing
@testable import EnvironmentProbe

@MainActor struct ActivationReadinessTests {
    @Test func applicationReadErrorStopsBeforeActivationOrRaise() {
        var changed = false
        #expect(throws: ProbeFailure.self) {
            try FixtureActivation.focus(activate: { changed = true; return .success }, isActive: { throw ProbeFailure("AXFrontmost read failed", kind: .assertion) }, raise: { changed = true; return .success })
        }
        #expect(!changed)
    }
    @Test func exitedOwnedProcessCannotActivateOrRaise() {
        var changed = false
        #expect(throws: ProbeFailure.self) {
            try FixtureActivation.focus(activate: { changed = true; return .success }, isActive: { throw ProbeFailure("Owned fixture exited", kind: .assertion) }, raise: { changed = true; return .success })
        }
        #expect(!changed)
    }
}
