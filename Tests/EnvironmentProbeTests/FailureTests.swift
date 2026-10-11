import Testing

@testable import EnvironmentProbe

struct FailureTests {
  @Test func distinguishesUnavailableCapabilityFromAssertionFailure() {
    #expect(ProbeFailure("Missing AX grant").status == "setup-failed")
    #expect(ProbeFailure("Geometry readback mismatch", kind: .assertion).status == "failed")
  }
  @MainActor @Test func preservesCategoryAtBoundedWaitFailure() {
    do {
      try SystemObservation.wait("synthetic action readback", seconds: 0, kind: .assertion) {
        false
      }
      Issue.record("The wait unexpectedly succeeded")
    } catch let error as ProbeFailure {
      #expect(error.status == "failed")
    } catch { Issue.record("Unexpected error: \(error)") }
  }
}
