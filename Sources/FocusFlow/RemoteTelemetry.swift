import Foundation

/// What may leave the Mac: per event, the properties and their kinds. Everything else is dropped.
///
/// There is no `default`, so a new event does not compile until someone decides what it may send.
enum RemoteContract {
    enum Kind {
        case int, signedInt, bool, intOrBool
        case oneOf(Set<String>)
        case frames
    }

    private static let phases: Set<String> = ["idle", "focus", "shortBreak", "longBreak"]
    private static let sections = Set(DashboardSection.allCases.map(\.rawValue))
    private static let providers = Set(AIProvider.allCases.map(\.rawValue))
    private static let ruleKinds = Set(TrackingRule.Kind.allCases.map(\.rawValue))
    private static let via: Set<String> = ["hotkey", "escape"]
    private static let sources: Set<String> = [
        "auto", "break_panel", "break_suggestion", "button", "card", "dashboard", "enter", "hotkey", "link", "menu", "menu_streak",
        "project_card", "project_page", "project_task", "projects", "quick_capture", "sidebar", "timer_entry",
    ]
    private static let settings: Set<String> = [
        "logging.enabled", "mcp.config_copied",
        "focus.language", "focus.focus_minutes", "focus.short_break_minutes", "focus.long_break_minutes",
        "focus.sessions_until_long_break", "focus.auto_start_focus", "focus.daily_goal_minutes", "focus.block_domains",
        "ai.provider", "ai.start_ollama",
        "tracking.enabled", "tracking.window_titles", "tracking.browser_addresses", "tracking.idle_minutes",
        "tracking.side_window", "tracking.detect_from_text",
    ]

    static func properties(of name: AnalyticsEventName) -> [String: Kind] {
        switch name {
        case .menuOpened, .breakPanelClosed, .timerEntryOpened:
            ["phase": .oneOf(phases)]
        case .dashboardOpened:
            ["section": .oneOf(sections), "source": .oneOf(sources), "was_open": .bool]
        case .dashboardSectionViewed:
            ["section": .oneOf(sections)]
        case .settingsTabViewed:
            ["tab": .oneOf(["timer", "blocking", "general", "ai", "tracking"])]
        case .statsRangeChanged:
            ["days": .int]
        case .appLaunched:
            ["open_todos": .int, "focus_minutes": .int, "blocked_apps": .int, "blocked_domains": .int,
             "ai_provider": .oneOf(providers), "tracking_enabled": .bool]
        case .appQuit:
            ["session_seconds": .int]
        case .focusStarted, .breakStarted:
            ["phase": .oneOf(phases), "planned_minutes": .int, "round": .int, "source": .oneOf(sources)]
        case .focusEnded, .breakEnded:
            ["phase": .oneOf(phases), "reason": .oneOf(["completed", "stopped", "skipped", "quit"]), "completed": .bool,
             "planned_seconds": .int, "elapsed_seconds": .int, "wall_seconds": .int]
        case .timerPaused:
            ["phase": .oneOf(phases), "remaining_seconds": .int]
        case .timerResumed:
            ["phase": .oneOf(phases), "paused_seconds": .int]
        case .timerEntryCancelled, .quickCaptureCancelled:
            ["via": .oneOf(via)]
        case .quickCaptureOpened, .projectOpened, .todoCompleted, .todoReopened, .todoDeleted:
            ["source": .oneOf(sources)]
        case .focusTaskSelected:
            ["has_project": .bool]
        case .noteCaptured:
            ["source": .oneOf(sources), "length": .int, "open_todos": .int]
        case .noteRefined:
            ["used_ai": .bool, "duration_ms": .int, "waited_seconds": .int, "todo_count": .int]
        case .todoEstimateChanged:
            ["method": .oneOf(["menu", "typed"]), "old_minutes": .int, "new_minutes": .int]
        case .todosCleared:
            ["count": .int, "source": .oneOf(sources)]
        case .todoListFilterChanged:
            ["filter": .oneOf(["done", "open"])]
        case .suggestionShown:
            ["estimated_minutes": .int, "available_minutes": .int]
        case .taskAdded:
            ["estimated_minutes": .int, "source": .oneOf(sources)]
        case .todoBlockedAppsChanged, .projectBlockedAppsChanged:
            ["custom": .bool]
        case .projectCreated, .projectDeleted, .blockedDomainAdded, .blockedDomainRemoved:
            ["count": .int]
        case .projectStyleChanged:
            ["color_index": .int]
        case .projectGoalChanged, .sessionProjectChanged, .trackedBlockAssigned:
            ["minutes": .int]
        case .trackingPermissionRequested:
            ["permission": .oneOf(["accessibility"]), "granted": .bool]
        case .trackingRuleAdded:
            ["kind": .oneOf(ruleKinds), "count": .int]
        case .trackingRuleRemoved:
            ["kind": .oneOf(ruleKinds)]
        case .appLinkOpened:
            // The command is the host of a link and can be any text.
            ["command": .oneOf(["focus", "add-todo", "complete", "quit"]), "trusted": .bool, "handled": .bool]
        case .settingChanged:
            ["setting": .oneOf(settings), "old_value": .intOrBool, "new_value": .intOrBool]
        case .addDomainCancelled:
            ["had_text": .bool]
        case .helperInstalled, .helperUninstalled, .staleBlockRemoved:
            ["success": .bool]
        case .aiRequest:
            ["provider": .oneOf(providers), "success": .bool, "duration_ms": .int]
        case .aiBatchFinished:
            ["trigger": .oneOf(["calm_window", "deadline", "waited"]), "jobs": .int, "duration_ms": .int]
        case .ollamaStarted:
            ["success": .bool, "duration_ms": .int]
        case .modelPullFinished:
            ["success": .bool, "duration_seconds": .int]
        case .appCrashed:
            ["exception_type": .signedInt, "exception_code": .signedInt, "signal": .signedInt, "crash_build": .int,
             "frames": .frames]
        case .dashboardClosed, .focusDurationInvalid, .focusProjectSelected, .todoTitleChanged, .suggestionSkipped,
             .todoProjectChanged, .projectRenamed, .projectFinished, .projectReopened, .trackedDataDeleted,
             .appBlocked, .blockedAppAdded, .blockedAppRemoved, .addDomainOpened, .addDomainInvalid, .modelPullStarted:
            [:]
        }
    }

