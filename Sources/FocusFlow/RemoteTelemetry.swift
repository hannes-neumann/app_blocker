import Foundation

protocol TelemetryTransport: AnyObject {
    func send(_ data: Data, completion: @escaping (Bool) -> Void)
}

final class URLSessionTelemetryTransport: TelemetryTransport {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func send(_ data: Data, completion: @escaping (Bool) -> Void) {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "FocusFlowPostHogKey") as? String,
              !key.isEmpty else { completion(true); return }
        var request = URLRequest(url: URL(string: "https://eu.i.posthog.com/batch/")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        session.dataTask(with: request) { _, response, _ in
            completion((response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false)
        }.resume()
    }
}

final class PostHogAnalyticsSink: AnalyticsSink {
    private struct RemoteEvent: Codable {
        let event: String
        let properties: [String: AnyEncodable]
        let timestamp: Date
    }
    private struct Payload: Encodable {
        let api_key: String
        let batch: [RemoteEvent]
    }
    private let transport: TelemetryTransport
    private let key: String
    private let telemetryID: UUID
    private let language: String
    private let queueURL = Storage.directory.appendingPathComponent("telemetry-queue.json")
    private var events: [RemoteEvent] = []
    private var timer: Timer?

    @MainActor init?(transport: TelemetryTransport = URLSessionTelemetryTransport()) {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "FocusFlowPostHogKey") as? String, !key.isEmpty else { return nil }
        self.key = key
        self.telemetryID = Analytics.settings.telemetryID
        self.language = L10n.language.rawValue
        self.transport = transport
        events = (try? JSONDecoder().decode([RemoteEvent].self, from: Data(contentsOf: queueURL))) ?? []
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.flush() }
    }

    func record(_ event: AnalyticsEvent) {
        var properties: [String: AnyEncodable] = [
            "distinct_id": AnyEncodable(telemetryID.uuidString),
            "$process_person_profile": AnyEncodable(false),
            "$geoip_disable": AnyEncodable(true),
            "app_version": AnyEncodable(event.appVersion),
            "macos_version": AnyEncodable(ProcessInfo.processInfo.operatingSystemVersionString.split(separator: ".").prefix(2).joined(separator: ".")),
            "arch": AnyEncodable(ProcessInfo.processInfo.machineArchitecture),
            "language": AnyEncodable(language)
        ]
        event.properties.forEach { properties[$0.key] = AnyEncodable($0.value) }
        let date = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: event.timestamp)
        let timestamp = Calendar.current.date(from: date) ?? event.timestamp
        events.append(RemoteEvent(event: event.name.rawValue, properties: properties, timestamp: timestamp))
        events = Array(events.suffix(500))
        save()
    }

    func flush() {
        guard !events.isEmpty else { return }
        let sending = events
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Payload(api_key: key, batch: sending)) else { return }
        transport.send(data) { [weak self] success in
            guard success else { return }
            self?.events.removeFirst(min(sending.count, self?.events.count ?? 0))
            self?.save()
        }
    }

    func reset() {
        events = []
        try? FileManager.default.removeItem(at: queueURL)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: queueURL, options: .atomic)
    }
}

struct AnyEncodable: Codable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ value: Any) {
        encodeValue = { encoder in
            var container = encoder.singleValueContainer()
            switch value {
            case let v as String: try container.encode(v)
            case let v as Bool: try container.encode(v)
            case let v as Int: try container.encode(v)
            case let v as Double: try container.encode(v)
            case let v as AnalyticsValue: try v.encode(to: encoder)
            default: try container.encodeNil()
            }
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) { self.init(value); return }
        if let value = try? c.decode(Int.self) { self.init(value); return }
        if let value = try? c.decode(Double.self) { self.init(value); return }
        self.init(try c.decode(String.self))
    }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
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

