import AppKit

/// Lets only one FocusFlow use a data folder. Each running app keeps projects and todos in memory, so a second
/// copy (e.g. another build) would show old data and overwrite what the first one saved.
final class InstanceLock {
    private let descriptor: Int32

    /// Nil when another running FocusFlow holds the lock. The system releases it when the app ends, even after a crash.
    init?(directory: URL = Storage.directory) {
        let path = directory.appendingPathComponent("instance.lock").path
        // Close-on-exec, so a child process such as Ollama does not keep the lock after the app quit.
        descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            // Without a lock file, starting is better than not starting at all.
            NSLog("Could not open \(path): \(String(cString: strerror(errno)))")
            return
        }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0, errno == EWOULDBLOCK {
            // A failed initializer still runs deinit, which closes the descriptor.
            return nil
        }
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }
}

/// Ends other running copies. Only the app holding the `InstanceLock` does this: newer copies quit by themselves,
/// so what is left are builds from before the lock.
@MainActor
enum OtherInstances {
    private static var observer: NSKeyValueObservation?
    private static var ending: Set<pid_t> = []

    /// With its own data folder a copy is a test run and leaves the real app alone.
    private static var isTestRun: Bool { ProcessInfo.processInfo.environment["FOCUSFLOW_DATA_DIR"] != nil }

    static func others(of bundleID: String?, in apps: [NSRunningApplication], ownPID: pid_t) -> [NSRunningApplication] {
        guard let bundleID else { return [] }
        return apps.filter { $0.bundleIdentifier == bundleID && $0.processIdentifier != ownPID && !$0.isTerminated }
    }

    /// Returns once they are gone, so their last save cannot overwrite what this app loads.
    static func endAll() {
        guard !isTestRun else { return }
        let found = others(of: Bundle.main.bundleIdentifier, in: NSWorkspace.shared.runningApplications,
                           ownPID: ProcessInfo.processInfo.processIdentifier)
        found.forEach(end)
    }

    /// Ends copies started later. They get a moment, as those that know the lock quit on their own.
    static func keepAway() {
        guard !isTestRun else { return }
        // Launch notifications are not sent for menu bar apps, so watch the list of running apps.
        observer = NSWorkspace.shared.observe(\.runningApplications) { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { endLater() } }
        }
        // One that started while this app was loading.
        endLater()
    }

    private static func endLater() {
        for app in others(of: Bundle.main.bundleIdentifier, in: NSWorkspace.shared.runningApplications,
                          ownPID: ProcessInfo.processInfo.processIdentifier) where ending.insert(app.processIdentifier).inserted {
            let pid = app.processIdentifier
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if alive(pid) {
                    NSLog("Ending another copy of FocusFlow: \(app.bundleURL?.path ?? "?")")
                    app.terminate()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if alive(pid) { app.forceTerminate() }
                    MainActor.assumeIsolated { _ = ending.remove(pid) }
                }
            }
        }
    }

    private static func end(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        app.terminate()
        if !wait(for: pid, seconds: 5) {
            app.forceTerminate()
            _ = wait(for: pid, seconds: 2)
        }
    }

    /// `isTerminated` only updates while the run loop runs, which it does not yet at launch.
    private static func wait(for pid: pid_t, seconds: Double) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while alive(pid), Date() < end { usleep(50_000) }
        return !alive(pid)
    }

    nonisolated private static func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }
}
