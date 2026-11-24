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
        // Tests running in parallel start processes, which share the lock until their exec.
        var free = false
        for _ in 0..<100 where !free {
            free = InstanceLock(directory: dir) != nil
            if !free { usleep(20_000) }
        }
        #expect(free)
    }
}
