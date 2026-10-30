import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var tab = 0

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            Picker("Bereich", selection: $tab) {
                Label("Timer", systemImage: "timer").tag(0)
                Label("Blockieren", systemImage: "hand.raised").tag(1)
                Label("KI", systemImage: "sparkles").tag(3)
                Label("Allgemein", systemImage: "gearshape").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 8)

            switch tab {
            case 0: TimerSettingsView(settings: $state.settings)
            case 1: BlockingSettingsView(settings: $state.settings)
            case 3: AISettingsView(ai: state.ai)
            default: GeneralSettingsView()
            }
        }
    }
}

private struct TimerSettingsView: View {
    @Binding var settings: FocusSettings

    var body: some View {
        Form {
            NumberField(title: "Fokus", value: $settings.focusMinutes, range: 1...180)
            NumberField(title: "Kurze Pause", value: $settings.shortBreakMinutes, range: 1...60)
            NumberField(title: "Lange Pause", value: $settings.longBreakMinutes, range: 1...120)
            NumberField(title: "Lange Pause nach", value: $settings.sessionsUntilLongBreak, range: 1...12, unit: "Runden")
            Toggle("Nach der Pause automatisch weiterfokussieren", isOn: $settings.autoStartFocus)
            NumberField(title: "Tagesziel", value: $settings.dailyGoalMinutes, range: 5...600, step: 25, unit: "Min Fokus")
        }
        .formStyle(.grouped)
    }
}

private struct BlockingSettingsView: View {
    @Environment(AppState.self) private var state
    @Binding var settings: FocusSettings
    @State private var newDomain = ""
    @State private var domainError = false

    var body: some View {
        Form {
            Section("Apps") {
                if settings.blockedApps.isEmpty {
                    Text("Noch keine Apps ausgewählt.").foregroundStyle(.secondary)
                }
                ForEach(settings.blockedApps) { app in
                    HStack {
                        AppIcon(bundleID: app.bundleID)
                        Text(app.name)
                        Spacer()
                        Button { settings.blockedApps.removeAll { $0 == app } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("App auswählen…", action: chooseApps)
                    Menu("Laufende App") {
                        ForEach(runningApps, id: \.bundleID) { app in
                            Button(app.name) { add(app) }
                        }
                    }
                    .fixedSize()
                }
            }

            Section {
                Toggle("Webseiten blockieren", isOn: $settings.blockDomains)
                ForEach(settings.blockedDomains, id: \.self) { domain in
                    HStack {
                        Text(domain)
                        Spacer()
                        Button { settings.blockedDomains.removeAll { $0 == domain } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("z. B. netflix.com", text: $newDomain)
                        .onSubmit(addDomain)
                    Button("Hinzufügen", action: addDomain)
                        .disabled(newDomain.isEmpty)
                }
                if domainError {
                    Text("Das sieht nicht nach einer gültigen Domain aus.").font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Webseiten")
            } footer: {
                Text("Webseiten werden systemweit über /etc/hosts blockiert. Bereits geöffnete Tabs können bis zum Neuladen weiterlaufen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if state.isHelperInstalled {
                        Label("Installiert", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Entfernen") { state.uninstallHelper() }
                    } else {
                        Label("Nicht installiert", systemImage: "xmark.circle").foregroundStyle(.secondary)
                        Spacer()
                        Button("Installieren…") { state.installHelper() }
                    }
                }
            } header: {
                Text("Webseiten-Helfer")
            } footer: {
                Text("Ein kleiner Systemdienst, der /etc/hosts bearbeiten darf. Du gibst dein Admin-Passwort nur einmal bei der Installation ein. Er sperrt nur, solange FocusFlow läuft und im Fokus ist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var runningApps: [BlockedApp] {
        let ownID = Bundle.main.bundleIdentifier
        let existing = Set(settings.blockedApps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != ownID, id != "com.apple.finder", !existing.contains(id) else { return nil }
                return BlockedApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            add(BlockedApp(bundleID: id, name: name))
        }
    }

    private func add(_ app: BlockedApp) {
        guard !settings.blockedApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        settings.blockedApps.append(app)
    }

    private func addDomain() {
        guard let domain = DomainBlocker.normalize(newDomain) else {
            domainError = true
            return
        }
        domainError = false
        if !settings.blockedDomains.contains(domain) { settings.blockedDomains.append(domain) }
        newDomain = ""
    }
}

private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.dashed").frame(width: 20, height: 20)
        }
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section("Schnellnotiz") {
                LabeledContent("Tastenkürzel", value: AppState.shortcutDescription)
                Text("Öffnet überall ein kleines Textfeld. Deine Notiz wird zu einem konkreten Todo mit geschätzter Dauer, das dir in einer passenden Pause vorgeschlagen wird.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
