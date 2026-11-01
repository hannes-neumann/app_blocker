import AppKit
import Carbon
import Observation

@MainActor @Observable
final class AppState {
    var settings: FocusSettings = Storage.load(FocusSettings.self, from: "settings.json") ?? FocusSettings() {
        didSet {
            Storage.save(settings, to: "settings.json")
            L10n.language = settings.language
            trackSettingsChange(from: oldValue)
            syncDomains()
            if phase == .focus && settings != oldValue { applyBlocking(true) }
        }
    }
    let todos = TodoStore()
    let projects = ProjectStore()
    let stats = StatsStore()
    let ai = AIEngine()

    private(set) var phase: Phase = .idle
    private(set) var remaining: TimeInterval = 0
    private(set) var phaseDuration: TimeInterval = 1
    private(set) var isPaused = false
    private(set) var completedFocusSessions = 0
    private(set) var suggestion: Todo?
    private(set) var domainBlockError: String?
    private(set) var hasStaleHostsBlock = false
    private(set) var isHelperInstalled = false
    var dashboardSection: DashboardSection = .focus {
        didSet { if dashboardSection != oldValue { Analytics.track(.dashboardSectionViewed, ["section": .string(dashboardSection.rawValue)]) } }
    }
    var selectedTaskID: UUID? {
        didSet {
            guard selectedTaskID != oldValue else { return }
            Analytics.track(.focusTaskSelected, ["todo_id": .string(selectedTaskID?.uuidString ?? ""),
                                                 "has_project": .bool(selectedTask?.projectID != nil)])
        }
    }

    var selectedTask: Todo? {
        guard let selectedTaskID else { return nil }
        return todos.todos.first { $0.id == selectedTaskID }
    }

    var selectedProject: Project? {
        projects.project(selectedTask?.projectID)
    }

    var activeBlockedApps: [BlockedApp] {
        if let taskApps = selectedTask?.blockedApps { return taskApps }
        if let projectApps = selectedProject?.blockedApps { return projectApps }
        return settings.blockedApps
    }

    static let shortcutDescription = "⌃⌥N"
    static let timerShortcutDescription = "⌃⌥T"

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var focusStartedAt: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var skippedSuggestions: Set<UUID> = []
    @ObservationIgnored private var askedForHelper = false
    @ObservationIgnored private var phaseStartedAt: Date?
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private let appBlocker = AppBlocker()
    @ObservationIgnored private let domainBlocker = DomainBlocker()
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var timerHotKey: HotKey?
    @ObservationIgnored private(set) var panels: PanelController!

    var remainingText: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var progress: Double { phase == .idle ? 0 : 1 - remaining / phaseDuration }

    var cycleText: String {
        let n = max(settings.sessionsUntilLongBreak, 1)
        // During a break the round that just ended counts; otherwise the one that is running or next.
        let round = phase.isBreak ? (completedFocusSessions - 1) % n + 1 : completedFocusSessions % n + 1
        return "Runde \(round) von \(n)"
    }

    func setup() {
        L10n.language = settings.language
        panels = PanelController(state: self)
        ai.refreshStatus()
        todos.refiner = { [ai] note in await ai.refine(note) }
        Analytics.start()
        Analytics.track(.appLaunched, [
            "os_version": .string(ProcessInfo.processInfo.operatingSystemVersionString),
            "open_todos": .int(todos.open.count),
            "focus_minutes": .int(settings.focusMinutes),
            "blocked_apps": .int(settings.blockedApps.count),
            "blocked_domains": .int(settings.blockDomains ? settings.blockedDomains.count : 0),
            "ai_provider": .string(ai.settings.provider.rawValue),
        ])
        refreshHelperStatus()
        syncDomains()
        domainBlocker.setBlocking(false)
        appBlocker.onBlocked = { [weak self] name, bundleID in
            self?.panels.showBlockedHUD(appName: name)
            Analytics.track(.appBlocked, ["bundle_id": .string(bundleID), "app_name": .string(name)])
        }
        todos.onCompletionChange = { [weak self] todo in self?.stats.todoChanged(todo) }
        hotKey = HotKey(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey) { [weak self] in
            self?.showQuickCapture(source: "hotkey")
        }
        timerHotKey = HotKey(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [weak self] in
            self?.showTimerEntry()
        }
        todos.resumePendingRefinements()
    }

    func shutdown() {
        endPhase(reason: "quit")
        Analytics.flushChanges()
        Analytics.track(.appQuit, ["session_seconds": .int(Int(Date().timeIntervalSince(Analytics.launchedAt)))])
        Analytics.flush()
        appBlocker.stop()
        domainBlocker.setBlocking(false)
        ai.shutdown()
    }

    // MARK: - Timer

