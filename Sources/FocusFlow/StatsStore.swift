import Foundation
import Observation

struct FocusRecord: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var focusedSeconds: Double
    var plannedSeconds: Double
    /// Ran until the timer hit zero (not skipped or stopped).
    var completed: Bool
}

/// Kept apart from the todo list so clearing done todos does not erase history.
struct TodoCompletionRecord: Codable, Identifiable {
    var id: UUID // the todo's id
    var title: String
    var estimatedMinutes: Int?
    var completedAt: Date
}

struct DayStat: Identifiable {
    var day: Date
    var focusMinutes: Double
    var sessions: Int
    var completedSessions: Int
    var todosDone: Int
    var id: Date { day }
}

@MainActor @Observable
final class StatsStore {
    private(set) var focusRecords: [FocusRecord] = Storage.load([FocusRecord].self, from: "focus-sessions.json") ?? []
    private(set) var todoCompletions: [TodoCompletionRecord] = Storage.load([TodoCompletionRecord].self, from: "todo-completions.json") ?? []

    private var calendar: Calendar { .current }

    func recordFocus(start: Date, focusedSeconds: Double, plannedSeconds: Double, completed: Bool) {
        // Ignore accidental starts.
        guard focusedSeconds >= 60 else { return }
        focusRecords.append(FocusRecord(start: start, end: Date(), focusedSeconds: focusedSeconds,
                                        plannedSeconds: plannedSeconds, completed: completed))
        Storage.save(focusRecords, to: "focus-sessions.json")
    }

    func todoChanged(_ todo: Todo) {
        todoCompletions.removeAll { $0.id == todo.id }
        if let completedAt = todo.completedAt {
            todoCompletions.append(TodoCompletionRecord(id: todo.id, title: todo.title,
                                                        estimatedMinutes: todo.estimatedMinutes, completedAt: completedAt))
        }
        Storage.save(todoCompletions, to: "todo-completions.json")
    }

    /// One entry per day for the last `count` days, oldest first, including empty days.
    func days(_ count: Int) -> [DayStat] {
        let today = calendar.startOfDay(for: Date())
        var byDay: [Date: DayStat] = [:]
        for offset in 0..<count {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            byDay[day] = DayStat(day: day, focusMinutes: 0, sessions: 0, completedSessions: 0, todosDone: 0)
        }
        for record in focusRecords {
            let day = calendar.startOfDay(for: record.start)
            guard byDay[day] != nil else { continue }
            byDay[day]!.focusMinutes += record.focusedSeconds / 60
            byDay[day]!.sessions += 1
            if record.completed { byDay[day]!.completedSessions += 1 }
        }
        for completion in todoCompletions {
            let day = calendar.startOfDay(for: completion.completedAt)
            byDay[day]?.todosDone += 1
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// Focus minutes per hour of the day (0–23) over the last `count` days.
    func minutesByHour(lastDays count: Int) -> [(hour: Int, minutes: Double)] {
        let since = calendar.date(byAdding: .day, value: -(count - 1), to: calendar.startOfDay(for: Date()))!
        var minutes = Array(repeating: 0.0, count: 24)
        for record in focusRecords where record.start >= since {
            minutes[calendar.component(.hour, from: record.start)] += record.focusedSeconds / 60
        }
        return minutes.enumerated().map { (hour: $0.offset, minutes: $0.element) }
    }

    var todayFocusMinutes: Double {
        let today = calendar.startOfDay(for: Date())
        return focusRecords.filter { calendar.startOfDay(for: $0.start) == today }.reduce(0) { $0 + $1.focusedSeconds / 60 }
    }

    /// Consecutive days with focus time, counting back from today (or yesterday if today is still empty).
    var streak: Int {
        let focusDays = Set(focusRecords.map { calendar.startOfDay(for: $0.start) })
        var day = calendar.startOfDay(for: Date())
        if !focusDays.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while focusDays.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}
