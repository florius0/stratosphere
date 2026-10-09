import AppKit
import Testing
@testable import EnvironmentProbe

@MainActor struct ActivationReadinessTests {
    @Test func onlyCannotCompleteMeansNotReady() throws {
        #expect(try FixtureActivation.readiness(.cannotComplete) == false)
        #expect(try FixtureActivation.readiness(.success) == true)
        for status in [AXError.apiDisabled, .invalidUIElement, .attributeUnsupported, .failure] {
            #expect(throws: ProbeFailure.self) { try FixtureActivation.readiness(status) }
        }
    }
    @Test func transientReadTriggersActivationThenRequiresObservedReadiness() throws {
        var activated = false, reads = 0, raised = false
        try FixtureActivation.focus(activate: { activated = true; return .success }, isActive: {
            reads += 1
            return try FixtureActivation.readiness(reads == 1 ? .cannotComplete : .success) && activated
        }, raise: { #expect(activated && reads >= 2); raised = true; return .success })
        #expect(raised)
    }
}
