import SwiftUI

struct BundleAppIcon: View {
    let bundleID: String
    var size: CGFloat = 18

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed").frame(width: size, height: size)
        }
    }
}

extension TrackingRule.Kind {
    var title: String {
        switch self {
        case .app: L10n.text("ruleKindApp")
        case .domain: L10n.text("ruleKindDomain")
        case .title: L10n.text("ruleKindTitle")
        }
    }

    var symbol: String {
        switch self {
        case .app: "app"
        case .domain: "globe"
        case .title: "macwindow"
        }
    }

    var placeholder: String {
        switch self {
        case .app: ""
        case .domain: L10n.text("ruleDomainPlaceholder")
        case .title: L10n.text("ruleTitlePlaceholder")
        }
    }
}

extension ActivitySegment.Assignment {
    var symbol: String? {
        switch self {
        case .none: nil
        case .rule: "wand.and.stars"
        case .focus: "timer"
        case .manual: "hand.point.up.left"
        }
    }

    var help: String {
        switch self {
        case .none: ""
        case .rule: L10n.text("assignedByRule")
        case .focus: L10n.text("assignedByFocus")
        case .manual: L10n.text("assignedManually")
        }
    }
}

// MARK: - Overview card

/// Today's automatically tracked time, which can be assigned to projects block by block.
struct TrackedTodayCard: View {
    @Environment(AppState.self) private var state
    @State private var showAll = false
    @State private var ruleDraft: RuleDraft?

