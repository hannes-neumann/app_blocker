import Foundation
import Testing
@testable import FocusFlow

/// The store saves to todos.json, so these run one after the other on a fresh file.
@Suite("Todos", .serialized)
@MainActor
struct TodoStoreTests {
    let store: TodoStore
    var jobs: [@MainActor () async -> Void] = []

    init() {
        TestSupport.isolate()
        TestSupport.remove("todos.json")
        store = TodoStore()
    }

    /// A store whose model work waits until `runJobs`, like during a focus session.
    func deferredStore(answer: [RefinedTodo]) -> (TodoStore, () async -> Void) {
        var pending: [@MainActor () async -> Void] = []
        store.enqueue = { pending.append($0) }
        store.refiner = { _ in (answer, true) }
        return (store, {
            while !pending.isEmpty { await pending.removeFirst()() }
        })
    }

    @Test func noteWaitsWithAKeywordGuess() throws {
        let (store, _) = deferredStore(answer: [])
        store.capture("mail an anna schreiben", source: "test")
        let todo = try #require(store.todos.first)
        #expect(todo.isRefining)
        #expect(todo.estimatedMinutes == 5)
        #expect(todo.title == "Mail an anna schreiben")
    }

    @Test func refinedTodosKeepIdAndProject() async throws {
        let (store, run) = deferredStore(answer: [RefinedTodo(title: "Folien bauen", minutes: 40),
                                                  RefinedTodo(title: "Probelauf", minutes: 15)])
        store.capture("präsentation vorbereiten", source: "test")
        let placeholder = try #require(store.todos.first)
        let project = UUID()
        store.setProject(placeholder.id, projectID: project)
        await run()
        #expect(store.todos.map(\.title) == ["Folien bauen", "Probelauf"])
        #expect(store.todos[0].id == placeholder.id)
        #expect(store.todos.allSatisfy { $0.projectID == project && !$0.isRefining && $0.refinedByAI })
    }

    @Test func whatTheUserChangesWins() async throws {
        let (store, run) = deferredStore(answer: [RefinedTodo(title: "Vom Modell", minutes: 99)])
        store.capture("umbenannt", source: "test")
        store.capture("abgehakt", source: "test")
        store.capture("gelöscht", source: "test")
        let id = { (note: String) in store.todos.first { $0.sourceNote == note }!.id }
        store.setTitle(id("umbenannt"), title: "Mein Titel")
        store.toggleDone(id("abgehakt"), source: "test")
        store.delete(id("gelöscht"), source: "test")
        await run()
        #expect(Set(store.todos.map(\.title)) == ["Mein Titel", "Abgehakt"])
        #expect(!store.todos.contains { $0.isRefining || $0.title == "Vom Modell" })
    }

    @Test func breakSuggestionPicksTheLongestFittingTodo() {
        store.add(id: UUID(), title: "Kurz", estimatedMinutes: 3, projectID: nil, source: "test")
        store.add(id: UUID(), title: "Passt", estimatedMinutes: 5, projectID: nil, source: "test")
        store.add(id: UUID(), title: "Zu lang", estimatedMinutes: 20, projectID: nil, source: "test")
        #expect(store.suggestion(fitting: 5, excluding: [])?.title == "Passt")
        let passt = store.todos.first { $0.title == "Passt" }!.id
        #expect(store.suggestion(fitting: 5, excluding: [passt])?.title == "Kurz")
    }

    @Test func todosSurviveARestart() {
        store.add(id: UUID(), title: "Bleibt", estimatedMinutes: 10, projectID: nil, source: "test")
        #expect(TodoStore().todos.map(\.title) == ["Bleibt"])
    }
}
