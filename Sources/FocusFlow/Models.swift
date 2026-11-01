import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case german = "de"
    case english = "en"

    var id: String { rawValue }
    var title: String { self == .german ? "Deutsch" : "English" }
}

enum L10n {
    static var language: AppLanguage = .german

    static func text(_ key: String) -> String {
        translations[key]?[language] ?? key
    }

    static func text(_ key: String, _ values: CVarArg...) -> String {
        String(format: text(key), arguments: values)
    }

    private static let translations: [String: [AppLanguage: String]] = [
        "ready": [.german: "Bereit", .english: "Ready"],
        "focus": [.german: "Fokus", .english: "Focus"],
        "shortBreak": [.german: "Kurze Pause", .english: "Short break"],
        "longBreak": [.german: "Lange Pause", .english: "Long break"],
        "focusSection": [.german: "Fokus", .english: "Focus"],
        "projects": [.german: "Projekte", .english: "Projects"],
        "todos": [.german: "Todos", .english: "Tasks"],
        "stats": [.german: "Statistik", .english: "Statistics"],
        "settings": [.german: "Einstellungen", .english: "Settings"],
        "timer": [.german: "Timer", .english: "Timer"],
        "blocking": [.german: "Blockieren", .english: "Blocking"],
        "general": [.german: "Allgemein", .english: "General"],
        "language": [.german: "Sprache", .english: "Language"],
        "german": [.german: "Deutsch", .english: "German"],
        "english": [.german: "Englisch", .english: "English"],
        "startFocus": [.german: "Fokus starten", .english: "Start focus"],
        "resume": [.german: "Weiter", .english: "Resume"],
        "pause": [.german: "Pause", .english: "Pause"],
        "skip": [.german: "Überspringen", .english: "Skip"],
        "stop": [.german: "Stopp", .english: "Stop"],
        "today": [.german: "Heute", .english: "Today"],
        "todaySummary": [.german: "Heute %d von %d Min", .english: "Today %d of %d min"],
        "breakSuggestion": [.german: "Vorschlag für die Pause", .english: "Break suggestion"],
        "statistics": [.german: "Statistik", .english: "Statistics"],
        "done": [.german: "Erledigt", .english: "Done"],
        "dashboard": [.german: "Dashboard", .english: "Dashboard"],
        "quit": [.german: "Beenden", .english: "Quit"],
        "add": [.german: "Hinzufügen", .english: "Add"],
        "save": [.german: "Speichern", .english: "Save"],
        "delete": [.german: "Löschen", .english: "Delete"],
        "tasks": [.german: "Aufgaben", .english: "Tasks"],
        "apps": [.german: "Apps", .english: "Apps"],
        "websites": [.german: "Webseiten", .english: "Websites"],
        "focusTimeByTask": [.german: "Fokuszeit pro Aufgabe", .english: "Focus time per task"],
        "progress": [.german: "Dein Fortschritt", .english: "Your progress"],
        "sevenDays": [.german: "7 Tage", .english: "7 days"],
        "thirtyDays": [.german: "30 Tage", .english: "30 days"],
        "taskSessionsRange": [.german: "Letzte Sitzungen im gewählten Zeitraum", .english: "Sessions in the selected period"],
        "noTaskSessions": [.german: "Noch keine Aufgaben-Sessions", .english: "No task sessions yet"],
        "chooseTaskHint": [.german: "Wähle vor dem Start eines Fokus eine Aufgabe aus.", .english: "Choose a task before starting focus."],
        "noProjectTask": [.german: "Kein Projekt / keine Aufgabe", .english: "No project / task"],
        "ownAppRule": [.german: "Eigene App-Regel verwenden", .english: "Use custom app rule"],
        "inheritRule": [.german: "Erbt die Regel des übergeordneten Bereichs.", .english: "Inherits the rule from its parent."],
        "noBlockedApps": [.german: "Keine Apps blockieren", .english: "Block no apps"],
        "customDuration": [.german: "Eigene Dauer eingeben…", .english: "Enter custom duration…"]
        , "pauseFit": [.german: "Passt in deine Pause:", .english: "Fits your break:"]
        , "noPauseTask": [.german: "Kein offenes Todo passt in diese Pause. Gönn dir eine echte Pause!", .english: "No open task fits this break. Take a real break!"]
        , "nextSuggestion": [.german: "Anderer Vorschlag", .english: "Another suggestion"]
        , "upNext": [.german: "Als Nächstes", .english: "Up next"]
        , "noOpenTasks": [.german: "Keine offenen Todos.", .english: "No open tasks."]
        , "openTasks": [.german: "Offen (%d)", .english: "Open (%d)"]
        , "completedTasks": [.german: "Erledigt (%d)", .english: "Completed (%d)"]
        , "clearCompleted": [.german: "Erledigte löschen", .english: "Delete completed"]
        , "aboutTotal": [.german: "Zusammen etwa %@", .english: "About %@ total"]
    ]
}

