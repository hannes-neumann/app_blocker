import AppKit

/// Quits blocked apps while a focus phase runs and keeps them from being reopened.
@MainActor
final class AppBlocker {
    var onBlocked: ((_ name: String, _ bundleID: String) -> Void)?

    private var blockedBundleIDs: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    func start(bundleIDs: Set<String>) {
        blockedBundleIDs = bundleIDs
        guard observers.isEmpty else { return }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.enforce(app) }
            })
        }
        NSWorkspace.shared.runningApplications.forEach(enforce)
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        blockedBundleIDs = []
    }

    private func enforce(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, blockedBundleIDs.contains(id), !app.isTerminated else { return }
        // A polite quit lets the app ask about unsaved work. If it refuses, at least get it out of sight.
        if !app.terminate() { app.hide() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if !app.isTerminated { app.hide() }
        }
        onBlocked?(app.localizedName ?? id, id)
    }
}
