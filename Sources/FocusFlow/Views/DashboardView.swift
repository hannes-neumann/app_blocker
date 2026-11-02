import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case focus, projects, todos, stats, settings
    var id: Self { self }

    var title: String {
        switch self {
        case .focus: L10n.text("overview")
        case .projects: L10n.text("projects")
        case .todos: L10n.text("todos")
        case .stats: L10n.text("insights")
        case .settings: L10n.text("settings")
        }
    }

    var symbol: String {
        switch self {
        case .focus: "square.grid.2x2"
        case .projects: "folder"
        case .todos: "checklist"
        case .stats: "chart.xyaxis.line"
        case .settings: "gearshape"
        }
    }
}

/// What the sidebar can select: a page, or one project.
private enum SidebarItem: Hashable {
    case section(DashboardSection)
    case project(UUID)
}

struct DashboardView: View {
    @Environment(AppState.self) private var state
    @State private var creatingProject = false

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    row(.focus)
                    row(.todos).badge(state.todos.open.count)
                    row(.stats)
                }
                Section {
                    Label(L10n.text("allProjects"), systemImage: DashboardSection.projects.symbol)
                        .tag(SidebarItem.section(.projects))
                    ForEach(state.projects.projects) { project in
                        HStack(spacing: 8) {
                            ProjectDot(colorIndex: project.colorIndex, size: 9)
                            Text(project.name).lineLimit(1)
                            Spacer()
                            Text(formatDuration(weekMinutes(project)))
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.project(project.id))
                    }
                    Button { creatingProject = true } label: {
                        Label(L10n.text("newProject"), systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } header: {
                    Text(L10n.text("projects"))
                }
                Section {
                    row(.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            switch state.dashboardSection {
            case .focus: OverviewPage()
            case .projects:
                if let id = state.openProjectID, let project = state.projects.project(id) {
                    ProjectDetailPage(project: project)
                } else {
                    ProjectsOverviewPage()
                }
            case .todos: TodosPage()
            case .stats: InsightsPage()
            case .settings: SettingsView()
            }
        }
        .navigationTitle(title)
        .frame(minWidth: 940, minHeight: 640)
        .sheet(isPresented: $creatingProject) {
            ProjectEditorSheet(project: nil) { project in
                state.openProjectID = project.id
                state.dashboardSection = .projects
            }
        }
    }

    private func row(_ section: DashboardSection) -> some View {
        Label(section.title, systemImage: section.symbol).tag(SidebarItem.section(section))
    }

    private var title: String {
        if state.dashboardSection == .projects, let project = state.projects.project(state.openProjectID) { return project.name }
        return state.dashboardSection.title
    }

    private var selection: Binding<SidebarItem?> {
        Binding {
            if state.dashboardSection == .projects, let id = state.openProjectID { return .project(id) }
            return .section(state.dashboardSection)
        } set: { item in
            switch item {
            case .section(let section):
                state.openProjectID = nil
                state.dashboardSection = section
            case .project(let id):
                state.openProjectID = id
                state.dashboardSection = .projects
                Analytics.track(.projectOpened, ["project_id": .string(id.uuidString), "source": "sidebar"])
            case nil:
                break
            }
        }
    }

    private func weekMinutes(_ project: Project) -> Double {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return state.stats.focusRecords.filter { $0.projectID == project.id && $0.start >= start }
            .reduce(0) { $0 + $1.focusedSeconds / 60 }
    }
}

// MARK: - Overview

private struct OverviewPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let week = InsightsReport(records: state.stats.focusRecords, todos: state.todos.todos, projects: state.projects.projects,
                                  days: 7, dailyGoal: state.settings.dailyGoalMinutes)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greeting
                HStack(alignment: .top, spacing: 18) {
                    TimerHeroCard()
                    VStack(spacing: 18) {
                        TodayCard()
                        if state.phase.isBreak { BreakCard() }
                    }
                    .frame(width: 300)
                }
                BlockingWarnings()
                kpis(week)
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(title: L10n.text("thisWeek"), subtitle: L10n.text("minutesPerDayByProject"))
                        if week.totalMinutes < 1 {
                            EmptyHint(symbol: "chart.bar", text: L10n.text("noFocusYetWeek"))
                        } else {
                            StackedFocusChart(report: week, goal: state.settings.dailyGoalMinutes).frame(height: 210)
                        }
                    }
                    .card()
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(title: L10n.text("insights")) {
                            Button(L10n.text("showAll")) { state.dashboardSection = .stats }.buttonStyle(.link).font(.caption)
                        }
                        InsightList(insights: week.insights, limit: 3)
                    }
                    .card()
                    .frame(width: 320)
                }
                TrackedTodayCard()
                HStack(alignment: .top, spacing: 18) {
                    TodaySessionsCard()
                    UpNextCard()
                }
            }
            .padding(24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
    }

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let key = hour < 11 ? "greetingMorning" : hour < 17 ? "greetingDay" : "greetingEvening"
        return VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(key)).font(.largeTitle.weight(.bold))
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale)))
                .foregroundStyle(.secondary)
        }
    }

    private func kpis(_ week: InsightsReport) -> some View {
        Grid(horizontalSpacing: 14) {
            GridRow {
                StatTile(title: L10n.text("focusThisWeek"), value: formatDuration(week.totalMinutes),
                         detail: L10n.text("vsLastWeekNone"), trend: week.trend, symbol: "timer")
                StatTile(title: L10n.text("sessions"), value: "\(week.sessions)",
                         detail: week.sessions == 0 ? L10n.text("noSessionsYet")
                             : L10n.text("avgSession", formatDuration(week.averageSessionMinutes)),
                         symbol: "repeat")
                StatTile(title: L10n.text("completionRate"),
                         value: week.completionRate.map { "\(Int(($0 * 100).rounded()))" } ?? "–", unit: week.completionRate == nil ? "" : "%",
                         detail: L10n.text("completionRateDetail"), progress: week.completionRate, symbol: "checkmark.seal")
                StatTile(title: L10n.text("streak"), value: "\(state.stats.streak)",
                         unit: L10n.text(state.stats.streak == 1 ? "day" : "days"),
                         detail: L10n.text("goalDaysThisWeek", week.goalDays), symbol: "flame")
            }
        }
    }
}

