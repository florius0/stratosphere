import Darwin
import Foundation
import Testing
@testable import EnvironmentProbe

@MainActor struct ProcessOwnerTests {
    @Test func childInheritsProbeProcessGroup() throws {
        let child = OwnedProcess()
        try child.launch(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        defer { try? child.stop() }
        #expect(getpgid(child.processIdentifier) == getpgrp())
        try child.stop()
        #expect(try !child.isRunning())
    }
    @Test func metadataCommandCapturesOutputAndStatus() throws {
        let result = try SystemObservation.command("/bin/sh", ["-c", "printf synthetic-metadata; exit 7"])
        #expect(result.0 == 7)
        #expect(result.1 == "synthetic-metadata")
    }
    @Test func escalatesOnlyOwnedChildWhenTermIsIgnored() throws {
        let child = OwnedProcess()
        let ready = FileManager.default.temporaryDirectory.appendingPathComponent("stratosphere-child-ready-\(UUID().uuidString)")
        let descriptor = open(ready.path, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw ProbeFailure("Could not create test child observation") }
        defer { Darwin.close(descriptor); try? FileManager.default.removeItem(at: ready) }
        try child.launch(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "trap '' TERM; printf ready; exec /bin/sleep 30"], outputDescriptor: descriptor)
        defer { try? child.stop() }
        try SystemObservation.wait("harmless child to ignore TERM", seconds: 2, kind: .assertion) {
            try String(contentsOf: ready, encoding: .utf8) == "ready"
        }
        try child.stop(termGrace: 0.05, killGrace: 1)
        #expect(try !child.isRunning())
        #expect(child.status.map { $0 & 0x7f } == SIGKILL)
    }
}