    static func sanitize(_ name: AnalyticsEventName, _ values: AnalyticsProperties) -> AnalyticsProperties {
        let allowed = properties(of: name)
        return values.reduce(into: [:]) { result, entry in
            guard let kind = allowed[entry.key] else { return }
            switch (kind, entry.value) {
            case (.int, .int(let v)), (.intOrBool, .int(let v)): result[entry.key] = .int(min(max(v, 0), 1_000_000))
            case (.signedInt, .int), (.bool, .bool), (.intOrBool, .bool): result[entry.key] = entry.value
            case (.oneOf(let set), .string(let v)) where set.contains(v): result[entry.key] = entry.value
            case (.frames, .string(let v)) where CrashFrames.isValid(v): result[entry.key] = entry.value
            default: break
            }
        }
    }
}

enum TelemetryResult { case success, retry, drop }

/// Sends one HTTP body. The completion may run on any thread.
protocol TelemetryTransport: AnyObject {
    func send(_ body: Data, completion: @escaping @Sendable (TelemetryResult) -> Void)
    func cancel()
}

final class PostHogTransport: TelemetryTransport {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    func send(_ body: Data, completion: @escaping @Sendable (TelemetryResult) -> Void) {
        var request = URLRequest(url: URL(string: "https://eu.i.posthog.com/batch/")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The default would name the exact system build.
        request.setValue("FocusFlow", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        session.dataTask(with: request) { _, response, _ in
            completion(Self.result(status: (response as? HTTPURLResponse)?.statusCode))
        }.resume()
    }

    func cancel() {
        session.getAllTasks { $0.forEach { $0.cancel() } }
    }

    /// A body the server refuses would be refused again, so only temporary errors are retried.
    static func result(status: Int?) -> TelemetryResult {
        switch status {
        case .some(200..<300): .success
        case .some(400..<500) where status != 429 && status != 408: .drop
        default: .retry
        }
    }
}

/// Sends allowed events to PostHog EU while the user agreed to it. Separate from the local log.
@MainActor
final class RemoteTelemetry {
    /// Raise this when more data is sent than PRIVACY.md said before: everyone is asked again, and nothing is sent until then.
    static let policyVersion = 1
    static let maxQueued = 500
    static let batchSize = 100

    static var bundledKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "FocusFlowPostHogKey") as? String, !key.isEmpty else { return nil }
        return key
    }

    static var defaultQueueURL: URL { Storage.directory.appendingPathComponent("telemetry-queue.json") }

    static func shouldAsk(hasKey: Bool, answeredPolicy: Int, phase: Phase) -> Bool {
        hasKey && answeredPolicy < policyVersion && phase == .idle
    }

    struct Item: Codable, Equatable {
        var uuid = UUID()
        let event: String
        /// Minutes since 1970.
        let minute: Int
        let session: UUID
        let version: String
        let language: String
        var properties: AnalyticsProperties
    }