    func startFocus(source: String = "button") { begin(.focus, source: source) }

    func startFocus(minutes: Int) {
        guard phase == .idle, minutes > 0 else { return }
        begin(.focus, durationMinutes: minutes, source: "timer_entry")
    }

    func togglePause() {
        guard phase != .idle else { return }
        if isPaused {
            endDate = Date().addingTimeInterval(remaining)
            isPaused = false
            Analytics.track(.timerResumed, ["phase": .string(phase.rawValue),
                                            "paused_seconds": .int(Int(Date().timeIntervalSince(pausedAt ?? Date())))])
        } else {
            tick()
            isPaused = true
            pausedAt = Date()
            Analytics.track(.timerPaused, ["phase": .string(phase.rawValue), "remaining_seconds": .int(Int(remaining))])
        }
    }

    func skipPhase() { finishPhase(playSound: false, reason: "skipped") }

    func stop() {
        endPhase(reason: "stopped")
        ticker?.invalidate()
        phase = .idle
        remaining = 0
        isPaused = false
        completedFocusSessions = 0
        endBreak()
        applyBlocking(false)
    }

    private func begin(_ newPhase: Phase, durationMinutes: Int? = nil, source: String) {
        phase = newPhase
        let duration = durationMinutes ?? minutes(for: newPhase)
        phaseDuration = TimeInterval(max(duration, 1) * 60)
        remaining = phaseDuration
        endDate = Date().addingTimeInterval(phaseDuration)
        isPaused = false
        if newPhase == .focus { focusStartedAt = Date() }
        phaseStartedAt = Date()
        Analytics.track(newPhase == .focus ? .focusStarted : .breakStarted, [
            "phase": .string(newPhase.rawValue),
            "planned_minutes": .int(Int(phaseDuration / 60)),
            "round": .int(completedFocusSessions % max(settings.sessionsUntilLongBreak, 1) + (newPhase == .focus ? 1 : 0)),
            "source": .string(source),
        ])
        startTicker()
        applyBlocking(newPhase == .focus)

        if newPhase.isBreak {
            skippedSuggestions = []
            refreshSuggestion()
            panels.showBreak()
        } else {
            endBreak()
        }
    }

    private func finishPhase(playSound: Bool = true, reason: String = "completed") {
        if playSound { NSSound(named: "Glass")?.play() }
        let finished = phase
        endPhase(reason: reason)
        switch finished {
        case .focus:
            completedFocusSessions += 1
            let isLong = completedFocusSessions % max(settings.sessionsUntilLongBreak, 1) == 0
            begin(isLong ? .longBreak : .shortBreak, source: "auto")
        case .shortBreak, .longBreak:
            if settings.autoStartFocus {
                begin(.focus, source: "auto")
            } else {
                // Keep the round count so the next focus phase continues the cycle.
                ticker?.invalidate()
                phase = .idle
                remaining = 0
                endBreak()
            }
        case .idle:
            break
        }
    }

    /// Logs the end of the running phase and records focus time in the statistics.
    private func endPhase(reason: String) {
        guard phase != .idle else { return }
        if !isPaused, let endDate { remaining = max(0, endDate.timeIntervalSinceNow) }
        let completed = reason == "completed" && remaining <= 0
        Analytics.track(phase == .focus ? .focusEnded : .breakEnded, [
            "phase": .string(phase.rawValue),
            "reason": .string(reason),
            "completed": .bool(completed),
            "planned_seconds": .int(Int(phaseDuration)),
            "elapsed_seconds": .int(Int(phaseDuration - remaining)),
            "wall_seconds": .int(Int(Date().timeIntervalSince(phaseStartedAt ?? Date()))),
        ])
        if phase == .focus { recordFocus(completed: completed) }
    }

