import AppKit
import Carbon
import Observation

@MainActor @Observable
final class AppState {
    var settings: FocusSettings = Storage.load(FocusSettings.self, from: "settings.json") ?? FocusSettings() {
        didSet {
            Storage.save(settings, to: "settings.json")
            syncDomains()
            if phase == .focus && settings != oldValue { applyBlocking(true) }
        }
    }
    let todos = TodoStore()
    let stats = StatsStore()

    private(set) var phase: Phase = .idle
    private(set) var remaining: TimeInterval = 0
    private(set) var phaseDuration: TimeInterval = 1
    private(set) var isPaused = false
    private(set) var completedFocusSessions = 0
    private(set) var suggestion: Todo?
    private(set) var aiStatus: AIStatus = .unavailable("")
    private(set) var domainBlockError: String?
    private(set) var hasStaleHostsBlock = false
    private(set) var isHelperInstalled = false
    var dashboardSection: DashboardSection = .focus

    static let shortcutDescription = "⌃⌥N"

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var focusStartedAt: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var skippedSuggestions: Set<UUID> = []
    @ObservationIgnored private var askedForHelper = false
    @ObservationIgnored private let appBlocker = AppBlocker()
    @ObservationIgnored private let domainBlocker = DomainBlocker()
    @ObservationIgnored private var hotKey: HotKey?
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
        panels = PanelController(state: self)
        aiStatus = TodoRefiner.status
        refreshHelperStatus()
        syncDomains()
        domainBlocker.setBlocking(false)
        appBlocker.onBlocked = { [weak self] name in self?.panels.showBlockedHUD(appName: name) }
        todos.onCompletionChange = { [weak self] todo in self?.stats.todoChanged(todo) }
        hotKey = HotKey(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey) { [weak self] in
            self?.showQuickCapture()
        }
        todos.resumePendingRefinements()
    }

    func shutdown() {
        if phase == .focus { recordFocus(completed: false) }
        appBlocker.stop()
        domainBlocker.setBlocking(false)
    }

    // MARK: - Timer

    func startFocus() { begin(.focus) }

    func togglePause() {
        guard phase != .idle else { return }
        if isPaused {
            endDate = Date().addingTimeInterval(remaining)
            isPaused = false
        } else {
            tick()
            isPaused = true
        }
    }

    func skipPhase() { finishPhase(playSound: false) }

    func stop() {
        if phase == .focus { recordFocus(completed: false) }
        ticker?.invalidate()
        phase = .idle
        remaining = 0
        isPaused = false
        completedFocusSessions = 0
        endBreak()
        applyBlocking(false)
    }

    private func begin(_ newPhase: Phase) {
        phase = newPhase
        phaseDuration = TimeInterval(max(minutes(for: newPhase), 1) * 60)
        remaining = phaseDuration
        endDate = Date().addingTimeInterval(phaseDuration)
        isPaused = false
        if newPhase == .focus { focusStartedAt = Date() }
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

    private func finishPhase(playSound: Bool = true) {
        if playSound { NSSound(named: "Glass")?.play() }
        switch phase {
        case .focus:
            recordFocus(completed: remaining <= 0)
            completedFocusSessions += 1
            let isLong = completedFocusSessions % max(settings.sessionsUntilLongBreak, 1) == 0
            begin(isLong ? .longBreak : .shortBreak)
        case .shortBreak, .longBreak:
            if settings.autoStartFocus {
                begin(.focus)
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

    private func recordFocus(completed: Bool) {
        guard let start = focusStartedAt else { return }
        if !isPaused { remaining = max(0, (endDate ?? Date()).timeIntervalSinceNow) }
        // Paused time is excluded because `remaining` does not move while paused.
        stats.recordFocus(start: start, focusedSeconds: phaseDuration - remaining,
                          plannedSeconds: phaseDuration, completed: completed)
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
            appBlocker.start(bundleIDs: Set(settings.blockedApps.map(\.bundleID).filter { $0 != ownID }))
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
            refreshHelperStatus()
            domainBlockError = ok ? nil : "Webseiten werden nicht blockiert (Installation des Helfers abgebrochen)."
        }
    }

    func uninstallHelper() {
        Task {
            _ = await domainBlocker.uninstallHelper()
            refreshHelperStatus()
        }
    }

    func removeStaleHostsBlock() {
        Task {
            _ = await domainBlocker.removeStaleBlock()
            refreshHelperStatus()
        }
    }

    // MARK: - Quick capture & break suggestions

    func showQuickCapture() {
        panels.showCapture { [weak self] text in self?.todos.capture(text) }
    }

    func refreshSuggestion() {
        guard phase.isBreak else { suggestion = nil; return }
        // Round up so a 5 min todo still fits a 5 min break once the first second has ticked.
        let available = max(Int((remaining / 60).rounded(.up)), 1)
        suggestion = todos.suggestion(fitting: available, excluding: skippedSuggestions)
        if suggestion == nil && !skippedSuggestions.isEmpty {
            // Every fitting todo was skipped once: start over.
            skippedSuggestions = []
            suggestion = todos.suggestion(fitting: available, excluding: [])
        }
    }

    func nextSuggestion() {
        if let suggestion { skippedSuggestions.insert(suggestion.id) }
        refreshSuggestion()
    }

    func completeSuggestion() {
        guard let suggestion else { return }
        todos.toggleDone(suggestion.id)
        refreshSuggestion()
    }

    private func endBreak() {
        suggestion = nil
        panels.hideBreak()
    }
}
