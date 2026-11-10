import Charts
import SwiftUI

// MARK: - Surfaces

extension View {
    func card(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

struct CardHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            accessory
        }
    }
}

extension CardHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A headline number with a label, an optional trend and a progress bar.
struct StatTile: View {
    let title: String
    let value: String
    var unit = ""
    var detail: String?
    var trend: Double?
    var progress: Double?
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                if let symbol { Image(systemName: symbol) }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.callout).foregroundStyle(.secondary) }
            }
            if let progress {
                ProgressView(value: min(max(progress, 0), 1)).controlSize(.small)
            }
            if let trend {
                TrendLabel(trend: trend)
            } else if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 14)
    }
}

/// "+23 % vs. previous period", with an arrow so the direction never depends on color alone.
struct TrendLabel: View {
    let trend: Double

    var body: some View {
        let percent = Int((abs(trend) * 100).rounded())
        HStack(spacing: 3) {
            Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
            Text(L10n.text(trend >= 0 ? "trendUp" : "trendDown", percent))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(trend >= 0 ? Color.green : Color.secondary)
    }
}

/// A round progress ring with content in the middle.
struct Ring<Content: View>: View {
    let progress: Double
    var color: Color = .accentColor
    var lineWidth: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
            content
        }
    }
}

// MARK: - Projects

struct ProjectDot: View {
    let colorIndex: Int?
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(colorIndex.map(ProjectPalette.color) ?? ProjectPalette.none)
            .frame(width: size, height: size)
    }
}

