import Charts
import SwiftUI

/// Focus time, projects, habits and estimates over a chosen period.
struct InsightsPage: View {
    @Environment(AppState.self) private var state
    @State private var range = 7
    @State private var showAllSessions = false

    var body: some View {
        let goal = state.settings.dailyGoalMinutes
        let report = InsightsReport(records: state.stats.focusRecords, todos: state.todos.todos, projects: state.projects.projects,
                                    days: range, dailyGoal: goal)
        let days = state.stats.days(range)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("insights")).font(.largeTitle.weight(.bold))
                        Text(L10n.text("insightsSubtitle")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(L10n.text("period"), selection: $range) {
                        Text(L10n.text("sevenDays")).tag(7)
                        Text(L10n.text("thirtyDays")).tag(30)
                        Text(L10n.text("ninetyDays")).tag(90)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: range) { Analytics.track(.statsRangeChanged, ["days": .int(range)]) }
                }

                Grid(horizontalSpacing: 14) {
                    GridRow {
                        StatTile(title: L10n.text("focusTime"), value: formatDuration(report.totalMinutes),
                                 detail: L10n.text("vsLastWeekNone"), trend: report.trend, symbol: "timer")
                        StatTile(title: L10n.text("perActiveDay"),
                                 value: formatDuration(report.activeDays == 0 ? 0 : report.totalMinutes / Double(report.activeDays)),
                                 detail: L10n.text("activeDays", report.activeDays, range), symbol: "calendar")
                        StatTile(title: L10n.text("dailyGoal"), value: "\(report.goalDays)", unit: "/ \(range)",
                                 detail: L10n.text("goalDaysDetail", goal), progress: Double(report.goalDays) / Double(range),
                                 symbol: "target")
                        StatTile(title: L10n.text("sessions"), value: "\(report.sessions)",
                                 detail: report.sessions == 0 ? L10n.text("noSessionsYet")
                                     : L10n.text("sessionsDetail", formatDuration(report.averageSessionMinutes),
                                                 Int(((report.completionRate ?? 0) * 100).rounded())),
                                 symbol: "repeat")
                        StatTile(title: L10n.text("todosDone"), value: "\(days.reduce(0) { $0 + $1.todosDone })",
                                 detail: L10n.text("inPeriod", range), symbol: "checkmark.circle")
                    }
                }

