import AppKit
import SwiftUI

/// A borderless floating panel that can take keyboard input without activating the app,
/// so the app you were working in stays in front.
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(closesOnResignKey: Bool) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        if closesOnResignKey {
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: self, queue: .main) { [weak self] _ in
                self?.orderOut(nil)
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
        orderOut(nil)
    }

    func setContent<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    /// Places the panel horizontally centered at the given fraction of the screen height (from the top).
    func position(verticalFraction: CGFloat) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let origin = NSPoint(x: screen.midX - frame.width / 2,
                             y: screen.maxY - screen.height * verticalFraction - frame.height / 2)
        setFrameOrigin(origin)
    }

    func positionTopRight() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 16, y: screen.maxY - frame.height - 16))
    }
}

@MainActor
final class PanelController {
    private unowned let state: AppState
    private let capturePanel = FloatingPanel(closesOnResignKey: true)
    private let breakPanel = FloatingPanel(closesOnResignKey: false)
    private let hudPanel = FloatingPanel(closesOnResignKey: false)
    private var dashboardWindow: NSWindow?
    private var hudWorkItem: DispatchWorkItem?

    init(state: AppState) {
        self.state = state
        hudPanel.ignoresMouseEvents = true
    }

    func showCapture(onSubmit: @escaping (String) -> Void) {
        if capturePanel.isVisible {
            capturePanel.orderOut(nil)
            Analytics.track(.quickCaptureCancelled, ["via": "hotkey"])
            return
        }
        let close = { [capturePanel] in capturePanel.orderOut(nil) }
        capturePanel.setContent(QuickCaptureView(
            onSubmit: { text in onSubmit(text); close() },
            onCancel: { Analytics.track(.quickCaptureCancelled, ["via": "escape"]); close() }
        ))
        capturePanel.position(verticalFraction: 0.3)
        capturePanel.makeKeyAndOrderFront(nil)
    }

    func showBreak() {
        breakPanel.setContent(BreakView().environment(state))
        breakPanel.positionTopRight()
        breakPanel.orderFrontRegardless()
    }

    /// The user closed the break panel by hand.
    func dismissBreak() {
        Analytics.track(.breakPanelClosed, ["phase": .string(state.phase.rawValue)])
        hideBreak()
    }

    func hideBreak() {
        breakPanel.orderOut(nil)
    }

    func showBlockedHUD(appName: String) {
        hudPanel.setContent(BlockedHUDView(appName: appName))
        hudPanel.position(verticalFraction: 0.5)
        hudPanel.orderFrontRegardless()
        hudWorkItem?.cancel()
        let item = DispatchWorkItem { [hudPanel] in hudPanel.orderOut(nil) }
        hudWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }

    func showDashboard(_ section: DashboardSection, source: String) {
        Analytics.track(.dashboardOpened, ["section": .string(section.rawValue), "source": .string(source),
                                           "was_open": .bool(dashboardWindow?.isVisible ?? false)])
        state.dashboardSection = section
        let window = dashboardWindow ?? makeDashboardWindow()
        dashboardWindow = window
        // Show up in the Dock and app switcher while the dashboard is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeDashboardWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: DashboardView().environment(state))
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "FocusFlow"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1000, height: 720))
        window.center()
        window.setFrameAutosaveName("FocusFlowDashboard")
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { Analytics.track(.dashboardClosed) }
            NSApp.setActivationPolicy(.accessory)
        }
        return window
    }
}
