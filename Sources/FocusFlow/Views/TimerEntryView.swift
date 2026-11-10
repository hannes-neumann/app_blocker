import SwiftUI

/// What a focus session counts for.
enum FocusTarget: Hashable {
    case none
    case project(UUID)
    case task(UUID)
}

/// The ⌃⌥T panel: a duration, and a project or task picked with the keyboard.
struct TimerEntryView: View {
    @Environment(AppState.self) private var state
    let defaultMinutes: Int
    let onStart: (Int, FocusTarget) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var invalid = false
    @State private var query = ""
    @State private var selection: FocusTarget
    @FocusState private var field: Field?

    private enum Field { case duration, search }

    private struct Row: Identifiable {
        let target: FocusTarget
        let title: String
        let detail: String?
        let colorIndex: Int?
        var id: FocusTarget { target }
    }

    private static let rowHeight: CGFloat = 30
    private static let visibleRows: CGFloat = 7

    init(defaultMinutes: Int, initialTarget: FocusTarget,
         onStart: @escaping (Int, FocusTarget) -> Void, onCancel: @escaping () -> Void) {
        self.defaultMinutes = defaultMinutes
        self.onStart = onStart
        self.onCancel = onCancel
        _text = State(initialValue: "\(defaultMinutes)")
        _selection = State(initialValue: initialTarget)
    }

    var body: some View {
        let rows = self.rows
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                TextField(L10n.text("durationPlaceholder"), text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($field, equals: .duration)
                    .onSubmit(start)
                    .onChange(of: text) { invalid = false }
                    .onKeyPress(.upArrow) { move(-1, in: rows); return .handled }
                    .onKeyPress(.downArrow) { move(1, in: rows); return .handled }
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(invalid ? Color.red : Color.secondary.opacity(0.3))
                            .frame(height: 1)
                    }
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                TextField(L10n.text("targetSearchPlaceholder"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($field, equals: .search)
                    .onSubmit(start)
                    .onKeyPress(.upArrow) { move(-1, in: rows); return .handled }
                    .onKeyPress(.downArrow) { move(1, in: rows); return .handled }
                    .onChange(of: query) {
                        // Typing narrows the list; the best match is picked so ↩ starts right away.
                        let matches = self.rows
                        if let first = matches.first(where: { $0.target != .none }) ?? matches.first {
                            selection = first.target
                        }
                    }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(rows) { row in
                            rowView(row)
                                .id(row.target)
                                // A separate double tap would hold back the single tap until the double-click time is over.
                                .onTapGesture { selection = row.target }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { selection = row.target; start() })
                        }
                        if rows.isEmpty {
                            Text(L10n.text("noTargetMatch"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
                        }
                    }
                }
                .frame(height: Self.rowHeight * Self.visibleRows + 12)
                .onChange(of: selection) { proxy.scrollTo(selection) }
                .onAppear { proxy.scrollTo(selection) }
            }
            HStack(spacing: 8) {
                ForEach([15, 25, 45, 60], id: \.self) { minutes in
                    Button(formatMinutes(minutes)) {
                        text = "\(minutes)"
                        start()
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text(L10n.text("timerEntryFooter"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onExitCommand(perform: onCancel)
        .onAppear {
            field = .duration
            if !rows.contains(where: { $0.target == selection }) { selection = .none }
        }
    }

    private func rowView(_ row: Row) -> some View {
        let selected = row.target == selection
        return HStack(spacing: 10) {
            Group {
                switch row.target {
                case .none: Circle().strokeBorder(Color.secondary, lineWidth: 1.5).frame(width: 10, height: 10)
                case .project: ProjectDot(colorIndex: row.colorIndex, size: 10)
                case .task: Image(systemName: "circle").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 16)
            Text(row.title).lineLimit(1)
            Spacer(minLength: 8)
            if let detail = row.detail {
                HStack(spacing: 5) {
                    if case .task = row.target, row.colorIndex != nil { ProjectDot(colorIndex: row.colorIndex, size: 7) }
                    Text(detail).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(selected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    /// "No project", the projects, then open tasks; filtered by every typed word.
    private var rows: [Row] {
        var rows = [Row(target: .none, title: L10n.text("noProject"), detail: nil, colorIndex: nil)]
        rows += state.projects.projects.map { project in
            Row(target: .project(project.id), title: project.name, detail: L10n.text("project"), colorIndex: project.colorIndex)
        }
        rows += state.todos.open.map { todo in
            let project = state.projects.project(todo.projectID)
            let parts = [project?.name, todo.estimatedMinutes.map(formatMinutes)].compactMap { $0 }
            return Row(target: .task(todo.id), title: todo.title, detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
                       colorIndex: project?.colorIndex)
        }
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return rows }
        return rows.filter { row in
            let haystack = row.title + " " + (row.detail ?? "")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    private func move(_ step: Int, in rows: [Row]) {
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.target == selection } ?? -1
        selection = rows[min(max(index + step, 0), rows.count - 1)].target
    }

    private func start() {
        guard let minutes = parseDuration(text), minutes <= 480 else {
            invalid = true
            field = .duration
            return
        }
        // A filter that matches nothing must not silently start without a project.
        guard rows.contains(where: { $0.target == selection }) else { return }
        onStart(minutes, selection)
    }
}

/// The ⌃⌥T panel while a phase is running: the time left and the controls, all reachable from the keyboard.
struct TimerSessionView: View {
    @Environment(AppState.self) private var state
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.phase.title, systemImage: state.phase.symbol)
                    .font(.headline)
                Spacer()
                Text(state.cycleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if state.phase == .focus {
                HStack(spacing: 6) {
                    ProjectDot(colorIndex: state.selectedProject?.colorIndex, size: 8)
                    Text(state.selectedTask?.title ?? state.selectedProject?.name ?? L10n.text("noProject"))
                        .lineLimit(1)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Text(state.remainingText)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            ProgressView(value: state.progress)
                .tint(state.phase.isBreak ? .green : state.selectedProject?.color ?? .accentColor)
            HStack(spacing: 8) {
                Button { state.togglePause() } label: {
                    Label(L10n.text(state.isPaused ? "resume" : "pause"), systemImage: state.isPaused ? "play.fill" : "pause.fill")
                        .frame(minWidth: 90)
                }
                .keyboardShortcut(.defaultAction)
                Button {
                    state.skipPhase()
                    onClose()
                } label: {
                    Label(L10n.text("skip"), systemImage: "forward.end.fill")
                }
                .keyboardShortcut("s", modifiers: [])
                Spacer()
                Button(role: .destructive) {
                    state.stop()
                    onClose()
                } label: {
                    Label(L10n.text("stop"), systemImage: "stop.fill")
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }
            .controlSize(.large)
            Text(L10n.text("timerSessionFooter"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onExitCommand(perform: onClose)
    }
}
