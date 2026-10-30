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
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.setup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }
}
