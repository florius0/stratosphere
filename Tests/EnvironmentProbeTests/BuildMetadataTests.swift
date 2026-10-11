import Testing

@testable import EnvironmentProbe

struct BuildMetadataTests {
  @Test func missingMetadataIsUnavailable() {
    let metadata = BuildMetadata.read(nil)
    #expect(metadata.status == "unavailable")
    #expect(metadata.values["compiler"] == "unavailable")
    #expect(metadata.values["sdk"] == "unavailable")
  }
  @Test func preservesHostBuildVersionsWithoutImplyingRuntimeVersions() {
    let metadata = BuildMetadata.read(
      #"{"compiler":"Apple Swift 6.3.3","sdk":"26.5","macOS":"26.5","sourceRevision":"abc-dirty","xcode":"Xcode 26.5","sdkPath":"/private/host/sdk","secret":"discard"}"#
    )
    #expect(metadata.status == "provided")
    #expect(metadata.values["compiler"] == "Apple Swift 6.3.3")
    #expect(metadata.values["sdk"] == "26.5")
    #expect(metadata.values["sourceRevision"] == "abc-dirty")
    #expect(metadata.values["sdkPath"] == nil)
    #expect(metadata.values["secret"] == nil)
  }
  @Test func malformedMetadataIsExplicitlyInvalid() {
    for raw in ["{", "[]", #"{"compiler":42}"#, #"{"sdk":""}"#, #"{"compiler":"bad\u0000value"}"#] {
      let metadata = BuildMetadata.read(raw)
      #expect(metadata.status == "invalid")
      #expect(metadata.values["compiler"] == "unavailable")
    }
  }
}
