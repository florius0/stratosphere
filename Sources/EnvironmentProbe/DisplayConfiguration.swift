import AppKit

struct DisplayOrigin: Codable { let id: CGDirectDisplayID; let x: Int32; let y: Int32 }
struct DisplayConfigurationRequest: Codable {
    let version: Int
    let origins: [DisplayOrigin]
    static func decode(_ data: Data, live: [CGDirectDisplayID]) throws -> Self {
        guard data.count <= 262_144, let request = try? JSONDecoder().decode(Self.self, from: data), request.version == 1,
              !request.origins.isEmpty, request.origins.allSatisfy({ $0.id != 0 }),
              Set(request.origins.map(\.id)).count == request.origins.count, Set(request.origins.map(\.id)) == Set(live) else {
            throw ProbeFailure("Configuration request must contain exact Int32 origins for every unique live display")
        }
        return request
    }
    static func make(_ origins: [CGDirectDisplayID: CGPoint]) throws -> Self {
        let entries = try origins.keys.sorted().map { id -> DisplayOrigin in
            guard id != 0, let point = origins[id], let x = Int32(exactly: point.x), let y = Int32(exactly: point.y) else { throw ProbeFailure("Configuration origin is not an exact Int32 value", kind: .assertion) }
            return DisplayOrigin(id: id, x: x, y: y)
        }
        guard !entries.isEmpty else { throw ProbeFailure("Empty configuration request", kind: .assertion) }
        return Self(version: 1, origins: entries)
    }
}
struct DisplayConfigurationReply: Codable {
    let version: Int
    let success: Bool
    let stage: String
    let target: CGDirectDisplayID?
    let cgError: Int32?
    let error: String?
}
struct DisplayConfigurationFailure: Error, CustomStringConvertible {
    let reply: DisplayConfigurationReply
    var description: String { reply.error ?? "Display configuration failed at \(reply.stage)" }
}
@MainActor enum DisplayConfigurationHelper {
    static func apply(_ origins: [CGDirectDisplayID: CGPoint], profile: Profile, executable: String = CommandLine.arguments[0]) throws {
        let request = try JSONEncoder().encode(DisplayConfigurationRequest.make(origins))
        let output = try SystemObservation.command(executable, ["--configure-displays", "--profile", profile.rawValue, "--request", String(decoding: request, as: UTF8.self)], timeout: 8)
        guard output.1.utf8.count <= 262_144, let reply = try? JSONDecoder().decode(DisplayConfigurationReply.self, from: Data(output.1.utf8)), reply.version == 1 else { throw ProbeFailure("Configuration helper returned malformed result", kind: .assertion) }
        guard output.0 == 0, reply.success, reply.stage == "complete", reply.cgError == nil, reply.error == nil else { throw DisplayConfigurationFailure(reply: reply) }
    }
    static func run(_ arguments: [String]) -> Int32 {
        var stage = "guard", target: CGDirectDisplayID?, cgError: Int32?
        do {
            guard arguments.count == 5, arguments[0] == "--configure-displays", arguments[1] == "--profile", arguments[3] == "--request", let profile = Profile(rawValue: arguments[2]) else { throw ProbeFailure("Invalid display configuration helper arguments") }
            try DisplayReadout.validateContext(profile: profile)
            let sip = try SystemObservation.command("/usr/bin/csrutil", ["status"])
            guard sip.0 == 0, sip.1.contains("System Integrity Protection status: enabled.") else { throw ProbeFailure("Configuration requires SIP enabled") }
            stage = "preflight"
            let request = try DisplayConfigurationRequest.decode(Data(arguments[4].utf8), live: DisplayReadout.rawIdentifiers(kind: .setup))
            var transaction: CGDisplayConfigRef?
            stage = "CGBeginDisplayConfiguration"
            var result = CGBeginDisplayConfiguration(&transaction)
            cgError = result.rawValue
            guard result == .success, let transaction else { throw ProbeFailure("\(stage) failed with CGError \(result.rawValue)") }
            var committed = false
            defer { if !committed { CGCancelDisplayConfiguration(transaction) } }
            for origin in request.origins.sorted(by: { $0.id < $1.id }) {
                target = origin.id
                stage = "CGConfigureDisplayMirrorOfDisplay"
                result = CGConfigureDisplayMirrorOfDisplay(transaction, origin.id, kCGNullDirectDisplay)
                cgError = result.rawValue
                guard result == .success else { throw ProbeFailure("\(stage) failed for display \(origin.id) with CGError \(result.rawValue)") }
                stage = "CGConfigureDisplayOrigin"
                result = CGConfigureDisplayOrigin(transaction, origin.id, origin.x, origin.y)
                cgError = result.rawValue
                guard result == .success else { throw ProbeFailure("\(stage) failed for display \(origin.id) with CGError \(result.rawValue)") }
            }
            stage = "CGCompleteDisplayConfiguration"; target = nil
            result = CGCompleteDisplayConfiguration(transaction, .forSession)
            cgError = result.rawValue
            guard result == .success else { throw ProbeFailure("\(stage) failed with CGError \(result.rawValue)") }
            committed = true
            emit(DisplayConfigurationReply(version: 1, success: true, stage: "complete", target: nil, cgError: nil, error: nil))
            return 0
        } catch {
            emit(DisplayConfigurationReply(version: 1, success: false, stage: stage, target: target, cgError: cgError, error: String(describing: error)))
            return 1
        }
    }
    private static func emit(_ reply: DisplayConfigurationReply) {
        if let data = try? JSONEncoder().encode(reply) { print(String(decoding: data, as: UTF8.self)) }
    }
}