/// The remote contract is deliberately closed: adding an event requires reviewing its data.
enum RemoteTelemetry {
    static let allowlist: [AnalyticsEventName: Set<String>] = {
        var all = Dictionary(uniqueKeysWithValues: AnalyticsEventName.allCases.map { ($0, Set<String>()) })
        let keys: [AnalyticsEventName: Set<String>] = [
            .appLaunched: ["open_todos", "focus_minutes", "blocked_apps", "blocked_domains", "tracking_enabled", "ai_provider"],
            .appQuit: ["session_seconds"], .dashboardOpened: ["section", "source", "was_open"],
            .dashboardSectionViewed: ["section"], .settingsTabViewed: ["tab"], .statsRangeChanged: ["days"],
            .focusStarted: ["phase", "source"], .focusEnded: ["phase", "reason", "duration_seconds"],
            .breakStarted: ["phase"], .breakEnded: ["phase"], .timerPaused: ["phase", "remaining_seconds"],
            .timerResumed: ["phase"], .focusDurationInvalid: [], .timerEntryOpened: ["phase"],
            .timerEntryCancelled: ["via"], .focusTaskSelected: ["has_project"], .appBlocked: [],
            .breakPanelClosed: ["phase"], .quickCaptureOpened: ["source"], .quickCaptureCancelled: ["via"],
            .noteCaptured: ["source"], .noteRefined: ["success"], .todoCompleted: ["source"],
            .todoReopened: ["source"], .todoEstimateChanged: ["estimate_minutes"], .todoTitleChanged: [],
            .todoDeleted: ["source"], .todosCleared: ["count", "source"], .todoListFilterChanged: ["filter"],
            .suggestionShown: [], .suggestionSkipped: [], .taskAdded: [], .todoProjectChanged: ["has_project"],
            .todoBlockedAppsChanged: ["custom"], .projectCreated: ["count"], .projectRenamed: [],
            .projectBlockedAppsChanged: ["custom"], .projectDeleted: ["count"], .projectFinished: [],
            .projectReopened: [], .projectStyleChanged: ["style"], .projectGoalChanged: ["minutes"],
            .focusProjectSelected: [], .sessionProjectChanged: ["has_project"], .projectOpened: ["source"],
            .trackingPermissionRequested: ["permission", "granted"], .trackingRuleAdded: ["kind"],
            .trackingRuleRemoved: ["kind"], .trackedBlockAssigned: ["matched"], .trackedDataDeleted: [],
            .appLinkOpened: ["command", "trusted", "handled"], .settingChanged: ["setting", "old_value", "new_value"],
            .blockedAppAdded: [], .blockedAppRemoved: [], .blockedDomainAdded: ["count"],
            .blockedDomainRemoved: ["count"], .addDomainOpened: [], .addDomainCancelled: ["had_text"],
            .addDomainInvalid: [], .helperInstalled: ["success"], .helperUninstalled: ["success"],
            .staleBlockRemoved: ["success"], .aiRequest: ["provider", "success"], .aiBatchFinished: ["trigger", "jobs", "failed"],
            .ollamaStarted: ["success"], .modelPullStarted: [], .modelPullFinished: ["success"]
            , .appCrashed: ["exception_type", "exception_code", "signal", "frames"]
        ]
        keys.forEach { all[$0.key] = $0.value }
        return all
    }()

    static let allowedStringValues: [String: Set<String>] = [
        "phase": ["idle", "focus", "shortBreak", "longBreak"], "source": ["button", "hotkey", "menu", "dashboard", "sidebar", "break_suggestion"],
        "via": ["hotkey", "escape"], "filter": ["done", "open"], "section": ["focus", "projects", "todos", "stats"],
        "style": ["default", "blue", "green", "orange", "purple", "pink"], "permission": ["accessibility"],
        "kind": ["app", "domain", "title", "learned"], "provider": ["apple", "ollama", "none"],
        "trigger": ["focus", "break", "manual"], "setting": ["logging.enabled"]
    ]
}

