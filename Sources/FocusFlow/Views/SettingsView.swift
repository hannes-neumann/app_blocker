import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var tab = 0

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            Picker(L10n.text("area"), selection: $tab) {
                Label(L10n.text("timer"), systemImage: "timer").tag(0)
                Label(L10n.text("blocking"), systemImage: "hand.raised").tag(1)
                Label(L10n.text("ai"), systemImage: "sparkles").tag(3)
                Label(L10n.text("timeTracking"), systemImage: "eye").tag(4)
                Label(L10n.text("general"), systemImage: "gearshape").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 8)
            .onChange(of: tab, initial: true) {
                Analytics.track(.settingsTabViewed, ["tab": .string([0: "timer", 1: "blocking", 2: "general", 3: "ai", 4: "tracking"][tab] ?? "\(tab)")])
            }

            switch tab {
            case 0: TimerSettingsView(settings: $state.settings)
            case 1: BlockingSettingsView(settings: $state.settings)
            case 3: AISettingsView(ai: state.ai)
            case 4: TrackingSettingsView()
            default: GeneralSettingsView()
            }
        }
    }
}

private struct TimerSettingsView: View {
    @Binding var settings: FocusSettings

    var body: some View {
        Form {
            NumberField(title: L10n.text("focus"), value: $settings.focusMinutes, range: 1...180)
            NumberField(title: L10n.text("shortBreak"), value: $settings.shortBreakMinutes, range: 1...60)
            NumberField(title: L10n.text("longBreak"), value: $settings.longBreakMinutes, range: 1...120)
            NumberField(title: L10n.text("longBreakAfter"), value: $settings.sessionsUntilLongBreak, range: 1...12, unit: L10n.text("rounds"))
            Toggle(L10n.text("autoStartFocus"), isOn: $settings.autoStartFocus)
            NumberField(title: L10n.text("dailyGoal"), value: $settings.dailyGoalMinutes, range: 5...600, step: 25, unit: L10n.text("minFocus"))
        }
        .formStyle(.grouped)
    }
}

private struct BlockingSettingsView: View {
    @Environment(AppState.self) private var state
    @Binding var settings: FocusSettings
    @State private var addingDomain = false

