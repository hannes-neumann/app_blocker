import Foundation

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