/// The timer itself, with the project the session counts for.
private struct TimerHeroCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let project = state.selectedProject
        let color = state.phase.isBreak ? Color.green : project?.color ?? .accentColor
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.phase.title, systemImage: state.phase.symbol).font(.title3.weight(.semibold))
                Spacer()
                Text(state.cycleText).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 28) {
                Ring(progress: state.phase == .idle ? 0 : state.progress, color: color, lineWidth: 12) {
                    VStack(spacing: 4) {
                        Text(state.phase == .idle ? String(format: "%02d:00", state.settings.focusMinutes) : state.remainingText)
                            .font(.system(size: 46, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if state.phase != .idle {
                            HStack(spacing: 5) {
                                if !state.phase.isBreak { ProjectDot(colorIndex: project?.colorIndex, size: 8) }
                                Text(state.phase.isBreak ? state.phase.title : project?.name ?? L10n.text("noProject"))
                                    .lineLimit(1)
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                }
                .frame(width: 210, height: 210)
                VStack(alignment: .leading, spacing: 16) {
                    if state.phase == .focus {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text("workingOn")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                if let project { ProjectIcon(project: project, size: 26) }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(project?.name ?? L10n.text("noProject")).font(.headline)
                                    if let task = state.selectedTask { Text(task.title).foregroundStyle(.secondary).lineLimit(2) }
                                }
                            }
                        }
                    } else {
                        FocusTargetPicker()
                    }
                    TimerControls(large: true)
                    Text(blockingSummary).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card(padding: 22)
    }

    private var blockingSummary: String {
        let apps = state.activeBlockedApps.count
        let domains = state.settings.blockDomains ? state.settings.blockedDomains.count : 0
        return L10n.text("blockingSummary", apps, domains)
    }
}

private struct TodayCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let today = state.stats.todayFocusMinutes
        let goal = state.settings.dailyGoalMinutes
        let sessions = state.stats.focusRecords.filter { Calendar.current.isDateInToday($0.start) }.count
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("today")).font(.headline)
            HStack(spacing: 16) {
                Ring(progress: today / Double(max(goal, 1)), color: .accentColor, lineWidth: 9) {
                    VStack(spacing: 0) {
                        Text("\(Int((min(today / Double(max(goal, 1)), 9.99) * 100).rounded()))%")
                            .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(L10n.text("ofGoal")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(today))").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("/ \(goal) \(L10n.text("minUnit"))").foregroundStyle(.secondary)
                    }
                    Text(L10n.text(sessions == 1 ? "sessionsTodayOne" : "sessionsToday", sessions)).font(.callout).foregroundStyle(.secondary)
                    Text(today >= Double(goal) ? L10n.text("goalReached") : L10n.text("minutesLeft", goal - Int(today)))
                        .font(.caption).foregroundStyle(today >= Double(goal) ? .green : .secondary)
                }
            }
        }
        .card()
    }
}

