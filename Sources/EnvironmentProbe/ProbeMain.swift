import AppKit
import ApplicationServices
import Darwin

@main struct ProbeMain {
  @MainActor static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "--observe-focus" { exit(FocusReadout.run(arguments)) }
    if arguments.first == "--configure-displays" { exit(DisplayConfigurationHelper.run(arguments)) }
    if let first = arguments.first, ["--observe-displays", "--observe-display-ids"].contains(first)
    {
      exit(DisplayReadout.run(arguments))
    }
    var report: [String: Any] = [
      "schema_version": 1, "status": "setup-failed", "kind": "partial-environment-qualification",
      "unqualified": [
        "daemon-and-watchdog-recovery", "AX-stall-recovery", "installed-product-and-grant-survival",
        "input-injection-and-screen-capture", "real-app-integrations", "physical-hardware",
        "unattended-host-controller",
      ],
    ]
    var options: Options?
    var fixture: FixtureQualification?
    var displays: DisplayQualification?
    var exitCode: Int32 = 1
    var cleanupErrors: [String] = []
    var fallback: FailureKind = .setup
    do {
      defer {
        do { try fixture?.cleanup() } catch { cleanupErrors.append(String(describing: error)) }
        do { try displays?.cleanup() } catch { cleanupErrors.append(String(describing: error)) }
        do { try fixture?.restoreFocus() } catch { cleanupErrors.append(String(describing: error)) }
      }
      options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
      guard let options else {
        print(Options.usage)
        return
      }
      report["profile"] = options.profile.rawValue
      report["focus_experiment"] = FocusExperiment.enabled(ProcessInfo.processInfo.environment)
      let environment = ProcessInfo.processInfo.environment
      let buildMetadata = BuildMetadata.read(environment["STRATOSPHERE_BUILD_METADATA"])
      report["build_toolchain"] = buildMetadata.json
      let model = try SystemObservation.sysctl("hw.model")
      report["hardware_model"] = model
      // This check precedes all AppKit launch, AX mutation and display work.
      try Isolation.validate(profile: options.profile, environment: environment, model: model)
      let os = ProcessInfo.processInfo.operatingSystemVersion
      let architecture = try SystemObservation.sysctl("hw.machine")
      report["environment"] = [
        "macos": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
        "build": try SystemObservation.sysctl("kern.osversion"), "architecture": architecture,
        "source_revision": buildMetadata.values["sourceRevision"] ?? "unavailable",
        "image_identity": environment["STRATOSPHERE_IMAGE_IDENTITY"] ?? "unavailable",
        "runner_name": environment["RUNNER_NAME"] ?? "unavailable",
        "runner_image_version": environment["ImageVersion"] ?? "unavailable",
      ]
      guard os.majorVersion >= 26, architecture == "arm64" else {
        throw ProbeFailure("Qualification requires macOS 26+ on native arm64")
      }
      let sip = try SystemObservation.command("/usr/bin/csrutil", ["status"])
      report["sip"] = sip.1
      guard sip.0 == 0, sip.1.contains("System Integrity Protection status: enabled.") else {
        throw ProbeFailure("SIP enabled state was not established")
      }
      report["gui_session"] = try SystemObservation.validateSession()
      report["capabilities"] = [
        "probe_ax_trusted": AXIsProcessTrusted(),
        "screen_capture_granted": CGPreflightScreenCaptureAccess(),
      ]
      guard AXIsProcessTrusted() else {
        throw ProbeFailure(
          "AX permission is absent in EnvironmentProbe; prepare the isolated launch profile")
      }
      report["probe_signature"] = try SystemObservation.command(
        "/usr/bin/codesign", ["-dv", "--verbose=4", CommandLine.arguments[0]]
      ).1
      report["fixture_signature"] = try SystemObservation.command(
        "/usr/bin/codesign", ["-dv", "--verbose=4", options.fixture.path]
      ).1
      report["fixture_version"] =
        (NSDictionary(contentsOf: options.fixture.appendingPathComponent("Contents/Info.plist"))?[
          "CFBundleShortVersionString"] as? String) ?? "unavailable"
      let observations = options.output.deletingLastPathComponent().appendingPathComponent(
        "fixture-\(UUID().uuidString).json")
      try FileManager.default.createDirectory(
        at: observations.deletingLastPathComponent(), withIntermediateDirectories: true)
      let activeFixture = try FixtureQualification(
        bundle: options.fixture, observations: observations, profile: options.profile)
      fixture = activeFixture
      try activeFixture.launchAndDiscover()
      let activeDisplays = try DisplayQualification(profile: options.profile)
      displays = activeDisplays
      fallback = .assertion
      try activeDisplays.qualify { first, second in
        try activeFixture.placeWindows(on: first, and: second)
      }
      report["status"] = "passed"
      exitCode = 0
    } catch {
      report["status"] =
        (error as? ProbeFailure)?.status ?? (error as? DisplayConfigurationFailure)?.kind.status
        ?? fallback.status
      report["error"] = String(describing: error)
    }
    // Always finish cleanup before atomically publishing a final result.
    report["fixture_observations"] = fixture?.evidence ?? []
    report["display_observations"] = displays?.evidence ?? []
    if !cleanupErrors.isEmpty {
      report["status"] = "failed"
      report["cleanup_errors"] = cleanupErrors
      exitCode = 1
    }
    report["finished_at"] = ISO8601DateFormatter().string(from: Date())
    if let output = options?.output ?? recoverOutput(Array(CommandLine.arguments.dropFirst())) {
      do {
        try FileManager.default.createDirectory(
          at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
          withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output, options: .atomic)
      } catch {
        fputs("Cannot publish probe result: \(error)\n", stderr)
        exitCode = 1
      }
    }
    if let error = report["error"] { fputs("\(error)\n", stderr) }
    exit(exitCode)
  }
  private static func recoverOutput(_ args: [String]) -> URL? {
    guard let index = args.firstIndex(of: "--output"), args.indices.contains(index + 1),
      !args[index + 1].hasPrefix("--")
    else { return nil }
    return URL(fileURLWithPath: args[index + 1])
  }
}
