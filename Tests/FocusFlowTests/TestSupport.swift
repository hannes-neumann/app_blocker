import Foundation
@testable import FocusFlow

/// Points FocusFlow's storage at a fresh scratch folder before anything reads or writes the real data.
/// Every suite calls this first: even logging an event reads the settings from `Storage`.
enum TestSupport {
    static let dataDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FocusFlowTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("FOCUSFLOW_DATA_DIR", dir.path, 1)
        precondition(Storage.directory == dir, "Storage was used before the tests redirected it")
        return dir
    }()

    static func isolate() { _ = dataDirectory }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: dataDirectory.appendingPathComponent(name))
    }

    /// The package root, from this file's location.
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
