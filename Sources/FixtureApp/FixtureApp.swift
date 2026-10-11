import AppKit

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
  private var windows: [NSWindow] = []
  private var timer: Timer?
  private let output: URL?
  init(output: URL?) { self.output = output }
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSWindow.allowsAutomaticWindowTabbing = false
    for (index, title) in ["Stratosphere Fixture Alpha", "Stratosphere Fixture Beta"].enumerated() {
      let window = NSWindow(
        contentRect: NSRect(x: 100 + index * 80, y: 100 + index * 80, width: 500, height: 320),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      window.title = title
      window.identifier = NSUserInterfaceItemIdentifier("fixture-\(index)")
      window.minSize = NSSize(width: 260, height: 180)
      window.isReleasedWhenClosed = false
      let label = NSTextField(
        labelWithString: "Synthetic test window \(index + 1)\nNo personal application content")
      label.alignment = .center
      label.frame = NSRect(x: 30, y: 120, width: 440, height: 60)
      window.contentView?.addSubview(label)
      windows.append(window)
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate()
    observe()
    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.observe() }
    }
  }
  private func observe() {
    guard let output else { return }
    let observations: [[String: Any]] = windows.map { window in
      let frame = window.frame
      return [
        "title": window.title, "window_number": window.windowNumber,
        "key": window.isKeyWindow, "main": window.isMainWindow, "visible": window.isVisible,
        "screen":
          (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .uint32Value ?? 0,
        "frame": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height],
      ]
    }
    do {
      let data = try JSONSerialization.data(
        withJSONObject: [
          "pid": ProcessInfo.processInfo.processIdentifier, "windows": observations,
        ], options: [.sortedKeys])
      try data.write(to: output, options: .atomic)
    } catch { fputs("Fixture observation write failed: \(error)\n", stderr) }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct FixtureApp {
  @MainActor static func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    let output: URL?
    if args.isEmpty {
      output = nil
    } else if args.count == 2, args[0] == "--observations" {
      output = URL(fileURLWithPath: args[1])
    } else {
      fputs("FixtureApp [--observations PATH]\n", stderr)
      exit(64)
    }
    let application = NSApplication.shared
    let delegate = FixtureDelegate(output: output)
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { application.run() }
  }
}
