import Foundation
import Testing
@testable import FocusFlow

@Suite("Finished projects")
struct FinishedProjectTests {
    init() { TestSupport.isolate() }

    @Test func projectFinishedAtRoundTripsAndOldDataDefaultsToActive() throws {
        var project = Project(name: "Archivierung")
        project.finishedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let decoded = try JSONDecoder().decode(
            Project.self,
            from: JSONEncoder().encode(project)
        )
        #expect(decoded == project)
        #expect(decoded.finishedAt == project.finishedAt)
        #expect(decoded.isFinished)

        let oldJSON = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Altes Projekt","createdAt":0,"colorIndex":2}"#
        let oldProject = try JSONDecoder().decode(Project.self, from: Data(oldJSON.utf8))
        #expect(oldProject.finishedAt == nil)
        #expect(!oldProject.isFinished)
    }

    @Suite(.serialized)
    @MainActor
    struct StoreTests {
        init() { TestSupport.isolate() }

        @Test func setFinishedMovesProjectOutOfAndBackIntoActive() throws {
            let store = ProjectStore()
            let project = try #require(store.add("Abgeschlossen"))

            store.setFinished(project.id, true)
            #expect(store.project(project.id)?.finishedAt != nil)
            #expect(store.project(project.id)?.isFinished == true)
            #expect(!store.active.contains(where: { $0.id == project.id }))

            store.setFinished(project.id, false)
            #expect(store.project(project.id)?.finishedAt == nil)
            #expect(store.project(project.id)?.isFinished == false)
            #expect(store.active.contains(where: { $0.id == project.id }))
        }
    }

    @Test func mcpPlanningContextExcludesFinishedProjects() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusFlowFinishedMCP-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let active = Project(name: "Aktiv")
        var finished = Project(name: "Fertig")
        finished.finishedAt = Date()
        try JSONEncoder().encode([active, finished]).write(to: dir.appendingPathComponent("projects.json"))
        try JSONEncoder().encode([] as [Todo]).write(to: dir.appendingPathComponent("todos.json"))

        let packageRoot = TestSupport.packageRoot
        let binary = packageRoot.appendingPathComponent(".build/debug/focusflow-mcp")
        let process = Process()
        process.executableURL = binary
        process.environment = ["FOCUSFLOW_DATA_DIR": dir.path]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "get_planning_context",
                "arguments": [String: Any](),
            ],
        ]
        input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: request) + Data("\n".utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let reply = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["isError"] as? Bool != true)
        let structured = try #require(result["structuredContent"] as? [String: Any])
        let projects = try #require(structured["projects"] as? [[String: Any]])
        let names = projects.compactMap { $0["name"] as? String }
        #expect(names == ["Aktiv"])
        #expect(!names.contains("Fertig"))
    }
}
