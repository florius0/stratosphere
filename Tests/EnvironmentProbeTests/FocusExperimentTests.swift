import Testing

@testable import EnvironmentProbe

struct FocusExperimentTests {
  @Test func experimentRequiresExactExplicitOptIn() {
    #expect(!FocusExperiment.enabled([:]))
    for value in ["", "0", "true", "yes"] {
      #expect(!FocusExperiment.enabled(["STRATOSPHERE_FOCUS_EXPERIMENT": value]))
    }
    #expect(FocusExperiment.enabled(["STRATOSPHERE_FOCUS_EXPERIMENT": "1"]))
  }
}
