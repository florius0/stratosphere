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

enum DisplayReadout {
    static func profile(_ arguments: [String]) throws -> Profile {
        guard arguments.count == 3, arguments[0] == "--observe-displays", arguments[1] == "--profile", let profile = Profile(rawValue: arguments[2]) else {
            throw ProbeFailure("Display observation requires --observe-displays --profile hosted|guest")
        }
        return profile
    }
    @MainActor static func read(profile: Profile, kind: FailureKind, executable: String = CommandLine.arguments[0]) throws -> [DisplayObservation] {
        let output: (Int32, String)
        do { output = try SystemObservation.command(executable, ["--observe-displays", "--profile", profile.rawValue], timeout: 4) }
        catch {
            if (error as? ProbeFailure)?.kind == .cleanup { throw error }
            throw ProbeFailure("Display observer failed: \(error)", kind: kind)
        }
        guard output.0 == 0 else { throw ProbeFailure("Display observer exited \(output.0): \(output.1)", kind: kind) }
        return try DisplaySnapshot.decode(Data(output.1.utf8), kind: kind)
    }
    @MainActor static func run(_ arguments: [String]) -> Int32 {
        do {
            let profile = try profile(arguments)
            try Isolation.validate(profile: profile, environment: ProcessInfo.processInfo.environment, model: SystemObservation.sysctl("hw.model"))
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26, try SystemObservation.sysctl("hw.machine") == "arm64" else {
                throw ProbeFailure("Display observation requires macOS 26+ on arm64")
            }
            _ = try SystemObservation.validateSession()
            let snapshot = DisplaySnapshot(version: 1, displays: try observe())
            let data = try JSONEncoder().encode(snapshot)
            _ = try DisplaySnapshot.decode(data, kind: .setup)
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch { fputs("\(error)\n", stderr); return 1 }
    }
    @MainActor static func identifiers(kind: FailureKind) throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { throw ProbeFailure("Cannot read display topology", kind: kind) }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { throw ProbeFailure("Cannot read display topology", kind: kind) }
        return ids.prefix(Int(count)).sorted()
    }
    @MainActor private static func observe() throws -> [DisplayObservation] {
        try identifiers(kind: .setup).map { id in
            guard let mode = CGDisplayCopyDisplayMode(id) else { throw ProbeFailure("Display mode unavailable for \(id)") }
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(), let text = CFUUIDCreateString(nil, uuid) else { throw ProbeFailure("Display UUID unavailable for \(id)") }
            return DisplayObservation(id: id, uuid: text as String, bounds: CGDisplayBounds(id), pixels: CGSize(width: mode.pixelWidth, height: mode.pixelHeight), logical: CGSize(width: mode.width, height: mode.height), refresh: mode.refreshRate, mirrored: CGDisplayIsInMirrorSet(id) != 0, main: CGDisplayIsMain(id) != 0, vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
        }
    }
}
