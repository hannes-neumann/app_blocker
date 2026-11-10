import Foundation
import Testing
@testable import FocusFlow

/// Files written by older versions must keep loading, or an update would lose the user's data.
@Suite("Stored data")
struct StoredDataTests {
    init() { TestSupport.isolate() }

    @Test func projectFromBeforeTrackingRules() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Uni","createdAt":0,"colorIndex":2}"#
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.name == "Uni")
        #expect(project.colorIndex == 2)
        #expect(project.trackingRules.isEmpty)
    }

    @Test func settingsFillInMissingValues() throws {
        let ai = try JSONDecoder().decode(AISettings.self, from: Data(#"{"provider":"ollama"}"#.utf8))
        #expect(ai.provider == .ollama)
        #expect(ai.ollamaModel == AISettings().ollamaModel)
        #expect(ai.startOllama)
        let tracking = try JSONDecoder().decode(TrackingSettings.self, from: Data("{}".utf8))
        #expect(tracking == TrackingSettings())
        #expect(!tracking.enabled, "time tracking must stay off until the user turns it on")
    }

    @Test func todoRoundTrip() throws {
        let todo = Todo(title: "A", estimatedMinutes: 5, sourceNote: "a", projectID: UUID())
        #expect(try JSONDecoder().decode(Todo.self, from: JSONEncoder().encode(todo)) == todo)
    }
}
