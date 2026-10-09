import AppKit
import ApplicationServices
import Darwin

struct FocusSnapshot: Codable {
    let version: Int
    let target: pid_t
    let targetLive: Bool
    let workspacePID: pid_t?
    let nativeActive: Bool?
    let axTrusted: Bool
    let systemStatus: Int32
    let systemPID: pid_t?
    static func decode(_ data: Data, target: pid_t) throws -> Self {
        guard data.count <= 65_536, let snapshot = try? JSONDecoder().decode(Self.self, from: data), snapshot.version == 1, snapshot.target == target, target > 0 else { throw ProbeFailure("Malformed focus observer reply", kind: .assertion) }
        return snapshot
    }
}
@MainActor enum FocusReadout {
    static func read(target: pid_t, profile: Profile, executable: String = CommandLine.arguments[0]) throws -> FocusSnapshot {
        let result = try SystemObservation.command(executable, ["--observe-focus", "--profile", profile.rawValue, "--pid", String(target)], timeout: 4)
        guard result.0 == 0 else { throw ProbeFailure("Focus observer failed: \(result.1)", kind: .assertion) }
        return try FocusSnapshot.decode(Data(result.1.utf8), target: target)
    }
    static func run(_ arguments: [String]) -> Int32 {
        do {
            guard arguments.count == 5, arguments[0] == "--observe-focus", arguments[1] == "--profile", arguments[3] == "--pid", let profile = Profile(rawValue: arguments[2]), let target = pid_t(arguments[4]), target > 0 else { throw ProbeFailure("Invalid focus observer arguments") }
            try DisplayReadout.validateContext(profile: profile)
            let application = NSRunningApplication(processIdentifier: target)
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 2)
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &value)
            var focusedPID: pid_t?
            if status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                var pid: pid_t = 0
                if AXUIElementGetPid(value as! AXUIElement, &pid) == .success { focusedPID = pid }
            }
            let snapshot = FocusSnapshot(version: 1, target: target, targetLive: application != nil && application?.isTerminated == false, workspacePID: NSWorkspace.shared.frontmostApplication?.processIdentifier, nativeActive: application?.isActive, axTrusted: AXIsProcessTrusted(), systemStatus: status.rawValue, systemPID: focusedPID)
            print(String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)); return 0
        } catch { fputs("\(error)\n", stderr); return 1 }
    }
}
