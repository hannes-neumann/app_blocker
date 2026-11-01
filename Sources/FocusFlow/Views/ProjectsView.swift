import AppKit
import Charts
import SwiftUI

private struct ProjectAppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.dashed").frame(width: 20, height: 20)
        }
    }
}

// MARK: - All projects

struct ProjectsOverviewPage: View {
    @Environment(AppState.self) private var state
    @State private var creating = false

    var body: some View {
        let month = InsightsReport(records: state.stats.focusRecords, todos: state.todos.todos, projects: state.projects.projects,
                                   days: 30, dailyGoal: state.settings.dailyGoalMinutes)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("projects")).font(.largeTitle.weight(.bold))
                        Text(L10n.text("projectsSubtitle")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { creating = true } label: { Label(L10n.text("newProject"), systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                if state.projects.projects.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 44)).foregroundStyle(.tertiary)
                        Text(L10n.text("noProjectsTitle")).font(.title3.weight(.semibold))
                        Text(L10n.text("noProjectsText")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                        Button(L10n.text("createFirstProject")) { creating = true }.buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                    .card()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(state.projects.projects) { ProjectCard(project: $0) }
                        Button { creating = true } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus").font(.title2)
                                Text(L10n.text("newProject"))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 170)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if month.totalMinutes >= 1 {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 14) {
                                CardHeader(title: L10n.text("last30Days"), subtitle: L10n.text("minutesPerDayByProject"))
                                StackedFocusChart(report: month).frame(height: 200)
                            }
                            .card()
                            VStack(alignment: .leading, spacing: 14) {
                                CardHeader(title: L10n.text("projectShare"), subtitle: L10n.text("last30Days"))
                                ProjectShareList(report: month)
                            }
                            .card()
                            .frame(width: 320)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $creating) {
            ProjectEditorSheet(project: nil) { project in state.openProjectID = project.id }
        }
    }
}

private struct ProjectCard: View {
    @Environment(AppState.self) private var state
    let project: Project
    @State private var hovering = false

    var body: some View {
        let records = state.stats.focusRecords.filter { $0.projectID == project.id }
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let week = records.filter { $0.start >= weekStart }.reduce(0) { $0 + $1.focusedSeconds / 60 }
        let total = records.reduce(0) { $0 + $1.focusedSeconds / 60 }
        let openTasks = state.todos.open.filter { $0.projectID == project.id }.count
        let spark = sparkline(records)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProjectIcon(project: project, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(.headline).lineLimit(1)
                    Text(L10n.text(openTasks == 1 ? "openTasksOne" : "openTasksCount", openTasks)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.startFocus(for: project, source: "project_card") } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 28, height: 28)
                        .background(project.color.opacity(0.15), in: Circle())
                        .foregroundStyle(project.color)
                }
                .buttonStyle(.plain)
                .disabled(state.phase != .idle)
                .help(L10n.text("startFocusForProject"))
            }
            Chart {
                ForEach(Array(spark.enumerated()), id: \.offset) { index, minutes in
                    BarMark(x: .value("day", String(index)), y: .value("minutes", minutes), width: .ratio(0.7))
                        .foregroundStyle(project.color.opacity(index == spark.count - 1 ? 1 : 0.7))
                        .cornerRadius(2)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 40)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(formatDuration(week)).font(.title3.weight(.semibold)).monospacedDigit()
                    Text(L10n.text("thisWeek")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatDuration(total)).font(.callout.weight(.medium)).monospacedDigit()
                    Text(L10n.text("total")).font(.caption).foregroundStyle(.secondary)
                }
            }
            // The row is always there, so cards with and without a weekly goal line up.
            if let goal = project.weeklyGoalMinutes, goal > 0 {
                ProgressView(value: min(week / Double(goal), 1)).tint(project.color).controlSize(.small)
                    .help(L10n.text("weeklyGoalProgress", Int(week), goal))
            } else {
                Text(L10n.text("noWeeklyGoal")).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .card(padding: 16)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(project.color.opacity(hovering ? 0.8 : 0), lineWidth: 1.5))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            state.openProjectID = project.id
            state.dashboardSection = .projects
            Analytics.track(.projectOpened, ["project_id": .string(project.id.uuidString), "source": "card"])
        }
    }

    /// Minutes per day for the last 14 days, oldest first.
    private func sparkline(_ records: [FocusRecord]) -> [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var values = Array(repeating: 0.0, count: 14)
        for record in records {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: record.start), to: today).day ?? 99
            if (0..<14).contains(days) { values[13 - days] += record.focusedSeconds / 60 }
        }
        return values
    }
}

// MARK: - One project

struct ProjectDetailPage: View {
    @Environment(AppState.self) private var state
    let project: Project
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var range = 30