    var body: some View {
        Form {
            Section(L10n.text("apps")) {
                if settings.blockedApps.isEmpty {
                    Text(L10n.text("noAppsSelected")).foregroundStyle(.secondary)
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
                    Button(L10n.text("chooseApp"), action: chooseApps)
                    Menu(L10n.text("runningApp")) {
                        ForEach(runningApps, id: \.bundleID) { app in
                            Button(app.name) { add(app) }
                        }
                    }
                    .fixedSize()
                }
            }

            Section {
                Toggle(L10n.text("blockWebsites"), isOn: $settings.blockDomains)
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
                if settings.blockedDomains.isEmpty {
                    Text(L10n.text("noWebsitesSelected")).foregroundStyle(.secondary)
                }
                Button(L10n.text("addWebsite"), systemImage: "plus") {
                    addingDomain = true
                    Analytics.track(.addDomainOpened)
                }
            } header: {
                Text(L10n.text("websites"))
            } footer: {
                Text(L10n.text("websitesFooter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if state.isHelperInstalled {
                        Label(L10n.text("installed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button(L10n.text("remove")) { state.uninstallHelper() }
                    } else {
                        Label(L10n.text("notInstalled"), systemImage: "xmark.circle").foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.text("install")) { state.installHelper() }
                    }
                }
            } header: {
                Text(L10n.text("websiteHelper"))
            } footer: {
                Text(L10n.text("helperFooter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $addingDomain) {
            AddDomainSheet { domain in
                if !settings.blockedDomains.contains(domain) { settings.blockedDomains.append(domain) }
            }
        }
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
}

/// Asks for the address of a website to block and shows which domain that becomes.
private struct AddDomainSheet: View {
    let add: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var showError = false
    @FocusState private var focused: Bool

    private var domain: String? { DomainBlocker.normalize(url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("blockWebsiteTitle")).font(.headline)
            Text(L10n.text("blockWebsiteText"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("address")).font(.caption).foregroundStyle(.secondary)
                TextField("https://www.netflix.com", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: url) { showError = false }
            }
            Group {
                if let domain {
                    Label(L10n.text("blocksDomain", domain, domain), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if showError {
                    Label(L10n.text("invalidDomain"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text(" ")
                }
            }
            .font(.caption)
            HStack {
                Spacer()
                Button(L10n.text("cancel"), role: .cancel) {
                    Analytics.track(.addDomainCancelled, ["had_text": .bool(!url.isEmpty)])
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("add"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { focused = true }
    }

    private func submit() {
        guard let domain else {
            showError = true
            Analytics.track(.addDomainInvalid, content: ["text": url])
            return
        }
        add(domain)
        dismiss()
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
    @Environment(AppState.self) private var state
    @State private var loggingEnabled = Analytics.settings.enabled
    @State private var telemetryEnabled = Analytics.settings.telemetryEnabled
    @State private var logSize = LocalFileSink.totalSize

    var body: some View {
        Form {
            Section(L10n.text("language")) {
                Picker(L10n.text("language"), selection: Binding(
                    get: { state.settings.language },
                    set: { state.settings.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language == .english ? L10n.text("english") : L10n.text("german"))
                            .tag(language)
                    }
                }
            }
            Section(L10n.text("quickNote")) {
                LabeledContent(L10n.text("shortcut"), value: AppState.shortcutDescription)
                LabeledContent(L10n.text("timerShortcut"), value: AppState.timerShortcutDescription)
                Text(L10n.text("quickNoteFooter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ClaudeSection()

            if Bundle.main.object(forInfoDictionaryKey: "FocusFlowPostHogKey") as? String != nil {
            Section(L10n.text("telemetry")) {
                Toggle(L10n.text("telemetryOptIn"), isOn: $telemetryEnabled)
                    .onChange(of: telemetryEnabled) { Analytics.setTelemetryEnabled(telemetryEnabled) }
                Text(L10n.text("telemetryFooter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(L10n.text("privacyPolicy"), destination: URL(string: "https://github.com/hannes-neumann/app_blocker/blob/main/PRIVACY.md")!)
                Button(L10n.text("resetTelemetry")) { Analytics.resetTelemetryIdentity() }
            }
            }

            Section {
                Toggle(L10n.text("logUsage"), isOn: $loggingEnabled)
                    .onChange(of: loggingEnabled) {
                        // Log the switch itself while logging is still on.
                        if !loggingEnabled { Analytics.track(.settingChanged, ["setting": "logging.enabled", "old_value": true, "new_value": false]) }
                        Analytics.settings.enabled = loggingEnabled
                        if loggingEnabled { Analytics.track(.settingChanged, ["setting": "logging.enabled", "old_value": false, "new_value": true]) }
                    }
                LabeledContent(L10n.text("stored"), value: ByteCountFormatter.string(fromByteCount: logSize, countStyle: .file))
                HStack {
                    Button(L10n.text("showInFinder")) { NSWorkspace.shared.open(LocalFileSink.directory) }
                    Button(L10n.text("deleteLog"), role: .destructive) {
                        Analytics.flush()
                        LocalFileSink.deleteAll()
                        logSize = LocalFileSink.totalSize
                    }
                }
            } header: {
                Text(L10n.text("log"))
            } footer: {
                Text(L10n.text("logFooter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Analytics.flush()
            logSize = LocalFileSink.totalSize
        }
    }
}

/// How to connect Claude to FocusFlow's MCP server.
private struct ClaudeSection: View {
    @State private var copied: String?

    private static let serverURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/focusflow-mcp")

    var body: some View {
        let path = Self.serverURL.path
        let available = FileManager.default.isExecutableFile(atPath: path)
        Section {
            if available {
                LabeledContent(L10n.text("mcpServer")) {
                    Text(path).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                }
                HStack {
                    Button(copied == "desktop" ? L10n.text("copied") : L10n.text("copyForClaudeDesktop")) {
                        copy("desktop", """
                        "focusflow": {
                          "command": "\(path)"
                        }
                        """)
                    }
                    Button(copied == "code" ? L10n.text("copied") : L10n.text("copyForClaudeCode")) {
                        copy("code", "claude mcp add --scope user focusflow -- \"\(path)\"")
                    }
                }
            } else {
                Text(L10n.text("mcpOnlyInApp")).foregroundStyle(.secondary)
            }
        } header: {
            Text("Claude")
        } footer: {
            Text(L10n.text("mcpFooter")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func copy(_ kind: String, _ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = kind
        Analytics.track(.settingChanged, ["setting": "mcp.config_copied", "old_value": "", "new_value": .string(kind)])
    }
}
