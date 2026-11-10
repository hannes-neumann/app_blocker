import Foundation
import Testing
@testable import FocusFlow

@Suite("Running the model in batches")
@MainActor
struct AIBatchQueueTests {
    typealias Queue = AIBatchQueue
    let calm = Queue.Conditions(loadPerCore: 0.1, isConstrained: false)
    let busy = Queue.Conditions(loadPerCore: 0.9, isConstrained: false)
    let onBattery = Queue.Conditions(loadPerCore: 0.1, isConstrained: true)

    init() { TestSupport.isolate() }

    @Test func waitsDuringFocusUntilShortlyBeforeTheBreak() {
        #expect(Queue.trigger(moment: .focus(remaining: 600), waited: 999, conditions: calm) == nil)
        #expect(Queue.trigger(moment: .focus(remaining: 100), waited: 0, conditions: calm) == .calmWindow)
    }

    @Test func busyOrBatteryWaitsForTheDeadline() {
        #expect(Queue.trigger(moment: .focus(remaining: 100), waited: 0, conditions: busy) == nil)
        #expect(Queue.trigger(moment: .focus(remaining: 100), waited: 0, conditions: onBattery) == nil)
    }

    @Test func outsideFocusRunsAfterAMinute() {
        #expect(Queue.trigger(moment: .free, waited: 30, conditions: calm) == nil)
        #expect(Queue.trigger(moment: .free, waited: 61, conditions: onBattery) == .waited)
    }

    @Test func flushRunsAllJobsInOneSession() async {
        let queue = AIBatchQueue()
        var sessions = 0, ran: [Int] = [], finished = false
        queue.session = { work in
            sessions += 1
            await work()
        }
        queue.onBatchFinished = { finished = true }
        for n in 1...3 { queue.enqueue(kind: "test") { ran.append(n) } }
        #expect(ran.isEmpty, "jobs must wait for the batch")
        queue.flush()
        for _ in 0..<100 where !finished { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(ran == [1, 2, 3])
        #expect(sessions == 1)
    }
}
