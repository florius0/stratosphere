import AppKit
import ApplicationServices
import Darwin

enum WindowGeometry {
    static func matches(_ actual: CGRect, _ desired: CGRect) -> Bool {
        abs(actual.minX - desired.minX) < 2 && abs(actual.minY - desired.minY) < 2 && abs(actual.width - desired.width) < 2 && abs(actual.height - desired.height) < 2
    }
    static func values(_ frame: CGRect) -> [String: CGFloat] { ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height] }
}

@MainActor final class FixtureQualification {
    private let process = OwnedProcess()
    private let binary: URL
    private let observations: URL
    private var app: AXUIElement?
    private var windows: [AXUIElement] = []
    private let previousFrontmost: NSRunningApplication?
    private(set) var evidence: [[String: Any]] = []
    init(bundle: URL, observations: URL) throws {
        self.observations = observations
        previousFrontmost = NSWorkspace.shared.frontmostApplication
        guard bundle.pathExtension == "app", let metadata = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
              let executable = metadata["CFBundleExecutable"] as? String, executable == "FixtureApp",
              metadata["CFBundleIdentifier"] as? String == "dev.stratosphere.fixture" else {
            throw ProbeFailure("--fixture must identify the assembled dev.stratosphere.fixture app bundle")
        }
        binary = bundle.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw ProbeFailure("Fixture binary missing or not executable") }
    }
    func launchAndDiscover() throws {
        try process.launch(executable: binary, arguments: ["--observations", observations.path])
        let application = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 2)
        app = application
        try SystemObservation.wait("two cross-process fixture AX windows") {
            guard try self.process.isRunning() else { throw ProbeFailure("Fixture exited before window discovery") }
            guard let value = try? self.copy(application, kAXWindowsAttribute, kind: .setup), let discovered = value as? [AXUIElement], discovered.count == 2 else { return false }
            let byTitle = try discovered.map { (try self.copy($0, kAXTitleAttribute, kind: .setup) as? String ?? "", $0) }
            guard Set(byTitle.map(\.0)) == Set(["Stratosphere Fixture Alpha", "Stratosphere Fixture Beta"]) else { return false }
            self.windows = byTitle.sorted { $0.0 < $1.0 }.map(\.1)
            for window in self.windows { AXUIElementSetMessagingTimeout(window, 2) }
            return true
        }
        evidence.append(["phase": "discovered", "pid": process.processIdentifier, "process_group": process.processGroup, "probe_group": getpgrp(), "windows": try windows.map { try copy($0, kAXTitleAttribute) as? String ?? "" }])
    }
    private func copy(_ element: AXUIElement, _ attribute: String, kind: FailureKind = .assertion) throws -> CFTypeRef {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else { throw ProbeFailure("AX read \(attribute) failed with \(error.rawValue)", kind: kind) }
        return value
    }
    private func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) throws {
        let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        guard error == .success else { throw ProbeFailure("AX write \(attribute) failed with \(error.rawValue)", kind: .assertion) }
    }
    private func geometry(_ window: AXUIElement) throws -> CGRect {
        let positionValue = try copy(window, kAXPositionAttribute), sizeValue = try copy(window, kAXSizeAttribute)
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { throw ProbeFailure("AX geometry type mismatch", kind: .assertion) }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point), AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { throw ProbeFailure("AX geometry extraction failed", kind: .assertion) }
        return CGRect(origin: point, size: size)
    }
    private func fixtureWindows() throws -> [[String: Any]] {
        let data = try Data(contentsOf: observations)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (result["pid"] as? NSNumber)?.int32Value == process.processIdentifier,
              let windows = result["windows"] as? [[String: Any]], windows.count == 2 else { throw ProbeFailure("Fixture observation identity mismatch", kind: .assertion) }
        return windows
    }
    func placeWindows(on first: CGDirectDisplayID, and second: CGDirectDisplayID) throws {
        guard let app, windows.count == 2 else { throw ProbeFailure("Fixture not discovered", kind: .assertion) }
        for (index, display) in [first, second].enumerated() {
            let window = windows[index], bounds = CGDisplayBounds(display)
            let desired = CGRect(x: bounds.minX + 70, y: bounds.minY + 90, width: CGFloat(560 + index * 40), height: CGFloat(360 + index * 30))
            var point = desired.origin, size = desired.size
            guard let sizeValue = AXValueCreate(.cgSize, &size), let pointValue = AXValueCreate(.cgPoint, &point) else { throw ProbeFailure("Cannot create AX geometry values", kind: .assertion) }
            try set(window, kAXSizeAttribute, sizeValue)
            try set(window, kAXPositionAttribute, pointValue)
            try set(app, kAXFrontmostAttribute, kCFBooleanTrue)
            try set(window, kAXMainAttribute, kCFBooleanTrue)
            try set(window, kAXFocusedAttribute, kCFBooleanTrue)
            let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            guard raised == .success else { throw ProbeFailure("AX raise failed: \(raised.rawValue)", kind: .assertion) }
            let title = try copy(window, kAXTitleAttribute) as? String ?? ""
            var readback: [String: Any] = [:]
            do {
                try SystemObservation.wait("AX and native fixture geometry/focus on display \(display)", kind: .assertion) {
                guard WindowGeometry.matches(try self.geometry(window), desired),
                      let own = try? self.fixtureWindows().first(where: { $0["title"] as? String == title }),
                      own["key"] as? Bool == true, own["visible"] as? Bool == true,
                      (own["screen"] as? NSNumber)?.uint32Value == display,
                      let number = own["window_number"] as? NSNumber,
                      let observed = CGWindowListCopyWindowInfo(.optionIncludingWindow, number.uint32Value) as? [[String: Any]],
                      let native = observed.first(where: { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == self.process.processIdentifier }),
                      native[kCGWindowIsOnscreen as String] as? Bool == true,
                      let rawBounds = native[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: rawBounds as CFDictionary), WindowGeometry.matches(rect, desired) else { return false }
                let system = AXUIElementCreateSystemWide()
                AXUIElementSetMessagingTimeout(system, 2)
                let focused = try self.copy(system, kAXFocusedApplicationAttribute)
                guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
                var focusedPID: pid_t = 0
                guard AXUIElementGetPid(focused as! AXUIElement, &focusedPID) == .success, focusedPID == self.process.processIdentifier,
                      CFEqual(try self.copy(app, kAXFocusedWindowAttribute), window) else { return false }
                readback = ["title": title, "display": display, "window_number": number, "native_bounds": rawBounds, "fixture": own, "focused_pid": focusedPID]
                return true
            }
            } catch {
                evidence.append(placementFailure(window: window, app: app, title: title, desired: desired, display: display, usedBounds: bounds, error: error))
                throw error
            }
            evidence.append(readback)
        }
    }
    private func placementFailure(window: AXUIElement, app: AXUIElement, title: String, desired: CGRect, display: CGDirectDisplayID, usedBounds: CGRect, error: Error) -> [String: Any] {
        var row: [String: Any] = ["phase": "placement-failed", "error": String(describing: error), "title": title, "display": display, "pid": process.processIdentifier, "desired_frame": WindowGeometry.values(desired), "used_display_bounds": WindowGeometry.values(usedBounds), "parent_display_bounds": WindowGeometry.values(CGDisplayBounds(display)), "frontmost_pid": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0]
        func record(_ key: String, _ read: () throws -> Any) {
            do { row[key] = try read() }
            catch { row[key + "_error"] = String(describing: error) }
        }
        record("ax_frame") { WindowGeometry.values(try geometry(window)) }
        record("fixture") {
            guard let own = try fixtureWindows().first(where: { $0["title"] as? String == title }) else { throw ProbeFailure("Fixture window absent") }
            return own
        }
        record("native_window") {
            guard let own = row["fixture"] as? [String: Any], let number = own["window_number"] as? NSNumber,
                  let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, number.uint32Value) as? [[String: Any]],
                  let native = list.first(where: { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == process.processIdentifier }) else { throw ProbeFailure("Native fixture window unavailable") }
            return native
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 2)
        record("system_focused_pid") {
            let focused = try copy(system, kAXFocusedApplicationAttribute)
            guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { throw ProbeFailure("System focus is not an AX application") }
            var pid: pid_t = 0
            guard AXUIElementGetPid(focused as! AXUIElement, &pid) == .success else { throw ProbeFailure("System focused PID unavailable") }
            return pid
        }
        record("system_focused_window_is_target") { CFEqual(try copy(system, kAXFocusedWindowAttribute), window) }
        record("app_focused_window_is_target") { CFEqual(try copy(app, kAXFocusedWindowAttribute), window) }
        record("app_focused_window_title") {
            let focused = try copy(app, kAXFocusedWindowAttribute)
            guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { throw ProbeFailure("App focus is not an AX window") }
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
            evidence.append(["phase": "focus-cleanup", "outcome": "unavailable", "reason": "No baseline frontmost application"])
            return
        }
        let pid = previousFrontmost.processIdentifier
        guard !previousFrontmost.isTerminated else {
            evidence.append(["phase": "focus-cleanup", "outcome": "unavailable", "pid": pid, "reason": "Baseline application exited"])
            return
        }
        evidence.append(["phase": "focus-cleanup", "outcome": "attempted", "pid": pid])
        guard previousFrontmost.activate() else { throw ProbeFailure("Baseline focus activation rejected for PID \(pid)", kind: .cleanup) }
        try SystemObservation.wait("baseline frontmost PID \(pid)", seconds: 3, kind: .cleanup) {
            if previousFrontmost.isTerminated { return true }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
            if AXIsProcessTrusted() {
                let system = AXUIElementCreateSystemWide()
                AXUIElementSetMessagingTimeout(system, 1)
                guard let value = try? self.copy(system, kAXFocusedApplicationAttribute, kind: .cleanup) else { return false }
                guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
                var observed: pid_t = 0
                guard AXUIElementGetPid(value as! AXUIElement, &observed) == .success, observed == pid else { return false }
            }
            return true
        }
        if previousFrontmost.isTerminated {
            evidence.append(["phase": "focus-cleanup", "outcome": "unavailable", "pid": pid, "reason": "Baseline application exited during restoration"])
        } else {
            evidence.append(["phase": "focus-cleanup", "outcome": "restored", "pid": pid, "observed_frontmost_pid": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0, "ax_available": AXIsProcessTrusted()])
        }
    }
}
