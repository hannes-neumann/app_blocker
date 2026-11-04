import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.phase == .idle {
            Image(systemName: "timer")
        } else {
            HStack(spacing: 4) {
                Image(systemName: state.isPaused ? "pause.fill" : state.phase.symbol)
                Text(state.remainingText).monospacedDigit()
            }
        }
    }
}

struct MenuContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var newNote = ""
    @State private var showDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            timerSection
            todaySummary
            BlockingWarnings()
            if state.phase.isBreak { suggestionSection }
            Divider()
            todoSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            state.refreshSuggestion()
            Analytics.track(.menuOpened, ["phase": .string(state.phase.rawValue)])
        }
    }

    // MARK: Timer

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.phase.title, systemImage: state.phase.symbol)
                    .font(.headline)
                Spacer()
                Text(state.cycleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(state.phase == .idle ? formatClock(state.settings.focusMinutes) : state.remainingText)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            ProgressView(value: state.progress)
                .tint(state.phase.isBreak ? .green : state.selectedProject?.color ?? .accentColor)

            if state.phase == .focus {
                HStack(spacing: 6) {
                    ProjectDot(colorIndex: state.selectedProject?.colorIndex, size: 8)
                    Text(state.selectedTask?.title ?? state.selectedProject?.name ?? L10n.text("noProject"))
                        .lineLimit(1)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                FocusTargetPicker(compact: true)
            }
            TimerControls()
        }
    }

    private var todaySummary: some View {
        let today = Int(state.stats.todayFocusMinutes)
        let goal = state.settings.dailyGoalMinutes
        let streak = state.stats.streak
        return Button {
            dismiss()
            state.panels.showDashboard(.stats, source: "menu_streak")
        } label: {
            HStack(spacing: 10) {
                Gauge(value: Double(min(today, goal)), in: 0...Double(max(goal, 1))) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .scaleEffect(0.45)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.text("todaySummary", today, goal)).font(.callout.weight(.medium))
                    Text(streak > 0 ? L10n.text(streak == 1 ? "streakOneDay" : "streakDays", streak) : L10n.text("startStreak"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.text("statistics")).font(.caption)
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(.primary)
            .padding(8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let record = state.lastFocusRecord {
                Text(L10n.text("lastSession")).font(.caption).foregroundStyle(.secondary)
                SessionRow(record: record)
                Divider()
            }
            Text(L10n.text("breakSuggestion")).font(.caption).foregroundStyle(.secondary)
            if let todo = state.suggestion {
                HStack {
                    Text(todo.title).fontWeight(.medium)
                    Spacer()
                    if let minutes = todo.estimatedMinutes { EstimateBadge(minutes: minutes) }
                }
                HStack {
                    Button(L10n.text("done")) { state.completeSuggestion() }
                    Button(L10n.text("nextSuggestion")) { state.nextSuggestion() }
                }
                .controlSize(.small)
            } else {
                Text(L10n.text("noPauseTask")).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Todos

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("todos")).font(.headline)
                Spacer()
                Text(L10n.text("quickNoteShortcut", AppState.shortcutDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField(L10n.text("addNote"), text: $newNote)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    state.todos.capture(newNote, source: "menu")
                    newNote = ""
                }

            let open = state.todos.open
            if open.isEmpty {
                Text(L10n.text("noOpenTasks"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(open) { TodoRow(todo: $0) }
                    }
                }
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: open.count < 7)
            }

            let done = state.todos.done
            if !done.isEmpty {
                DisclosureGroup(L10n.text("completedTasks", done.count), isExpanded: $showDone) {
                    VStack(spacing: 2) {
                        ForEach(done.prefix(10)) { TodoRow(todo: $0) }
                    }
                    Button(L10n.text("clearCompleted")) { state.todos.clearDone(source: "menu") }
                        .controlSize(.small)
                }
                .font(.callout)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(L10n.text("dashboard")) {
                dismiss()
                state.panels.showDashboard(.focus, source: "menu")
            }
            Button(L10n.text("settings") + "…") {
                dismiss()
                state.panels.showDashboard(.settings, source: "menu")
            }
            Spacer()
            Button(L10n.text("quit")) { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
    }

    private func formatClock(_ minutes: Int) -> String {
        String(format: "%02d:00", minutes)
    }
}

struct TodoRow: View {
    @Environment(AppState.self) private var state
    let todo: Todo
    @State private var hovering = false
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { state.todos.toggleDone(todo.id, source: "menu") } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // Tooltips don't show while a menu-bar app is inactive, so a click reveals the full text instead.
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: expanded)
                if expanded && todo.sourceNote != todo.title {
                    Text(L10n.text("notePrefix", todo.sourceNote))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }

            Spacer(minLength: 4)

            if todo.isRefining {
                Image(systemName: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(L10n.text("refinePending"))
            } else if todo.refinedByAI {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .help(L10n.text("refinedByAI"))
            }
            EstimateControl(todo: todo)

            // Always laid out and only faded in, so hovering never changes the row's size
            // (which would make the whole menu window jump).
            Button { state.todos.delete(todo.id, source: "menu") } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .help(L10n.text("delete"))
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
    }
}