                if report.totalMinutes < 1 {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar.xaxis").font(.system(size: 40)).foregroundStyle(.tertiary)
                        Text(L10n.text("noDataTitle")).font(.title3.weight(.semibold))
                        Text(L10n.text("noDataText")).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .card()
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            CardHeader(title: L10n.text("focusPerDay"), subtitle: L10n.text("minutesByProjectGoal", goal))
                            StackedFocusChart(report: report, goal: goal).frame(height: 230)
                        }
                        .card()
                        VStack(alignment: .leading, spacing: 14) {
                            CardHeader(title: L10n.text("whatStoodOut"))
                            InsightList(insights: report.insights, limit: 6)
                        }
                        .card()
                        .frame(width: 340)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            CardHeader(title: L10n.text("projectShare"), subtitle: L10n.text("clickProjectHint"))
                            ProjectShareList(report: report)
                        }
                        .card()
                        VStack(alignment: .leading, spacing: 14) {
                            CardHeader(title: L10n.text("whenYouWork"), subtitle: L10n.text("minutesByHour"))
                            HourChart(minutes: report.minutesByHour).frame(height: 170)
                        }
                        .card()
                        VStack(alignment: .leading, spacing: 14) {
                            CardHeader(title: L10n.text("byWeekday"), subtitle: L10n.text("minutesPerWeekday"))
                            WeekdayChart(minutes: report.minutesByWeekday).frame(height: 170)
                        }
                        .card()
                    }

                    HStack(alignment: .top, spacing: 18) {
                        EstimateCard(report: report)
                        TaskTimeCard(records: report.records)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        let sessions = report.records
                        CardHeader(title: L10n.text("allSessions"),
                                   subtitle: report.unassignedMinutes > 0
                                       ? L10n.text("unassignedMinutesHint", formatDuration(report.unassignedMinutes))
                                       : L10n.text("sessionsAssignHint")) {
                            if sessions.count > 10 {
                                Button(showAllSessions ? L10n.text("showLess") : L10n.text("showAllCount", sessions.count)) {
                                    showAllSessions.toggle()
                                }
                                .buttonStyle(.link).font(.caption)
                            }
                        }
                        VStack(spacing: 0) {
                            let shown = showAllSessions ? Array(sessions) : Array(sessions.prefix(10))
                            ForEach(shown) { record in
                                SessionRow(record: record, showDate: true)
                                if record.id != shown.last?.id { Divider() }
                            }
                        }
                    }
                    .card()
                }
            }
            .padding(24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WeekdayChart: View {
    let minutes: [Double]
    @State private var selected: String?

    var body: some View {
        let names = (0..<7).map(InsightsReport.shortWeekdayName)
        Chart {
            ForEach(0..<7, id: \.self) { index in
                BarMark(x: .value("weekday", names[index]), y: .value("minutes", minutes[index]), width: .ratio(0.6))
                    .foregroundStyle(Color.accentColor.opacity(selected == nil || selected == names[index] ? 1 : 0.35))
                    .cornerRadius(3)
            }
            if let selected, let index = names.firstIndex(of: selected) {
                RuleMark(x: .value("weekday", selected))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ValueCallout(title: InsightsReport.weekdayName(index), lines: [(nil, formatDuration(minutes[index]))])
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartXAxis { AxisMarks { AxisValueLabel() } }
        .chartYAxis {
            AxisMarks { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() }
        }
    }
}

/// How the time actually spent on finished tasks compares to their estimates.
private struct EstimateCard: View {
    let report: InsightsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: L10n.text("estimateAccuracy"), subtitle: L10n.text("estimateAccuracyHint"))
            if let ratio = report.estimateRatio {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ratio.formatted(.number.precision(.fractionLength(1)).locale(L10n.locale)) + "×")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(L10n.text("ofEstimate")).foregroundStyle(.secondary)
                }
                Text(ratio > 1.15 ? L10n.text("estimateTooLow") : ratio < 0.85 ? L10n.text("estimateTooHigh") : L10n.text("estimateGood"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.text("basedOnTasks", report.estimateSamples)).font(.caption).foregroundStyle(.tertiary)
            } else {
                EmptyHint(symbol: "hourglass", text: L10n.text("estimateNoData"))
            }
        }
        .card()
        .frame(width: 340)
    }
}

/// Where the time went, by task.
private struct TaskTimeCard: View {
    @Environment(AppState.self) private var state
    let records: [FocusRecord]

    var body: some View {
        let tasks = taskTotals
        let maxMinutes = tasks.map(\.minutes).max() ?? 1
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: L10n.text("focusTimeByTask"), subtitle: L10n.text("taskSessionsRange"))
            if tasks.isEmpty {
                EmptyHint(symbol: "checklist", text: L10n.text("chooseTaskHint"))
            } else {
                VStack(spacing: 10) {
                    ForEach(tasks.prefix(8), id: \.title) { task in
                        let project = state.projects.project(task.projectID)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                ProjectDot(colorIndex: project?.colorIndex, size: 8)
                                Text(task.title).lineLimit(1)
                                if let project { Text(project.name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                Spacer()
                                Text(formatDuration(task.minutes)).monospacedDigit()
                            }
                            .font(.callout)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(project?.color ?? ProjectPalette.none)
                                    .frame(width: max(4, geo.size.width * task.minutes / maxMinutes))
                            }
                            .frame(height: 5)
                        }
                    }
                }
            }
        }
        .card()
    }

    private var taskTotals: [(title: String, projectID: UUID?, minutes: Double)] {
        var totals: [String: (title: String, projectID: UUID?, minutes: Double)] = [:]
        for record in records {
            guard let title = record.taskTitle else { continue }
            let key = record.taskID?.uuidString ?? title
            totals[key, default: (title, record.projectID, 0)].minutes += record.focusedSeconds / 60
        }
        return totals.values.sorted { $0.minutes > $1.minutes }
    }
}
