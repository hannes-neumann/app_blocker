import AppKit
import ApplicationServices
import Observation

/// Decides which project a piece of tracked activity belongs to.
struct TrackingRule: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case app, domain, title
        /// A word the language model learned from the screen. Matches visible text, never the window metadata.
        case learned
    }

    var id = UUID()
    var kind: Kind
    /// A bundle ID for apps, an address such as "github.com/acme" for domains, a word for window titles.
    var value: String
    /// The app's name, for showing app rules.
    var label: String?

    /// How specific the rule is; the most specific matching rule wins.
    var weight: Int {
        switch kind {
        case .domain: 300 + value.count
        case .title: 200 + value.count
        case .app: 100
        case .learned: 150
        }
    }

    func matches(bundleID: String, title: String?, address: String?) -> Bool {
        switch kind {
        case .app:
            return bundleID == value
        case .learned:
            return false
        case .title:
            guard let title, !value.isEmpty else { return false }
            return title.localizedCaseInsensitiveContains(value)
        case .domain:
            guard let address, let rule = Self.normalizedAddress(value) else { return false }
            let (ruleHost, rulePath) = Self.split(rule)
            let (host, path) = Self.split(address)
            guard host == ruleHost || host.hasSuffix("." + ruleHost) else { return false }
            return rulePath.isEmpty || path.hasPrefix(rulePath)
        }
    }

    /// "https://www.GitHub.com/acme/?tab=1" → "github.com/acme". Only web addresses; nil otherwise.
    static func normalizedAddress(_ text: String) -> String? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "https://" + raw }
        guard let url = URL(string: raw), let scheme = url.scheme, ["http", "https"].contains(scheme),
              var host = url.host, !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return host + path
    }

    private static func split(_ address: String) -> (host: String, path: String) {
        guard let slash = address.firstIndex(of: "/") else { return (address, "") }
        return (String(address[..<slash]), String(address[slash...]))
    }
}

/// A window that is visible next to the front app, e.g. a PDF beside a chat.
struct SideWindow: Codable, Equatable {
    var bundleID: String
    var appName: String
    var title: String?
    var address: String?
}

/// A stretch of time in one app, window and web address.
struct ActivitySegment: Codable, Identifiable {
    enum Assignment: String, Codable {
        /// No rule matched.
        case none
        case rule
        /// A focus session for a project was running.
        case focus
        /// Found from the words of the visible windows, without a rule.
        case inferred
        /// Set by the user; rules never change it again.
        case manual
    }

    var id = UUID()
    var start: Date
    var end: Date
    var bundleID: String
    var appName: String
    var title: String?
    var address: String?
    /// The second visible app, if any. It counts for rules just like the front app.
    var side: SideWindow?
    var projectID: UUID?
    var assignment = Assignment.none
    /// The project came from a rule on `side`, not on the front app.
    var decidedBySide = false

    var seconds: Double { end.timeIntervalSince(start) }
}

/// What a block of tracked time consisted of, e.g. "Safari · github.com/acme".
struct ActivityItem: Identifiable {
    let bundleID: String
    let appName: String
    let detail: String?
    let address: String?
    let title: String?
    var seconds: Double
    var id: String { bundleID + "|" + (detail ?? "") }

    init(bundleID: String, appName: String, title: String?, address: String?, seconds: Double = 0) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.address = address
        detail = address ?? title
        self.seconds = seconds
    }
}

/// Neighboring segments of the same project, shown and assigned together.
struct ActivityBlock: Identifiable {
    let id: UUID
    var start: Date
    var end: Date
    let projectID: UUID?
    var assignment: ActivitySegment.Assignment
    var segmentIDs: [UUID]
    var seconds: Double
    /// Front apps, most time first.
    var items: [ActivityItem]
    /// Apps that were visible next to them.
    var sideItems: [ActivityItem]
}

