import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case focus, projects, todos, stats, settings
    var id: Self { self }

    var title: String {
        switch self {
        case .focus: "Fokus"
        case .projects: "Projekte"
        case .todos: "Todos"
        case .stats: "Statistik"
        case .settings: "Einstellungen"
        }
    }

    var symbol: String {
        switch self {
        case .focus: "timer"
        case .projects: "folder"
        case .todos: "checklist"
        case .stats: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}

struct DashboardView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $state.dashboardSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(section == .todos ? state.todos.open.count : 0)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch state.dashboardSection {
            case .focus: FocusPage()
            case .projects: ProjectsView()
            case .todos: TodosPage()
            case .stats: StatsView()
            case .settings: SettingsView()
            }
        }
        .navigationTitle(state.dashboardSection.title)
        .frame(minWidth: 860, minHeight: 600)
    }
}

// MARK: - Focus

private struct FocusPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    timerCard
                    VStack(spacing: 12) {
                        todayCard
                        if state.phase.isBreak { suggestionCard }
                    }
                    .frame(width: 280)
                }
                BlockingWarnings()
                upNextCard
            }
            .padding(24)
        }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.phase.title, systemImage: state.phase.symbol).font(.title3.weight(.semibold))
                Spacer()
                Text(state.cycleText).foregroundStyle(.secondary)
            }
            Text(state.phase == .idle ? String(format: "%02d:00", state.settings.focusMinutes) : state.remainingText)
                .font(.system(size: 88, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            ProgressView(value: state.progress)
                .tint(state.phase.isBreak ? .green : .accentColor)
            TaskPicker()
            TimerControls(large: true)
            Text(blockingSummary).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .card()
    }

    private var blockingSummary: String {
        let apps = state.activeBlockedApps.count
        let domains = state.settings.blockDomains ? state.settings.blockedDomains.count : 0
        return "Im Fokus blockiert: \(apps) \(apps == 1 ? "App" : "Apps") · \(domains) \(domains == 1 ? "Webseite" : "Webseiten")"
    }

    private struct TaskPicker: View {
        @Environment(AppState.self) private var state

        var body: some View {
            Picker("Fokusaufgabe", selection: Binding(
                get: { state.selectedTaskID },
                set: { state.selectedTaskID = $0 }
            )) {
                Text("Kein Projekt / keine Aufgabe").tag(UUID?.none)
                ForEach(state.projects.projects) { project in
                    Section(project.name) {
                        ForEach(state.todos.open.filter { $0.projectID == project.id }) { task in
                            Text(task.title).tag(UUID?.some(task.id))
                        }
                    }
                }
            }
            .labelsHidden()
            .disabled(state.phase != .idle)
        }
    }

    private var todayCard: some View {
        let today = Int(state.stats.todayFocusMinutes)
        let goal = state.settings.dailyGoalMinutes
        let streak = state.stats.streak
        return VStack(alignment: .leading, spacing: 10) {
            Text("Heute").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(today)").font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("/ \(goal) Min").foregroundStyle(.secondary)
            }
            ProgressView(value: Double(min(today, goal)), total: Double(max(goal, 1)))
            Text(streak > 0 ? "Serie: \(streak) \(streak == 1 ? "Tag" : "Tage") in Folge" : "Starte heute deine Serie")
                .font(.caption).foregroundStyle(.secondary)
            Button("Statistik ansehen") { state.dashboardSection = .stats }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var suggestionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vorschlag für die Pause").font(.headline)
            if let todo = state.suggestion {
                Text(todo.title).fixedSize(horizontal: false, vertical: true)
                if let minutes = todo.estimatedMinutes { EstimateBadge(minutes: minutes) }
                HStack {
                    Button("Erledigt") { state.completeSuggestion() }
                    Button("Anderer") { state.nextSuggestion() }
                }
            } else {
                Text("Nichts passt rein, einfach durchatmen.").foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var upNextCard: some View {
        let open = state.todos.open
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Als Nächstes").font(.headline)
                Spacer()
                if open.count > 5 {
                    Button("Alle \(open.count) Todos") { state.dashboardSection = .todos }.buttonStyle(.link)
                }
            }
            NoteField()
            if open.isEmpty {
                Text("Keine offenen Todos.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(open.prefix(5)) { todo in
                        DashboardTodoRow(todo: todo)
                        if todo.id != open.prefix(5).last?.id { Divider() }
                    }
                }
            }
        }
        .padding(20)
        .card()
    }
}

// MARK: - Todos

private struct TodosPage: View {
    @Environment(AppState.self) private var state
    @State private var showDone = false

    var body: some View {
        let todos = showDone ? state.todos.done : state.todos.open
        let total = state.todos.open.compactMap(\.estimatedMinutes).reduce(0, +)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Anzeigen", selection: $showDone) {
                    Text("Offen (\(state.todos.open.count))").tag(false)
                    Text("Erledigt (\(state.todos.done.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if showDone {
                    Button("Erledigte löschen") { state.todos.clearDone() }
                        .disabled(todos.isEmpty)
                } else {
                    Text("Zusammen etwa \(formatMinutes(total))").foregroundStyle(.secondary)
                }
            }
            if !showDone { NoteField() }

            if todos.isEmpty {
                ContentUnavailableView(showDone ? "Noch nichts erledigt" : "Keine offenen Todos",
                                       systemImage: showDone ? "checkmark.circle" : "tray",
                                       description: Text(showDone ? "" : "Notiere etwas oben oder überall mit \(AppState.shortcutDescription)."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(todos) { todo in
                            DashboardTodoRow(todo: todo)
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
private struct NoteField: View {
    @Environment(AppState.self) private var state
    @State private var text = ""

    var body: some View {
        TextField("Notiz hinzufügen, wird zu Todos mit Zeitschätzung…", text: $text)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                state.todos.capture(text)
                text = ""
            }
    }
}

private struct DashboardTodoRow: View {
    @Environment(AppState.self) private var state
    let todo: Todo
    @State private var title = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { state.todos.toggleDone(todo.id) } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(todo.isRefining)

            VStack(alignment: .leading, spacing: 3) {
                TextField("Titel", text: $title, axis: .vertical)
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

            if todo.isRefining {
                ProgressView().controlSize(.small)
            } else {
                if todo.refinedByAI {
                    Image(systemName: "sparkles").foregroundStyle(.purple)
                        .help("Von Apple Intelligence formuliert und geschätzt")
                }
                EstimateControl(todo: todo)
            }
            Button { state.todos.delete(todo.id) } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Löschen")
        }
        .padding(.vertical, 8)
        .onAppear { title = todo.title }
        .onChange(of: todo.title) { _, new in if !editing { title = new } }
    }

    private var detail: String {
        var parts: [String] = []
        if todo.sourceNote != todo.title { parts.append("Notiz: \(todo.sourceNote)") }
        if let done = todo.completedAt {
            parts.append("erledigt \(done.formatted(.relative(presentation: .named)))")
        } else {
            parts.append("notiert \(todo.createdAt.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private func saveTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { title = todo.title } else if trimmed != todo.title { state.todos.setTitle(todo.id, title: trimmed) }
    }
}

private extension View {
    func card() -> some View {
        background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
