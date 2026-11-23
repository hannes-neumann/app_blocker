import Foundation
import Testing
import Sparkle
@testable import FocusFlow

@MainActor
@Suite("Updater")
struct UpdaterTests {
    init() { TestSupport.isolate() }

    @Test("May update in every non-focus phase")
    func mayUpdateNow() {
        #expect(!Updater.mayUpdateNow(phase: .focus))
        #expect(Updater.mayUpdateNow(phase: .idle))
        #expect(Updater.mayUpdateNow(phase: .shortBreak))
        #expect(Updater.mayUpdateNow(phase: .longBreak))
    }

    @Test("Postponed installation runs once after focus")
    func postponedInstallationRunsOnce() {
        let updater = Updater()
        var calls = 0
        updater.postponedInstallHandler = { calls += 1 }
        updater.phaseChanged(from: .focus, to: .shortBreak)
        updater.phaseChanged(from: .shortBreak, to: .idle)
        #expect(calls == 1)
    }

    @Test("Delegate methods expose the selectors Sparkle invokes")
    func delegateSelectors() {
        let updater = Updater()
        #expect(updater.responds(to: #selector(Updater.updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:))))
        #expect(updater.responds(to: #selector(Updater.standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:))))
        #expect(updater.responds(to: #selector(Updater.standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:))))
        #expect(updater.responds(to: #selector(Updater.standardUserDriverWillShowModalAlert)))
    }

    @Test("Updater is disabled without a public key")
    func disabledWithoutKey() {
        let updater = Updater()
        #expect(!updater.isEnabled)
    }
}
