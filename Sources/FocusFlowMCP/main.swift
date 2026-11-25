// focusflow-mcp: an MCP server (stdio, JSON-RPC) that lets Claude read FocusFlow's todos and projects,
// plan them into calendar blocks, and add, complete or start todos.
//
// It only reads FocusFlow's files. Changes go through the app's `focusflow://` URL scheme, so the running
// app stays the only writer and nothing it holds in memory gets overwritten.

import Foundation

// MARK: - FocusFlow data

struct TodoFile: Decodable {
    let id: UUID
    let title: String
    let estimatedMinutes: Int?
    let createdAt: Date
    let completedAt: Date?
    let projectID: UUID?
    let isRefining: Bool?
}

struct ProjectFile: Decodable {
    let id: UUID
    let name: String
    let weeklyGoalMinutes: Int?
    /// Set when the user marked the project as finished in the app.
    let finishedAt: Date?
}

struct FocusRecordFile: Decodable {
    let start: Date
    let focusedSeconds: Double
    let taskID: UUID?
    let projectID: UUID?
}

struct SettingsFile: Decodable {
    var language = "de"
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var sessionsUntilLongBreak = 4
    var dailyGoalMinutes = 100

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsFile()
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        sessionsUntilLongBreak = try c.decodeIfPresent(Int.self, forKey: .sessionsUntilLongBreak) ?? d.sessionsUntilLongBreak
        dailyGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyGoalMinutes) ?? d.dailyGoalMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case language, focusMinutes, shortBreakMinutes, longBreakMinutes, sessionsUntilLongBreak, dailyGoalMinutes
    }
}

