import AppKit
import SwiftUI

/// Takes the click that first reaches a panel, instead of spending it on focusing the panel.
private final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A borderless floating panel that can take keyboard input without activating the app,
/// so the app you were working in stays in front.
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?
    /// Sees every key before the content does; true means handled. macOS only lets Tab and the arrow keys reach
    /// buttons with "Keyboard navigation" turned on, so a panel made of buttons needs this.
    var onKey: ((NSEvent) -> Bool)?

    init(closesOnResignKey: Bool, movable: Bool = false) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = movable
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

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
        orderOut(nil)
    }

    func setContent<V: View>(_ view: V) {
        let hosting = PanelHostingView(rootView: view)
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
    private let capturePanel = FloatingPanel(closesOnResignKey: true, movable: true)
    private let timerPanel = FloatingPanel(closesOnResignKey: true)
    private let projectPanel = FloatingPanel(closesOnResignKey: false, movable: true)
    private let telemetryPanel = FloatingPanel(closesOnResignKey: false, movable: true)
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

    func showTimerEntry() {
        if timerPanel.isVisible {
            timerPanel.orderOut(nil)
            Analytics.track(.timerEntryCancelled, ["via": "hotkey"])
            return
        }
        Analytics.track(.timerEntryOpened, ["phase": .string(state.phase.rawValue)])
        let close = { [timerPanel] in timerPanel.orderOut(nil) }
        timerPanel.onKey = nil
        guard state.phase == .idle else {
            let selection = TimerSessionSelection()
            let perform = { [state] (action: TimerSessionAction) in
                switch action {
                case .pause: state.togglePause()
                case .skip: state.skipPhase(); close()
                case .stop: state.stop(); close()
                }
            }
            timerPanel.onKey = { selection.handle($0, perform: perform) }
            timerPanel.setContent(TimerSessionView(selection: selection, perform: perform, onClose: close).environment(state))
            timerPanel.position(verticalFraction: 0.3)
            timerPanel.makeKeyAndOrderFront(nil)
            return
        }
        let initial: FocusTarget = state.selectedTaskID.map { .task($0) } ?? state.selectedProjectID.map { .project($0) } ?? .none
        timerPanel.setContent(TimerEntryView(
            defaultMinutes: state.settings.focusMinutes,
            initialTarget: initial,
            onStart: { [self] minutes, target in
                close()
                state.startFocus(minutes: minutes, target: target)
            },
            onCancel: { Analytics.track(.timerEntryCancelled, ["via": "escape"]); close() }
        ).environment(state))
        timerPanel.position(verticalFraction: 0.3)
        timerPanel.makeKeyAndOrderFront(nil)
    }

    /// A new project from the menu bar. A sheet there would close together with the menu bar window
    /// as soon as it takes a click, so the editor gets its own panel.
    func showProjectEditor(onCreate: @escaping (Project) -> Void) {
        let close = { [projectPanel] in projectPanel.orderOut(nil) }
        projectPanel.setContent(ProjectEditorSheet(project: nil, onCreate: onCreate, onClose: close)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .environment(state))
        projectPanel.position(verticalFraction: 0.3)
        projectPanel.makeKeyAndOrderFront(nil)
        projectPanel.orderFrontRegardless()
    }

    /// Closing it without an answer (esc) counts as no.
    func showTelemetryConsent() {
        guard !telemetryPanel.isVisible else { return }
        telemetryPanel.onCancel = { Analytics.answerTelemetry(false) }
        telemetryPanel.setContent(TelemetryConsentView { [telemetryPanel] allowed in
            Analytics.answerTelemetry(allowed)
            telemetryPanel.orderOut(nil)
        })
        telemetryPanel.position(verticalFraction: 0.35)
        telemetryPanel.orderFrontRegardless()
    }

    /// Without an answer, so the question comes back when the timer is idle again.
    func hideTelemetryConsent() {
        telemetryPanel.orderOut(nil)
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
        window.representedURL = Bundle.main.bundleURL
        window.standardWindowButton(.documentIconButton)?.image = NSApp.applicationIconImage
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
