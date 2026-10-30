import Foundation

enum Phase: String, Codable {
    case idle, focus, shortBreak, longBreak

    var isBreak: Bool { self == .shortBreak || self == .longBreak }

    var title: String {
        switch self {
        case .idle: "Bereit"
        case .focus: "Fokus"
        case .shortBreak: "Kurze Pause"
        case .longBreak: "Lange Pause"
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

struct FocusSettings: Codable, Equatable {
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
