import Foundation
import AppKit
import Sparkle

/// Keeps update UI out of focus sessions and lets Sparkle finish on termination.
@MainActor
final class Updater: NSObject, ObservableObject {
    private let defaults = UserDefaults.standard
    private var controller: SPUStandardUpdaterController?
    private weak var state: AppState?

    @Published private(set) var isEnabled = false
    @Published private(set) var lastCheck: Date?

    override init() {
        super.init()
        lastCheck = defaults.object(forKey: "FocusFlowUpdateLastCheck") as? Date
    }

    func start(for state: AppState) {
        self.state = state
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let driver = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        controller = driver
        driver.updater.sendsSystemProfile = false
        driver.startUpdater()
        isEnabled = true
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    func checkNow() {
        guard isEnabled, Self.mayUpdateNow(phase: state?.phase ?? .idle), let controller else { return }
        let now = Date()
        lastCheck = now
        defaults.set(now, forKey: "FocusFlowUpdateLastCheck")
        controller.checkForUpdates(nil)
    }

    static func mayUpdateNow(phase: Phase) -> Bool {
        phase != .focus
    }
}

extension Updater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem) -> Bool {
        !Self.mayUpdateNow(phase: state?.phase ?? .idle)
    }
}

@MainActor
extension Updater: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus _: Bool
    ) -> Bool {
        guard let state else { return true }
        return Self.mayUpdateNow(phase: state.phase)
    }

    func standardUserDriverWillShowModalAlert() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