struct ToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// A snapshot of FocusFlow's files.
struct FocusData {
    static let directory: URL = {
        if let custom = ProcessInfo.processInfo.environment["FOCUSFLOW_DATA_DIR"] { return URL(fileURLWithPath: custom) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusFlow", isDirectory: true)
    }()

    let todos: [TodoFile]
    let projects: [ProjectFile]
    let records: [FocusRecordFile]
    let settings: SettingsFile

    init() {
        todos = Self.load([TodoFile].self, "todos.json") ?? []
        // Finished projects are done: Claude neither plans nor files new todos under them.
        projects = (Self.load([ProjectFile].self, "projects.json") ?? []).filter { $0.finishedAt == nil }
        records = Self.load([FocusRecordFile].self, "focus-sessions.json") ?? []
        settings = Self.load(SettingsFile.self, "settings.json") ?? SettingsFile()
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    var german: Bool { settings.language != "en" }
    var openTodos: [TodoFile] { todos.filter { $0.completedAt == nil && $0.isRefining != true } }

    func project(_ id: UUID?) -> ProjectFile? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    /// Finds a project by ID or (part of) its name.
    func findProject(_ text: String) throws -> ProjectFile {
        if let id = UUID(uuidString: text), let project = project(id) { return project }
        let exact = projects.filter { $0.name.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        if let match = exact.first { return match }
        let partial = projects.filter { $0.name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        if partial.count == 1 { return partial[0] }
        let names = projects.map(\.name).joined(separator: ", ")
        throw ToolError(partial.isEmpty ? "No project matches “\(text)”. Projects: \(names)"
                                        : "“\(text)” matches several projects: \(partial.map(\.name).joined(separator: ", "))")
    }

    func findTodo(_ text: String) throws -> TodoFile {
        if let id = UUID(uuidString: text), let todo = todos.first(where: { $0.id == id }) { return todo }
        let matches = openTodos.filter { $0.title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        if matches.count == 1 { return matches[0] }
        throw ToolError(matches.isEmpty ? "No open todo matches “\(text)”." : "“\(text)” matches several todos: "
            + matches.map { "\($0.title) (\($0.id.uuidString))" }.joined(separator: "; "))
    }

    func focusedMinutes(task id: UUID) -> Double {
        records.filter { $0.taskID == id }.reduce(0) { $0 + $1.focusedSeconds / 60 }
    }

    /// Median of actual focus time / estimate over finished todos, like the app's insights. 1 without data.
    var estimateFactor: (factor: Double, samples: Int) {
        let ratios = todos.compactMap { todo -> Double? in
            guard todo.completedAt != nil, let estimate = todo.estimatedMinutes, estimate > 0 else { return nil }
            let actual = focusedMinutes(task: todo.id)
            return actual >= 1 ? actual / Double(estimate) : nil
        }.sorted()
        guard ratios.count >= 3 else { return (1, ratios.count) }
        return (min(max(ratios[ratios.count / 2], 0.8), 2), ratios.count)
    }

    /// Minutes to plan for a todo: its estimate (30 without one) times the estimate factor, minus time
    /// already spent, rounded up to 5 minutes.
    func plannedMinutes(_ todo: TodoFile, factor: Double) -> Int {
        let total = Double(todo.estimatedMinutes ?? 30) * factor
        let left = max(total - focusedMinutes(task: todo.id), Double(min(todo.estimatedMinutes ?? 30, 15)))
        return Int((left / 5).rounded(.up)) * 5
    }
}

// MARK: - Dates

let isoOut: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = .current
    return f
}()

func parseDate(_ text: String) -> Date? {
    let f = ISO8601DateFormatter()
    for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
        f.formatOptions = options
        if let date = f.date(from: text) { return date }
    }
    // Without an offset: local time.
    let local = DateFormatter()
    local.locale = Locale(identifier: "en_US_POSIX")
    local.timeZone = .current
    for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
        local.dateFormat = format
        if let date = local.date(from: text) { return date }
    }
    return nil
}

// MARK: - Links into the app

/// Sends a command to FocusFlow through its URL scheme, in the background. Launches the app if needed.
func sendToApp(_ command: String, _ query: [String: String], needsToken: Bool) throws {
    var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
    if needsToken {
        guard let token = try? String(contentsOf: FocusData.directory.appendingPathComponent("mcp-token"), encoding: .utf8) else {
            throw ToolError("FocusFlow has not been started on this Mac yet. Start it once, then try again.")
        }
        items.append(URLQueryItem(name: "token", value: token.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    var components = URLComponents()
    components.scheme = "focusflow"
    components.host = command
    components.queryItems = items.sorted { $0.name < $1.name }
    guard let url = components.url else { throw ToolError("Could not build the FocusFlow link.") }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-g", url.absoluteString]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ToolError("FocusFlow could not be opened. Is it installed?") }
}

func focusLink(project: UUID?, task: UUID?) -> String {
    var components = URLComponents()
    components.scheme = "focusflow"
    components.host = "focus"
    components.queryItems = [task.map { URLQueryItem(name: "task", value: $0.uuidString) }
                             ?? project.map { URLQueryItem(name: "project", value: $0.uuidString) }].compactMap { $0 }
    return components.url!.absoluteString
}

/// Waits until the app has written a change, so a tool only reports success once it happened.
func waitFor(_ condition: (FocusData) -> Bool) -> FocusData? {
    for _ in 0..<30 {
        let data = FocusData()
        if condition(data) { return data }
        Thread.sleep(forTimeInterval: 0.2)
    }
    return nil
}

// MARK: - Planning

struct PlannedItem: Encodable {
    let todo_id: String
    let title: String
    let minutes: Int
    /// The todo goes on in a later block.
    let continues: Bool
}

struct PlannedBlock: Encodable {
    let start: String
    let end: String
    let project_id: String?
    let project: String?
    let work_minutes: Int
    let breaks: String
    let title: String
    let description: String
    let focus_link: String
    let todos: [PlannedItem]
}

/// Packs todos into free calendar slots as focus blocks: grouped by project, split into pomodoros with
/// short breaks, never longer than `maxBlock`. Deterministic, so the result always fits the slots.
func planBlocks(data: FocusData, slots rawSlots: [(Date, Date)], todos: [TodoFile], maxBlock: Int, gap: Int,
                groupByProject: Bool, factor: Double, now: Date) -> (blocks: [PlannedBlock], unplanned: [(TodoFile, Int)]) {
    let focus = max(data.settings.focusMinutes, 5)
    let shortBreak = data.settings.shortBreakMinutes
    func wall(_ work: Int) -> Int { work + max(0, (work + focus - 1) / focus - 1) * shortBreak }
    func maxWork(_ budget: Int) -> Int {
        var work = 0
        while wall(work + 5) <= budget { work += 5 }
        return work
    }

    var queue = todos.map { (todo: $0, remaining: data.plannedMinutes($0, factor: factor)) }
    if groupByProject {
        // Keep the given order, but pull each project's todos together behind its first one.
        var order: [UUID?] = []
        for item in queue where !order.contains(where: { $0 == item.todo.projectID }) { order.append(item.todo.projectID) }
        queue = order.flatMap { project in queue.filter { $0.todo.projectID == project } }
    }

    // Slots in the past are cut to now, rounded up to the next 5 minutes.
    let calendar = Calendar.current
    let nowRounded: Date = {
        let minute = calendar.component(.minute, from: now)
        let base = calendar.date(bySetting: .second, value: 0, of: now) ?? now
        return base.addingTimeInterval(Double((5 - minute % 5) % 5) * 60)
    }()
    let slots = rawSlots.map { (max($0.0, nowRounded), $0.1) }.filter { $0.1.timeIntervalSince($0.0) >= 15 * 60 }.sorted { $0.0 < $1.0 }

    let minBlock = min(focus, 20)
    var blocks: [PlannedBlock] = []
    for (slotStart, slotEnd) in slots {
        var cursor = slotStart
        while !queue.isEmpty {
            let budget = min(maxBlock, Int(slotEnd.timeIntervalSince(cursor) / 60))
            guard budget >= minBlock else { break }
            let project = queue[0].todo.projectID
            var items: [PlannedItem] = []
            var work = 0
            while let next = queue.first, !groupByProject || next.todo.projectID == project {
                if wall(work + next.remaining) <= budget {
                    items.append(PlannedItem(todo_id: next.todo.id.uuidString, title: next.todo.title, minutes: next.remaining, continues: false))
                    work += next.remaining
                    queue.removeFirst()
                    continue
                }
                // Split a todo that does not fit, if a meaningful part does.
                let part = maxWork(budget) - work
                if part >= 15 && (items.isEmpty || part >= 25) {
                    items.append(PlannedItem(todo_id: next.todo.id.uuidString, title: next.todo.title, minutes: part, continues: true))
                    work += part
                    queue[0].remaining -= part
                }
                break
            }
            guard !items.isEmpty else { break }
            let end = cursor.addingTimeInterval(Double(wall(work)) * 60)
            blocks.append(makeBlock(data: data, start: cursor, end: end, projectID: groupByProject ? project : nil,
                                    items: items, work: work, focus: focus, shortBreak: shortBreak))
            cursor = end.addingTimeInterval(Double(gap) * 60)
        }
    }
    return (blocks, queue.map { ($0.todo, $0.remaining) })
}

func makeBlock(data: FocusData, start: Date, end: Date, projectID: UUID?, items: [PlannedItem], work: Int,
               focus: Int, shortBreak: Int) -> PlannedBlock {
    let de = data.german
    let project = data.project(projectID)
    let sessions = (work + focus - 1) / focus
    let breaks = sessions <= 1 ? (de ? "keine Pause" : "no break")
        : de ? "\(sessions) × \(focus) Min Fokus mit \(sessions - 1) × \(shortBreak) Min Pause"
             : "\(sessions) × \(focus) min focus with \(sessions - 1) × \(shortBreak) min break"
    let head = project?.name ?? (de ? "Fokus" : "Focus")
    let title = items.count == 1 ? "\(head): \(items[0].title)" : "\(head): " + (de ? "\(items.count) Aufgaben" : "\(items.count) tasks")
    let firstTask = UUID(uuidString: items[0].todo_id)
    let link = focusLink(project: projectID, task: firstTask)
    var lines = items.map { item in
        "• \(item.title) (\(item.minutes) \(de ? "Min" : "min")\(item.continues ? (de ? ", geht weiter" : ", continues") : ""))"
    }
    lines.append("")
    lines.append(breaks)
    lines.append((de ? "Fokus starten: " : "Start focus: ") + link)
    lines.append(de ? "Geplant mit FocusFlow" : "Planned with FocusFlow")
    return PlannedBlock(start: isoOut.string(from: start), end: isoOut.string(from: end), project_id: projectID?.uuidString,
                        project: project?.name, work_minutes: work, breaks: breaks, title: "🎯 " + title,
                        description: lines.joined(separator: "\n"), focus_link: link, todos: items)
}

// MARK: - Tools

typealias JSON = [String: Any]

struct Tool {
    let name: String
    let description: String
    let schema: JSON
    let readOnly: Bool
    let run: (JSON) throws -> Any
}

func todoJSON(_ todo: TodoFile, _ data: FocusData, factor: Double) -> JSON {
    var result: JSON = [
        "id": todo.id.uuidString,
        "title": todo.title,
        "age_days": Int(Date().timeIntervalSince(todo.createdAt) / 86_400),
        "focused_minutes": Int(data.focusedMinutes(task: todo.id).rounded()),
    ]
    if let project = data.project(todo.projectID) { result["project"] = project.name; result["project_id"] = project.id.uuidString }
    if let estimate = todo.estimatedMinutes { result["estimate_minutes"] = estimate }
    if todo.completedAt == nil { result["planned_minutes"] = data.plannedMinutes(todo, factor: factor) }
    if let done = todo.completedAt { result["completed_at"] = isoOut.string(from: done) }
    return result
}

// get_planning_context

let getPlanningContextSchema: JSON = ["type": "object", "properties": [String: Any]()]

func runGetPlanningContext(_ args: JSON) throws -> Any {
    let data = FocusData()
    let (factor, samples) = data.estimateFactor
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? today
    let monthAgo = calendar.date(byAdding: .day, value: -30, to: today)!
    var hours = Array(repeating: 0.0, count: 24)
    for record in data.records where record.start >= monthAgo {
        hours[calendar.component(.hour, from: record.start)] += record.focusedSeconds / 60
    }
    var windows: [(hour: Int, minutes: Double)] = []
    for hour in 0..<23 where hours[hour] + hours[hour + 1] > 0 {
        windows.append((hour, hours[hour] + hours[hour + 1]))
    }
    windows.sort { $0.minutes > $1.minutes }
    // The strongest windows that don't overlap each other.
    var picked: [(hour: Int, minutes: Double)] = []
    for window in windows where picked.count < 3 && !picked.contains(where: { abs($0.hour - window.hour) < 2 }) {
        picked.append(window)
    }
    let bestHours: [JSON] = picked.map { window in
        ["from": String(format: "%02d:00", window.hour), "to": String(format: "%02d:00", window.hour + 2),
         "focus_minutes": Int(window.minutes)]
    }
    let open = data.openTodos.sorted { $0.createdAt < $1.createdAt }
    let todayMinutes: Double = data.records.filter { $0.start >= today }.reduce(0) { $0 + $1.focusedSeconds / 60 }
    var projects: [JSON] = []
    for project in data.projects {
        let todos = open.filter { $0.projectID == project.id }
        let week: Double = data.records.filter { $0.projectID == project.id && $0.start >= weekStart }
            .reduce(0) { $0 + $1.focusedSeconds / 60 }
        var result: JSON = ["id": project.id.uuidString, "name": project.name]
        result["focus_minutes_this_week"] = Int(week)
        result["open_todos"] = todos.count
        result["open_planned_minutes"] = todos.reduce(0) { $0 + data.plannedMinutes($1, factor: factor) }
        if let goal = project.weeklyGoalMinutes { result["weekly_goal_minutes"] = goal }
        projects.append(result)
    }
    var settings: JSON = [:]
    settings["focus_minutes"] = data.settings.focusMinutes
    settings["short_break_minutes"] = data.settings.shortBreakMinutes
    settings["long_break_minutes"] = data.settings.longBreakMinutes
    settings["sessions_until_long_break"] = data.settings.sessionsUntilLongBreak
    settings["daily_goal_minutes"] = data.settings.dailyGoalMinutes
    var estimate: JSON = ["factor": (factor * 100).rounded() / 100, "finished_todos_measured": samples]
    estimate["note"] = samples >= 3
        ? "Finished todos took this many times their estimate (median); planned_minutes already includes it."
        : "Too few finished todos with focus time to measure; estimates are used as they are."
    var result: JSON = [:]
    result["now"] = isoOut.string(from: Date())
    result["time_zone"] = TimeZone.current.identifier
    result["language"] = data.settings.language
    result["settings"] = settings
    result["estimate_factor"] = estimate
    result["best_focus_hours_last_30_days"] = bestHours
    result["focus_today_minutes"] = Int(todayMinutes)
    result["projects"] = projects
    result["open_todos"] = open.map { todoJSON($0, data, factor: factor) }
    return result
}

// list_todos

let listTodosSchema: JSON = [
            "type": "object",
            "properties": [
                "project": ["type": "string", "description": "Only todos of this project (name or ID)."],
                "include_done": ["type": "boolean", "description": "Also list finished todos."],
                "limit": ["type": "integer", "description": "At most this many (default 100)."],
            ],
        ]

func runListTodos(_ args: JSON) throws -> Any {
    let data = FocusData()
    var todos = (args["include_done"] as? Bool == true ? data.todos : data.openTodos).sorted { $0.createdAt < $1.createdAt }
    if let name = args["project"] as? String {
        let project = try data.findProject(name)
        todos = todos.filter { $0.projectID == project.id }
    }
    let factor = data.estimateFactor.factor
    return ["todos": todos.prefix(args["limit"] as? Int ?? 100).map { todoJSON($0, data, factor: factor) }] as JSON
}

// plan_focus_blocks

let planFocusBlocksSchema: JSON = [
            "type": "object",
            "required": ["free_slots"],
            "properties": [
                "free_slots": [
                    "type": "array",
                    "description": "Free time in the calendar, e.g. derived from its events. ISO 8601 with offset.",
                    "items": [
                        "type": "object",
                        "required": ["start", "end"],
                        "properties": ["start": ["type": "string"], "end": ["type": "string"]],
                    ],
                ],
                "todo_ids": [
                    "type": "array", "items": ["type": "string"],
                    "description": "Only these todos, most important first. Default: all open todos, oldest first.",
                ],
                "project": ["type": "string", "description": "Only todos of this project (name or ID)."],
                "max_block_minutes": ["type": "integer", "description": "Longest block including breaks (default 120)."],
                "gap_minutes": ["type": "integer", "description": "Free time between two blocks (default 15)."],
                "group_by_project": ["type": "boolean", "description": "Keep blocks to one project each (default true)."],
                "use_estimate_factor": ["type": "boolean", "description": "Stretch estimates by how long the user really needs (default true)."],
            ],
        ]

func runPlanFocusBlocks(_ args: JSON) throws -> Any {
    let data = FocusData()
    guard let rawSlots = args["free_slots"] as? [JSON], !rawSlots.isEmpty else { throw ToolError("free_slots is empty.") }
    let slots = try rawSlots.map { slot -> (Date, Date) in
        guard let startText = slot["start"] as? String, let endText = slot["end"] as? String,
              let start = parseDate(startText), let end = parseDate(endText) else {
            throw ToolError("Every slot needs start and end in ISO 8601, e.g. 2026-11-04T09:00:00+01:00.")
        }
        guard end > start else { throw ToolError("Slot \(startText) ends before it starts.") }
        return (start, end)
    }
    var todos: [TodoFile]
    if let ids = args["todo_ids"] as? [String], !ids.isEmpty {
        todos = try ids.map { try data.findTodo($0) }.filter { $0.completedAt == nil }
    } else {
        todos = data.openTodos.sorted { $0.createdAt < $1.createdAt }
    }
    if let name = args["project"] as? String {
        let project = try data.findProject(name)
        todos = todos.filter { $0.projectID == project.id }
    }
    guard !todos.isEmpty else { throw ToolError("There are no open todos to plan.") }
    let factor = args["use_estimate_factor"] as? Bool == false ? 1 : data.estimateFactor.factor
    let plan = planBlocks(data: data, slots: slots, todos: todos,
                          maxBlock: max(args["max_block_minutes"] as? Int ?? 120, 20),
                          gap: max(args["gap_minutes"] as? Int ?? 15, 0),
                          groupByProject: args["group_by_project"] as? Bool ?? true, factor: factor, now: Date())
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.blocks))
    return [
        "blocks": encoded,
        "unplanned": plan.unplanned.map { ["todo_id": $0.0.id.uuidString, "title": $0.0.title, "remaining_minutes": $0.1] },
        "assumptions": [
            "estimate_factor": (factor * 100).rounded() / 100,
            "focus_minutes": data.settings.focusMinutes,
            "short_break_minutes": data.settings.shortBreakMinutes,
            "todos_without_estimate_minutes": 30,
        ],
    ] as JSON
}

// add_todo

let addTodoSchema: JSON = [
            "type": "object",
            "required": ["title"],
            "properties": [
                "title": ["type": "string"],
                "estimate_minutes": ["type": "integer"],
                "project": ["type": "string", "description": "Project name or ID."],
            ],
        ]

func runAddTodo(_ args: JSON) throws -> Any {
    let data = FocusData()
    guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
        throw ToolError("title is empty.")
    }
    let id = UUID()
    var query = ["id": id.uuidString, "title": title]
    if let minutes = args["estimate_minutes"] as? Int, minutes > 0 { query["minutes"] = "\(minutes)" }
    if let name = args["project"] as? String { query["project"] = try data.findProject(name).id.uuidString }
    try sendToApp("add-todo", query, needsToken: true)
    guard let updated = waitFor({ $0.todos.contains { $0.id == id } }), let todo = updated.todos.first(where: { $0.id == id }) else {
        throw ToolError("FocusFlow did not confirm the new todo. Is the app running?")
    }
    return ["added": todoJSON(todo, updated, factor: updated.estimateFactor.factor)] as JSON
}

// complete_todo

let completeTodoSchema: JSON = [
            "type": "object",
            "required": ["todo"],
            "properties": ["todo": ["type": "string", "description": "Todo ID, or a unique part of its title."]],
        ]

func runCompleteTodo(_ args: JSON) throws -> Any {
    guard let text = args["todo"] as? String else { throw ToolError("todo is missing.") }
    let todo = try FocusData().findTodo(text)
    guard todo.completedAt == nil else { return ["already_done": todo.title] as JSON }
    try sendToApp("complete", ["task": todo.id.uuidString], needsToken: true)
    guard waitFor({ $0.todos.first { $0.id == todo.id }?.completedAt != nil }) != nil else {
        throw ToolError("FocusFlow did not confirm. Is the app running?")
    }
    return ["completed": todo.title] as JSON
}

// start_focus

let startFocusSchema: JSON = [
            "type": "object",
            "properties": [
                "todo": ["type": "string", "description": "Todo ID or a unique part of its title."],
                "project": ["type": "string", "description": "Project name or ID (ignored if todo is given)."],
                "minutes": ["type": "integer", "description": "Length; default is the user's focus length."],
            ],
        ]

func runStartFocus(_ args: JSON) throws -> Any {
    let data = FocusData()
    var query: [String: String] = [:]
    if let text = args["todo"] as? String { query["task"] = try data.findTodo(text).id.uuidString }
    else if let name = args["project"] as? String { query["project"] = try data.findProject(name).id.uuidString }
    if let minutes = args["minutes"] as? Int, minutes > 0 { query["minutes"] = "\(min(minutes, 480))" }
    try sendToApp("focus", query, needsToken: false)
    return ["requested": "FocusFlow starts the session unless one is already running."] as JSON
}

let tools: [Tool] = [
    Tool(name: "get_planning_context",
         description: """
        Everything needed to plan the user's FocusFlow todos into their calendar: open todos with estimates \
        and the minutes to plan for them, projects with weekly goals and progress, pomodoro settings, how \
        accurate the user's estimates are, and the hours they usually focus best. Call this first when asked \
        to plan or schedule todos. Typical flow: get_planning_context → read the calendar's events for the \
        days in question → derive free slots (respect the user's wishes, working hours and focus hours) → \
        plan_focus_blocks → show the plan to the user → only after they agree, create one calendar event per \
        block with its title, description, start and end.
        """,
         schema: getPlanningContextSchema, readOnly: true, run: runGetPlanningContext),
    Tool(name: "list_todos",
         description: "Lists the user's FocusFlow todos, open ones by default, oldest first.",
         schema: listTodosSchema, readOnly: true, run: runListTodos),
    Tool(name: "plan_focus_blocks",
         description: """
        Packs open todos into the given free time slots as focus blocks: todos of one project together, split \
        into pomodoros with breaks, long todos split across blocks. Returns blocks with start, end, a ready \
        calendar title and description (including a link that starts the focus session in FocusFlow), plus \
        the todos that did not fit. Does not create anything; create the calendar events yourself after the \
        user confirmed the plan.
        """,
         schema: planFocusBlocksSchema, readOnly: true, run: runPlanFocusBlocks),
    Tool(name: "add_todo",
         description: "Adds a todo to FocusFlow, optionally with an estimate and a project.",
         schema: addTodoSchema, readOnly: false, run: runAddTodo),
    Tool(name: "complete_todo",
         description: "Marks a FocusFlow todo as done.",
         schema: completeTodoSchema, readOnly: false, run: runCompleteTodo),
    Tool(name: "start_focus",
         description: "Starts a focus session in FocusFlow now, for a todo or a project. Only works while no session runs.",
         schema: startFocusSchema, readOnly: false, run: runStartFocus),
]

// MARK: - JSON-RPC over stdio

func send(_ message: JSON) {
    guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

func reply(_ id: Any, result: JSON) { send(["jsonrpc": "2.0", "id": id, "result": result]) }
func replyError(_ id: Any, code: Int, _ message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func handle(_ message: JSON) {
    let method = message["method"] as? String ?? ""
    guard let id = message["id"] else { return } // Notifications need no answer.
    switch method {
    case "initialize":
        let params = message["params"] as? JSON
        reply(id, result: [
            "protocolVersion": params?["protocolVersion"] as? String ?? "2025-06-18",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "focusflow", "version": "0.1.0"],
            "instructions": """
            FocusFlow is the user's Pomodoro and todo app. Use these tools to see their todos and projects and \
            to plan them into the calendar as focus blocks. Never create calendar events before the user has \
            seen and approved the plan.
            """,
        ])
    case "ping":
        reply(id, result: [:])
    case "tools/list":
        reply(id, result: ["tools": tools.map { tool in
            ["name": tool.name, "description": tool.description, "inputSchema": tool.schema,
             "annotations": ["readOnlyHint": tool.readOnly, "openWorldHint": false]] as JSON
        }])
    case "tools/call":
        let params = message["params"] as? JSON ?? [:]
        guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
            replyError(id, code: -32602, "Unknown tool")
            return
        }
        do {
            let output = try tool.run(params["arguments"] as? JSON ?? [:])
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            var result: JSON = ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]]]
            if let object = output as? JSON { result["structuredContent"] = object }
            reply(id, result: result)
        } catch {
            let text = (error as? ToolError)?.message ?? error.localizedDescription
            reply(id, result: ["content": [["type": "text", "text": text]], "isError": true])
        }
    default:
        replyError(id, code: -32601, "Method not found: \(method)")
    }
}

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: data) as? JSON else { continue }
    handle(message)
}