struct ProjectIcon: View {
    let project: Project
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: project.symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(project.color, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Picks the project (and optionally a task) the next focus session counts for.
struct FocusTargetPicker: View {
    @Environment(AppState.self) private var state
    var compact = false
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !compact {
                Text(L10n.text("workingOn")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            if compact {
                HStack {
                    projectMenu
                    if state.selectedProject != nil { taskMenu }
                }
            } else {
                FlowLayout(spacing: 6) {
                        chip(nil)
                        ForEach(state.projects.projects) { chip($0) }
                        Button { creating = true } label: {
                            Label(L10n.text("newProject"), systemImage: "plus")
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                if state.selectedProject != nil { taskMenu }
            }
        }
        .disabled(state.phase == .focus)
        .sheet(isPresented: $creating) {
            ProjectEditorSheet(project: nil) { project in state.selectedProjectID = project.id }
        }
    }

    private func createProject() {
        if compact {
            state.panels.showProjectEditor { project in state.selectedProjectID = project.id }
        } else {
            creating = true
        }
    }

    private func chip(_ project: Project?) -> some View {
        let selected = state.selectedProject?.id == project?.id
        return Button { state.selectedProjectID = project?.id } label: {
            HStack(spacing: 6) {
                ProjectDot(colorIndex: project?.colorIndex, size: 8)
                Text(project?.name ?? L10n.text("noProject")).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(selected ? (project?.color ?? .secondary).opacity(0.18) : Color.primary.opacity(0.05)))
            .overlay(Capsule().strokeBorder(selected ? (project?.color ?? .secondary) : .clear, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var projectMenu: some View {
        Menu {
            Button { state.selectedProjectID = nil } label: { Text(L10n.text("noProject")) }
            Divider()
            ForEach(state.projects.projects) { project in
                Button { state.selectedProjectID = project.id } label: { Text(project.name) }
            }
            Divider()
            Button(L10n.text("newProject") + "…") { createProject() }
        } label: {
            HStack(spacing: 6) {
                ProjectDot(colorIndex: state.selectedProject?.colorIndex, size: 8)
                Text(state.selectedProject?.name ?? L10n.text("noProject")).lineLimit(1)
            }
        }
        .fixedSize()
    }

    private var taskMenu: some View {
        let tasks = state.todos.open.filter { $0.projectID == state.selectedProject?.id }
        return Menu {
            Button(L10n.text("noTask")) { state.selectedTaskID = nil }
            if !tasks.isEmpty { Divider() }
            ForEach(tasks) { task in
                Button(task.title) { state.selectedTaskID = task.id }
            }
        } label: {
            Label(state.selectedTask?.title ?? L10n.text("noTask"), systemImage: "checklist").lineLimit(1)
        }
        .fixedSize(horizontal: compact, vertical: false)
        .disabled(tasks.isEmpty && state.selectedTask == nil)
        .help(tasks.isEmpty ? L10n.text("noTasksInProject") : L10n.text("chooseTask"))
    }
}

/// Menu that moves a recorded session to another project.
struct AssignProjectMenu<Label: View>: View {
    @Environment(AppState.self) private var state
    let record: FocusRecord
    @ViewBuilder var label: Label

    var body: some View {
        Menu {
            Button { state.stats.assign(record.id, to: nil) } label: {
                if record.projectID == nil { Image(systemName: "checkmark") }
                Text(L10n.text("noProject"))
            }
            Divider()
            ForEach(state.projects.projects) { project in
                Button { state.stats.assign(record.id, to: project) } label: {
                    if record.projectID == project.id { Image(systemName: "checkmark") }
                    Text(project.name)
                }
            }
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.text("assignSession"))
    }
}

/// One past focus session with its project, which can be changed in place.
struct SessionRow: View {
    @Environment(AppState.self) private var state
    let record: FocusRecord
    var showDate = false

    var body: some View {
        let project = state.projects.project(record.projectID)
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(project?.color ?? ProjectPalette.none)
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.taskTitle ?? project?.name ?? L10n.text("focusSession")).lineLimit(1)
                Text(timeText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !record.completed {
                Image(systemName: "stop.circle").foregroundStyle(.secondary).help(L10n.text("sessionEndedEarly"))
            }
            Text(formatDuration(record.focusedSeconds / 60)).monospacedDigit().foregroundStyle(.secondary)
            AssignProjectMenu(record: record) {
                HStack(spacing: 5) {
                    ProjectDot(colorIndex: project?.colorIndex, size: 8)
                    Text(project?.name ?? L10n.text("assign"))
                        .foregroundStyle(project == nil ? Color.accentColor : .primary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
        }
        .padding(.vertical, 4)
    }

    private var timeText: String {
        let start = record.start.formatted(.dateTime.hour().minute().locale(L10n.locale))
        let end = record.end.formatted(.dateTime.hour().minute().locale(L10n.locale))
        let range = "\(start)–\(end)"
        guard showDate else { return range }
        return record.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale)) + ", " + range
    }
}

/// Creates or edits a project: name, color and icon.
struct ProjectEditorSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let project: Project?
    var onCreate: (Project) -> Void = { _ in }
    /// Set when the editor runs in its own panel instead of a sheet.
    var onClose: (() -> Void)?
    @State private var name = ""
    @State private var colorIndex = 0
    @State private var symbol = "folder.fill"
    @State private var goalText = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(project == nil ? "newProject" : "editProject")).font(.headline)
            HStack(spacing: 12) {
                ProjectIcon(project: preview, size: 44)
                TextField(L10n.text("projectNamePlaceholder"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focused)
                    .onSubmit(save)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("color")).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(0..<ProjectPalette.count, id: \.self) { index in
                        Button { colorIndex = index } label: {
                            Circle().fill(ProjectPalette.color(index)).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: colorIndex == index ? 2 : 0).padding(-3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("icon")).font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
                    ForEach(ProjectPalette.symbols, id: \.self) { item in
                        Button { symbol = item } label: {
                            Image(systemName: item)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 7)
                                    .fill(symbol == item ? ProjectPalette.color(colorIndex).opacity(0.2) : Color.primary.opacity(0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(symbol == item ? ProjectPalette.color(colorIndex) : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("weeklyGoal")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField(L10n.text("weeklyGoalPlaceholder"), text: $goalText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text(L10n.text("weeklyGoalHint")).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button(L10n.text("cancel"), role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                Button(L10n.text(project == nil ? "create" : "save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            name = project?.name ?? ""
            colorIndex = project?.colorIndex ?? state.projects.nextColorIndex
            symbol = project?.symbol ?? "folder.fill"
            goalText = project?.weeklyGoalMinutes.map { formatMinutes($0) } ?? ""
            focused = true
        }
    }

    private var preview: Project {
        Project(name: name, colorIndex: colorIndex, symbol: symbol)
    }

    private func save() {
        let goal = parseDuration(goalText)
        if let project {
            state.projects.rename(project.id, name: name)
            if project.colorIndex != colorIndex || project.symbol != symbol {
                state.projects.setStyle(project.id, colorIndex: colorIndex, symbol: symbol)
            }
            if project.weeklyGoalMinutes != goal { state.projects.setWeeklyGoal(project.id, minutes: goal) }
        } else if let created = state.projects.add(name, colorIndex: colorIndex, symbol: symbol) {
            if let goal { state.projects.setWeeklyGoal(created.id, minutes: goal) }
            onCreate(created)
        } else {
            return
        }
        close()
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

// MARK: - Charts

/// Tooltip shown above the hovered mark.
struct ValueCallout: View {
    let title: String
    let lines: [(color: Color?, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 5) {
                    if let color = line.color { Circle().fill(color).frame(width: 7, height: 7) }
                    Text(line.text).font(.callout.weight(.medium)).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.background, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator))
    }
}

extension ProjectSlice {
    var color: Color { colorIndex.map(ProjectPalette.color) ?? ProjectPalette.none }
}

/// Focus minutes per day, stacked by project, with an optional goal line.
struct StackedFocusChart: View {
    let report: InsightsReport
    var goal: Int?
    @State private var selected: Date?

    var body: some View {
        let series = report.series
        let colors = Dictionary(series.map { (report.seriesID(of: $0), $0.color) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(series.map { (report.seriesID(of: $0), $0.name) }, uniquingKeysWith: { a, _ in a })
        let order = series.map { report.seriesID(of: $0) }
        let selectedDay = selected.map { Calendar.current.startOfDay(for: $0) }
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(report.daily.sorted { (order.firstIndex(of: $0.seriesID) ?? 0) < (order.firstIndex(of: $1.seriesID) ?? 0) }) { cell in
                    BarMark(x: .value("day", cell.day, unit: .day), y: .value("minutes", cell.minutes))
                        .foregroundStyle(colors[cell.seriesID] ?? ProjectPalette.none)
                        .opacity(selectedDay == nil || selectedDay == cell.day ? 1 : 0.4)
                        .cornerRadius(3)
                }
                if let goal, goal > 0 {
                    RuleMark(y: .value("goal", goal))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(L10n.text("goal")).font(.caption2).foregroundStyle(.secondary)
                        }
                }
                if let day = selectedDay {
                    let cells = report.daily.filter { $0.day == day }.sorted { $0.minutes > $1.minutes }
                    RuleMark(x: .value("day", day, unit: .day))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ValueCallout(
                                title: day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(L10n.locale)) + " · "
                                    + formatDuration(cells.reduce(0) { $0 + $1.minutes }),
                                lines: cells.map { (colors[$0.seriesID], "\(names[$0.seriesID] ?? "") \(formatDuration($0.minutes))") })
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartXScale(domain: report.days.first!...Calendar.current.date(byAdding: .day, value: 1, to: report.days.last!)!)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: report.days.count <= 7 ? 1 : report.days.count <= 31 ? 5 : 14)) {
                    AxisValueLabel(format: report.days.count <= 7
                        ? .dateTime.weekday(.abbreviated).locale(L10n.locale)
                        : .dateTime.day().month(.defaultDigits).locale(L10n.locale), centered: report.days.count <= 7)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)") }
                }
            }
            if series.count > 1 { ChartLegend(items: series.map { ($0.color, $0.name) }) }
        }
    }
}

struct ChartLegend: View {
    let items: [(color: Color, name: String)]

    var body: some View {
        FlowLayout(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 10, height: 10)
                    Text(item.name).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Lays out children in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty && current.width + spacing + size.width > width {
                rows.append(current)
                current = ([], 0, 0)
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Horizontal bars per project with name and share, easier to compare than a pie.
struct ProjectShareList: View {
    @Environment(AppState.self) private var state
    let report: InsightsReport

    var body: some View {
        let maxMinutes = report.slices.map(\.minutes).max() ?? 1
        VStack(spacing: 10) {
            ForEach(report.slices) { slice in
                Button {
                    if let id = slice.projectID {
                        state.openProjectID = id
                        state.dashboardSection = .projects
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            ProjectDot(colorIndex: slice.colorIndex, size: 8)
                            Text(slice.name).lineLimit(1)
                            Spacer()
                            Text(formatDuration(slice.minutes)).monospacedDigit()
                            Text("\(Int((slice.minutes / max(report.totalMinutes, 1) * 100).rounded())) %")
                                .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                        }
                        .font(.callout)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(slice.color)
                                .frame(width: max(4, geo.size.width * slice.minutes / maxMinutes))
                        }
                        .frame(height: 6)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(slice.projectID == nil)
            }
        }
    }
}

/// Focus minutes per hour of the day.
struct HourChart: View {
    let minutes: [Double]
    var color: Color = .accentColor
    @State private var selection: Double?

    private var selected: Int? { selection.map { min(max(Int($0.rounded()), 0), 23) } }

    var body: some View {
        Chart {
            ForEach(0..<24, id: \.self) { hour in
                if minutes[hour] > 0 {
                    // Explicit start and end: a width ratio has no effect on a plain numeric x axis.
                    RectangleMark(xStart: .value("hour", Double(hour) - 0.35), xEnd: .value("hour", Double(hour) + 0.35),
                                  yStart: .value("minutes", 0), yEnd: .value("minutes", minutes[hour]))
                        .foregroundStyle(color.opacity(selected == nil || selected == hour ? 1 : 0.35))
                        .cornerRadius(3)
                }
            }
            if let hour = selected, minutes.indices.contains(hour) {
                RuleMark(x: .value("hour", Double(hour)))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ValueCallout(title: L10n.text("hourRange", hour, hour + 1),
                                     lines: [(nil, formatDuration(minutes[hour]))])
                    }
            }
        }
        .chartXSelection(value: $selection)
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0.0, 6, 12, 18]) { value in
                AxisValueLabel { Text(L10n.text("hourLabel", Int(value.as(Double.self) ?? 0))) }
            }
        }
        .chartYAxis {
            AxisMarks { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() }
        }
    }
}

/// Short text observations with an icon each.
struct InsightList: View {
    let insights: [Insight]
    var limit = 4

    var body: some View {
        if insights.isEmpty {
            Text(L10n.text("insightsEmpty")).font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(insights.prefix(limit)) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.symbol)
                            .frame(width: 26, height: 26)
                            .foregroundStyle(tint(insight.tone))
                            .background(tint(insight.tone).opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                        Text(insight.text).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func tint(_ tone: Insight.Tone) -> Color {
        switch tone {
        case .positive: .green
        case .neutral: .accentColor
        case .hint: .orange
        }
    }
}
