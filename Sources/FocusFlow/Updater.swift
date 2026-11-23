import Foundation
import AppKit
import Observation
@preconcurrency import Sparkle

/// Keeps update UI out of focus sessions and lets Sparkle finish on termination.
@MainActor
@Observable
final class Updater: NSObject {
    private var controller: SPUStandardUpdaterController?
    private weak var state: AppState?
    private let configuredPublicKey: String?
    private(set) var isEnabled = false
    private(set) var pendingUpdate = false
    var postponedInstallHandler: (() -> Void)?

    init(publicKey: String? = nil) {
        configuredPublicKey = publicKey
        super.init()
    }

    func start(for state: AppState) {
        self.state = state
        guard let key = configuredPublicKey ?? Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
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

    var lastUpdateCheckDate: Date? { controller?.updater.lastUpdateCheckDate }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    func checkNow() {
        guard isEnabled, Self.mayUpdateNow(phase: state?.phase ?? .idle), let controller else { return }
        pendingUpdate = false
        controller.checkForUpdates(nil)
    }

    func phaseChanged(from oldPhase: Phase, to newPhase: Phase) {
        guard oldPhase == .focus, newPhase != .focus else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deliverDeferredIfSafe(currentPhase: self.state?.phase ?? newPhase)
        }
    }

    func deliverDeferredIfSafe(currentPhase: Phase) {
        guard currentPhase != .focus else { return }
        if let handler = postponedInstallHandler {
            postponedInstallHandler = nil
            handler()
        }
        if pendingUpdate {
            pendingUpdate = false
            controller?.checkForUpdates(nil)
        }
    }

    static func mayUpdateNow(phase: Phase) -> Bool {
        phase != .focus
    }
}

extension Updater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !Self.mayUpdateNow(phase: state?.phase ?? .idle) else { return false }
        if postponedInstallHandler == nil {
            postponedInstallHandler = installHandler
        }
        return true
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
        if !Self.mayUpdateNow(phase: state.phase) {
            pendingUpdate = true
            return false
        }
        return true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate { pendingUpdate = true }
    }

    func standardUserDriverWillShowModalAlert() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pendingUpdate = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingUpdate = false
    }
}
