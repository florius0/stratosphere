import Darwin
import Foundation
import Testing

@testable import EnvironmentProbe

struct DisplayReadoutTests {
  private var observation: DisplayObservation {
    DisplayObservation(
      id: 9, uuid: "00000000-0000-0000-0000-000000000009",
      bounds: CGRect(x: -1440, y: 0, width: 1440, height: 900),
      pixels: CGSize(width: 1440, height: 900), logical: CGSize(width: 1440, height: 900),
      refresh: 60, active: true, mirrored: false, main: true, vendor: 505, product: 1,
      serial: 791101)
  }
  @Test func preservesSuppliedStructuredGeometry() throws {
    let data = try JSONEncoder().encode(DisplaySnapshot(version: 1, displays: [observation]))
    #expect(try DisplaySnapshot.decode(data, kind: .assertion) == [observation])
  }
  @Test func rejectsMissingMalformedAndEmptyResults() {
    for raw in ["{}", "{", #"{"version":1,"displays":[]}"#] {
      #expect(throws: ProbeFailure.self) {
        try DisplaySnapshot.decode(Data(raw.utf8), kind: .assertion)
      }
    }
  }
  @Test func rejectsDuplicateIdentityAndUnsupportedVersion() throws {
    for snapshot in [
      DisplaySnapshot(version: 2, displays: [observation]),
      DisplaySnapshot(version: 1, displays: [observation, observation]),
    ] {
      let data = try JSONEncoder().encode(snapshot)
      #expect(throws: ProbeFailure.self) { try DisplaySnapshot.decode(data, kind: .assertion) }
    }
  }
  @Test func readOnlyArgumentsRequireExplicitKnownProfile() throws {
    #expect(try DisplayReadout.profile(["--observe-displays", "--profile", "guest"]) == .guest)
    for args in [
      ["--observe-displays"], ["--observe-displays", "--profile", "host"],
      ["--observe-displays", "--profile", "guest", "--fixture", "/tmp/app"],
    ] {
      #expect(throws: ProbeFailure.self) { try DisplayReadout.profile(args) }
    }
  }
  @Test func rejectsMissingUuidAndInvalidGeometryWithCallerCategory() throws {
    var bad = observation
    bad.logical.width = 0
    let data = try JSONEncoder().encode(DisplaySnapshot(version: 1, displays: [bad]))
    for kind in [FailureKind.setup, .assertion, .cleanup] {
      do {
        _ = try DisplaySnapshot.decode(data, kind: kind)
        Issue.record("Invalid geometry accepted")
      } catch let error as ProbeFailure { #expect(error.kind == kind) }
    }
    let valid = try JSONEncoder().encode(DisplaySnapshot(version: 1, displays: [observation]))
    var object = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    var displays = try #require(object["displays"] as? [[String: Any]])
    displays[0].removeValue(forKey: "uuid")
    object["displays"] = displays
    #expect(throws: ProbeFailure.self) {
      try DisplaySnapshot.decode(JSONSerialization.data(withJSONObject: object), kind: .assertion)
    }
  }
  @MainActor @Test func freshOwnedReadoutProcessForEverySnapshot() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "stratosphere-reader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let script = directory.appendingPathComponent("reader")
    let pids = directory.appendingPathComponent("pids")
    let data = try JSONEncoder().encode(DisplaySnapshot(version: 1, displays: [observation]))
    let payload = String(decoding: data, as: UTF8.self)
    let source =
      "#!/bin/sh\n[ \"$1\" = --observe-displays ] && [ \"$2\" = --profile ] && [ \"$3\" = guest ] || exit 2\nprintf '%s\\n' \"$$\" >> '\(pids.path)'\nprintf '%s\\n' '\(payload)'\n"
    try source.write(to: script, atomically: true, encoding: .utf8)
    chmod(script.path, 0o700)
    #expect(
      try DisplayReadout.read(profile: .guest, kind: .assertion, executable: script.path) == [
        observation
      ])
    #expect(
      try DisplayReadout.read(profile: .guest, kind: .assertion, executable: script.path) == [
        observation
      ])
    let children = try String(contentsOf: pids, encoding: .utf8).split(separator: "\n")
    #expect(children.count == 2)
    #expect(Set(children).count == 2)
    for text in children {
      let pid = try #require(Int32(text))
      #expect(kill(pid, 0) == -1)
      #expect(errno == ESRCH)
    }
  }
  @MainActor @Test func unsuccessfulReadoutDoesNotBecomeEmptySuccess() {
    do {
      _ = try DisplayReadout.read(profile: .guest, kind: .assertion, executable: "/usr/bin/false")
      Issue.record("Unsuccessful helper accepted")
    } catch let error as ProbeFailure { #expect(error.kind == .assertion) } catch {
      Issue.record("Unexpected failure: \(error)")
    }
  }

}
