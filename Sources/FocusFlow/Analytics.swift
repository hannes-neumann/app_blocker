import Foundation

/// A property value of an event. Kept to the types analytics backends like Firebase accept.
enum AnalyticsValue: Codable, Equatable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }

    init?(_ any: Any) {
        switch any {
        case let v as Bool: self = .bool(v)
        case let v as Int: self = .int(v)
        case let v as Double: self = .double(v)
        case let v as String: self = .string(v)
        case let v as any RawRepresentable<String>: self = .string(v.rawValue)
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        }
    }
}

typealias AnalyticsProperties = [String: AnalyticsValue]

/// Everything the user does in the app. Names and keys are snake_case and at most 40 characters,
/// the limits of Firebase Analytics, so events can be sent there unchanged later.
enum AnalyticsEventName: String, Codable, CaseIterable {
    // App
    case appLaunched = "app_launched"
    case appQuit = "app_quit"
    case menuOpened = "menu_opened"
    case dashboardOpened = "dashboard_opened"
    case dashboardSectionViewed = "dashboard_section_viewed"
    case dashboardClosed = "dashboard_closed"
    case settingsTabViewed = "settings_tab_viewed"
    case statsRangeChanged = "stats_range_changed"
    // Timer
    case focusStarted = "focus_started"
    case focusEnded = "focus_ended"
    case breakStarted = "break_started"
    case breakEnded = "break_ended"
    case timerPaused = "timer_paused"
    case timerResumed = "timer_resumed"
    case focusDurationInvalid = "focus_duration_invalid"
    case timerEntryOpened = "timer_entry_opened"
    case timerEntryCancelled = "timer_entry_cancelled"
    case focusTaskSelected = "focus_task_selected"
    case appBlocked = "app_blocked"
    case breakPanelClosed = "break_panel_closed"
    // Todos
    case quickCaptureOpened = "quick_capture_opened"
    case quickCaptureCancelled = "quick_capture_cancelled"
    case noteCaptured = "note_captured"
    case noteRefined = "note_refined"
    case todoCompleted = "todo_completed"
    case todoReopened = "todo_reopened"
    case todoEstimateChanged = "todo_estimate_changed"
    case todoTitleChanged = "todo_title_changed"
    case todoDeleted = "todo_deleted"
    case todosCleared = "todos_cleared"
    case todoListFilterChanged = "todo_list_filter_changed"
    case suggestionShown = "suggestion_shown"
    case suggestionSkipped = "suggestion_skipped"
    case taskAdded = "task_added"
    case todoProjectChanged = "todo_project_changed"
    case todoBlockedAppsChanged = "todo_blocked_apps_changed"
    // Projects
    case projectCreated = "project_created"
    case projectRenamed = "project_renamed"
    case projectBlockedAppsChanged = "project_blocked_apps_changed"
    case projectDeleted = "project_deleted"
    case projectFinished = "project_finished"
    case projectReopened = "project_reopened"
    case projectStyleChanged = "project_style_changed"
    case projectGoalChanged = "project_goal_changed"
    case focusProjectSelected = "focus_project_selected"
    case sessionProjectChanged = "session_project_changed"
    case projectOpened = "project_opened"
    // Automatic time tracking
    case trackingPermissionRequested = "tracking_permission_requested"
    case trackingRuleAdded = "tracking_rule_added"
    case trackingRuleRemoved = "tracking_rule_removed"
    case trackedBlockAssigned = "tracked_block_assigned"
    case trackedDataDeleted = "tracked_data_deleted"
    // Links and Claude
    case appLinkOpened = "app_link_opened"
    // Settings & blocking
    case settingChanged = "setting_changed"
    case blockedAppAdded = "blocked_app_added"
    case blockedAppRemoved = "blocked_app_removed"
    case blockedDomainAdded = "blocked_domain_added"
    case blockedDomainRemoved = "blocked_domain_removed"
    case addDomainOpened = "add_domain_opened"
    case addDomainCancelled = "add_domain_cancelled"
    case addDomainInvalid = "add_domain_invalid"
    case helperInstalled = "helper_installed"
    case helperUninstalled = "helper_uninstalled"
    case staleBlockRemoved = "stale_block_removed"
    // AI
    case aiRequest = "ai_request"
    case aiBatchFinished = "ai_batch_finished"
    case ollamaStarted = "ollama_started"
    case modelPullStarted = "model_pull_started"
    case modelPullFinished = "model_pull_finished"
    case appCrashed = "app_crashed"
}

