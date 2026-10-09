import Foundation
import Darwin
import Testing
@testable import EnvironmentProbe

struct DisplayPresenceTests {
    @Test func presenceDoesNotRequireModeFieldsDuringRemoval() throws {
        #expect(try DisplayIDSnapshot.decode(Data(#"{"version":1,"ids":[1]}"#.utf8), kind: .cleanup) == [1])
    }
    @Test func rejectsInvalidPresenceResults() {
        for raw in ["{}", "{", #"{"version":2,"ids":[1]}"#, #"{"version":1,"ids":[1,1]}"#, #"{"version":1,"ids":[0]}"#, #"{"version":1,"ids":[]}"#] {
            #expect(throws: ProbeFailure.self) { try DisplayIDSnapshot.decode(Data(raw.utf8), kind: .cleanup) }
        }
    }
    @Test func presenceHelperRequiresKnownProfileAndExactArguments() throws {
        #expect(try DisplayReadout.profile(["--observe-display-ids", "--profile", "guest"]) == .guest)
        #expect(throws: ProbeFailure.self) { try DisplayReadout.profile(["--observe-display-ids", "--profile", "personal"]) }
    }
    @MainActor @Test func ownedPresenceHelperUsesIdsOnlyMode() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("stratosphere-presence-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: script) }
        let source = "#!/bin/sh\n[ \"$1\" = --observe-display-ids ] && [ \"$2\" = --profile ] && [ \"$3\" = guest ] || exit 2\nprintf '%s\\n' '{\"version\":1,\"ids\":[1]}'\n"
        try source.write(to: script, atomically: true, encoding: .utf8)
        chmod(script.path, 0o700)
        #expect(try DisplayReadout.identifiers(profile: .guest, kind: .cleanup, executable: script.path) == [1])
    }

}
