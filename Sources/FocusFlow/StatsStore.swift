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
    var taskID: UUID?
    var taskTitle: String?
    var projectID: UUID?
    var projectName: String?
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

    /// Returns the new record, or nil for accidental starts under a minute.
    @discardableResult
    func recordFocus(start: Date, focusedSeconds: Double, plannedSeconds: Double, completed: Bool,
                     task: Todo?, project: Project?) -> FocusRecord? {
        guard focusedSeconds >= 60 else { return nil }
        let record = FocusRecord(start: start, end: Date(), focusedSeconds: focusedSeconds,
                                 plannedSeconds: plannedSeconds, completed: completed,
                                 taskID: task?.id, taskTitle: task?.title,
                                 projectID: project?.id, projectName: project?.name)
        focusRecords.append(record)
        Storage.save(focusRecords, to: "focus-sessions.json")
        return record
    }

    /// Moves a past session to another project (or to none), e.g. when it was started without one.
    func assign(_ recordID: UUID, to project: Project?) {
        guard let index = focusRecords.firstIndex(where: { $0.id == recordID }) else { return }
        let old = focusRecords[index].projectID
        focusRecords[index].projectID = project?.id
        focusRecords[index].projectName = project?.name
        Storage.save(focusRecords, to: "focus-sessions.json")
        Analytics.track(.sessionProjectChanged, ["record_id": .string(recordID.uuidString),
                                                 "old_project_id": .string(old?.uuidString ?? ""),
                                                 "new_project_id": .string(project?.id.uuidString ?? ""),
                                                 "minutes": .int(Int(focusRecords[index].focusedSeconds / 60))])
    }

    /// Sessions of a deleted project become unassigned instead of pointing nowhere.
    func detachProject(_ projectID: UUID) {
        var changed = false
        for i in focusRecords.indices where focusRecords[i].projectID == projectID {
            focusRecords[i].projectID = nil
            changed = true
        }
        if changed { Storage.save(focusRecords, to: "focus-sessions.json") }
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
