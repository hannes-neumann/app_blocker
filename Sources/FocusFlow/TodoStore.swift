import Foundation
import Observation

@MainActor @Observable
final class TodoStore {
    private(set) var todos: [Todo] = Storage.load([Todo].self, from: "todos.json") ?? []
    @ObservationIgnored var onCompletionChange: ((Todo) -> Void)?
    @ObservationIgnored var refiner: (String) async -> (todos: [RefinedTodo], usedAI: Bool) = { note in
        ([TodoRefiner.heuristic(note)], false)
    }

    var open: [Todo] { todos.filter { !$0.isDone } }
    var done: [Todo] { todos.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) } }

    func capture(_ note: String, source: String) {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let placeholder = Todo(title: text, sourceNote: text, isRefining: true)
        Analytics.track(.noteCaptured, ["source": .string(source), "note_id": .string(placeholder.id.uuidString),
                                        "length": .int(text.count), "open_todos": .int(open.count)],
                        content: ["note": text])
        todos.insert(placeholder, at: 0)
        save()
        refine(placeholder)
    }

    func addTask(title: String, projectID: UUID) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let todo = Todo(title: text, sourceNote: text, projectID: projectID)
        todos.insert(todo, at: 0)
        save()
        Analytics.track(.taskAdded, ["todo_id": .string(todo.id.uuidString), "project_id": .string(projectID.uuidString)],
                        content: ["title": text])
    }

    func setProject(_ todoID: UUID, projectID: UUID?) {
        mutate(todoID) { $0.projectID = projectID }
        Analytics.track(.todoProjectChanged, ["todo_id": .string(todoID.uuidString),
                                              "project_id": .string(projectID?.uuidString ?? "")])
    }

    func setBlockedApps(_ apps: [BlockedApp]?, for todoID: UUID) {
        mutate(todoID) { $0.blockedApps = apps }
        Analytics.track(.todoBlockedAppsChanged, ["todo_id": .string(todoID.uuidString), "custom": .bool(apps != nil),
                                                  "bundle_ids": .string(apps?.map(\.bundleID).joined(separator: ",") ?? "")])
    }

    /// Notes that were still being refined when the app quit.
    func resumePendingRefinements() {
        todos.filter(\.isRefining).forEach(refine)
    }

    private func refine(_ placeholder: Todo) {
        Task {
            let started = Date()
            let result = await refiner(placeholder.sourceNote)
            guard let index = todos.firstIndex(where: { $0.id == placeholder.id }) else { return }
            let refined = result.todos.map {
                Todo(title: $0.title, estimatedMinutes: $0.minutes, sourceNote: placeholder.sourceNote,
                     createdAt: placeholder.createdAt, refinedByAI: result.usedAI)
            }
            Analytics.track(.noteRefined, [
                "note_id": .string(placeholder.id.uuidString),
                "used_ai": .bool(result.usedAI),
                "duration_ms": .int(Int(Date().timeIntervalSince(started) * 1000)),
                "todo_count": .int(refined.count),
                "todo_ids": .string(refined.map(\.id.uuidString).joined(separator: ",")),
                "estimated_minutes": .string(refined.map { String($0.estimatedMinutes ?? 0) }.joined(separator: ",")),
            ], content: ["note": placeholder.sourceNote, "titles": refined.map(\.title).joined(separator: "\n")])
            todos.replaceSubrange(index...index, with: refined)
            save()
        }
    }

    func toggleDone(_ id: UUID, source: String) {
        mutate(id) { $0.completedAt = $0.isDone ? nil : Date() }
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        onCompletionChange?(todo)
        Analytics.track(todo.isDone ? .todoCompleted : .todoReopened, Self.properties(of: todo, ["source": .string(source)]))
    }

    /// `method` is how the user picked the value, e.g. "menu" or "typed".
    func setEstimate(_ id: UUID, minutes: Int, method: String) {
        guard let old = todos.first(where: { $0.id == id }) else { return }
        mutate(id) { $0.estimatedMinutes = minutes }
        Analytics.track(.todoEstimateChanged, Self.properties(of: old, [
            "method": .string(method), "old_minutes": .int(old.estimatedMinutes ?? 0), "new_minutes": .int(minutes),
        ]))
    }

    func setTitle(_ id: UUID, title: String) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let old = todos.first(where: { $0.id == id }) else { return }
        mutate(id) { $0.title = text }
        Analytics.track(.todoTitleChanged, Self.properties(of: old), content: ["old_title": old.title, "new_title": text])
    }

    func delete(_ id: UUID, source: String) {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        todos.removeAll { $0.id == id }
        save()
        Analytics.track(.todoDeleted, Self.properties(of: todo, ["source": .string(source)]), content: ["title": todo.title])
    }

    func clearDone(source: String) {
        let count = done.count
        todos.removeAll(where: \.isDone)
        save()
        Analytics.track(.todosCleared, ["count": .int(count), "source": .string(source)])
    }

    /// The facts about a todo most events carry, so estimates can be compared with what happened.
    private static func properties(of todo: Todo, _ extra: AnalyticsProperties = [:]) -> AnalyticsProperties {
        var p: AnalyticsProperties = [
            "todo_id": .string(todo.id.uuidString),
            "estimated_minutes": .int(todo.estimatedMinutes ?? 0),
            "refined_by_ai": .bool(todo.refinedByAI),
            "age_minutes": .int(Int(Date().timeIntervalSince(todo.createdAt) / 60)),
        ]
        p.merge(extra) { _, new in new }
        return p
    }

    /// The open todo that fills the given time best: the longest one that still fits, oldest first on ties.
    func suggestion(fitting minutes: Int, excluding excluded: Set<UUID>) -> Todo? {
        todos
            .filter { !$0.isDone && !$0.isRefining && !excluded.contains($0.id) }
            .filter { ($0.estimatedMinutes ?? .max) <= minutes }
            .max { a, b in
                let ea = a.estimatedMinutes ?? 0, eb = b.estimatedMinutes ?? 0
                return ea != eb ? ea < eb : a.createdAt > b.createdAt
            }
    }

    private func mutate(_ id: UUID, _ change: (inout Todo) -> Void) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        change(&todos[index])
        save()
    }

    private func save() {
        Storage.save(todos, to: "todos.json")
    }
}