struct TrackingSettings: Codable, Equatable {
    var enabled = false
    var windowTitles = true
    var browserAddresses = false
    var idleMinutes = 3
    var sideWindow = true
    /// Detect projects from the text of the visible windows, when no rule matches. Text is never stored.
    var detectFromText = true
    /// Apps that are never tracked or read. Editable in Settings.
    var excludedApps = ContextFilter.defaultExcludedBundleIDs

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TrackingSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        windowTitles = try c.decodeIfPresent(Bool.self, forKey: .windowTitles) ?? d.windowTitles
        browserAddresses = try c.decodeIfPresent(Bool.self, forKey: .browserAddresses) ?? d.browserAddresses
        idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? d.idleMinutes
        sideWindow = try c.decodeIfPresent(Bool.self, forKey: .sideWindow) ?? d.sideWindow
        detectFromText = try c.decodeIfPresent(Bool.self, forKey: .detectFromText) ?? d.detectFromText
        excludedApps = try c.decodeIfPresent([String].self, forKey: .excludedApps) ?? d.excludedApps
    }
}

/// Records which app, window and web page is in front, so time can be counted per project without a timer.
///
/// Besides the front app it looks at the next app whose window is still largely visible, because the
/// app in front is not always the telling one: with a PDF and a chat side by side, the PDF says more.
/// Samples every few seconds and when the front app changes. Window titles need the Accessibility
/// permission, browser addresses the Automation permission per browser. Nothing is captured from the
/// screen itself, and everything stays in `Activity/` on this Mac, one file per day.
@MainActor @Observable
final class ActivityTracker {
    static let directory = Storage.directory.appendingPathComponent("Activity", isDirectory: true)
    static let sampleInterval: TimeInterval = 5
    /// Days kept in memory for the dashboard; older days stay on disk until `retentionDays`.
    static let loadedDays = 35
    static let retentionDays = 365
    /// Neighboring segments of one project closer than this form one block.
    static let blockGap: TimeInterval = 120
    static let browsers: [String: String] = [
        "com.apple.Safari": "URL of front document",
        "com.apple.SafariTechnologyPreview": "URL of front document",
        "com.google.Chrome": "URL of active tab of front window",
        "com.brave.Browser": "URL of active tab of front window",
        "com.microsoft.edgemac": "URL of active tab of front window",
        "com.vivaldi.Vivaldi": "URL of active tab of front window",
        "company.thebrowser.Browser": "URL of active tab of front window",
    ]
    private static let ignored: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]

    var settings: TrackingSettings = Storage.load(TrackingSettings.self, from: "tracking.json") ?? TrackingSettings() {
        didSet {
            guard settings != oldValue else { return }
            Storage.save(settings, to: "tracking.json")
            Analytics.trackChanges(in: "tracking", from: oldValue, to: settings)
            if !settings.enabled { closeCurrent() }
            if settings.enabled && !oldValue.enabled { start() }
        }
    }
    private(set) var segments: [ActivitySegment] = []
    private(set) var hasAccessibility = AXIsProcessTrusted()
    /// Browsers whose address the user did not allow FocusFlow to read.
    private(set) var deniedBrowsers: Set<String> = []

    /// The project of a running focus session, and all projects with their rules.
    @ObservationIgnored var context: () -> (focusProjectID: UUID?, projects: [Project]) = { (nil, []) }
    /// Asks the local language model which project visible text belongs to. Nil when none is available.
    @ObservationIgnored var classify: ((String, [Project]) async -> ProjectClassification?)?
    /// Stores words the model learned for a project. Set by the app, which owns the projects.
    @ObservationIgnored var learn: ((UUID, [String]) -> Void)?
    @ObservationIgnored private var classifying = false
    @ObservationIgnored private var lastClassification: (key: Int, at: Date)?
    @ObservationIgnored private var currentID: UUID?
    @ObservationIgnored private var lastSampleAt: Date?
    @ObservationIgnored private var sampling = false
    @ObservationIgnored private var dirtyDays: Set<Date> = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private let probeQueue = DispatchQueue(label: "FocusFlow.activity")

    private var calendar: Calendar { .current }

    init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Running

    func start() {
        guard settings.enabled, timer == nil else { return }
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closeCurrent() }
            })
        }
        tick()
    }

    func stop() {
        closeCurrent()
        timer?.invalidate()
        timer = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        save()
    }

    /// Asks macOS for the Accessibility permission, which window titles need.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
        if !hasAccessibility, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        Analytics.track(.trackingPermissionRequested, ["permission": "accessibility", "granted": .bool(hasAccessibility)])
    }

    func refreshPermissions() {
        hasAccessibility = AXIsProcessTrusted()
    }

    private func tick() {
        guard settings.enabled else { return }
        hasAccessibility = AXIsProcessTrusted()
        let now = Date()
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= Double(settings.idleMinutes * 60) || Self.screenIsLocked {
            closeCurrent(at: now.addingTimeInterval(-idle))
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier, !Self.ignored.contains(bundleID),
              ContextFilter.isAllowed(bundleID: bundleID, excluded: Set(settings.excludedApps)) else {
            closeCurrent()
            return
        }
        guard !sampling else { return }
        sampling = true
        let pid = app.processIdentifier
        let name = app.localizedName ?? bundleID
        let wantsTitle = settings.windowTitles && hasAccessibility
        let wantsText = settings.detectFromText && hasAccessibility
        let readsAddresses = settings.browserAddresses
        let denied = deniedBrowsers
        let wantsSide = settings.sideWindow
        let excluded = Set(settings.excludedApps)
        let ignored = Self.ignored.union([Bundle.main.bundleIdentifier ?? ""]).union(excluded)
        probeQueue.async {
            let title = wantsTitle ? Self.windowTitle(pid: pid) : nil
            // Text is read only to match project names; it is passed on and never stored.
            var contextText = wantsText ? AccessibilityText.windowText(pid: pid) : nil
            let script = readsAddresses && !denied.contains(bundleID) ? Self.browsers[bundleID] : nil
            let address = script.map { Self.browserAddress(bundleID: bundleID, expression: $0) }
            var side: SideWindow?
            var sideDenied: String?
            if wantsSide, let sidePID = Self.sideWindowPID(frontPID: pid),
               let sideApp = NSRunningApplication(processIdentifier: sidePID), let sideID = sideApp.bundleIdentifier,
               !ignored.contains(sideID) {
                let sideScript = readsAddresses && !denied.contains(sideID) ? Self.browsers[sideID] : nil
                let sideAddress = sideScript.map { Self.browserAddress(bundleID: sideID, expression: $0) }
                if case .denied = sideAddress { sideDenied = sideID }
                var url: String?
                if case .address(let value) = sideAddress { url = value }
                side = SideWindow(bundleID: sideID, appName: sideApp.localizedName ?? sideID,
                                  title: wantsTitle ? Self.windowTitle(pid: sidePID) : nil, address: url)
                if wantsText { contextText = (contextText ?? "") + "\n" + (AccessibilityText.windowText(pid: sidePID) ?? "") }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.sampling = false
                    if case .denied = address { self.deniedBrowsers.insert(bundleID) }
                    if let sideDenied { self.deniedBrowsers.insert(sideDenied) }
                    var url: String?
                    if case .address(let value) = address { url = value }
                    self.record(at: Date(), bundleID: bundleID, appName: name, title: title, address: url, side: side,
                                contextText: contextText)
                }
            }
        }
    }

    private func record(at now: Date, bundleID: String, appName: String, title: String?, address: String?, side: SideWindow?,
                        contextText: String? = nil) {
        guard settings.enabled else { return }
        let (projectID, assignment, bySide) = resolve(bundleID: bundleID, title: title, address: address, side: side,
                                                      contextText: contextText)
        let previousSample = lastSampleAt
        let continuous = previousSample.map { now.timeIntervalSince($0) <= Self.sampleInterval * 3 } ?? false
        if let index = currentIndex, continuous, calendar.isDate(segments[index].start, inSameDayAs: now),
           segments[index].bundleID == bundleID, segments[index].title == title, segments[index].address == address,
           segments[index].side == side,
           segments[index].assignment == .manual || (segments[index].projectID == projectID && segments[index].assignment == assignment)
            // A segment the model assigned stays one segment while the same screen goes on without a rule.
            || (segments[index].assignment == .inferred && assignment == .none) {
            segments[index].end = now
        } else {
            closeCurrent()
            // Count the time since the last sample for the new app, unless the day changed in between.
            let start = continuous ? previousSample.flatMap { calendar.isDate($0, inSameDayAs: now) ? $0 : nil } ?? now : now
            let segment = ActivitySegment(start: start, end: now, bundleID: bundleID, appName: appName, title: title,
                                          address: address, side: side, projectID: projectID, assignment: assignment,
                                          decidedBySide: bySide)
            segments.append(segment)
            currentID = segment.id
            if projectID == nil, let contextText { requestClassification(contextText, segmentID: segment.id) }
        }
        lastSampleAt = now
        dirtyDays.insert(calendar.startOfDay(for: now))
        if now.timeIntervalSince(lastSave) >= 60 { save() }
    }

    /// Stage 2: the model looks at text that no rule or name matched. One request per screen, at most every
    /// two minutes, and only while no focus session decides. The result goes to the segment it was asked for,
    /// if that segment is still unassigned. The text is not stored.
    private func requestClassification(_ text: String, segmentID: UUID) {
        guard let classify, !classifying, context().focusProjectID == nil else { return }
        let key = text.hashValue
        if let last = lastClassification, last.key == key, Date().timeIntervalSince(last.at) < 120 { return }
        lastClassification = (key, Date())
        classifying = true
        let projects = context().projects
        Task { [weak self] in
            let result = await classify(text, projects)
            guard let self else { return }
            self.classifying = false
            guard let result else { return }
            self.learn?(result.projectID, result.keywords)
            guard let index = self.segments.firstIndex(where: { $0.id == segmentID }),
                  self.segments[index].assignment == .none else { return }
            self.segments[index].projectID = result.projectID
            self.segments[index].assignment = .inferred
            self.dirtyDays.insert(self.calendar.startOfDay(for: self.segments[index].start))
            self.save()
        }
    }

    private var currentIndex: Int? {
        guard let currentID else { return nil }
        return segments.lastIndex { $0.id == currentID }
    }

    /// Ends the running segment, e.g. when the Mac goes idle. `date` is when activity actually stopped.
    private func closeCurrent(at date: Date? = nil) {
        if let index = currentIndex, let date {
            segments[index].end = max(segments[index].start, min(segments[index].end, date))
        }
        if let index = currentIndex, segments[index].seconds < 1 { segments.remove(at: index) }
        currentID = nil
        lastSampleAt = nil
    }

    private func resolve(bundleID: String, title: String?, address: String?,
                         side: SideWindow?, contextText: String?) -> (UUID?, ActivitySegment.Assignment, Bool) {
        let context = context()
        if let focus = context.focusProjectID { return (focus, .focus, false) }
        guard let match = Self.match(context.projects, bundleID: bundleID, title: title, address: address, side: side) else {
            // No rule matched: the project whose name appears most often in the visible text, if any.
            if let contextText, let project = ProjectDetector.bestProject(in: contextText, projects: context.projects) {
                return (project, .inferred, false)
            }
            return (nil, .none, false)
        }
        return (match.project, .rule, match.bySide)
    }

    /// The project of the most specific rule matching the front app or the side window. On a tie the
    /// front app wins.
    static func match(_ projects: [Project], bundleID: String, title: String?, address: String?,
                      side: SideWindow? = nil) -> (project: UUID, bySide: Bool)? {
        let front = bestRule(projects, bundleID: bundleID, title: title, address: address)
        let other = side.flatMap { bestRule(projects, bundleID: $0.bundleID, title: $0.title, address: $0.address) }
        if let other, other.weight > front?.weight ?? 0 { return (other.project, true) }
        return front.map { ($0.project, false) }
    }

    private static func bestRule(_ projects: [Project], bundleID: String, title: String?,
                                 address: String?) -> (project: UUID, weight: Int)? {
        var best: (project: UUID, weight: Int)?
        for project in projects {
            for rule in project.trackingRules where rule.matches(bundleID: bundleID, title: title, address: address) {
                if rule.weight > best?.weight ?? 0 { best = (project.id, rule.weight) }
            }
        }
        return best
    }

    // MARK: - Probes (run off the main thread)

    private enum AddressResult { case address(String), unavailable, denied }

    /// The app behind the front one whose window is still largely visible, e.g. the other half of a split
    /// screen. Reads only window positions, not their content, so it needs no screen recording permission.
    nonisolated private static func sideWindowPID(frontPID: pid_t) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        // Front to back; layer 0 holds normal app windows.
        let windows: [(pid: pid_t, rect: CGRect)] = list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width >= 150, rect.height >= 150 else { return nil }
            return (pid, rect)
        }
        for (index, window) in windows.enumerated().prefix(8) where window.pid != frontPID {
            let area = window.rect.width * window.rect.height
            let covered = windows[..<index].reduce(0) { total, above in
                let overlap = above.rect.intersection(window.rect)
                return total + (overlap.isNull ? 0 : overlap.width * overlap.height)
            }
            let visible = area - covered
            if visible >= area * 0.35 && visible >= 300 * 300 { return window.pid }
        }
        return nil
    }

    nonisolated private static func windowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        // Don't wait long on apps that hang.
        AXUIElementSetMessagingTimeout(app, 0.3)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = (title as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(200))
    }

    nonisolated private static func browserAddress(bundleID: String, expression: String) -> AddressResult {
        let source = """
        with timeout of 2 seconds
            tell application id "\(bundleID)" to return \(expression)
        end timeout
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -1743: the user did not allow FocusFlow to control this browser.
            return error[NSAppleScript.errorNumber] as? Int == -1743 ? .denied : .unavailable
        }
        guard let text = result?.stringValue, let address = TrackingRule.normalizedAddress(text) else { return .unavailable }
        return .address(address)
    }

    nonisolated private static var screenIsLocked: Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return info["CGSSessionScreenIsLocked"] as? Bool == true
    }

    // MARK: - Reading

    /// Blocks of one day, oldest first.
    func blocks(on day: Date) -> [ActivityBlock] {
        let daySegments = segments.filter { calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
        var blocks: [ActivityBlock] = []
        var items: [[String: ActivityItem]] = []
        var sideItems: [[String: ActivityItem]] = []
        for segment in daySegments {
            if let last = blocks.last, last.projectID == segment.projectID, segment.start.timeIntervalSince(last.end) <= Self.blockGap {
                blocks[blocks.count - 1].end = max(last.end, segment.end)
                blocks[blocks.count - 1].segmentIDs.append(segment.id)
                blocks[blocks.count - 1].seconds += segment.seconds
                if segment.assignment == .manual { blocks[blocks.count - 1].assignment = .manual }
            } else {
                blocks.append(ActivityBlock(id: segment.id, start: segment.start, end: segment.end, projectID: segment.projectID,
                                            assignment: segment.assignment, segmentIDs: [segment.id], seconds: segment.seconds,
                                            items: [], sideItems: []))
                items.append([:])
                sideItems.append([:])
            }
            let item = ActivityItem(bundleID: segment.bundleID, appName: segment.appName, title: segment.title, address: segment.address)
            items[items.count - 1][item.id, default: item].seconds += segment.seconds
            if let side = segment.side {
                let item = ActivityItem(bundleID: side.bundleID, appName: side.appName, title: side.title, address: side.address)
                sideItems[sideItems.count - 1][item.id, default: item].seconds += segment.seconds
            }
        }
        for index in blocks.indices {
            blocks[index].items = items[index].values.sorted { $0.seconds > $1.seconds }
            blocks[index].sideItems = sideItems[index].values.sorted { $0.seconds > $1.seconds }
        }
        return blocks
    }

    /// Tracked minutes per project (nil = unassigned) since the start of `since`'s day.
    func minutesByProject(since: Date) -> [UUID?: Double] {
        let start = calendar.startOfDay(for: since)
        var result: [UUID?: Double] = [:]
        for segment in segments where segment.start >= start {
            result[segment.projectID, default: 0] += segment.seconds / 60
        }
        return result
    }

    func minutes(for projectID: UUID, since: Date) -> Double {
        let start = calendar.startOfDay(for: since)
        return segments.filter { $0.projectID == projectID && $0.start >= start }.reduce(0) { $0 + $1.seconds / 60 }
    }

    // MARK: - Changing

    func assign(_ block: ActivityBlock, to projectID: UUID?) {
        let ids = Set(block.segmentIDs)
        for index in segments.indices where ids.contains(segments[index].id) {
            segments[index].projectID = projectID
            segments[index].assignment = .manual
            dirtyDays.insert(calendar.startOfDay(for: segments[index].start))
        }
        save()
        Analytics.track(.trackedBlockAssigned, ["old_project_id": .string(block.projectID?.uuidString ?? ""),
                                                "new_project_id": .string(projectID?.uuidString ?? ""),
                                                "old_assignment": .string(block.assignment.rawValue),
                                                "minutes": .int(Int(block.seconds / 60))])
    }

    /// Re-runs the rules over all loaded segments that the user did not assign by hand.
    func applyRules(_ projects: [Project]) {
        for index in segments.indices where segments[index].assignment == .none || segments[index].assignment == .rule {
            let segment = segments[index]
            let match = Self.match(projects, bundleID: segment.bundleID, title: segment.title, address: segment.address,
                                   side: segment.side)
            guard match?.project != segment.projectID || match?.bySide ?? false != segment.decidedBySide else { continue }
            segments[index].projectID = match?.project
            segments[index].assignment = match == nil ? .none : .rule
            segments[index].decidedBySide = match?.bySide ?? false
            dirtyDays.insert(calendar.startOfDay(for: segment.start))
        }
        save()
    }

    /// Minutes of loaded activity that a rule would match, for previewing a new rule.
    func minutesMatching(_ rule: TrackingRule, since: Date) -> Double {
        let start = calendar.startOfDay(for: since)
        return segments.filter { $0.start >= start && $0.assignment != .manual && $0.assignment != .focus
            && (rule.matches(bundleID: $0.bundleID, title: $0.title, address: $0.address)
                || $0.side.map { rule.matches(bundleID: $0.bundleID, title: $0.title, address: $0.address) } == true) }
            .reduce(0) { $0 + $1.seconds / 60 }
    }

    /// Activity of a deleted project becomes unassigned, then the remaining rules get a chance.
    func detachProject(_ id: UUID, remaining projects: [Project]) {
        for index in segments.indices where segments[index].projectID == id {
            segments[index].projectID = nil
            segments[index].assignment = .none
            segments[index].decidedBySide = false
            dirtyDays.insert(calendar.startOfDay(for: segments[index].start))
        }
        applyRules(projects)
    }

    func deleteAll() {
        closeCurrent()
        segments = []
        dirtyDays = []
        for url in Self.files { try? FileManager.default.removeItem(at: url) }
        Analytics.track(.trackedDataDeleted)
    }

    // MARK: - Storage

    private static var files: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("activity-") && $0.pathExtension == "json" }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func url(for day: Date) -> URL {
        directory.appendingPathComponent("activity-\(dayFormatter.string(from: day)).json")
    }

    private func load() {
        let today = calendar.startOfDay(for: Date())
        let deleteBefore = calendar.date(byAdding: .day, value: -Self.retentionDays, to: today)!
        for url in Self.files {
            let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "activity-", with: "")
            if let day = Self.dayFormatter.date(from: name), day < deleteBefore { try? FileManager.default.removeItem(at: url) }
        }
        for offset in 0..<Self.loadedDays {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            if let data = try? Data(contentsOf: Self.url(for: day)),
               let daySegments = try? Self.decoder.decode([ActivitySegment].self, from: data) {
                segments.append(contentsOf: daySegments)
            }
        }
        segments.sort { $0.start < $1.start }
    }

    func save() {
        lastSave = Date()
        for day in dirtyDays {
            let daySegments = segments.filter { calendar.isDate($0.start, inSameDayAs: day) }
            guard let data = try? Self.encoder.encode(daySegments) else { continue }
            try? data.write(to: Self.url(for: day), options: .atomic)
        }
        dirtyDays = []
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