/// During a break: assign the session that just ended and see what fits into the break.
private struct BreakCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let record = state.lastFocusRecord {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("lastSession")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    SessionRow(record: record)
                }
                Divider()
            }
            Text(L10n.text("breakSuggestion")).font(.headline)
            if let todo = state.suggestion {
                Text(todo.title).fixedSize(horizontal: false, vertical: true)
                if let minutes = todo.estimatedMinutes { EstimateBadge(minutes: minutes) }
                HStack {
                    Button(L10n.text("done")) { state.completeSuggestion() }
                    Button(L10n.text("nextSuggestion")) { state.nextSuggestion() }
                }
            } else {
                Text(L10n.text("noPauseTask")).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TodaySessionsCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let sessions = state.stats.focusRecords.filter { Calendar.current.isDateInToday($0.start) }.sorted { $0.start > $1.start }
        let unassigned = sessions.filter { $0.projectID == nil }.count
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: L10n.text("todaysSessions"),
                       subtitle: unassigned > 0 ? L10n.text("unassignedHint", unassigned) : L10n.text("sessionsAssignHint"))
            if sessions.isEmpty {
                EmptyHint(symbol: "timer", text: L10n.text("noSessionsToday"))
            } else {
                DayTimeline(spans: sessions.map { record in
                    let project = state.projects.project(record.projectID)
                    return TimelineSpan(id: record.id, start: record.start, end: record.end,
                                        color: project?.color ?? ProjectPalette.none, help: project?.name ?? L10n.text("noProject"))
                })
                VStack(spacing: 0) {
                    ForEach(sessions.prefix(6)) { record in
                        SessionRow(record: record)
                        if record.id != sessions.prefix(6).last?.id { Divider() }
                    }
                }
            }
        }
        .card()
    }
}

/// One colored span on a `DayTimeline`.
struct TimelineSpan: Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let color: Color
    let help: String
}

/// Today's sessions or tracked activity as colored blocks on a time axis.
struct DayTimeline: View {
    let spans: [TimelineSpan]

    var body: some View {
        let calendar = Calendar.current
        let hours = spans.flatMap { [calendar.component(.hour, from: $0.start), calendar.component(.hour, from: $0.end)] }
        let first = max(0, min(hours.min() ?? 8, 8))
        let last = min(24, max((hours.max() ?? 18) + 1, 18))
        let dayStart = calendar.startOfDay(for: Date())
        let span = Double(last - first) * 3600
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05))
                    ForEach(spans) { item in
                        let offset = item.start.timeIntervalSince(dayStart) - Double(first) * 3600
                        let width = max(item.end.timeIntervalSince(item.start), 60)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.color)
                            .frame(width: max(3, geo.size.width * width / span))
                            .offset(x: geo.size.width * offset / span)
                            .help(item.help)
                    }
                }
            }
            .frame(height: 18)
            HStack {
                ForEach(Array(stride(from: first, through: last, by: max(1, (last - first) / 4))), id: \.self) { hour in
                    Text(L10n.text("hourLabel", hour)).font(.caption2).foregroundStyle(.secondary)
                    if hour < last { Spacer() }
                }
            }
        }
    }
}

private struct UpNextCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let open = state.todos.open
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: L10n.text("upNext"), subtitle: L10n.text("aboutTotal", formatMinutes(open.compactMap(\.estimatedMinutes).reduce(0, +)))) {
                if open.count > 5 {
                    Button(L10n.text("allTodos", open.count)) { state.dashboardSection = .todos }.buttonStyle(.link).font(.caption)
                }
            }
            NoteField()
            if open.isEmpty {
                EmptyHint(symbol: "tray", text: L10n.text("noOpenTasks"))
            } else {
                VStack(spacing: 0) {
                    ForEach(open.prefix(5)) { todo in
                        DashboardTodoRow(todo: todo)
                        if todo.id != open.prefix(5).last?.id { Divider() }
                    }
                }
            }
        }
        .card()
    }
}

struct EmptyHint: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }
}

// MARK: - Todos

private struct TodosPage: View {
    @Environment(AppState.self) private var state
    @State private var showDone = false
    @State private var projectFilter: UUID??

