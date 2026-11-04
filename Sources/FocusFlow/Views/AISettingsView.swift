import SwiftUI

struct AISettingsView: View {
    @Bindable var ai: AIEngine

    var body: some View {
        Form {
            Section {
                Picker(L10n.text("aiForTodos"), selection: $ai.settings.provider) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent(L10n.text("activeNow")) {
                    Label(ai.activeDescription, systemImage: ai.isUsingHeuristic ? "text.magnifyingglass" : "sparkles")
                }
            } footer: {
                Text(L10n.text("aiProviderFooter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(L10n.text("ollamaAutostart"), isOn: $ai.settings.startOllama)
                TextField(L10n.text("address"), text: $ai.settings.ollamaURL)
                modelRow
                statusRow
            } header: {
                Text("Ollama")
            } footer: {
                Text(L10n.text("ollamaFooter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Intelligence") {
                switch ai.appleStatus {
                case .available:
                    Label(L10n.text("available"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .unavailable(let reason):
                    Label(reason, systemImage: "xmark.circle").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        // The model list and the status need the server, which otherwise only runs for a batch.
        .onAppear { Task { await ai.holdServer() } }
        .onDisappear { ai.releaseServer() }
    }

    @ViewBuilder
    private var modelRow: some View {
        let installed = ai.ollamaStatus.installed
        if installed.isEmpty {
            TextField(L10n.text("model"), text: $ai.settings.ollamaModel)
        } else {
            Picker(L10n.text("model"), selection: $ai.settings.ollamaModel) {
                // Keep a typed model that is not downloaded yet selectable.
                ForEach(installed.contains(ai.settings.ollamaModel) ? installed : [ai.settings.ollamaModel] + installed, id: \.self) {
                    Text($0).tag($0)
                }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            switch ai.ollamaStatus {
            case .unknown, .checking:
                ProgressView().controlSize(.small)
                Text(L10n.text("checkingConnection")).foregroundStyle(.secondary)
            case .notRunning:
                Label(L10n.text(AIEngine.ollamaExecutable == nil ? "ollamaNotInstalled" : "ollamaNotRunning"),
                      systemImage: "xmark.circle").foregroundStyle(.secondary)
            case .modelMissing:
                Label(L10n.text("modelNotLoaded", ai.settings.ollamaModel), systemImage: "arrow.down.circle").foregroundStyle(.orange)
                Spacer()
                Button(L10n.text("loadModel")) { ai.pullModel() }
            case .pulling:
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("modelLoading", ai.settings.ollamaModel, Int(ai.pullProgress * 100))).foregroundStyle(.secondary)
                    ProgressView(value: ai.pullProgress)
                }
            case .ready:
                Label(L10n.text("readyStatus"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if ai.ollamaStatus != .modelMissing(installed: ai.ollamaStatus.installed) {
                Spacer()
                Button(L10n.text("checkAgain")) { Task { await ai.checkOllama() } }
                    .disabled(ai.ollamaStatus == .checking || ai.ollamaStatus == .pulling)
            }
        }
        if let error = ai.pullError {
            Text(L10n.text("loadFailed", error)).font(.caption).foregroundStyle(.red)
        }
    }
}