enum Phase: String, Codable {
    case idle, focus, shortBreak, longBreak

    var isBreak: Bool { self == .shortBreak || self == .longBreak }

    var title: String {
        switch self {
        case .idle: L10n.text("ready")
        case .focus: L10n.text("focus")
        case .shortBreak: L10n.text("shortBreak")
        case .longBreak: L10n.text("longBreak")
        }
    }

    var symbol: String {
        switch self {
        case .idle: "timer"
        case .focus: "brain.head.profile"
        case .shortBreak, .longBreak: "cup.and.saucer.fill"
        }
    }
}

struct BlockedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    /// nil means that the global blocking configuration is inherited.
    var blockedApps: [BlockedApp]?
}

struct FocusSettings: Codable, Equatable {
    var language: AppLanguage = .german
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var sessionsUntilLongBreak = 4
    var autoStartFocus = false
    var dailyGoalMinutes = 100
    var blockedApps: [BlockedApp] = []
    var blockDomains = true
    var blockedDomains = ["youtube.com", "reddit.com", "x.com", "twitter.com", "instagram.com", "facebook.com"]

    init() {}

    // Decode field by field so settings saved by older versions keep working when fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FocusSettings()
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? d.language
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        sessionsUntilLongBreak = try c.decodeIfPresent(Int.self, forKey: .sessionsUntilLongBreak) ?? d.sessionsUntilLongBreak
        autoStartFocus = try c.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? d.autoStartFocus
        dailyGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyGoalMinutes) ?? d.dailyGoalMinutes
        blockedApps = try c.decodeIfPresent([BlockedApp].self, forKey: .blockedApps) ?? d.blockedApps
        blockDomains = try c.decodeIfPresent(Bool.self, forKey: .blockDomains) ?? d.blockDomains
        blockedDomains = try c.decodeIfPresent([String].self, forKey: .blockedDomains) ?? d.blockedDomains
    }
}

struct Todo: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var estimatedMinutes: Int?
    /// The raw note the todo was derived from.
    var sourceNote: String
    var createdAt = Date()
    var completedAt: Date?
    /// True while the note is still being turned into concrete todos.
    var isRefining = false
    var refinedByAI = false
    var projectID: UUID?
    /// nil means that the project (or global) blocking configuration is inherited.
    var blockedApps: [BlockedApp]?

    var isDone: Bool { completedAt != nil }
}

enum Storage {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FocusFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

func formatMinutes(_ minutes: Int) -> String {
    minutes < 60 ? "\(minutes) Min" : String(format: "%d:%02d h", minutes / 60, minutes % 60)
}

/// Parses a typed duration such as "45", "45 min", "1h", "1,5 h", "1:30" or "1h 30" into minutes.
func parseDuration(_ input: String) -> Int? {
    let text = input.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard !text.isEmpty else { return nil }
    let patterns: [(String, ([Double]) -> Double)] = [
        (#"^(\d+):(\d{1,2})\s*(h|std)?$"#, { $0[0] * 60 + $0[1] }),
        (#"^(\d+(?:\.\d+)?)\s*(?:h|std|stunden?|hours?)\s*(\d+)\s*(?:m|min|minuten?)?$"#, { $0[0] * 60 + $0[1] }),
        (#"^(\d+(?:\.\d+)?)\s*(?:h|std|stunden?|hours?)$"#, { $0[0] * 60 }),
        (#"^(\d+(?:\.\d+)?)\s*(?:m|min|minuten?|minutes?)?$"#, { $0[0] }),
    ]
    for (pattern, combine) in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
        let numbers = (1..<match.numberOfRanges).compactMap { i -> Double? in
            Range(match.range(at: i), in: text).flatMap { Double(text[$0]) }
        }
        let minutes = Int(combine(numbers).rounded())
        return minutes > 0 ? minutes : nil
    }
    return nil
}