    private(set) var queue: [Item] = []
    private let key: String
    private let transport: TelemetryTransport
    private let queueURL: URL
    private let clock: () -> Date
    private let isAllowed: () -> Bool
    private let telemetryID: () -> UUID
    private var session = UUID()
    private var sending = false
    private var nextAttempt = Date.distantPast
    private var retryDelay: TimeInterval = 30
    /// Changes when the queue is cleared, so a request still under way cannot touch the new one.
    private var generation = 0
    private var timer: Timer?

    init(key: String, transport: TelemetryTransport, queueURL: URL, clock: @escaping () -> Date = Date.init,
         isAllowed: @escaping () -> Bool, telemetryID: @escaping () -> UUID) {
        self.key = key
        self.transport = transport
        self.queueURL = queueURL
        self.clock = clock
        self.isAllowed = isAllowed
        self.telemetryID = telemetryID
        if isAllowed() {
            load()
        } else {
            clear()
        }
    }

    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    func record(_ name: AnalyticsEventName, _ properties: AnalyticsProperties) {
        guard isAllowed() else { return }
        queue.append(Item(event: name.rawValue, minute: Int((clock().timeIntervalSince1970 / 60).rounded(.down)),
                          session: session, version: Self.safeVersion(Analytics.appVersion), language: L10n.language.rawValue,
                          properties: RemoteContract.sanitize(name, properties)))
        queue = Array(queue.suffix(Self.maxQueued))
        save()
    }

    func flush() {
        guard let (items, body) = nextBatch() else { return }
        sending = true
        let generation = generation
        transport.send(body) { [weak self] result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finish(items, result, generation) }
            }
        }
    }

    /// On quit: sends one batch and waits briefly. What does not make it is sent after the next launch.
    func flushOnQuit(timeout: TimeInterval = 1) {
        guard let (items, body) = nextBatch() else { return }
        final class Box: @unchecked Sendable { var result = TelemetryResult.retry }
        let box = Box(), done = DispatchSemaphore(value: 0)
        transport.send(body) { box.result = $0; done.signal() }
        if done.wait(timeout: .now() + timeout) == .success { finish(items, box.result, generation) }
    }

    /// Drops everything not sent yet and stops requests under way.
    func clear() {
        generation += 1
        transport.cancel()
        queue = []
        sending = false
        nextAttempt = .distantPast
        retryDelay = 30
        session = UUID()
        try? FileManager.default.removeItem(at: queueURL)
    }

    private func nextBatch() -> (items: [Item], body: Data)? {
        guard isAllowed(), !sending, !queue.isEmpty, clock() >= nextAttempt else { return nil }
        let items = Array(queue.prefix(Self.batchSize))
        guard let body = try? JSONSerialization.data(withJSONObject: ["api_key": key, "batch": items.map(payload)]) else { return nil }
        return (items, body)
    }

    private func finish(_ items: [Item], _ result: TelemetryResult, _ generation: Int) {
        guard generation == self.generation else { return }
        sending = false
        if result == .retry {
            nextAttempt = clock().addingTimeInterval(retryDelay)
            retryDelay = min(retryDelay * 2, 3600)
            return
        }
        let sent = Set(items.map(\.uuid))
        queue.removeAll { sent.contains($0.uuid) }
        retryDelay = 30
        save()
    }

    private func payload(_ item: Item) -> [String: Any] {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        var properties: [String: Any] = item.properties.mapValues { value -> Any in
            switch value {
            case .string(let v): v
            case .int(let v): v
            case .double(let v): v
            case .bool(let v): v
            }
        }
        properties["distinct_id"] = telemetryID().uuidString
        properties["$session_id"] = item.session.uuidString
        properties["$process_person_profile"] = false
        properties["$geoip_disable"] = true
        properties["app_version"] = item.version
        properties["macos_version"] = "\(system.majorVersion).\(system.minorVersion)"
        properties["arch"] = arch
        properties["language"] = item.language
        return ["event": item.event, "uuid": item.uuid.uuidString, "properties": properties,
                "timestamp": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(item.minute) * 60))]
    }

    /// Checks the file like new events: an older version may have allowed more.
    private func load() {
        let saved = (try? JSONDecoder().decode([Item].self, from: Data(contentsOf: queueURL))) ?? []
        queue = saved.suffix(Self.maxQueued).compactMap { item in
            guard let name = AnalyticsEventName(rawValue: item.event), AppLanguage(rawValue: item.language) != nil else { return nil }
            return Item(uuid: item.uuid, event: item.event, minute: item.minute, session: item.session,
                        version: Self.safeVersion(item.version), language: item.language,
                        properties: RemoteContract.sanitize(name, item.properties))
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueURL, options: .atomic)
    }

    private static func safeVersion(_ text: String) -> String {
        text.range(of: #"^[0-9]{1,4}(\.[0-9]{1,4}){1,2}\z"#, options: .regularExpression) != nil ? text : "dev"
    }
}