struct AnalyticsEvent: Codable {
    var id = UUID()
    let name: AnalyticsEventName
    var timestamp = Date()
    /// One app launch; groups the events of a session.
    let sessionID: UUID
    /// Stable per installation, anonymous.
    let installID: UUID
    let appVersion: String
    var properties: AnalyticsProperties
    /// Personal text such as notes, todo titles or domains. Stays on this Mac: sinks that send events
    /// elsewhere must drop it.
    var content: [String: String]?
}

/// A destination for events: the local log file now, later e.g. Firebase.
protocol AnalyticsSink: AnyObject {
    func record(_ event: AnalyticsEvent)
    /// Called on quit, so buffered events can be written.
    func flush()
}

/// Appends events as JSON lines to one file per day in `Logs/` of the app's storage folder.
///
/// Finished days are gzipped. The folder stays small through three limits: files older than
/// `retentionDays` are deleted, one day stops growing at `maxDayBytes`, and the oldest days are deleted
/// once all files together exceed `maxTotalBytes`. This runs on launch and at every day change.
final class LocalFileSink: AnalyticsSink {
    static let directory = Storage.directory.appendingPathComponent("Logs", isDirectory: true)
    static let retentionDays = 180
    static let maxDayBytes: Int64 = 10 * 1_024 * 1_024
    static let maxTotalBytes: Int64 = 50 * 1_024 * 1_024

    private let queue = DispatchQueue(label: "FocusFlow.analytics")
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return e
    }()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    // Only touched on `queue`.
    private var currentDay: String?
    private var currentDayBytes: Int64 = 0

    init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
    }

    func record(_ event: AnalyticsEvent) {
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)
        let day = dayFormatter.string(from: event.timestamp)
        queue.async { [self] in
            let url = Self.directory.appendingPathComponent("events-\(day).jsonl")
            if day != currentDay {
                currentDay = day
                currentDayBytes = Self.size(of: url)
                Self.maintain(keeping: url)
            }
            guard currentDayBytes + Int64(line.count) <= Self.maxDayBytes else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: url)
            }
            currentDayBytes += Int64(line.count)
        }
    }

    func flush() {
        queue.sync {}
    }

    /// Daily log files, oldest first: `events-YYYY-MM-DD.jsonl`, or `.jsonl.gz` once the day is over.
    static var files: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("events-") && ($0.pathExtension == "jsonl" || $0.lastPathComponent.hasSuffix(".jsonl.gz")) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static var totalSize: Int64 {
        files.reduce(0) { $0 + size(of: $1) }
    }

    static func deleteAll() {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// Compresses finished days, then applies the age and total size limits. `current` is today's file.
    private static func maintain(keeping current: URL) {
        for url in files where url.pathExtension == "jsonl" && url != current {
            gzip(url)
        }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        var remaining = files
        for url in remaining {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff, url != current { try? FileManager.default.removeItem(at: url) }
        }
        remaining = files.filter { $0 != current }
        var total = totalSize
        while total > maxTotalBytes, let oldest = remaining.first {
            total -= size(of: oldest)
            try? FileManager.default.removeItem(at: oldest)
            remaining.removeFirst()
        }
    }

    /// Replaces `url` with `url.gz`, readable with `zcat` or `gzip -d`.
    private static func gzip(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-f", "-9", url.path]
        try? process.run()
        process.waitUntilExit()
    }
}

struct AnalyticsSettings: Codable {
    var enabled = true
    var installID = UUID()
    var telemetryEnabled = false
    var telemetryID = UUID()
    var telemetrySessionID = UUID()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        installID = try c.decodeIfPresent(UUID.self, forKey: .installID) ?? UUID()
        telemetryEnabled = try c.decodeIfPresent(Bool.self, forKey: .telemetryEnabled) ?? false
        telemetryID = try c.decodeIfPresent(UUID.self, forKey: .telemetryID) ?? UUID()
        telemetrySessionID = try c.decodeIfPresent(UUID.self, forKey: .telemetrySessionID) ?? UUID()
    }
}

