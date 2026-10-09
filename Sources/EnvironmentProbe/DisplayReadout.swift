import AppKit

struct DisplaySnapshot: Codable {
    let version: Int
    let displays: [DisplayObservation]

    static func decode(_ data: Data, kind: FailureKind) throws -> [DisplayObservation] {
        guard data.count <= 262_144, let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.version == 1, !snapshot.displays.isEmpty,
              Set(snapshot.displays.map(\.id)).count == snapshot.displays.count else {
            throw ProbeFailure("Display observer returned malformed, unsupported or empty topology", kind: kind)
        }
        for display in snapshot.displays {
            let dimensions = [display.bounds.width, display.bounds.height, display.pixels.width, display.pixels.height, display.logical.width, display.logical.height]
            guard display.id != 0, UUID(uuidString: display.uuid) != nil,
                  dimensions.allSatisfy({ $0.isFinite && $0 > 0 }), display.bounds.minX.isFinite, display.bounds.minY.isFinite,
                  display.refresh.isFinite, display.refresh >= 0 else {
                throw ProbeFailure("Display observer returned invalid identity or geometry", kind: kind)
            }
        }
        guard snapshot.displays.filter(\.main).count == 1 else { throw ProbeFailure("Display observer returned no unique main display", kind: kind) }
        return snapshot.displays
    }
}

struct DisplayIDSnapshot: Codable {
    let version: Int
    let ids: [CGDirectDisplayID]
    static func decode(_ data: Data, kind: FailureKind) throws -> [CGDirectDisplayID] {
        guard data.count <= 262_144, let snapshot = try? JSONDecoder().decode(Self.self, from: data), snapshot.version == 1,
              !snapshot.ids.isEmpty, snapshot.ids.allSatisfy({ $0 != 0 }), Set(snapshot.ids).count == snapshot.ids.count else {
            throw ProbeFailure("Display presence observer returned invalid identifiers", kind: kind)
        }
        return snapshot.ids
    }
}

enum DisplayReadout {
    static func profile(_ arguments: [String]) throws -> Profile {
        guard arguments.count == 3, ["--observe-displays", "--observe-display-ids"].contains(arguments[0]), arguments[1] == "--profile", let profile = Profile(rawValue: arguments[2]) else {
            throw ProbeFailure("Display observation requires --observe-displays --profile hosted|guest")
        }
        return profile
    }
    @MainActor static func read(profile: Profile, kind: FailureKind, executable: String = CommandLine.arguments[0]) throws -> [DisplayObservation] {
        try DisplaySnapshot.decode(request("--observe-displays", profile: profile, kind: kind, executable: executable), kind: kind)
    }
    @MainActor static func identifiers(profile: Profile, kind: FailureKind, executable: String = CommandLine.arguments[0]) throws -> [CGDirectDisplayID] {
        try DisplayIDSnapshot.decode(request("--observe-display-ids", profile: profile, kind: kind, executable: executable), kind: kind)
    }
    @MainActor private static func request(_ mode: String, profile: Profile, kind: FailureKind, executable: String) throws -> Data {
        let output: (Int32, String)
        do { output = try SystemObservation.command(executable, [mode, "--profile", profile.rawValue], timeout: 4) }
        catch {
            if (error as? ProbeFailure)?.kind == .cleanup { throw error }
            throw ProbeFailure("Display observer failed: \(error)", kind: kind)
        }
        guard output.0 == 0 else { throw ProbeFailure("Display observer exited \(output.0): \(output.1)", kind: kind) }
        return Data(output.1.utf8)
    }
    @MainActor static func run(_ arguments: [String]) -> Int32 {
        do {
            let profile = try profile(arguments)
            try validateContext(profile: profile)
            let data: Data
            if arguments[0] == "--observe-display-ids" {
                data = try JSONEncoder().encode(DisplayIDSnapshot(version: 1, ids: try rawIdentifiers(kind: .setup)))
                _ = try DisplayIDSnapshot.decode(data, kind: .setup)
            } else {
                data = try JSONEncoder().encode(DisplaySnapshot(version: 1, displays: try observe()))
                _ = try DisplaySnapshot.decode(data, kind: .setup)
            }
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch { fputs("\(error)\n", stderr); return 1 }
    }
    @MainActor static func validateContext(profile: Profile) throws {
        try Isolation.validate(profile: profile, environment: ProcessInfo.processInfo.environment, model: SystemObservation.sysctl("hw.model"))
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26, try SystemObservation.sysctl("hw.machine") == "arm64" else { throw ProbeFailure("Display helper requires macOS 26+ on arm64") }
        _ = try SystemObservation.validateSession()
    }
    @MainActor static func rawIdentifiers(kind: FailureKind) throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { throw ProbeFailure("Cannot read display topology", kind: kind) }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { throw ProbeFailure("Cannot read display topology", kind: kind) }
        return ids.prefix(Int(count)).sorted()
    }
    @MainActor private static func observe() throws -> [DisplayObservation] {
        try rawIdentifiers(kind: .setup).map { id in
            guard let mode = CGDisplayCopyDisplayMode(id) else { throw ProbeFailure("Display mode unavailable for \(id)") }
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(), let text = CFUUIDCreateString(nil, uuid) else { throw ProbeFailure("Display UUID unavailable for \(id)") }
            return DisplayObservation(id: id, uuid: text as String, bounds: CGDisplayBounds(id), pixels: CGSize(width: mode.pixelWidth, height: mode.pixelHeight), logical: CGSize(width: mode.width, height: mode.height), refresh: mode.refreshRate, active: CGDisplayIsActive(id) != 0, mirrored: CGDisplayIsInMirrorSet(id) != 0, main: CGDisplayIsMain(id) != 0, vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
        }
    }
}
