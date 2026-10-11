import Testing

@testable import EnvironmentProbe

struct SIPQualificationTests {
  @Test func hostedDisabledIsLimitedEvidence() throws {
    let evidence = try SIPQualification.validate(
      profile: .hosted, exitCode: 0,
      output: "System Integrity Protection status: disabled.\n")
    #expect(evidence == false)
  }
  @Test func enabledQualifiesBothProfiles() throws {
    for profile in [Profile.hosted, .guest] {
      #expect(
        try SIPQualification.validate(
          profile: profile, exitCode: 0,
          output: "System Integrity Protection status: enabled.\n"))
    }
  }
  @Test func guestDisabledAndUnknownStatesFail() {
    #expect(throws: ProbeFailure.self) {
      try SIPQualification.validate(
        profile: .guest, exitCode: 0,
        output: "System Integrity Protection status: disabled.")
    }
    for output in [
      "", "System Integrity Protection status: unknown.",
      "System Integrity Protection status: enabled (Custom Configuration).",
    ] {
      #expect(throws: ProbeFailure.self) {
        try SIPQualification.validate(profile: .hosted, exitCode: 0, output: output)
      }
    }
    #expect(throws: ProbeFailure.self) {
      try SIPQualification.validate(
        profile: .hosted, exitCode: 1,
        output: "System Integrity Protection status: enabled.")
    }
  }
}
