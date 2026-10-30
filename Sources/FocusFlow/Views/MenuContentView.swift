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
            warnings
            if state.phase.isBreak { suggestionSection }
            Divider()
            todoSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { state.refreshSuggestion() }
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
                .tint(state.phase.isBreak ? .green : .accentColor)

            HStack {
                if state.phase == .idle {
                    Button { state.startFocus() } label: {
                        Label("Fokus starten", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button { state.togglePause() } label: {
                        Label(state.isPaused ? "Weiter" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    }
                    Button { state.skipPhase() } label: {
                        Label("Überspringen", systemImage: "forward.end.fill")
                    }
                    Spacer()
                    Button(role: .destructive) { state.stop() } label: {
                        Label("Stopp", systemImage: "stop.fill")
                    }
                }
            }
        }
    }

    private var todaySummary: some View {
        let today = Int(state.stats.todayFocusMinutes)
        let goal = state.settings.dailyGoalMinutes
        let streak = state.stats.streak
        return Button {
            dismiss()
            state.panels.showStats()
        } label: {
            HStack(spacing: 10) {
                Gauge(value: Double(min(today, goal)), in: 0...Double(max(goal, 1))) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .scaleEffect(0.45)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Heute \(today) von \(goal) Min").font(.callout.weight(.medium))
                    Text(streak > 0 ? "Serie: \(streak) \(streak == 1 ? "Tag" : "Tage") in Folge" : "Starte heute deine Serie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Statistik").font(.caption)
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(.primary)
            .padding(8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var warnings: some View {
        if let error = state.domainBlockError, !state.isHelperInstalled {
            VStack(alignment: .leading, spacing: 6) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Helfer installieren (einmalig)") { state.installHelper() }
                    .controlSize(.small)
            }
        }
        if state.hasStaleHostsBlock && state.phase == .idle {
            HStack {
                Label("Alte Webseiten-Sperre aktiv", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Aufheben") { state.removeStaleHostsBlock() }
                    .controlSize(.small)
            }
        }
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Vorschlag für die Pause").font(.caption).foregroundStyle(.secondary)
            if let todo = state.suggestion {
                HStack {
                    Text(todo.title).fontWeight(.medium)
                    Spacer()
                    if let minutes = todo.estimatedMinutes { EstimateBadge(minutes: minutes) }
                }
                HStack {
                    Button("Erledigt") { state.completeSuggestion() }
                    Button("Anderer") { state.nextSuggestion() }
                }
                .controlSize(.small)
            } else {
                Text("Nichts passt rein, einfach durchatmen.").foregroundStyle(.secondary)
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
                Text("Todos").font(.headline)
                Spacer()
                Text("Schnellnotiz: \(AppState.shortcutDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Notiz hinzufügen…", text: $newNote)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    state.todos.capture(newNote)
                    newNote = ""
                }

            let open = state.todos.open
            if open.isEmpty {
                Text("Keine offenen Todos.")
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
                DisclosureGroup("Erledigt (\(done.count))", isExpanded: $showDone) {
                    VStack(spacing: 2) {
                        ForEach(done.prefix(10)) { TodoRow(todo: $0) }
                    }
                    Button("Erledigte löschen") { state.todos.clearDone() }
                        .controlSize(.small)
                }
                .font(.callout)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Einstellungen…") {
                dismiss()
                state.panels.showSettings()
            }
            Spacer()
            Button("Beenden") { NSApp.terminate(nil) }
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

    private static let estimateOptions = [2, 5, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        HStack(spacing: 8) {
            Button { state.todos.toggleDone(todo.id) } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(todo.isRefining)

            Text(todo.title)
                .strikethrough(todo.isDone)
                .foregroundStyle(todo.isDone ? .secondary : .primary)
                .lineLimit(2)
                .help(todo.sourceNote)

            Spacer(minLength: 4)

            if todo.isRefining {
                ProgressView().controlSize(.small)
            } else {
                if todo.refinedByAI {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .help("Von Apple Intelligence formuliert und geschätzt")
                }
                Menu {
                    ForEach(Self.estimateOptions, id: \.self) { minutes in
                        Button(formatMinutes(minutes)) { state.todos.setEstimate(todo.id, minutes: minutes) }
                    }
                } label: {
                    EstimateBadge(minutes: todo.estimatedMinutes ?? 0)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Geschätzte Dauer anpassen")
            }

            // Always laid out and only faded in, so hovering never changes the row's size
            // (which would make the whole menu window jump).
            Button { state.todos.delete(todo.id) } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .help("Löschen")
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
    }
}
