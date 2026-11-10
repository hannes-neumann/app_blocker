import Foundation
import Testing
@testable import FocusFlow

/// Talks to the built `focusflow-mcp` like Claude does, on data written in the app's own format.
@Suite("Claude MCP server")
struct MCPServerTests {
    init() { TestSupport.isolate() }

    static var binary: URL? {
        let url = TestSupport.packageRoot.appendingPathComponent(".build/debug/focusflow-mcp")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Sends the requests and returns the replies by id.
    func call(_ requests: [[String: Any]], dataDirectory: URL) throws -> [Int: [String: Any]] {
        let binary = try #require(Self.binary, "build focusflow-mcp first (swift build)")
        let process = Process()
        process.executableURL = binary
        process.environment = ["FOCUSFLOW_DATA_DIR": dataDirectory.path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        for request in requests {
            input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: request) + Data("\n".utf8))
        }
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var replies: [Int: [String: Any]] = [:]
        for line in data.split(separator: UInt8(ascii: "\n")) {
            if let reply = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], let id = reply["id"] as? Int {
                replies[id] = reply
            }
        }
        return replies
    }

    func fixture() throws -> (URL, Project, [Todo]) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FocusFlowMCP-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let project = Project(name: "Uni")
        let todos = [
            Todo(title: "Übungsblatt 3 lösen", estimatedMinutes: 90, sourceNote: "x", createdAt: Date(timeIntervalSinceNow: -3600), projectID: project.id),
            Todo(title: "Mail an Prof", estimatedMinutes: 10, sourceNote: "x", createdAt: Date(timeIntervalSinceNow: -1800)),
            Todo(title: "Erledigt", estimatedMinutes: 10, sourceNote: "x", completedAt: Date()),
            Todo(title: "Noch in Arbeit", sourceNote: "x", isRefining: true),
        ]
        // Same encoder as `Storage.save`, so a format change in the app breaks this test.
        try JSONEncoder().encode(todos).write(to: dir.appendingPathComponent("todos.json"))
        try JSONEncoder().encode([project]).write(to: dir.appendingPathComponent("projects.json"))
        return (dir, project, todos)
    }

    func content(_ reply: [String: Any]?) throws -> [String: Any] {
        let result = try #require(reply?["result"] as? [String: Any])
        #expect(result["isError"] as? Bool != true, "\(result)")
        return try #require(result["structuredContent"] as? [String: Any])
    }

    @Test func listsToolsAndOpenTodos() throws {
        let (dir, _, _) = try fixture()
        let replies = try call([
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "list_todos", "arguments": [String: Any]()]],
        ], dataDirectory: dir)
        let tools = try #require((replies[2]?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(Set(tools.compactMap { $0["name"] as? String }) ==
                ["get_planning_context", "list_todos", "plan_focus_blocks", "add_todo", "complete_todo", "start_focus"])
        let todos = try #require(try content(replies[3])["todos"] as? [[String: Any]])
        #expect(todos.compactMap { $0["title"] as? String } == ["Übungsblatt 3 lösen", "Mail an Prof"])
    }

    @Test func plansBlocksInsideTheFreeSlots() throws {
        let (dir, project, _) = try fixture()
        let formatter = ISO8601DateFormatter()
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: 2 * 86400))
        let slots = [(9, 11), (14, 15)].map { (start, end) in
            ["start": formatter.string(from: day.addingTimeInterval(Double(start) * 3600)),
             "end": formatter.string(from: day.addingTimeInterval(Double(end) * 3600))]
        }
        let replies = try call([
            ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
             "params": ["name": "plan_focus_blocks", "arguments": ["free_slots": slots, "use_estimate_factor": false]]],
        ], dataDirectory: dir)
        let blocks = try #require(try content(replies[1])["blocks"] as? [[String: Any]])
        #expect(!blocks.isEmpty)
        let ranges = slots.map { (formatter.date(from: $0["start"]!)!, formatter.date(from: $0["end"]!)!) }
        var planned: [String: Int] = [:]
        var previousEnd = Date.distantPast
        for block in blocks {
            let start = try #require((block["start"] as? String).flatMap(formatter.date(from:)))
            let end = try #require((block["end"] as? String).flatMap(formatter.date(from:)))
            #expect(ranges.contains { start >= $0.0 && end <= $0.1 }, "block outside the free slots")
            #expect(start >= previousEnd, "blocks overlap")
            previousEnd = end
            for item in block["todos"] as? [[String: Any]] ?? [] {
                planned[item["title"] as! String, default: 0] += item["minutes"] as! Int
            }
            if block["project_id"] as? String == project.id.uuidString { #expect((block["focus_link"] as? String)?.hasPrefix("focusflow://") == true) }
        }
        #expect(planned["Übungsblatt 3 lösen", default: 0] + planned["Mail an Prof", default: 0] > 0)
        #expect(planned["Erledigt"] == nil && planned["Noch in Arbeit"] == nil)
    }
}