    var body: some View {
        let report = InsightsReport(records: state.stats.focusRecords, todos: state.todos.todos, projects: state.projects.projects,
                                    days: range, dailyGoal: 0, projectFilter: project.id)
        let allRecords = state.stats.focusRecords.filter { $0.projectID == project.id }
        let total = allRecords.reduce(0) { $0 + $1.focusedSeconds / 60 }
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let week = allRecords.filter { $0.start >= weekStart }.reduce(0) { $0 + $1.focusedSeconds / 60 }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Grid(horizontalSpacing: 14) {
                    GridRow {
                        StatTile(title: L10n.text("thisWeek"), value: formatDuration(week),
                                 detail: project.weeklyGoalMinutes.map { L10n.text("ofWeeklyGoal", formatDuration(Double($0))) } ?? L10n.text("noWeeklyGoal"),
                                 progress: project.weeklyGoalMinutes.map { week / Double(max($0, 1)) }, symbol: "calendar")
                        StatTile(title: L10n.text("total"), value: formatDuration(total),
                                 detail: L10n.text("sinceDate", project.createdAt.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.locale))),
                                 symbol: "sum")
                        StatTile(title: L10n.text("sessions"), value: "\(allRecords.count)",
                                 detail: allRecords.isEmpty ? L10n.text("noSessionsYet")
                                     : L10n.text("avgSession", formatDuration(total / Double(allRecords.count))), symbol: "repeat")
                        StatTile(title: L10n.text("lastPeriod", range), value: formatDuration(report.totalMinutes),
                                 detail: L10n.text("vsLastWeekNone"), trend: report.trend, symbol: "chart.line.uptrend.xyaxis")
                    }
                }
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(title: L10n.text("focusTime"), subtitle: L10n.text("minutesPerDay")) {
                            Picker(L10n.text("period"), selection: $range) {
                                Text(L10n.text("sevenDays")).tag(7)
                                Text(L10n.text("thirtyDays")).tag(30)
                                Text(L10n.text("ninetyDays")).tag(90)
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                        }
                        if report.totalMinutes < 1 {
                            EmptyHint(symbol: "chart.bar", text: L10n.text("noProjectFocusYet"))
                        } else {
                            StackedFocusChart(report: report).frame(height: 200)
                        }
                    }
                    .card()
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(title: L10n.text("whenYouWork"), subtitle: L10n.text("minutesByHour"))
                        HourChart(minutes: report.minutesByHour, color: project.color).frame(height: 200)
                    }
                    .card()
                    .frame(width: 340)
                }
                HStack(alignment: .top, spacing: 18) {
                    ProjectTasksCard(project: project)
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: L10n.text("recentSessions"), subtitle: L10n.text("sessionsAssignHint"))
                        if allRecords.isEmpty {
                            EmptyHint(symbol: "timer", text: L10n.text("noProjectFocusYet"))
                        } else {
                            VStack(spacing: 0) {
                                let recent = allRecords.sorted { $0.start > $1.start }.prefix(8)
                                ForEach(recent) { record in
                                    SessionRow(record: record, showDate: true)
                                    if record.id != recent.last?.id { Divider() }
                                }
                            }
                        }
                    }
                    .card()
                }
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: L10n.text("blockingForProject"), subtitle: L10n.text("blockingForProjectHint"))
                    AppOverrideEditor(value: project.blockedApps) { state.projects.setBlockedApps($0, for: project.id) }
                }
                .card()
            }
            .padding(24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $editing) { ProjectEditorSheet(project: project) }
        .confirmationDialog(L10n.text("deleteProjectTitle", project.name), isPresented: $confirmDelete) {
            Button(L10n.text("delete"), role: .destructive) { state.deleteProject(project.id) }
        } message: {
            Text(L10n.text("deleteProjectMessage"))
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { state.openProjectID = nil } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .help(L10n.text("allProjects"))
            ProjectIcon(project: project, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.largeTitle.weight(.bold)).lineLimit(1)
                let openCount = state.todos.open.filter { $0.projectID == project.id }.count
                Text(L10n.text(openCount == 1 ? "openTasksOne" : "openTasksCount", openCount))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { state.startFocus(for: project, source: "project_page") } label: {
                Label(L10n.text("startFocusForProject"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(project.color)
            .controlSize(.large)
            .disabled(state.phase != .idle)
            Menu {
                Button(L10n.text("editProject") + "…") { editing = true }
                Divider()
                Button(L10n.text("deleteProject") + "…", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title2)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

private struct ProjectTasksCard: View {
    @Environment(AppState.self) private var state
    let project: Project
    @State private var taskTitle = ""
    @State private var showDone = false

    var body: some View {
        let tasks = state.todos.todos.filter { $0.projectID == project.id }
        let open = tasks.filter { !$0.isDone }.sorted { $0.createdAt < $1.createdAt }
        let done = tasks.filter(\.isDone)
        let focus = focusPerTask
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: L10n.text("tasks"),
                       subtitle: L10n.text("aboutTotal", formatMinutes(open.compactMap(\.estimatedMinutes).reduce(0, +))))
            HStack {
                TextField(L10n.text("newTaskPlaceholder"), text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button(L10n.text("add"), action: addTask)
                    .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if open.isEmpty && done.isEmpty {
                EmptyHint(symbol: "checklist", text: L10n.text("noTasksInProject"))
            }
            VStack(spacing: 0) {
                ForEach(open) { task in
                    TaskRow(task: task, project: project, focusMinutes: focus[task.id] ?? 0)
                    Divider()
                }
            }
            if !done.isEmpty {
                DisclosureGroup(L10n.text("completedTasks", done.count), isExpanded: $showDone) {
                    VStack(spacing: 0) {
                        ForEach(done) { task in
                            TaskRow(task: task, project: project, focusMinutes: focus[task.id] ?? 0)
                            Divider()
                        }
                    }
                }
            }
        }
        .card()
    }

    private var focusPerTask: [UUID: Double] {
        var result: [UUID: Double] = [:]
        for record in state.stats.focusRecords { if let id = record.taskID { result[id, default: 0] += record.focusedSeconds / 60 } }
        return result
    }

    private func addTask() {
        state.todos.addTask(title: taskTitle, projectID: project.id)
        taskTitle = ""
    }
}

private struct TaskRow: View {
    @Environment(AppState.self) private var state
    let task: Todo
    let project: Project
    let focusMinutes: Double
    @State private var expanded = false
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { state.todos.toggleDone(task.id, source: "projects") } label: {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isDone ? .green : .secondary)
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 3) {
                    TextField(L10n.text("task"), text: $title)
                        .textFieldStyle(.plain)
                        .strikethrough(task.isDone)
                        .onSubmit { state.todos.setTitle(task.id, title: title) }
                    if focusMinutes >= 1 || task.estimatedMinutes != nil { progressLine }
                }
                Spacer()
                if !task.isDone {
                    Button {
                        state.selectedTaskID = task.id
                        state.startFocus(for: project, source: "project_task")
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(state.phase != .idle)
                    .help(L10n.text("startFocusOnTask"))
                }
                EstimateControl(todo: task)
                Button { expanded.toggle() } label: {
                    Image(systemName: task.blockedApps == nil ? "app.dashed" : "app.badge.checkmark")
                }
                .buttonStyle(.borderless)
                .help(L10n.text("appsForTask"))
                Button { state.todos.delete(task.id, source: "projects") } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            if expanded {
                AppOverrideEditor(value: task.blockedApps) { state.todos.setBlockedApps($0, for: task.id) }
                    .padding(.leading, 30)
            }
        }
        .padding(.vertical, 7)
        .onAppear { title = task.title }
        .onChange(of: task.title) { _, value in title = value }
    }

    /// Focused time against the estimate, so it shows when a task takes longer than planned.
    private var progressLine: some View {
        let estimate = Double(task.estimatedMinutes ?? 0)
        let over = estimate > 0 && focusMinutes > estimate
        return HStack(spacing: 8) {
            if estimate > 0 {
                ProgressView(value: min(focusMinutes / estimate, 1))
                    .tint(over ? .orange : project.color)
                    .frame(width: 90)
                    .controlSize(.mini)
            }
            Text(estimate > 0 ? L10n.text("focusedOfEstimate", formatDuration(focusMinutes), formatDuration(estimate))
                 : L10n.text("focusedOnly", formatDuration(focusMinutes)))
                .font(.caption).foregroundStyle(over ? .orange : .secondary)
            if over { Image(systemName: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
        }
    }
}

private struct AppOverrideEditor: View {
    let value: [BlockedApp]?
    let onChange: ([BlockedApp]?) -> Void
    @State private var custom = false
    @State private var apps: [BlockedApp] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L10n.text("ownAppRule"), isOn: $custom)
                .onChange(of: custom) { _, enabled in onChange(enabled ? apps : nil) }
            if custom {
                if apps.isEmpty {
                    Text(L10n.text("noBlockedApps")).foregroundStyle(.secondary)
                }
                ForEach(apps) { app in
                    HStack {
                        ProjectAppIcon(bundleID: app.bundleID)
                        Text(app.name)
                        Spacer()
                        Button { apps.removeAll { $0 == app }; onChange(apps) } label: {
                            Image(systemName: "minus.circle.fill")
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    Button(L10n.text("chooseApp"), action: chooseApps)
                    Menu(L10n.text("runningApp")) {
                        ForEach(runningApps, id: \.bundleID) { app in
                            Button(app.name) { apps.append(app); onChange(apps) }
                        }
                    }
                    .fixedSize()
                }
            } else {
                Text(L10n.text("inheritRule")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { custom = value != nil; apps = value ?? [] }
    }

    private var runningApps: [BlockedApp] {
        let existing = Set(apps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, !existing.contains(id) else { return nil }
                return BlockedApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !apps.contains(where: { $0.bundleID == id }) else { continue }
            apps.append(BlockedApp(bundleID: id,
                                   name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")))
        }
        onChange(apps)
    }
}
