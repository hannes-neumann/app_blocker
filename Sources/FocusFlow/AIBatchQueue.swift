import Darwin
import Foundation
import IOKit.ps

/// Model work that can wait, run together so the model is loaded once per batch instead of once per job.
/// During a focus session jobs wait until shortly before the break, and the end of the session is the deadline.
@MainActor
final class AIBatchQueue {
    enum Moment {
        case focus(remaining: TimeInterval)
        /// No running focus session, so nothing is being disturbed and nothing sets a deadline.
        case free
    }

    enum Trigger: String {
        case calmWindow = "calm_window"
        case deadline
        case waited
    }

    struct Conditions {
        /// One-minute load average per CPU core.
        var loadPerCore: Double
        /// On battery, in Low Power Mode or running hot: only the deadline may start the model.
        var isConstrained: Bool

        static var current: Conditions {
            var load = [0.0]
            getloadavg(&load, 1)
            let info = ProcessInfo.processInfo
            let isHot = info.thermalState == .serious || info.thermalState == .critical
            return Conditions(loadPerCore: load[0] / Double(max(info.activeProcessorCount, 1)),
                              isConstrained: isHot || info.isLowPowerModeEnabled || isOnBattery)
        }

        private static var isOnBattery: Bool {
            let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
            let source = IOPSGetProvidingPowerSourceType(snapshot).takeUnretainedValue() as String
            return source == kIOPSBatteryPowerValue
        }
    }

    private struct Job {
        let kind: String
        let enqueuedAt: Date
        let run: @MainActor () async -> Void
    }

    /// How long before the break a batch may start if the Mac is calm.
    static let focusWindow: TimeInterval = 120
    /// Outside a focus session, how long to wait so that several notes end up in one batch.
    static let freeDelay: TimeInterval = 60
    static let maxLoadPerCore = 0.5

    var moment: () -> Moment = { .free }
    /// Wraps a batch, e.g. to load the model before it and free it right after.
    var session: (@MainActor () async -> Void) async -> Void = { await $0() }
    var onBatchFinished: () -> Void = {}

    private var jobs: [Job] = []
    private var isRunning = false
    private var timer: Timer?

    func enqueue(kind: String, _ run: @escaping @MainActor () async -> Void) {
        jobs.append(Job(kind: kind, enqueuedAt: Date(), run: run))
        updateTimer()
    }

    /// The deadline: runs whatever is waiting, however busy the Mac is.
    func flush() {
        run(.deadline)
    }

    static func trigger(moment: Moment, waited: TimeInterval, conditions: Conditions) -> Trigger? {
        switch moment {
        case .focus(let remaining):
            remaining <= focusWindow && conditions.loadPerCore < maxLoadPerCore && !conditions.isConstrained ? .calmWindow : nil
        case .free:
            waited >= freeDelay ? .waited : nil
        }
    }

    /// The timer only exists while jobs wait, so an empty queue never wakes the Mac.
    private func updateTimer() {
        guard !jobs.isEmpty, !isRunning else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer?.tolerance = 5
    }

    private func evaluate() {
        guard let oldest = jobs.first,
              let trigger = Self.trigger(moment: moment(), waited: Date().timeIntervalSince(oldest.enqueuedAt),
                                         conditions: .current) else { return }
        run(trigger)
    }

    private func run(_ trigger: Trigger) {
        guard !isRunning, !jobs.isEmpty else { return }
        isRunning = true
        updateTimer()
        Task {
            let started = Date()
            var finished: [String] = []
            await session {
                // Jobs added meanwhile join this batch while the model is still loaded.
                while !self.jobs.isEmpty {
                    let job = self.jobs.removeFirst()
                    await job.run()
                    finished.append(job.kind)
                }
            }
            isRunning = false
            Analytics.track(.aiBatchFinished, ["trigger": .string(trigger.rawValue), "jobs": .int(finished.count),
                                               "kinds": .string(Set(finished).sorted().joined(separator: ",")),
                                               "duration_ms": .int(Int(Date().timeIntervalSince(started) * 1000))])
            onBatchFinished()
            updateTimer()
        }
    }
}
