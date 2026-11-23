import Foundation

enum TelemetryResult { case success, retry, drop }
protocol TelemetryTransport: AnyObject {
    func send(_ data: Data, completion: @escaping (TelemetryResult) -> Void)
}

final class URLSessionTelemetryTransport: TelemetryTransport {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func send(_ data: Data, completion: @escaping (TelemetryResult) -> Void) {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "FocusFlowPostHogKey") as? String,
              !key.isEmpty else { completion(.drop); return }
        var request = URLRequest(url: URL(string: "https://eu.i.posthog.com/batch/")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        session.dataTask(with: request) { _, response, _ in
            guard let status = (response as? HTTPURLResponse)?.statusCode else { completion(.retry); return }
            if (200..<300).contains(status) { completion(.success) }
            else if status == 429 || status >= 500 { completion(.retry) }
            else { completion(.drop) }
        }.resume()
    }
}

@MainActor final class PostHogAnalyticsSink: AnalyticsSink {
    private struct RemoteEvent: Codable {
        let event: String
        let properties: [String: RemoteValue]
        let timestamp: Date
        let uuid: UUID
    }
    private struct Payload: Encodable {
        let api_key: String
        let batch: [RemoteEvent]
    }
    private let transport: TelemetryTransport
    private let key: String
    private var telemetryID: UUID
    private var sessionID = UUID()
    private let queueURL: URL
    private var events: [RemoteEvent] = []
    private var timer: Timer?
    private var inFlight = false
    private var nextAttempt: Date = .distantPast
    private var retryDelay: TimeInterval = 30
    private var clock: () -> Date

    init?(key: String? = nil, transport: TelemetryTransport = URLSessionTelemetryTransport(),
          queueURL: URL = Storage.directory.appendingPathComponent("telemetry-queue.json"),
          clock: @escaping () -> Date = Date.init) {
        let resolvedKey = key ?? (Bundle.main.object(forInfoDictionaryKey: "FocusFlowPostHogKey") as? String)
        guard let resolvedKey, !resolvedKey.isEmpty else { return nil }
        self.key = resolvedKey
        self.telemetryID = Analytics.settings.telemetryID
        self.queueURL = queueURL
        self.transport = transport
        self.clock = clock
        events = (try? JSONDecoder().decode([RemoteEvent].self, from: Data(contentsOf: queueURL))) ?? []
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.flush() }
    }

    func record(_ event: AnalyticsEvent) {
        guard Analytics.settings.telemetryEnabled else { return }
        let language = L10n.language.rawValue
        var properties: [String: RemoteValue] = [
            "distinct_id": .string(telemetryID.uuidString),
            "$session_id": .string(sessionID.uuidString),
            "$process_person_profile": .bool(false),
            "$geoip_disable": .bool(true),
            "app_version": .string(event.appVersion),
            "macos_version": .string("\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)"),
            "arch": .string(ProcessInfo.processInfo.machineArchitecture),
            "language": .string(language)
        ]
        Analytics.sanitize(event.name, event.properties).forEach { properties[$0.key] = RemoteValue($0.value) }
        let date = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: event.timestamp)
        let timestamp = Calendar.current.date(from: date) ?? event.timestamp
        events.append(RemoteEvent(event: event.name.rawValue, properties: properties, timestamp: timestamp, uuid: event.id))
        events = Array(events.suffix(500))
        save()
    }

    func flush() {
        guard Analytics.settings.telemetryEnabled, !inFlight, !events.isEmpty,
              clock() >= nextAttempt else { return }
        inFlight = true
        let sending = Array(events.prefix(100))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Payload(api_key: key, batch: sending)) else { return }
        transport.send(data) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.inFlight = false
                guard Analytics.settings.telemetryEnabled else { return }
                if result == .success || result == .drop {
                    let sent = Set(sending.map(\.uuid))
                    self.events.removeAll { sent.contains($0.uuid) }
                    self.retryDelay = 30
                    self.save()
                } else {
                    self.nextAttempt = self.clock().addingTimeInterval(self.retryDelay)
                    self.retryDelay = min(self.retryDelay * 2, 3600)
                }
            }
        }
    }

    func reset() {
        events = []
        inFlight = false
        try? FileManager.default.removeItem(at: queueURL)
    }

    func resetIdentity() {
        telemetryID = Analytics.settings.telemetryID
        sessionID = UUID()
    }

    func disable() {
        reset()
        timer?.invalidate()
        timer = nil
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: queueURL, options: .atomic)
    }
}

enum RemoteValue: Codable, Equatable {
    case string(String), int(Int), double(Double), bool(Bool)
    init(_ value: AnalyticsValue) {
        switch value {
        case .string(let value): self = .string(value)
        case .int(let value): self = .int(value)
        case .double(let value): self = .double(value)
        case .bool(let value): self = .bool(value)
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .int(let value): try c.encode(value)
        case .double(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Int.self) { self = .int(value) }
        else if let value = try? c.decode(Double.self) { self = .double(value) }
        else { self = .string(try c.decode(String.self)) }
    }
}

private extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}

enum RemoteTelemetry {
    enum Kind: Equatable {
        case int, bool, intOrBool, oneOf(Set<String>)
    }