/// Records what the user does, for improving the app with real usage data.
///
/// Call `Analytics.track` from anywhere on the main actor. To send events to a backend later, implement
/// `AnalyticsSink` (dropping `content`, and asking the user first) and add it in `Analytics.sinks`.
@MainActor
enum Analytics {
    static var settings: AnalyticsSettings = {
        if let saved = Storage.load(AnalyticsSettings.self, from: "analytics.json") { return saved }
        // Save right away so the install ID stays the same across launches.
        let fresh = AnalyticsSettings()
        Storage.save(fresh, to: "analytics.json")
        return fresh
    }() {
        didSet { Storage.save(settings, to: "analytics.json") }
    }
    static var sinks: [AnalyticsSink] = [LocalFileSink()]
    static let sessionID = UUID()
    /// Set by `start()`; static properties are created lazily on first use.
    private(set) static var launchedAt = Date()

    static func start() {
        launchedAt = Date()
        if settings.telemetryEnabled, let remote = PostHogAnalyticsSink() {
            sinks.append(remote)
        }
    }
    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    static func track(_ name: AnalyticsEventName, _ properties: AnalyticsProperties = [:], content: [String: String]? = nil) {
        guard settings.enabled else { return }
        let safeProperties = sanitize(name, properties)
        let event = AnalyticsEvent(name: name, sessionID: sessionID, installID: settings.installID,
                                   appVersion: appVersion, properties: safeProperties, content: content)
        sinks.forEach { $0.record(event) }
    }

    /// Remote sinks receive only this explicit, reviewed contract; local logs retain their detail.
    static func sanitize(_ name: AnalyticsEventName, _ properties: AnalyticsProperties) -> AnalyticsProperties {
        let allowed = RemoteTelemetry.allowlist[name] ?? []
        return properties.filter { key, value in
            guard allowed.contains(key) else { return false }
            switch value {
            case .int, .double, .bool: return true
            case .string(let value): return RemoteTelemetry.allowedStringValues[key]?.contains(value) == true
            }
        }
    }

    static func flush() {
        sinks.forEach { $0.flush() }
    }

    static func resetTelemetryIdentity() {
        settings.telemetryID = UUID()
        settings.telemetrySessionID = UUID()
        sinks.compactMap { $0 as? PostHogAnalyticsSink }.forEach { $0.reset() }
    }

    static func setTelemetryEnabled(_ enabled: Bool) {
        settings.telemetryEnabled = enabled
        if enabled {
            if !sinks.contains(where: { $0 is PostHogAnalyticsSink }), let remote = PostHogAnalyticsSink() { sinks.append(remote) }
        } else {
            sinks.compactMap { $0 as? PostHogAnalyticsSink }.forEach { $0.reset() }
        }
    }

    // MARK: - Settings changes

    private static var pendingChanges: [String: (old: AnalyticsValue, new: AnalyticsValue)] = [:]
    private static var pendingFlush: Task<Void, Never>?

    /// Logs every field that differs between two settings values as `setting_changed`. Changes to one
    /// field within a second are merged, so typing "50" logs one change instead of "5" and "50".
    static func trackChanges<T>(in scope: String, from old: T, to new: T) {
        let oldFields = Dictionary(Mirror(reflecting: old).children.compactMap { c in c.label.map { ($0, c.value) } },
                                   uniquingKeysWith: { a, _ in a })
        for child in Mirror(reflecting: new).children {
            guard let label = child.label, let before = oldFields[label].flatMap(AnalyticsValue.init),
                  let after = AnalyticsValue(child.value), before != after else { continue }
            let key = "\(scope).\(snakeCase(label))"
            pendingChanges[key] = (pendingChanges[key]?.old ?? before, after)
        }
        pendingFlush?.cancel()
        pendingFlush = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            flushChanges()
        }
    }

    static func flushChanges() {
        for (key, change) in pendingChanges.sorted(by: { $0.key < $1.key }) where change.old != change.new {
            track(.settingChanged, ["setting": .string(key), "old_value": change.old, "new_value": change.new])
        }
        pendingChanges = [:]
    }

    private static func snakeCase(_ name: String) -> String {
        name.reduce(into: "") { result, c in
            if c.isUppercase { result += "_" + c.lowercased() } else { result.append(c) }
        }
    }
}