    var body: some View {
        let base = showDone ? state.todos.done : state.todos.open
        let todos = projectFilter.map { filter in base.filter { $0.projectID == filter } } ?? base
        let total = todos.filter { !$0.isDone }.compactMap(\.estimatedMinutes).reduce(0, +)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker(L10n.text("show"), selection: $showDone) {
                    Text(L10n.text("openTasks", state.todos.open.count)).tag(false)
                    Text(L10n.text("completedTasks", state.todos.done.count)).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: showDone) { Analytics.track(.todoListFilterChanged, ["filter": showDone ? "done" : "open"]) }
                Picker(L10n.text("project"), selection: $projectFilter) {
                    Text(L10n.text("allProjects")).tag(UUID??.none)
                    Text(L10n.text("noProject")).tag(UUID??.some(nil))
                    ForEach(state.projects.projects) { project in
                        Text(project.name).tag(UUID??.some(project.id))
                    }
                }
                .fixedSize()
                Spacer()
                if showDone {
                    Button(L10n.text("clearCompleted")) { state.todos.clearDone(source: "dashboard") }
                        .disabled(state.todos.done.isEmpty)
                } else {
                    Text(L10n.text("aboutTotal", formatMinutes(total))).foregroundStyle(.secondary)
                }
            }
            if !showDone { NoteField() }

            if todos.isEmpty {
                ContentUnavailableView(L10n.text(showDone ? "nothingDoneYet" : "noOpenTasks"),
                                       systemImage: showDone ? "checkmark.circle" : "tray",
                                       description: Text(showDone ? "" : L10n.text("captureHint", AppState.shortcutDescription)))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(todos) { todo in
                            DashboardTodoRow(todo: todo, showProject: true)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}

/// Adds a note that is turned into todos, like the quick capture.
struct NoteField: View {
    @Environment(AppState.self) private var state
    @State private var text = ""

    var body: some View {
        TextField(L10n.text("noteFieldPlaceholder"), text: $text)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                state.todos.capture(text, source: "dashboard")
                text = ""
            }
    }
}

struct DashboardTodoRow: View {
    @Environment(AppState.self) private var state
    let todo: Todo
    var showProject = false
    @State private var title = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { state.todos.toggleDone(todo.id, source: "dashboard") } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(todo.isRefining)

            VStack(alignment: .leading, spacing: 3) {
                TextField(L10n.text("title"), text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .focused($editing)
                    .disabled(todo.isRefining)
                    .onSubmit(saveTitle)
                    .onChange(of: editing) { _, isEditing in if !isEditing { saveTitle() } }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if showProject && !todo.isRefining { projectMenu }
            if todo.isRefining {
                ProgressView().controlSize(.small)
            } else {
                if todo.refinedByAI {
                    Image(systemName: "sparkles").foregroundStyle(.purple)
                        .help(L10n.text("refinedByAI"))
                }
                EstimateControl(todo: todo)
            }
            Button { state.todos.delete(todo.id, source: "dashboard") } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.text("delete"))
        }
        .padding(.vertical, 8)
        .onAppear { title = todo.title }
        .onChange(of: todo.title) { _, new in if !editing { title = new } }
    }

    private var projectMenu: some View {
        let project = state.projects.project(todo.projectID)
        return Menu {
            Button(L10n.text("noProject")) { state.todos.setProject(todo.id, projectID: nil) }
            Divider()
            ForEach(state.projects.projects) { item in
                Button(item.name) { state.todos.setProject(todo.id, projectID: item.id) }
            }
        } label: {
            HStack(spacing: 5) {
                ProjectDot(colorIndex: project?.colorIndex, size: 7)
                Text(project?.name ?? L10n.text("noProject")).font(.caption)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.text("moveToProject"))
    }

    private var detail: String {
        var parts: [String] = []
        if todo.sourceNote != todo.title { parts.append(L10n.text("notePrefix", todo.sourceNote)) }
        let relative = Date.RelativeFormatStyle(presentation: .named).locale(L10n.locale)
        if let done = todo.completedAt {
            parts.append(L10n.text("completedAgo", done.formatted(relative)))
        } else {
            parts.append(L10n.text("notedAgo", todo.createdAt.formatted(relative)))
        }
        return parts.joined(separator: " · ")
    }

    private func saveTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { title = todo.title } else if trimmed != todo.title { state.todos.setTitle(todo.id, title: trimmed) }
    }
}
