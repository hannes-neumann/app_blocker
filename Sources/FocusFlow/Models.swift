import Foundation

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
    /// Slot in `ProjectPalette`; stays with the project so its color never changes.
    var colorIndex = 0
    var symbol = "folder.fill"
    /// Optional focus target per week.
    var weeklyGoalMinutes: Int?
    /// Which tracked activity counts for this project.
    var trackingRules: [TrackingRule] = []

    init(name: String, colorIndex: Int = 0, symbol: String = "folder.fill") {
        self.name = name
        self.colorIndex = colorIndex
        self.symbol = symbol
    }

    // Projects saved before colors existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        blockedApps = try c.decodeIfPresent([BlockedApp].self, forKey: .blockedApps)
        // -1 marks "no color yet"; ProjectStore hands out a free one on load.
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? -1
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "folder.fill"
        weeklyGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .weeklyGoalMinutes)
        trackingRules = try c.decodeIfPresent([TrackingRule].self, forKey: .trackingRules) ?? []
    }
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
        // Tests point FocusFlow at a scratch folder, like the MCP server's FOCUSFLOW_DATA_DIR.
        let dir = ProcessInfo.processInfo.environment["FOCUSFLOW_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FocusFlow", isDirectory: true)
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
    minutes < 60 ? "\(minutes) \(L10n.text("minUnit"))" : String(format: "%d:%02d h", minutes / 60, minutes % 60)
}

/// Longer spans read better as hours: "45 Min", "3,5 h".
func formatDuration(_ minutes: Double) -> String {
    if minutes < 60 { return "\(Int(minutes.rounded())) \(L10n.text("minUnit"))" }
    let hours = minutes / 60
    return hours.formatted(.number.precision(.fractionLength(hours < 10 ? 1 : 0)).locale(L10n.locale)) + " h"
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
