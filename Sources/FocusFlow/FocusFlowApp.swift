import AppKit
import SwiftUI

@main
struct FocusFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView().environment(delegate.state)
        } label: {
            MenuBarLabel().environment(delegate.state)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state: AppState
    private let instanceLock: InstanceLock

    override init() {
        // Before AppState, which already reads and writes the data files.
        guard let lock = InstanceLock() else {
            NSLog("FocusFlow is already running, quitting this copy")
            exit(0)
        }
        instanceLock = lock
        state = AppState()
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // focusflow:// links, e.g. from calendar events or the MCP server. Registered this early so a link
        // that launches the app is not lost.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.setup()
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text) else { return }
        state.open(url)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }
}
