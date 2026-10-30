import Foundation
import Observation

@MainActor @Observable
final class TodoStore {
    private(set) var todos: [Todo] = Storage.load([Todo].self, from: "todos.json") ?? []
    @ObservationIgnored var onCompletionChange: ((Todo) -> Void)?

    var open: [Todo] { todos.filter { !$0.isDone } }
    var done: [Todo] { todos.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) } }

    func capture(_ note: String) {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let placeholder = Todo(title: text, sourceNote: text, isRefining: true)
        todos.insert(placeholder, at: 0)
        save()
        refine(placeholder)
    }

    /// Notes that were still being refined when the app quit.
    func resumePendingRefinements() {
        todos.filter(\.isRefining).forEach(refine)
    }

    private func refine(_ placeholder: Todo) {
        Task {
            let result = await TodoRefiner.refine(placeholder.sourceNote)
            guard let index = todos.firstIndex(where: { $0.id == placeholder.id }) else { return }
            let refined = result.todos.map {
                Todo(title: $0.title, estimatedMinutes: $0.minutes, sourceNote: placeholder.sourceNote,
                     createdAt: placeholder.createdAt, refinedByAI: result.usedAI)
            }
            todos.replaceSubrange(index...index, with: refined)
            save()
        }
    }

    func toggleDone(_ id: UUID) {
        mutate(id) { $0.completedAt = $0.isDone ? nil : Date() }
        if let todo = todos.first(where: { $0.id == id }) { onCompletionChange?(todo) }
    }

    func setEstimate(_ id: UUID, minutes: Int) {
        mutate(id) { $0.estimatedMinutes = minutes }
    }

    func setTitle(_ id: UUID, title: String) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        mutate(id) { $0.title = text }
    }

    func delete(_ id: UUID) {
        todos.removeAll { $0.id == id }
        save()
    }

    func clearDone() {
        todos.removeAll(where: \.isDone)
        save()
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