    var body: some View {
        let tracker = state.activity
        VStack(alignment: .leading, spacing: 12) {
            if !tracker.settings.enabled {
                CardHeader(title: L10n.text("autoTracking"), subtitle: L10n.text("autoTrackingPitch"))
                HStack(spacing: 12) {
                    Button {
                        state.activity.settings.enabled = true
                        if !state.activity.hasAccessibility { state.activity.requestAccessibility() }
                    } label: {
                        Label(L10n.text("enableAutoTracking"), systemImage: "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    Text(L10n.text("autoTrackingPrivacyShort")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                let blocks = tracker.blocks(on: Date())
                let total = blocks.reduce(0) { $0 + $1.seconds } / 60
                let unassigned = blocks.filter { $0.projectID == nil }.reduce(0) { $0 + $1.seconds } / 60
                let listed = Array(blocks.filter { $0.seconds >= 60 }.reversed())
                CardHeader(title: L10n.text("trackedToday"),
                           subtitle: total < 1 ? L10n.text("trackingRunning")
                               : L10n.text("trackedSummary", formatDuration(total), formatDuration(unassigned))) {
                    if listed.count > 6 {
                        Button(showAll ? L10n.text("showLess") : L10n.text("showAllCount", listed.count)) { showAll.toggle() }
                            .buttonStyle(.link).font(.caption)
                    }
                }
                if tracker.settings.windowTitles && !tracker.hasAccessibility {
                    AccessibilityHint()
                }
                if blocks.isEmpty {
                    EmptyHint(symbol: "eye", text: L10n.text("trackingNoDataYet"))
                } else {
                    DayTimeline(spans: blocks.map { block in
                        let project = state.projects.project(block.projectID)
                        return TimelineSpan(id: block.id, start: block.start, end: block.end,
                                            color: project?.color ?? ProjectPalette.none,
                                            help: (project?.name ?? L10n.text("noProject")) + " · " + formatDuration(block.seconds / 60))
                    })
                    ProjectTotals(blocks: blocks)
                    VStack(spacing: 0) {
                        let shown = showAll ? listed : Array(listed.prefix(6))
                        ForEach(shown) { block in
                            TrackedBlockRow(block: block) { item in ruleDraft = RuleDraft(item: item, projectID: block.projectID) }
                            if block.id != shown.last?.id { Divider() }
                        }
                    }
                }
            }
        }
        .card()
        .sheet(item: $ruleDraft) { TrackingRuleSheet(draft: $0) }
    }
}

private struct AccessibilityHint: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(L10n.text("accessibilityMissing")).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L10n.text("allowAccess")) { state.activity.requestAccessibility() }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Time per project in a list of blocks, as small labeled chips.
private struct ProjectTotals: View {
    @Environment(AppState.self) private var state
    let blocks: [ActivityBlock]

    var body: some View {
        var totals: [UUID?: Double] = [:]
        for block in blocks { totals[block.projectID, default: 0] += block.seconds / 60 }
        let sorted = totals.sorted { a, b in
            if (a.key == nil) != (b.key == nil) { return b.key == nil }
            return a.value > b.value
        }
        return FlowLayout(spacing: 8) {
            ForEach(sorted, id: \.key) { projectID, minutes in
                let project = state.projects.project(projectID)
                HStack(spacing: 5) {
                    ProjectDot(colorIndex: project?.colorIndex, size: 8)
                    Text(project?.name ?? L10n.text("noProject"))
                    Text(formatDuration(minutes)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
            }
        }
    }
}

struct TrackedBlockRow: View {
    @Environment(AppState.self) private var state
    let block: ActivityBlock
    let onCreateRule: (ActivityItem) -> Void

    var body: some View {
        let project = state.projects.project(block.projectID)
        let top = block.items.first
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(project?.color ?? ProjectPalette.none)
                .frame(width: 4, height: 30)
            if let top { BundleAppIcon(bundleID: top.bundleID, size: 22) }
            VStack(alignment: .leading, spacing: 2) {
                Text(top.map(Self.label) ?? "").lineLimit(1).truncationMode(.middle)
                Text(secondaryText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .help(tooltip)
            Spacer(minLength: 8)
            if let symbol = block.assignment.symbol {
                Image(systemName: symbol).font(.caption).foregroundStyle(.secondary).help(block.assignment.help)
            }
            Text(formatDuration(block.seconds / 60)).monospacedDigit().foregroundStyle(.secondary)
            Menu {
                Button { state.activity.assign(block, to: nil) } label: {
                    if block.projectID == nil { Image(systemName: "checkmark") }
                    Text(L10n.text("noProject"))
                }
                Divider()
                ForEach(state.projects.projects) { item in
                    Button { state.activity.assign(block, to: item.id) } label: {
                        if block.projectID == item.id { Image(systemName: "checkmark") }
                        Text(item.name)
                    }
                }
                let sources = [top, side].compactMap { $0 }
                if !sources.isEmpty {
                    Divider()
                    ForEach(sources) { item in
                        Button(L10n.text("ruleFrom", Self.label(item)) + "…") { onCreateRule(item) }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    ProjectDot(colorIndex: project?.colorIndex, size: 8)
                    Text(project?.name ?? L10n.text("assign"))
                        .foregroundStyle(project == nil ? Color.accentColor : .primary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.text("assignTrackedTime"))
        }
        .padding(.vertical, 4)
    }

    static func label(_ item: ActivityItem) -> String {
        guard let detail = item.detail, detail != item.appName else { return item.appName }
        return item.appName + " · " + detail
    }

    /// The window visible next to the front apps for a good part of the block, if any.
    private var side: ActivityItem? {
        block.sideItems.first.flatMap { $0.seconds >= block.seconds * 0.3 && $0.bundleID != block.items.first?.bundleID ? $0 : nil }
    }

    private var secondaryText: String {
        let start = block.start.formatted(.dateTime.hour().minute().locale(L10n.locale))
        let end = block.end.formatted(.dateTime.hour().minute().locale(L10n.locale))
        var parts = ["\(start)–\(end)"]
        if let side { parts.append(L10n.text("nextTo", Self.label(side))) }
        let others = block.items.count - 1
        if others > 0 { parts.append(L10n.text(others == 1 ? "moreItemsOne" : "moreItems", others)) }
        return parts.joined(separator: " · ")
    }

    private var tooltip: String {
        var lines = block.items.prefix(6).map { Self.label($0) + " · " + formatDuration($0.seconds / 60) }
        if !block.sideItems.isEmpty {
            lines.append(L10n.text("visibleNextTo"))
            lines += block.sideItems.prefix(4).map { "  " + Self.label($0) + " · " + formatDuration($0.seconds / 60) }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Rules

/// A rule suggested from tracked activity, edited in `TrackingRuleSheet`.
struct RuleDraft: Identifiable {
    let id = UUID()
    let bundleID: String
    let appName: String
    /// Suggested value per kind; kinds without one cannot be picked.
    let values: [TrackingRule.Kind: String]
    let projectID: UUID?

    init(item: ActivityItem, projectID: UUID?) {
        bundleID = item.bundleID
        appName = item.appName
        var values: [TrackingRule.Kind: String] = [.app: item.bundleID]
        if let address = item.address { values[.domain] = address.split(separator: "/").first.map(String.init) ?? address }
        if let title = item.title { values[.title] = title }
        self.values = values
        self.projectID = projectID
    }
}

struct TrackingRuleSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let draft: RuleDraft
    @State private var kind: TrackingRule.Kind
    @State private var value: String
    @State private var projectID: UUID?

    init(draft: RuleDraft) {
        self.draft = draft
        let kind: TrackingRule.Kind = draft.values[.domain] != nil ? .domain : .app
        _kind = State(initialValue: kind)
        _value = State(initialValue: draft.values[kind] ?? "")
        _projectID = State(initialValue: draft.projectID)
    }

    var body: some View {
        let rule = self.rule
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("createRule")).font(.title2.weight(.semibold))
                Text(L10n.text("createRuleHint")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker(L10n.text("ruleKind"), selection: $kind) {
                ForEach(TrackingRule.Kind.allCases.filter { draft.values[$0] != nil }, id: \.self) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { value = draft.values[kind] ?? "" }
            if kind == .app {
                HStack {
                    BundleAppIcon(bundleID: draft.bundleID, size: 22)
                    Text(draft.appName)
                }
            } else {
                TextField(kind.placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)
                if kind == .title {
                    Text(L10n.text("ruleTitleTip")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker(L10n.text("project"), selection: $projectID) {
                Text(L10n.text("chooseProject")).tag(UUID?.none)
                ForEach(state.projects.projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            if let rule {
                let minutes = state.activity.minutesMatching(rule, since: Date())
                Text(minutes >= 1 ? L10n.text("rulePreview", formatDuration(minutes)) : L10n.text("rulePreviewNone"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(L10n.text("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("createRule")) {
                    if let rule, let projectID { state.addTrackingRule(rule, to: projectID) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule == nil || projectID == nil)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private var rule: TrackingRule? {
        switch kind {
        case .app:
            return TrackingRule(kind: .app, value: draft.bundleID, label: draft.appName)
        case .domain:
            return TrackingRule.normalizedAddress(value).map { TrackingRule(kind: .domain, value: $0) }
        case .title:
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : TrackingRule(kind: .title, value: text)
        }
    }
}

/// The rules of one project and its tracked time, on the project page.
struct TrackingRulesCard: View {
    @Environment(AppState.self) private var state
    let project: Project
    @State private var kind = TrackingRule.Kind.domain
    @State private var value = ""

    var body: some View {
        let tracker = state.activity
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let week = tracker.minutes(for: project.id, since: weekStart)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: L10n.text("autoTracking"),
                       subtitle: tracker.settings.enabled ? L10n.text("trackedThisWeek", formatDuration(week)) : L10n.text("autoTrackingOff")) {
                if !tracker.settings.enabled {
                    Button(L10n.text("enableAutoTracking")) {
                        state.activity.settings.enabled = true
                        if !state.activity.hasAccessibility { state.activity.requestAccessibility() }
                    }
                    .font(.caption)
                }
            }
            if project.trackingRules.isEmpty {
                Text(L10n.text("noRulesHint")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(project.trackingRules) { rule in
                        HStack(spacing: 10) {
                            if rule.kind == .app {
                                BundleAppIcon(bundleID: rule.value)
                            } else {
                                Image(systemName: rule.kind.symbol).frame(width: 18).foregroundStyle(.secondary)
                            }
                            Text(rule.label ?? rule.value).lineLimit(1)
                            Text(rule.kind.title).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { state.removeTrackingRule(rule.id, from: project.id) } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.text("removeRule"))
                        }
                        .padding(.vertical, 6)
                        if rule.id != project.trackingRules.last?.id { Divider() }
                    }
                }
            }
            HStack(spacing: 8) {
                Picker(L10n.text("ruleKind"), selection: $kind) {
                    ForEach(TrackingRule.Kind.allCases, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                if kind == .app {
                    Menu(L10n.text("chooseApp")) {
                        ForEach(appChoices, id: \.bundleID) { app in
                            Button(app.name) {
                                state.addTrackingRule(TrackingRule(kind: .app, value: app.bundleID, label: app.name), to: project.id)
                            }
                        }
                    }
                    .fixedSize()
                    Spacer()
                } else {
                    TextField(kind.placeholder, text: $value)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTextRule)
                    Button(L10n.text("add"), action: addTextRule).disabled(textRule == nil)
                }
            }
        }
        .card()
    }

    private var textRule: TrackingRule? {
        switch kind {
        case .app: return nil
        case .domain: return TrackingRule.normalizedAddress(value).map { TrackingRule(kind: .domain, value: $0) }
        case .title:
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : TrackingRule(kind: .title, value: text)
        }
    }

    private func addTextRule() {
        guard let rule = textRule else { return }
        state.addTrackingRule(rule, to: project.id)
        value = ""
    }

    /// Apps seen by the tracker (most used first), then other running apps.
    private var appChoices: [BlockedApp] {
        let existing = Set(project.trackingRules.filter { $0.kind == .app }.map(\.value))
        var seconds: [String: (name: String, seconds: Double)] = [:]
        for segment in state.activity.segments {
            seconds[segment.bundleID, default: (segment.appName, 0)].seconds += segment.seconds
        }
        var apps = seconds.sorted { $0.value.seconds > $1.value.seconds }.map { BlockedApp(bundleID: $0.key, name: $0.value.name) }
        let seen = Set(apps.map(\.bundleID))
        apps += NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, !seen.contains(id), id != Bundle.main.bundleIdentifier else { return nil }
                return BlockedApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return apps.filter { !existing.contains($0.bundleID) }
    }
}

// MARK: - Settings

struct TrackingSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var activity = state.activity
        Form {
            Section {
                Toggle(L10n.text("autoTracking"), isOn: $activity.settings.enabled)
            } footer: {
                Text(L10n.text("autoTrackingFooter")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("trackingSources")) {
                Toggle(L10n.text("trackWindowTitles"), isOn: $activity.settings.windowTitles)
                if activity.settings.windowTitles {
                    LabeledContent(L10n.text("accessibilityPermission")) {
                        if activity.hasAccessibility {
                            Label(L10n.text("granted"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button(L10n.text("allowAccess")) { activity.requestAccessibility() }
                        }
                    }
                }
                Toggle(L10n.text("trackBrowserAddresses"), isOn: $activity.settings.browserAddresses)
                Text(L10n.text("browserAddressesHint")).font(.caption).foregroundStyle(.secondary)
                if !activity.deniedBrowsers.isEmpty {
                    HStack {
                        Text(L10n.text("browsersDenied", activity.deniedBrowsers.compactMap(appName).joined(separator: ", ")))
                            .font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button(L10n.text("openSystemSettings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                Toggle(isOn: $activity.settings.sideWindow) {
                    Text(L10n.text("trackSideWindow"))
                    Text(L10n.text("trackSideWindowHint"))
                }
                NumberField(title: L10n.text("pauseWhenIdle"), value: $activity.settings.idleMinutes, range: 1...30)
            }
            Section {
                LabeledContent(L10n.text("stored"), value: L10n.text("trackedDays", Set(activity.segments.map { Calendar.current.startOfDay(for: $0.start) }).count))
                HStack {
                    Button(L10n.text("showInFinder")) { NSWorkspace.shared.open(ActivityTracker.directory) }
                    Button(L10n.text("deleteTrackedData"), role: .destructive) { confirmDelete = true }
                }
            } header: {
                Text(L10n.text("trackingData"))
            } footer: {
                Text(L10n.text("trackingPrivacyFooter")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L10n.text("deleteTrackedDataTitle"), isPresented: $confirmDelete) {
            Button(L10n.text("delete"), role: .destructive) { state.activity.deleteAll() }
        }
        .task {
            // Notice a permission granted in System Settings without reopening the window.
            while !Task.isCancelled {
                state.activity.refreshPermissions()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func appName(_ bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }
}
