import Foundation

enum FailureKind: String, Codable {
  case setup, assertion, cleanup
  var status: String { self == .setup ? "setup-failed" : "failed" }
}
struct ProbeFailure: Error, CustomStringConvertible {
  let message: String
  let kind: FailureKind
  init(_ message: String, kind: FailureKind = .setup) {
    self.message = message
    self.kind = kind
  }
  var description: String { message }
  var status: String { kind.status }
}
enum Profile: String { case hosted, guest }
struct Options: Equatable {
  var profile: Profile
  var fixture: URL
  var output: URL
  static let usage =
    "EnvironmentProbe --profile hosted|guest --fixture PATH_TO_APP --output PATH_TO_JSON"
  static func parse(_ arguments: [String]) throws -> Options? {
    if arguments == ["--help"] { return nil }
    var values: [String: String] = [:]
    guard arguments.count == 6 else { throw ProbeFailure(usage) }
    for index in stride(from: 0, to: arguments.count, by: 2) {
      let key = arguments[index]
      let value = arguments[index + 1]
      guard ["--profile", "--fixture", "--output"].contains(key), values[key] == nil,
        !value.isEmpty, !value.hasPrefix("--")
      else { throw ProbeFailure(usage) }
      values[key] = value
    }
    guard let profile = Profile(rawValue: values["--profile"] ?? ""),
      let fixture = values["--fixture"], let output = values["--output"]
    else { throw ProbeFailure(usage) }
    return Options(
      profile: profile, fixture: URL(fileURLWithPath: fixture), output: URL(fileURLWithPath: output)
    )
  }
}
enum Isolation {
  static func validate(profile: Profile, environment: [String: String], model: String) throws {
    switch profile {
    case .guest:
      guard environment["STRATOSPHERE_GUEST"] == "1", model.hasPrefix("VirtualMac") else {
        throw ProbeFailure(
          "Guest execution requires STRATOSPHERE_GUEST=1 and independently observed VirtualMac hardware; personal hosts are refused."
        )
      }
    case .hosted:
      guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_OS"] == "macOS",
        environment["RUNNER_ENVIRONMENT"] == "github-hosted"
      else {
        throw ProbeFailure(
          "Hosted execution requires GitHub-hosted macOS runner identity; self-hosted and personal hosts are refused."
        )
      }
    }
  }
}

// Hosted regression evidence cannot establish the SIP-enabled core requirement.
enum SIPQualification {
  static func validate(profile: Profile, exitCode: Int32, output: String) throws -> Bool {
    let state = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard exitCode == 0 else { throw ProbeFailure("SIP observation failed") }
    if state == "System Integrity Protection status: enabled." { return true }
    if profile == .hosted, state == "System Integrity Protection status: disabled." { return false }
    throw ProbeFailure("SIP enabled state was not established")
  }
}
