import AppKit
import Observation
import SwiftUI
import UI

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Review panels only: never enumerate, reposition, or activate application windows.
@MainActor @Observable
final class NativePanelController {
    private(set) var isOpen = false
    private var railPanel: NSPanel?
    private var previewPanel: NSPanel?
    private var dismissalTask: Task<Void, Never>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var pointerTimer: Timer?
    private var renderedRailSize = NSSize.zero
    private var railInside = false
    private var previewInside = false
    private var session: CatalogSession?
    // Fixed bounds contain spring overshoot; the trailing edge stays beside the preview.
    private static let railInset: CGFloat = 12
    private static let railSize = NSSize(width: RailDimensions.fullWidth + 2 * railInset + 48,
                                         height: RailDimensions.height + 2 * railInset)

    func open(session: CatalogSession, appearance: ReviewAppearance, colorScheme: ColorScheme?) {
        close()
        guard let screen = NSScreen.main else { return }
        self.session = session
        session.nativeHover.close()
        let visible = screen.visibleFrame
        let rail = panel(size: Self.railSize)
        rail.setFrameOrigin(NSPoint(x: visible.minX + 45, y: max(visible.minY + 24, visible.midY - Self.railSize.height / 2)))
        let preview = panel(size: NSSize(width: 362, height: 442))
        preview.setFrameOrigin(NSPoint(x: rail.frame.maxX + 6, y: rail.frame.maxY - 448))
        railPanel = rail
        previewPanel = preview
        updateAppearance(appearance, colorScheme: colorScheme)
        isOpen = true
        updateMouseDelivery()
        rail.orderFrontRegardless()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseDelivery() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.updateMouseDelivery()
            if event.type == .leftMouseDown || event.type == .rightMouseDown { self?.dismissOnOutsideClick() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            let clicked = event.type == .leftMouseDown || event.type == .rightMouseDown
            Task { @MainActor in
                self?.updateMouseDelivery()
                if clicked { self?.dismissOnOutsideClick() }
            }
        }
    }

    func updateAppearance(_ appearance: ReviewAppearance, colorScheme: ColorScheme?) {
        guard let session else { return }
        railPanel?.contentView = NSHostingView(rootView: NativeRail(session: session, appearance: appearance,
            inset: Self.railInset, hostSize: Self.railSize, visibilityChanged: { [weak self] in self?.refreshPreview() },
            sizeChanged: { [weak self] size in
                self?.renderedRailSize = size
                self?.updateMouseDelivery()
            })
            .preferredColorScheme(colorScheme))
        previewPanel?.contentView = NSHostingView(rootView: NativePreview(session: session, appearance: appearance)
            .preferredColorScheme(colorScheme))
    }

    private func panel(size: NSSize) -> NSPanel {
        let panel = PassivePanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return panel
    }

    private func pointer(inside: Bool, region: PointerRegion) {
        guard let session else { return }
        dismissalTask?.cancel()
        if inside { session.nativeHover.enter(region) } else { session.nativeHover.leave(region) }
        if !inside {
            let generation = session.nativeHover.generation
            dismissalTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                session.nativeHover.dismiss(generation: generation)
            }
        }
    }

    private func refreshPreview() {
        guard isOpen, let session else { return }
        if session.nativeHover.visible { previewPanel?.orderFrontRegardless() }
        else { previewPanel?.orderOut(nil) }
        updateMouseDelivery()
    }

    private var interactiveRailFrame: NSRect {
        guard let railPanel else { return .zero }
        return RailPointerBounds.frame(host: railPanel.frame, renderedSize: renderedRailSize, inset: Self.railInset)
    }

    private var interactivePreviewFrame: NSRect {
        guard session?.nativeHover.visible == true, let previewPanel, previewPanel.isVisible else { return .zero }
        return previewPanel.frame.insetBy(dx: 6, dy: 6)
    }

    private func updateMouseDelivery() {
        let point = NSEvent.mouseLocation
        let inRail = interactiveRailFrame.contains(point)
        let inPreview = interactivePreviewFrame.contains(point)
        if let railPanel, railPanel.ignoresMouseEvents != !inRail { railPanel.ignoresMouseEvents = !inRail }
        if let previewPanel, previewPanel.ignoresMouseEvents != !inPreview { previewPanel.ignoresMouseEvents = !inPreview }
        // Ignored windows cannot supply hover events; track crossing from the same visible bounds.
        if inRail != railInside {
            railInside = inRail
            pointer(inside: inRail, region: .rail)
        }
        if inPreview != previewInside {
            previewInside = inPreview
            pointer(inside: inPreview, region: .preview)
        }
    }

    private func dismissOnOutsideClick() {
        let point = NSEvent.mouseLocation
        guard !interactiveRailFrame.contains(point), !interactivePreviewFrame.contains(point) else { return }
        session?.nativeHover.close()
    }

    func close() {
        dismissalTask?.cancel()
        dismissalTask = nil
        pointerTimer?.invalidate()
        pointerTimer = nil
        renderedRailSize = .zero
        railInside = false
        previewInside = false
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
        session?.nativeHover.close()
        railPanel?.close(); previewPanel?.close()
        railPanel = nil; previewPanel = nil
        session = nil
        isOpen = false
    }
}

private struct NativeRail: View {
    @Bindable var session: CatalogSession
    let appearance: ReviewAppearance
    let inset: CGFloat
    let hostSize: NSSize
    let visibilityChanged: () -> Void
    let sizeChanged: (CGSize) -> Void
    var body: some View {
        RailView(projects: RailPresentation.rows(projects: PresentationFixtures.projects, selected: session.selectedWorkspace),
                 expanded: Binding(get: { session.expanded }, set: { session.send(.setExpanded($0)) }), appearance: appearance,
                 focus: { session.send(.focus($0)) }, sizeChanged: sizeChanged)
            .padding(inset)
            .frame(width: hostSize.width, height: hostSize.height, alignment: .topTrailing)
            .onChange(of: session.nativeHover.visible) { visibilityChanged() }
    }
}
private struct NativePreview: View {
    @Bindable var session: CatalogSession
    let appearance: ReviewAppearance
    var body: some View {
        WorkspacePreview(root: PresentationFixtures.deepTree, expandedNodes: $session.expandedNodes,
                         selected: session.selectedWorkspace, appearance: appearance,
                         focus: { session.send(.focus($0)) })
            .padding(6)
    }
}
