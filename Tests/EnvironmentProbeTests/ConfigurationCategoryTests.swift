import Darwin
import Foundation
import Testing

@testable import EnvironmentProbe

@MainActor struct ConfigurationCategoryTests {
  @Test func helperSetupAndActionRepliesKeepDistinctCategories() throws {
    let script = FileManager.default.temporaryDirectory.appendingPathComponent(
      "stratosphere-category-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: script) }
    for (stage, expected) in [
      ("guard", FailureKind.setup), ("preflight", .setup), ("CGBeginDisplayConfiguration", .setup),
      ("CGConfigureDisplayOrigin", .assertion), ("CGCompleteDisplayConfiguration", .assertion),
    ] {
      let source =
        "#!/bin/sh\nprintf '%s' '{\"version\":1,\"success\":false,\"stage\":\"\(stage)\",\"kind\":\"\(expected == .setup ? "setup" : "assertion")\",\"error\":\"synthetic native failure\"}'\nexit 1\n"
      try source.write(to: script, atomically: true, encoding: .utf8)
      chmod(script.path, 0o700)
      do {
        try DisplayConfigurationHelper.apply([1: .zero], profile: .guest, executable: script.path)
        Issue.record("Helper failure accepted")
      } catch let error as DisplayConfigurationFailure { #expect(error.kind == expected) }
    }
  }
  @Test func callerCleanupContextOverridesHelperSetupReply() throws {
    let script = FileManager.default.temporaryDirectory.appendingPathComponent(
      "stratosphere-cleanup-category-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: script) }
    try
      "#!/bin/sh\nprintf '%s' '{\"version\":1,\"success\":false,\"stage\":\"guard\",\"kind\":\"setup\",\"error\":\"denied\"}'\nexit 1\n"
      .write(to: script, atomically: true, encoding: .utf8)
    chmod(script.path, 0o700)
    do {
      try DisplayConfigurationHelper.apply(
        [1: .zero], profile: .guest, kind: .cleanup, executable: script.path)
      Issue.record("Cleanup failure accepted")
    } catch let error as DisplayConfigurationFailure { #expect(error.kind == .cleanup) }
  }
  @Test func commandFailuresMapToCallerButPreserveOwnedCleanupFailure() {
    let launch = ProbeFailure("launch unavailable")
    #expect(DisplayConfigurationHelper.commandFailure(launch, kind: .assertion).kind == .assertion)
    #expect(DisplayConfigurationHelper.commandFailure(launch, kind: .cleanup).kind == .cleanup)
    #expect(
      DisplayConfigurationHelper.commandFailure(
        ProbeFailure("child cleanup", kind: .cleanup), kind: .assertion
      ).kind == .cleanup)
  }
}
