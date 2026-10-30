import SwiftUI

struct AISettingsView: View {
    @Bindable var ai: AIEngine

    var body: some View {
        Form {
            Section {
                Picker("KI für Todos", selection: $ai.settings.provider) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Gerade aktiv") {
                    Label(ai.activeDescription, systemImage: ai.activeDescription.hasPrefix("Stichwort") ? "text.magnifyingglass" : "sparkles")
                }
            } footer: {
                Text("„Automatisch“ nimmt Apple Intelligence, wenn verfügbar, sonst Ollama. Ohne KI übernimmt FocusFlow die Notiz als Todo und schätzt die Dauer anhand von Stichworten. Angaben wie „30 min“ oder „2h“ in der Notiz werden immer übernommen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Adresse", text: $ai.settings.ollamaURL)
                modelRow
                statusRow
            } header: {
                Text("Ollama")
            } footer: {
                Text("Ollama führt offene Sprachmodelle direkt auf deinem Mac aus, deine Notizen verlassen ihn nicht. Installieren mit „brew install ollama“ und starten mit „ollama serve“ (oder die Ollama-App von ollama.com öffnen).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Intelligence") {
                switch ai.appleStatus {
                case .available:
                    Label("Verfügbar", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .unavailable(let reason):
                    Label(reason, systemImage: "xmark.circle").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await ai.checkOllama() }
    }

    @ViewBuilder
    private var modelRow: some View {
        let installed = ai.ollamaStatus.installed
        if installed.isEmpty {
            TextField("Modell", text: $ai.settings.ollamaModel)
        } else {
            Picker("Modell", selection: $ai.settings.ollamaModel) {
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
                Text("Verbindung wird geprüft…").foregroundStyle(.secondary)
            case .notRunning:
                Label("Ollama läuft nicht", systemImage: "xmark.circle").foregroundStyle(.secondary)
            case .modelMissing:
                Label("\(ai.settings.ollamaModel) ist nicht geladen", systemImage: "arrow.down.circle").foregroundStyle(.orange)
                Spacer()
                Button("Modell laden") { ai.pullModel() }
            case .pulling:
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ai.settings.ollamaModel) wird geladen… \(Int(ai.pullProgress * 100)) %").foregroundStyle(.secondary)
                    ProgressView(value: ai.pullProgress)
                }
            case .ready:
                Label("Bereit", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if ai.ollamaStatus != .modelMissing(installed: ai.ollamaStatus.installed) {
                Spacer()
                Button("Erneut prüfen") { Task { await ai.checkOllama() } }
                    .disabled(ai.ollamaStatus == .checking || ai.ollamaStatus == .pulling)
            }
        }
        if let error = ai.pullError {
            Text("Laden fehlgeschlagen: \(error)").font(.caption).foregroundStyle(.red)
        }
    }
}
