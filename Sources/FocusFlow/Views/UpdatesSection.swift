import SwiftUI

struct UpdatesSection: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Section(L10n.text("updates")) {
            if state.updater.isEnabled {
                Toggle(L10n.text("automaticChecks"), isOn: Binding(
                    get: { state.updater.automaticallyChecks },
                    set: { state.updater.automaticallyChecks = $0 }
                ))
                Toggle(L10n.text("automaticDownloads"), isOn: Binding(
                    get: { state.updater.automaticallyDownloads },
                    set: { state.updater.automaticallyDownloads = $0 }
                ))
                LabeledContent(L10n.text("currentVersion"), value: state.updater.currentVersion)
                if let lastCheck = state.updater.lastUpdateCheckDate {
                    LabeledContent(L10n.text("lastCheck"), value: lastCheck.formatted(date: .abbreviated, time: .shortened))
                }
                Button(state.updater.pendingUpdate ? L10n.text("updateAvailable") : L10n.text("checkForUpdates")) {
                    state.updater.checkNow()
                }
                .disabled(state.phase == .focus)
                if state.phase == .focus {
                    Text(L10n.text("updatesDuringFocus"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.text("updatesOff")).foregroundStyle(.secondary)
            }
        }
    }
}