    static func allowlist(_ name: AnalyticsEventName) -> [String: Kind]? {
        let phases = Set(["idle", "focus", "shortBreak", "longBreak"])
        let sources = Set(["hotkey", "escape", "button", "menu", "dashboard", "sidebar", "card", "break_suggestion"])
        let sections = Set(["focus", "projects", "todos", "stats"])
        let via = Set(["hotkey", "escape"])
        let reasons = Set(["completed", "stopped", "skipped", "quit"])
        let providers = Set(["automatic", "ollama", "off"])
        let kinds = Set(["app", "domain", "title", "learned"])
        switch name {
        case .menuOpened, .breakPanelClosed, .timerEntryOpened: return ["phase": .oneOf(phases)]
        case .dashboardOpened: return ["section": .oneOf(sections), "source": .oneOf(sources), "was_open": .bool]
        case .dashboardSectionViewed: return ["section": .oneOf(sections)]
        case .settingsTabViewed: return ["tab": .oneOf(Set(["timer", "blocking", "general", "ai", "tracking"]))]
        case .statsRangeChanged: return ["days": .int]
        case .dashboardClosed: return [:]
        case .appLaunched: return ["open_todos": .int, "focus_minutes": .int, "blocked_apps": .int, "blocked_domains": .int, "ai_provider": .oneOf(providers), "tracking_enabled": .bool]
        case .appQuit: return ["session_seconds": .int]
        case .focusStarted, .breakStarted: return ["phase": .oneOf(phases), "planned_minutes": .int, "round": .int, "source": .oneOf(sources)]
        case .focusEnded, .breakEnded: return ["phase": .oneOf(phases), "reason": .oneOf(reasons), "completed": .bool, "planned_seconds": .int, "elapsed_seconds": .int, "wall_seconds": .int]
        case .timerPaused: return ["phase": .oneOf(phases), "remaining_seconds": .int]
        case .timerResumed: return ["phase": .oneOf(phases), "paused_seconds": .int]
        case .timerEntryCancelled, .quickCaptureCancelled: return ["via": .oneOf(via)]
        case .quickCaptureOpened: return ["source": .oneOf(sources)]
        case .focusDurationInvalid, .focusProjectSelected, .appBlocked, .todoTitleChanged,
             .suggestionSkipped, .projectRenamed, .projectFinished, .projectReopened, .trackedDataDeleted,
             .blockedAppAdded, .blockedAppRemoved, .addDomainOpened, .addDomainInvalid, .modelPullStarted: return [:]
        case .focusTaskSelected: return ["has_project": .bool]
        case .noteCaptured: return ["source": .oneOf(sources), "length": .int, "open_todos": .int]
        case .noteRefined: return ["used_ai": .bool, "duration_ms": .int, "waited_seconds": .int, "todo_count": .int]
        case .todoCompleted, .todoReopened, .todoDeleted: return ["source": .oneOf(sources)]
        case .todoEstimateChanged: return ["method": .oneOf(Set(["manual", "ai"])), "old_minutes": .int, "new_minutes": .int]
        case .todosCleared: return ["count": .int, "source": .oneOf(sources)]
        case .todoListFilterChanged: return ["filter": .oneOf(Set(["done", "open"]))]
        case .suggestionShown: return ["estimated_minutes": .int, "available_minutes": .int]
        case .taskAdded: return ["estimated_minutes": .int, "source": .oneOf(sources)]
        case .todoProjectChanged: return [:]
        case .todoBlockedAppsChanged, .projectBlockedAppsChanged: return ["custom": .bool]
        case .projectCreated, .projectDeleted: return ["count": .int]
        case .projectStyleChanged: return ["color_index": .int]
        case .projectGoalChanged: return ["minutes": .int]
        case .sessionProjectChanged: return ["minutes": .int]
        case .projectOpened: return ["source": .oneOf(sources)]
        case .trackingPermissionRequested: return ["permission": .oneOf(Set(["accessibility"])), "granted": .bool]
        case .trackingRuleAdded: return ["kind": .oneOf(kinds), "count": .int]
        case .trackingRuleRemoved: return ["kind": .oneOf(kinds)]
        case .trackedBlockAssigned: return ["minutes": .int, "old_assignment": .bool]
        case .appLinkOpened: return ["command": .oneOf(Set(["focus", "add-todo", "complete", "quit"])), "trusted": .bool, "handled": .bool]
        case .settingChanged: return ["setting": .oneOf(Set(["logging.enabled", "mcp.config_copied", "focus.focus_minutes", "focus.short_break_minutes", "focus.long_break_minutes", "focus.sessions_until_long_break", "focus.auto_start_focus", "focus.daily_goal_minutes", "ai.provider", "ai.start_ollama", "tracking.enabled"])), "old_value": .intOrBool, "new_value": .intOrBool]
        case .blockedDomainAdded, .blockedDomainRemoved: return ["count": .int]
        case .addDomainCancelled: return ["had_text": .bool]
        case .helperInstalled, .helperUninstalled, .staleBlockRemoved: return ["success": .bool]
        case .aiRequest: return ["provider": .oneOf(providers), "success": .bool, "duration_ms": .int]
        case .aiBatchFinished: return ["trigger": .oneOf(Set(["manual", "focus", "break"])), "jobs": .int, "duration_ms": .int]
        case .ollamaStarted: return ["success": .bool, "duration_ms": .int]
        case .modelPullFinished: return ["success": .bool, "duration_seconds": .int]
        case .appCrashed: return ["exception_type": .int, "exception_code": .int, "signal": .int, "frames": .oneOf(Set())]
        }
    }
}

