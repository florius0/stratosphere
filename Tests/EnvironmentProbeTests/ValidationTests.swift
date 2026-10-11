import Testing

@testable import EnvironmentProbe

struct ValidationTests {
  @Test func rejectsGuestMarkerOnPhysicalMac() {
    #expect(throws: ProbeFailure.self) {
      try Isolation.validate(
        profile: .guest, environment: ["STRATOSPHERE_GUEST": "1"], model: "Mac16,1")
    }
  }
  @Test func requiresBothGuestSignals() throws {
    try Isolation.validate(
      profile: .guest, environment: ["STRATOSPHERE_GUEST": "1"], model: "VirtualMac2,1")
    #expect(throws: ProbeFailure.self) {
      try Isolation.validate(profile: .guest, environment: [:], model: "VirtualMac2,1")
    }
  }
  @Test func refusesSelfHostedRunner() {
    #expect(throws: ProbeFailure.self) {
      try Isolation.validate(
        profile: .hosted,
        environment: [
          "GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS", "RUNNER_ENVIRONMENT": "self-hosted",
        ], model: "Mac16,1")
    }
  }
  @Test func acceptsHostedSignals() throws {
    try Isolation.validate(
      profile: .hosted,
      environment: [
        "GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS", "RUNNER_ENVIRONMENT": "github-hosted",
      ], model: "Mac16,1")
  }
  @Test func rejectsUnknownArgumentsAndProfiles() {
    for args in [
      ["--bogus"], ["--profile", "personal"], ["--profile", "guest"],
      [
        "--profile", "guest", "--profile", "guest", "--fixture", "/tmp/Fixture.app", "--output",
        "/tmp/result.json",
      ],
    ] {
      #expect(throws: ProbeFailure.self) { try Options.parse(args) }
    }
  }
  @Test func acceptsExactCLIContract() throws {
    let options = try Options.parse([
      "--profile", "guest", "--fixture", "/tmp/Fixture.app", "--output", "/tmp/result.json",
    ])
    #expect(options?.profile == .guest)
    #expect(options?.fixture.path == "/tmp/Fixture.app")
    #expect(try Options.parse(["--help"]) == nil)
  }
}
