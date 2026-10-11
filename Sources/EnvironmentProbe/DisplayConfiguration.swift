import AppKit

struct DisplayOrigin: Codable {
  let id: CGDirectDisplayID
  let x: Int32
  let y: Int32
}
struct DisplayConfigurationRequest: Codable {
  let version: Int
  let origins: [DisplayOrigin]
  static func decode(_ data: Data, live: [CGDirectDisplayID]) throws -> Self {
    guard data.count <= 262_144, let request = try? JSONDecoder().decode(Self.self, from: data),
      request.version == 1,
      !request.origins.isEmpty, request.origins.allSatisfy({ $0.id != 0 }),
      Set(request.origins.map(\.id)).count == request.origins.count,
      Set(request.origins.map(\.id)) == Set(live)
    else {
      throw ProbeFailure(
        "Configuration request must contain exact Int32 origins for every unique live display")
    }
    return request
  }
  static func make(_ origins: [CGDirectDisplayID: CGPoint]) throws -> Self {
    let entries = try origins.keys.sorted().map { id -> DisplayOrigin in
      guard id != 0, let point = origins[id], let x = Int32(exactly: point.x),
        let y = Int32(exactly: point.y)
      else {
        throw ProbeFailure("Configuration origin is not an exact Int32 value", kind: .assertion)
      }
      return DisplayOrigin(id: id, x: x, y: y)
    }
    guard !entries.isEmpty else {
      throw ProbeFailure("Empty configuration request", kind: .assertion)
    }
    return Self(version: 1, origins: entries)
  }
}
struct DisplayConfigurationReply: Codable {
  let version: Int
  let success: Bool
  let stage: String
  let kind: FailureKind?
  let target: CGDirectDisplayID?
  let cgError: Int32?
  let error: String?
}
struct DisplayConfigurationFailure: Error, CustomStringConvertible {
  let reply: DisplayConfigurationReply
  let kind: FailureKind
  var description: String { reply.error ?? "Display configuration failed at \(reply.stage)" }
}
@MainActor enum DisplayConfigurationHelper {
  static func apply(
    _ origins: [CGDirectDisplayID: CGPoint], profile: Profile, kind: FailureKind = .assertion,
    executable: String = CommandLine.arguments[0]
  ) throws {
    let request = try JSONEncoder().encode(DisplayConfigurationRequest.make(origins))
    let output: (Int32, String)
    do {
      output = try SystemObservation.command(
        executable,
        [
          "--configure-displays", "--profile", profile.rawValue, "--request",
          String(decoding: request, as: UTF8.self),
        ], timeout: 8)
    } catch { throw commandFailure(error, kind: kind) }
    guard output.1.utf8.count <= 262_144,
      let reply = try? JSONDecoder().decode(
        DisplayConfigurationReply.self, from: Data(output.1.utf8)), reply.version == 1
    else { throw ProbeFailure("Configuration helper returned malformed result", kind: kind) }
    if output.0 == 0, reply.success, reply.stage == "complete", reply.kind == nil,
      reply.cgError == nil, reply.error == nil
    {
      return
    }
    let setupStages = ["guard", "preflight", "CGBeginDisplayConfiguration"]
    let actionStages = [
      "CGConfigureDisplayMirrorOfDisplay", "CGConfigureDisplayOrigin",
      "CGCompleteDisplayConfiguration",
    ]
    guard !reply.success, let category = reply.kind, reply.error != nil,
      (setupStages.contains(reply.stage) && category == .setup)
        || (actionStages.contains(reply.stage) && category == .assertion)
        || ((setupStages + actionStages).contains(reply.stage) && category == .cleanup)
    else {
      throw ProbeFailure("Configuration helper returned invalid failure category", kind: kind)
    }
    throw DisplayConfigurationFailure(reply: reply, kind: kind == .cleanup ? .cleanup : category)
  }
  static func commandFailure(_ error: Error, kind: FailureKind) -> ProbeFailure {
    if let failure = error as? ProbeFailure, failure.kind == .cleanup { return failure }
    return ProbeFailure("Configuration helper command failed: \(error)", kind: kind)
  }
  static func run(_ arguments: [String]) -> Int32 {
    var stage = "guard"
    var target: CGDirectDisplayID?
    var cgError: Int32?
    var category = FailureKind.setup
    do {
      guard arguments.count == 5, arguments[0] == "--configure-displays",
        arguments[1] == "--profile", arguments[3] == "--request",
        let profile = Profile(rawValue: arguments[2])
      else { throw ProbeFailure("Invalid display configuration helper arguments") }
      try DisplayReadout.validateContext(profile: profile)
      let sip = try SystemObservation.command("/usr/bin/csrutil", ["status"])
      guard sip.0 == 0, sip.1.contains("System Integrity Protection status: enabled.") else {
        throw ProbeFailure("Configuration requires SIP enabled")
      }
      stage = "preflight"
      let request = try DisplayConfigurationRequest.decode(
        Data(arguments[4].utf8), live: DisplayReadout.rawIdentifiers(kind: .setup))
      var transaction: CGDisplayConfigRef?
      stage = "CGBeginDisplayConfiguration"
      var result = CGBeginDisplayConfiguration(&transaction)
      cgError = result.rawValue
      guard result == .success, let transaction else {
        throw ProbeFailure("\(stage) failed with CGError \(result.rawValue)")
      }
      category = .assertion
      var committed = false
      defer { if !committed { CGCancelDisplayConfiguration(transaction) } }
      for origin in request.origins.sorted(by: { $0.id < $1.id }) {
        target = origin.id
        stage = "CGConfigureDisplayMirrorOfDisplay"
        result = CGConfigureDisplayMirrorOfDisplay(transaction, origin.id, kCGNullDirectDisplay)
        cgError = result.rawValue
        guard result == .success else {
          throw ProbeFailure(
            "\(stage) failed for display \(origin.id) with CGError \(result.rawValue)",
            kind: .assertion)
        }
        stage = "CGConfigureDisplayOrigin"
        result = CGConfigureDisplayOrigin(transaction, origin.id, origin.x, origin.y)
        cgError = result.rawValue
        guard result == .success else {
          throw ProbeFailure(
            "\(stage) failed for display \(origin.id) with CGError \(result.rawValue)",
            kind: .assertion)
        }
      }
      stage = "CGCompleteDisplayConfiguration"
      target = nil
      result = CGCompleteDisplayConfiguration(transaction, .forSession)
      cgError = result.rawValue
      guard result == .success else {
        throw ProbeFailure("\(stage) failed with CGError \(result.rawValue)", kind: .assertion)
      }
      committed = true
      emit(
        DisplayConfigurationReply(
          version: 1, success: true, stage: "complete", kind: nil, target: nil, cgError: nil,
          error: nil))
      return 0
    } catch {
      emit(
        DisplayConfigurationReply(
          version: 1, success: false, stage: stage,
          kind: (error as? ProbeFailure)?.kind ?? category, target: target, cgError: cgError,
          error: String(describing: error)))
      return 1
    }
  }
  private static func emit(_ reply: DisplayConfigurationReply) {
    if let data = try? JSONEncoder().encode(reply) { print(String(decoding: data, as: UTF8.self)) }
  }
}
