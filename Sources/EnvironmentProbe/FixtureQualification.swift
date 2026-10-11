import AppKit
import ApplicationServices
import Darwin

@MainActor enum FixtureActivation {
  static func matches(
    owner: pid_t, live: Bool, nativeActive: Bool?, workspace: pid_t?, appFrontmost: Bool?
  ) -> Bool {
    owner > 0 && live && nativeActive == true && workspace == owner && appFrontmost == true
  }
  static func focus(
    activate: () throws -> AXError, isActive: () throws -> Bool, raise: () throws -> AXError,
    timeout: Double = 8
  ) throws {
    if try !isActive() {
      let status = try activate()
      guard status == .success else {
        throw ProbeFailure("AX activation failed: \(status.rawValue)", kind: .assertion)
      }
      try SystemObservation.wait(
        "owned fixture application activation", seconds: timeout, kind: .assertion, isActive)
    }
    let status = try raise()
    guard status == .success else {
      throw ProbeFailure("AX raise failed: \(status.rawValue)", kind: .assertion)
    }
  }
}

enum FocusExperiment {
  static func enabled(_ environment: [String: String]) -> Bool {
    environment["STRATOSPHERE_FOCUS_EXPERIMENT"] == "1"
  }
}

enum WindowGeometry {
  static func matches(_ actual: CGRect, _ desired: CGRect) -> Bool {
    abs(actual.minX - desired.minX) < 2 && abs(actual.minY - desired.minY) < 2
      && abs(actual.width - desired.width) < 2 && abs(actual.height - desired.height) < 2
  }
  static func values(_ frame: CGRect) -> [String: CGFloat] {
    ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
  }
}

