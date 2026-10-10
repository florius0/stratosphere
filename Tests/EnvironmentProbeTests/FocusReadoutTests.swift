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
    @MainActor @Test func retainsBeforeAfterDisagreementAndExactReadOrder() throws {
        var order: [String] = [], reads = 0
        let result = FocusReadout.measure(target: 42, live: true, trust: { order.append("trust"); return true }, system: {
            reads += 1; order.append("ax\(reads)")
            return reads == 1 ? (-25204, nil, 2000) : (0, 42, 1)
        }, workspace: { order.append("workspace"); return 42 }, active: { order.append("active"); return true }, app: { order.append("app"); return (0, true, 0) })
        #expect(order == ["trust", "ax1", "workspace", "active", "ax2", "app", "ax3"])
        let decoded = try FocusSnapshot.decode(JSONEncoder().encode(result), target: 42)
        #expect(decoded.systemStatus == -25204)
        #expect(decoded.systemPID == nil)
        #expect(decoded.systemAfterStatus == 0)
        #expect(decoded.systemAfterPID == 42)
    }

    @MainActor @Test func appStageRetainsEarlierErrorsAndReadDurations() {
        var reads = 0, appRead = false
        let result = FocusReadout.measure(target: 42, live: true, trust: { true }, system: {
            reads += 1
            return appRead ? (0, 42, 1) : (-25204, nil, 2000)
        }, workspace: { 42 }, active: { true }, app: { appRead = true; return (0, true, 0) })
        #expect(reads == 3)
        #expect(result.systemStatus == -25204)
        #expect(result.systemAfterStatus == -25204)
        #expect(result.systemAfterAppStatus == 0)
        #expect(result.systemAfterAppPID == 42)
        #expect(result.systemDurationMs == 2000)
        #expect(result.systemAfterAppDurationMs == 1)
        #expect(result.appFrontmostStatus == 0)
        #expect(result.appFrontmost == true)
    }

}