    private func recordFocus(completed: Bool) {
        guard let start = focusStartedAt else { return }
        if !isPaused { remaining = max(0, (endDate ?? Date()).timeIntervalSinceNow) }
        // Paused time is excluded because `remaining` does not move while paused.
        stats.recordFocus(start: start, focusedSeconds: phaseDuration - remaining,
                          plannedSeconds: phaseDuration, completed: completed,
                          task: selectedTask, project: selectedProject)
        focusStartedAt = nil
    }

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard !isPaused, let endDate, phase != .idle else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining == 0 { finishPhase() }
    }

    private func minutes(for phase: Phase) -> Int {
        switch phase {
        case .focus: settings.focusMinutes
        case .shortBreak: settings.shortBreakMinutes
        case .longBreak: settings.longBreakMinutes
        case .idle: 0
        }
    }

    // MARK: - Blocking

    private func applyBlocking(_ on: Bool) {
        if on {
            let ownID = Bundle.main.bundleIdentifier
            let apps = activeBlockedApps
            appBlocker.start(bundleIDs: Set(apps.map(\.bundleID).filter { $0 != ownID }))
        } else {
            appBlocker.stop()
        }

        let blockDomains = on && settings.blockDomains && !settings.blockedDomains.isEmpty
        domainBlocker.setBlocking(blockDomains)
        if blockDomains && !isHelperInstalled {
            // Ask automatically only once per launch; afterwards the menu offers a button.
            if askedForHelper {
                domainBlockError = "Webseiten werden nicht blockiert, der Helfer ist nicht installiert."
            } else {
                askedForHelper = true
                installHelper()
            }
        }
    }

    private func syncDomains() {
        domainBlocker.setDomains(settings.blockDomains ? settings.blockedDomains : [])
    }

    private func refreshHelperStatus() {
        isHelperInstalled = domainBlocker.isHelperInstalled
        // With the helper running, leftovers are cleaned up automatically.
        hasStaleHostsBlock = !isHelperInstalled && DomainBlocker.hostsHasBlock
    }

    func installHelper() {
        Task {
            let ok = await domainBlocker.installHelper()
            Analytics.track(.helperInstalled, ["success": .bool(ok)])
            refreshHelperStatus()
            domainBlockError = ok ? nil : "Webseiten werden nicht blockiert (Installation des Helfers abgebrochen)."
        }
    }

    func uninstallHelper() {
        Task {
            let ok = await domainBlocker.uninstallHelper()
            Analytics.track(.helperUninstalled, ["success": .bool(ok)])
            refreshHelperStatus()
        }
    }

    func removeStaleHostsBlock() {
        Task {
            let ok = await domainBlocker.removeStaleBlock()
            Analytics.track(.staleBlockRemoved, ["success": .bool(ok)])
            refreshHelperStatus()
        }
    }

    // MARK: - Quick capture & break suggestions

    func showQuickCapture(source: String) {
        Analytics.track(.quickCaptureOpened, ["source": .string(source)])
        panels.showCapture { [weak self] text in self?.todos.capture(text, source: "quick_capture") }
    }

    func showTimerEntry() {
        guard phase == .idle else { return }
        panels.showTimerEntry()
    }

    func refreshSuggestion() {
        guard phase.isBreak else { suggestion = nil; return }
        // Round up so a 5 min todo still fits a 5 min break once the first second has ticked.
        let available = max(Int((remaining / 60).rounded(.up)), 1)
        let previous = suggestion?.id
        suggestion = todos.suggestion(fitting: available, excluding: skippedSuggestions)
        if suggestion == nil && !skippedSuggestions.isEmpty {
            // Every fitting todo was skipped once: start over.
            skippedSuggestions = []
            suggestion = todos.suggestion(fitting: available, excluding: [])
        }
        if let suggestion, suggestion.id != previous {
            Analytics.track(.suggestionShown, ["todo_id": .string(suggestion.id.uuidString),
                                               "estimated_minutes": .int(suggestion.estimatedMinutes ?? 0),
                                               "available_minutes": .int(available)])
        }
    }

    func nextSuggestion() {
        if let suggestion {
            skippedSuggestions.insert(suggestion.id)
            Analytics.track(.suggestionSkipped, ["todo_id": .string(suggestion.id.uuidString)])
        }
        refreshSuggestion()
    }

    func completeSuggestion() {
        guard let suggestion else { return }
        todos.toggleDone(suggestion.id, source: "break_suggestion")
        refreshSuggestion()
    }

    private func endBreak() {
        suggestion = nil
        panels.hideBreak()
    }

    // MARK: - Analytics

    private func trackSettingsChange(from old: FocusSettings) {
        Analytics.trackChanges(in: "focus", from: old, to: settings)
        let oldApps = Set(old.blockedApps.map(\.bundleID)), newApps = Set(settings.blockedApps.map(\.bundleID))
        for app in settings.blockedApps where !oldApps.contains(app.bundleID) {
            Analytics.track(.blockedAppAdded, ["bundle_id": .string(app.bundleID), "app_name": .string(app.name)])
        }
        for app in old.blockedApps where !newApps.contains(app.bundleID) {
            Analytics.track(.blockedAppRemoved, ["bundle_id": .string(app.bundleID), "app_name": .string(app.name)])
        }
        for domain in settings.blockedDomains where !old.blockedDomains.contains(domain) {
            Analytics.track(.blockedDomainAdded, ["count": .int(settings.blockedDomains.count)], content: ["domain": domain])
        }
        for domain in old.blockedDomains where !settings.blockedDomains.contains(domain) {
            Analytics.track(.blockedDomainRemoved, ["count": .int(settings.blockedDomains.count)], content: ["domain": domain])
        }
    }
}
