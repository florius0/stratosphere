import Foundation
import Darwin
import Testing
@testable import EnvironmentProbe

struct DisplayConfigurationTests {
    @Test func acceptsCompleteLiveIdsAndInt32NegativeOrigins() throws {
        let raw = #"{"version":1,"origins":[{"id":1,"x":0,"y":0},{"id":4,"x":-1440,"y":-800}]}"#
        let request = try DisplayConfigurationRequest.decode(Data(raw.utf8), live: [1,4])
        #expect(request.origins.count == 2)
        #expect(request.origins.last?.x == -1440)
    }
    @Test func rejectsMalformedFractionalDuplicateMissingAndForeignIds() {
        for raw in ["{}", #"{"version":1,"origins":[{"id":1,"x":0.5,"y":0}]}"#, #"{"version":1,"origins":[{"id":1,"x":2147483648,"y":0}]}"#, #"{"version":1,"origins":[{"id":1,"x":0,"y":0},{"id":1,"x":0,"y":0}]}"#, #"{"version":1,"origins":[{"id":1,"x":0,"y":0}]}"#, #"{"version":1,"origins":[{"id":1,"x":0,"y":0},{"id":3,"x":0,"y":0}]}"#] {
            #expect(throws: ProbeFailure.self) { try DisplayConfigurationRequest.decode(Data(raw.utf8), live: [1,4]) }
        }
    }
    @Test func refusesLossyOriginConversionBeforeLaunchingHelper() {
        #expect(throws: ProbeFailure.self) { try DisplayConfigurationRequest.make([1: CGPoint(x: 0.5, y: 0)]) }
        #expect(throws: ProbeFailure.self) { try DisplayConfigurationRequest.make([1: CGPoint(x: CGFloat.infinity, y: 0)]) }
    }
    @MainActor @Test func ownedHelperReceivesExactRequestAndRejectsBadReplies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stratosphere-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("helper"), request = directory.appendingPathComponent("request")
        let source = "#!/bin/sh\n[ \"$1\" = --configure-displays ] && [ \"$2\" = --profile ] && [ \"$3\" = guest ] && [ \"$4\" = --request ] || exit 2\nprintf '%s' \"$5\" > '\(request.path)'\nprintf '%s' '{\"version\":1,\"success\":true,\"stage\":\"complete\"}'\n"
        try source.write(to: script, atomically: true, encoding: .utf8); chmod(script.path, 0o700)
        try DisplayConfigurationHelper.apply([1: .zero, 4: CGPoint(x: -1440, y: -800)], profile: .guest, executable: script.path)
        let decoded = try DisplayConfigurationRequest.decode(Data(contentsOf: request), live: [1,4])
        #expect(decoded.origins.last?.x == -1440)
        try "#!/bin/sh\nprintf '%s' '{}'\n".write(to: script, atomically: true, encoding: .utf8); chmod(script.path, 0o700)
        #expect(throws: ProbeFailure.self) { try DisplayConfigurationHelper.apply([1: .zero], profile: .guest, executable: script.path) }
        let failure = "#!/bin/sh\nprintf '%s' '{\"version\":1,\"success\":false,\"stage\":\"CGConfigureDisplayOrigin\",\"kind\":\"assertion\",\"target\":4,\"cgError\":1001,\"error\":\"native failure\"}'\nexit 1\n"
        try failure.write(to: script, atomically: true, encoding: .utf8); chmod(script.path, 0o700)
        do { try DisplayConfigurationHelper.apply([1: .zero], profile: .guest, executable: script.path); Issue.record("Native helper failure accepted") }
        catch let error as DisplayConfigurationFailure { #expect(error.reply.target == 4); #expect(error.reply.cgError == 1001) }
    }

}
