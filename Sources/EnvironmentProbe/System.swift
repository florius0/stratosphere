import AppKit
import ApplicationServices
import Darwin

@MainActor enum SystemObservation {
    static func sysctl(_ name: String) throws -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { throw ProbeFailure("Cannot read \(name)") }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { throw ProbeFailure("Cannot read \(name)") }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    static func command(_ executable: String, _ arguments: [String], timeout: Double = 10) throws -> (Int32, String) {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("stratosphere-metadata-\(UUID().uuidString).txt")
        let descriptor = open(output.path, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw ProbeFailure("Cannot create metadata output") }
        defer { Darwin.close(descriptor); try? FileManager.default.removeItem(at: output) }
        let child = OwnedProcess()
        do {
            try child.launch(executable: URL(fileURLWithPath: executable), arguments: arguments, outputDescriptor: descriptor)
            guard try child.waitForExit(seconds: timeout) else {
                try child.stop()
                throw ProbeFailure("Metadata command timed out: \(executable)")
            }
            guard let status = child.terminationStatus else { throw ProbeFailure("Metadata command status unavailable") }
            let data = try Data(contentsOf: output)
            return (status, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            let commandError = error
            do { try child.stop() }
            catch { throw ProbeFailure("Metadata child cleanup failed: \(error)", kind: .cleanup) }
            throw commandError
        }
    }
    static func wait(_ reason: String, seconds: Double = 8, kind: FailureKind = .setup, _ condition: () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if try condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        throw ProbeFailure("Timed out waiting for \(reason)", kind: kind)
    }
    static func validateSession() throws -> [String: Any] {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true,
              (session[kCGSessionUserIDKey as String] as? NSNumber)?.uint32Value == getuid() else {
            throw ProbeFailure("Probe must execute as the active GUI login user in the console session.")
        }
        return ["on_console": true, "login_complete": true, "uid": getuid()]
    }
}
