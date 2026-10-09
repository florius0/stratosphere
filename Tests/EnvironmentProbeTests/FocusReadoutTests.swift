import Foundation
import Testing
@testable import EnvironmentProbe

struct FocusReadoutTests {
    @Test func preservesDisagreementAndCannotCompleteAsDiagnosticData() throws {
        let snapshot = FocusSnapshot(version: 1, target: 42, targetLive: true, workspacePID: 7, nativeActive: false, axTrusted: true, systemStatus: -25204, systemPID: nil)
        let result = try FocusSnapshot.decode(JSONEncoder().encode(snapshot), target: 42)
        #expect(result.workspacePID == 7)
        #expect(result.systemStatus == -25204)
        #expect(result.systemPID == nil)
        #expect(result.nativeActive == false)
    }
    @Test func rejectsMalformedWrongPidAndUnsupportedVersion() throws {
        #expect(throws: ProbeFailure.self) { try FocusSnapshot.decode(Data("{}".utf8), target: 42) }
        let snapshot = FocusSnapshot(version: 2, target: 41, targetLive: true, workspacePID: 41, nativeActive: true, axTrusted: true, systemStatus: 0, systemPID: 41)
        #expect(throws: ProbeFailure.self) { try FocusSnapshot.decode(JSONEncoder().encode(snapshot), target: 42) }
    }
}