@MainActor final class FixtureQualification {
  private let process = OwnedProcess()
  private let binary: URL
  private let profile: Profile
  private let observations: URL
  private var app: AXUIElement?
  private var windows: [AXUIElement] = []
  private var activationSignals: [String: Any] = [:]
  private let previousFrontmost: NSRunningApplication?
  private(set) var evidence: [[String: Any]] = []
  init(bundle: URL, observations: URL, profile: Profile) throws {
    self.profile = profile
    self.observations = observations
    previousFrontmost = NSWorkspace.shared.frontmostApplication
    guard bundle.pathExtension == "app",
      let metadata = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
      let executable = metadata["CFBundleExecutable"] as? String, executable == "FixtureApp",
      metadata["CFBundleIdentifier"] as? String == "dev.stratosphere.fixture"
    else {
      throw ProbeFailure(
        "--fixture must identify the assembled dev.stratosphere.fixture app bundle")
    }
    binary = bundle.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
    guard FileManager.default.isExecutableFile(atPath: binary.path) else {
      throw ProbeFailure("Fixture binary missing or not executable")
    }
  }
  func launchAndDiscover() throws {
    try process.launch(executable: binary, arguments: ["--observations", observations.path])
    let application = AXUIElementCreateApplication(process.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 2)
    app = application
    try SystemObservation.wait("two cross-process fixture AX windows") {
      guard try self.process.isRunning() else {
        throw ProbeFailure("Fixture exited before window discovery")
      }
      guard let value = try? self.copy(application, kAXWindowsAttribute, kind: .setup),
        let discovered = value as? [AXUIElement], discovered.count == 2
      else { return false }
      let byTitle = try discovered.map {
        (try self.copy($0, kAXTitleAttribute, kind: .setup) as? String ?? "", $0)
      }
      guard
        Set(byTitle.map(\.0)) == Set(["Stratosphere Fixture Alpha", "Stratosphere Fixture Beta"])
      else { return false }
      self.windows = byTitle.sorted { $0.0 < $1.0 }.map(\.1)
      for window in self.windows { AXUIElementSetMessagingTimeout(window, 2) }
      return true
    }
    evidence.append([
      "phase": "discovered", "pid": process.processIdentifier,
      "process_group": process.processGroup, "probe_group": getpgrp(),
      "windows": try windows.map { try copy($0, kAXTitleAttribute) as? String ?? "" },
    ])
  }
  private func copy(_ element: AXUIElement, _ attribute: String, kind: FailureKind = .assertion)
    throws -> CFTypeRef
  {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success, let value else {
      throw ProbeFailure("AX read \(attribute) failed with \(error.rawValue)", kind: kind)
    }
    return value
  }
  private func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) throws {
    let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
    guard error == .success else {
      throw ProbeFailure("AX write \(attribute) failed with \(error.rawValue)", kind: .assertion)
    }
  }
  private func geometry(_ window: AXUIElement) throws -> CGRect {
    let positionValue = try copy(window, kAXPositionAttribute)
    let sizeValue = try copy(window, kAXSizeAttribute)
    guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
      CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { throw ProbeFailure("AX geometry type mismatch", kind: .assertion) }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else { throw ProbeFailure("AX geometry extraction failed", kind: .assertion) }
    return CGRect(origin: point, size: size)
  }
  private func fixtureWindows() throws -> [[String: Any]] {
    let data = try Data(contentsOf: observations)
    guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      (result["pid"] as? NSNumber)?.int32Value == process.processIdentifier,
      let windows = result["windows"] as? [[String: Any]], windows.count == 2
    else { throw ProbeFailure("Fixture observation identity mismatch", kind: .assertion) }
    return windows
  }
  func placeWindows(on first: DisplayObservation, and second: DisplayObservation) throws {
    guard let app, windows.count == 2 else {
      throw ProbeFailure("Fixture not discovered", kind: .assertion)
    }
    for (index, observedDisplay) in [first, second].enumerated() {
      let display = observedDisplay.id
      let window = windows[index]
      let bounds = observedDisplay.bounds
      let desired = CGRect(
        x: bounds.minX + 70, y: bounds.minY + 90, width: CGFloat(560 + index * 40),
        height: CGFloat(360 + index * 30))
      var point = desired.origin
      var size = desired.size
      guard let sizeValue = AXValueCreate(.cgSize, &size),
        let pointValue = AXValueCreate(.cgPoint, &point)
      else { throw ProbeFailure("Cannot create AX geometry values", kind: .assertion) }
      try set(window, kAXSizeAttribute, sizeValue)
      try set(window, kAXPositionAttribute, pointValue)
      if FocusExperiment.enabled(ProcessInfo.processInfo.environment) {
        let title = try copy(window, kAXTitleAttribute) as? String ?? ""
        focusExperiment(
          window: window, app: app, title: title, desired: desired, display: display,
          usedBounds: bounds)
        throw ProbeFailure(
          "Focus experiment completed; inspect per-stage evidence before selecting normal focus actions",
          kind: .assertion)
      }
      do {
        try FixtureActivation.focus(
          activate: {
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
          },
          isActive: {
            try self.ownedApplicationIsActive()
          },
          raise: {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
          })
      } catch {
        let title = (try? copy(window, kAXTitleAttribute)) as? String ?? "fixture window"
        var row = placementFailure(
          window: window, app: app, title: title, desired: desired, display: display,
          usedBounds: bounds, error: error)
        row["phase"] = "activation-failed"
        row["target_pid"] = process.processIdentifier
        row["activation_signals"] = activationSignals
        do { row["owned_process_live"] = try process.isRunning() } catch {
          row["owned_process_live_error"] = String(describing: error)
        }
        row["native_application_active"] =
          NSRunningApplication(processIdentifier: process.processIdentifier)?.isActive ?? false
        do {
          let fresh = try FocusReadout.read(target: process.processIdentifier, profile: profile)
          let data = try JSONEncoder().encode(fresh)
          row["fresh_focus_observer"] = try JSONSerialization.jsonObject(with: data)
          row["parent_frontmost_pid_after_observer"] =
            NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
          row["parent_native_active_after_observer"] =
            NSRunningApplication(processIdentifier: process.processIdentifier)?.isActive ?? false
        } catch { row["fresh_focus_observer_error"] = String(describing: error) }
        evidence.append(row)
        throw error
      }
      var activated = activationSignals
      activated["phase"] = "activation-ready"
      activated["display"] = display
      evidence.append(activated)
      let title = try copy(window, kAXTitleAttribute) as? String ?? ""
      var readback: [String: Any] = [:]
      do {
        try SystemObservation.wait(
          "AX and native fixture geometry/focus on display \(display)", kind: .assertion
        ) {
          guard WindowGeometry.matches(try self.geometry(window), desired),
            let own = try? self.fixtureWindows().first(where: { $0["title"] as? String == title }),
            own["key"] as? Bool == true, own["visible"] as? Bool == true,
            (own["screen"] as? NSNumber)?.uint32Value == display,
            let number = own["window_number"] as? NSNumber,
            let observed = CGWindowListCopyWindowInfo(.optionIncludingWindow, number.uint32Value)
              as? [[String: Any]],
            let native = observed.first(where: {
              ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                == self.process.processIdentifier
            }),
            native[kCGWindowIsOnscreen as String] as? Bool == true,
            let rawBounds = native[kCGWindowBounds as String] as? [String: Any],
            let rect = CGRect(dictionaryRepresentation: rawBounds as CFDictionary),
            WindowGeometry.matches(rect, desired)
          else { return false }
          let system = AXUIElementCreateSystemWide()
          AXUIElementSetMessagingTimeout(system, 2)
          let focused = try self.copy(system, kAXFocusedApplicationAttribute)
          guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
          var focusedPID: pid_t = 0
          guard AXUIElementGetPid(focused as! AXUIElement, &focusedPID) == .success,
            focusedPID == self.process.processIdentifier,
            CFEqual(try self.copy(app, kAXFocusedWindowAttribute), window)
          else { return false }
          readback = [
            "title": title, "display": display, "window_number": number, "native_bounds": rawBounds,
            "fixture": own, "focused_pid": focusedPID,
          ]
          return true
        }
      } catch {
        evidence.append(
          placementFailure(
            window: window, app: app, title: title, desired: desired, display: display,
            usedBounds: bounds, error: error))
        throw error
      }
      evidence.append(readback)
    }
  }
  private func ownedApplicationIsActive() throws -> Bool {
    let owner = process.processIdentifier
    let live = try process.isRunning()
    activationSignals = ["target_pid": owner, "owned_process_live": live]
    guard live, let app else {
      throw ProbeFailure("Owned fixture exited during activation", kind: .assertion)
    }
    var applicationPID: pid_t = 0
    let identityStatus = AXUIElementGetPid(app, &applicationPID)
    guard identityStatus == .success, applicationPID == owner else {
      throw ProbeFailure("Owned AX application identity mismatch", kind: .assertion)
    }
    // Activation is foreground application state. Keyboard focus is checked
    // only after AXRaise by the unchanged independent focus assertions.
    let native = NSRunningApplication(processIdentifier: owner)?.isActive
    let workspace = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(app, kAXFrontmostAttribute as CFString, &value)
    let frontmost = value as? Bool
    activationSignals["native_active"] = native.map { $0 as Any } ?? NSNull()
    activationSignals["workspace_pid"] = workspace.map { $0 as Any } ?? NSNull()
    activationSignals["app_frontmost_status"] = status.rawValue
    activationSignals["app_frontmost"] = frontmost.map { $0 as Any } ?? NSNull()
    guard status == .success else {
      throw ProbeFailure(
        "AX read owned AXFrontmost failed with \(status.rawValue)", kind: .assertion)
    }
    guard frontmost != nil else {
      throw ProbeFailure("Owned AXFrontmost is not Boolean", kind: .assertion)
    }
    return FixtureActivation.matches(
      owner: owner, live: live, nativeActive: native, workspace: workspace, appFrontmost: frontmost)
  }
  private func focusExperiment(
    window: AXUIElement, app: AXUIElement, title: String, desired: CGRect,
    display: CGDirectDisplayID, usedBounds: CGRect
  ) {
    let start = ProcessInfo.processInfo.systemUptime
    func capture(_ stage: String, status: Any) {
      func readback(_ timing: String) {
        var row = placementFailure(
          window: window, app: app, title: title, desired: desired, display: display,
          usedBounds: usedBounds, error: nil)
        row["phase"] = "focus-experiment"
        row["stage"] = stage
        row["timing"] = timing
        row["action_status"] = status
        row["elapsed_ms"] = (ProcessInfo.processInfo.systemUptime - start) * 1000
        evidence.append(row)
      }
      readback("immediate")
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      readback("after-runloop")
    }
    var writable: [String: Bool] = [:]
    var capabilities: [String: Any] = ["phase": "focus-experiment-capabilities"]
    for (name, element, attribute) in [
      ("window_main", window, kAXMainAttribute), ("window_focused", window, kAXFocusedAttribute),
      ("application_focused_window", app, kAXFocusedWindowAttribute),
      ("application_frontmost", app, kAXFrontmostAttribute),
    ] {
      var settable = DarwinBoolean(false)
      let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
      writable[name] = status == .success && settable.boolValue
      capabilities[name] = ["status": status.rawValue, "settable": settable.boolValue]
    }
    evidence.append(capabilities)
    capture("baseline", status: "read-only")
    capture(
      "app-frontmost",
      status: AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        .rawValue)
    capture(
      "raise-after-frontmost",
      status: AXUIElementPerformAction(window, kAXRaiseAction as CFString).rawValue)
    capture(
      "window-main",
      status: AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        .rawValue)
    capture(
      "window-focused",
      status: AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        .rawValue)
    if writable["application_focused_window"] == true {
      capture(
        "application-focused-window",
        status: AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window)
          .rawValue)
    } else {
      capture("application-focused-window", status: "not-settable")
    }
    capture(
      "raise-before-activation",
      status: AXUIElementPerformAction(window, kAXRaiseAction as CFString).rawValue)
    capture(
      "native-app-activation",
      status: NSRunningApplication(processIdentifier: process.processIdentifier)?.activate()
        ?? false)
    capture(
      "raise-after-activation",
      status: AXUIElementPerformAction(window, kAXRaiseAction as CFString).rawValue)
    capture(
      "frontmost-after-raise",
      status: AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        .rawValue)
  }
  private func placementFailure(
    window: AXUIElement, app: AXUIElement, title: String, desired: CGRect,
    display: CGDirectDisplayID, usedBounds: CGRect, error: Error?
  ) -> [String: Any] {
    var row: [String: Any] = [
      "phase": "placement-failed", "title": title, "display": display,
      "pid": process.processIdentifier, "desired_frame": WindowGeometry.values(desired),
      "used_display_bounds": WindowGeometry.values(usedBounds),
      "parent_display_bounds": WindowGeometry.values(CGDisplayBounds(display)),
      "frontmost_pid": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
    ]
    if let error { row["error"] = String(describing: error) }
    func record(_ key: String, _ read: () throws -> Any) {
      do { row[key] = try read() } catch { row[key + "_error"] = String(describing: error) }
    }
    record("ax_frame") { WindowGeometry.values(try geometry(window)) }
    record("ax_main") {
      guard let value = try copy(window, kAXMainAttribute) as? Bool else {
        throw ProbeFailure("AXMain is not Boolean")
      }
      return value
    }
    record("ax_focused") {
      guard let value = try copy(window, kAXFocusedAttribute) as? Bool else {
        throw ProbeFailure("AXFocused is not Boolean")
      }
      return value
    }
    record("fixture") {
      guard let own = try fixtureWindows().first(where: { $0["title"] as? String == title }) else {
        throw ProbeFailure("Fixture window absent")
      }
      return own
    }
    record("native_window") {
      guard let own = row["fixture"] as? [String: Any],
        let number = own["window_number"] as? NSNumber,
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, number.uint32Value)
          as? [[String: Any]],
        let native = list.first(where: {
          ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == process.processIdentifier
        })
      else { throw ProbeFailure("Native fixture window unavailable") }
      return native
    }
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 2)
    var focusedApplication: CFTypeRef?
    let focusStatus = AXUIElementCopyAttributeValue(
      system, kAXFocusedApplicationAttribute as CFString, &focusedApplication)
    row["system_focused_application_status"] = focusStatus.rawValue
    record("system_focused_pid") {
      guard focusStatus == .success, let focused = focusedApplication else {
        throw ProbeFailure("AXFocusedApplication returned \(focusStatus.rawValue)")
      }
      guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
        throw ProbeFailure("System focus is not an AX application")
      }
      var pid: pid_t = 0
      guard AXUIElementGetPid(focused as! AXUIElement, &pid) == .success else {
        throw ProbeFailure("System focused PID unavailable")
      }
      return pid
    }
    record("system_focused_window_is_target") {
      CFEqual(try copy(system, kAXFocusedWindowAttribute), window)
    }
    record("app_focused_window_is_target") {
      CFEqual(try copy(app, kAXFocusedWindowAttribute), window)
    }
    record("app_focused_window_title") {
      let focused = try copy(app, kAXFocusedWindowAttribute)
      guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
        throw ProbeFailure("App focus is not an AX window")
      }
      return try copy(focused as! AXUIElement, kAXTitleAttribute) as? String ?? "unavailable"
    }
    return row
  }
  func cleanup() throws {
    try process.stop()
    try? FileManager.default.removeItem(at: observations)
    evidence.append(["phase": "fixture-cleaned", "pid": process.processIdentifier])
  }
  func restoreFocus() throws {
    guard let previousFrontmost else {
      evidence.append([
        "phase": "focus-cleanup", "outcome": "unavailable",
        "reason": "No baseline frontmost application",
      ])
      return
    }
    let pid = previousFrontmost.processIdentifier
    guard !previousFrontmost.isTerminated else {
      evidence.append([
        "phase": "focus-cleanup", "outcome": "unavailable", "pid": pid,
        "reason": "Baseline application exited",
      ])
      return
    }
    evidence.append(["phase": "focus-cleanup", "outcome": "attempted", "pid": pid])
    guard previousFrontmost.activate() else {
      throw ProbeFailure("Baseline focus activation rejected for PID \(pid)", kind: .cleanup)
    }
    try SystemObservation.wait("baseline frontmost PID \(pid)", seconds: 3, kind: .cleanup) {
      if previousFrontmost.isTerminated { return true }
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
      if AXIsProcessTrusted() {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 1)
        guard let value = try? self.copy(system, kAXFocusedApplicationAttribute, kind: .cleanup)
        else { return false }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        var observed: pid_t = 0
        guard AXUIElementGetPid(value as! AXUIElement, &observed) == .success, observed == pid
        else { return false }
      }
      return true
    }
    if previousFrontmost.isTerminated {
      evidence.append([
        "phase": "focus-cleanup", "outcome": "unavailable", "pid": pid,
        "reason": "Baseline application exited during restoration",
      ])
    } else {
      evidence.append([
        "phase": "focus-cleanup", "outcome": "restored", "pid": pid,
        "observed_frontmost_pid": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
        "ax_available": AXIsProcessTrusted(),
      ])
    }
  }
}
