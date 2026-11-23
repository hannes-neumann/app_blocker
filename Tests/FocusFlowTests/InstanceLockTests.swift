import Foundation
import Testing
@testable import FocusFlow

@Suite struct InstanceLockTests {
    init() { TestSupport.isolate() }

    @Test func onlyOneInstancePerDataFolder() throws {
        let dir = TestSupport.dataDirectory.appendingPathComponent("lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var first = InstanceLock(directory: dir)
        #expect(first != nil)
        #expect(InstanceLock(directory: dir) == nil)
        first = nil
        #expect(InstanceLock(directory: dir) != nil)
    }
}
