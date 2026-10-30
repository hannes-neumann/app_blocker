import Charts
import SwiftUI

struct StatsView: View {
    @Environment(AppState.self) private var state
    @State private var range = 7

    var body: some View {
        let days = state.stats.days(range)
        let goal = state.settings.dailyGoalMinutes

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Dein Fortschritt").font(.title2.weight(.semibold))
                    Spacer()
                    Picker("Zeitraum", selection: $range) {
                        Text("7 Tage").tag(7)
                        Text("30 Tage").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                tiles(days: days, goal: goal)

                ChartCard(title: "Fokuszeit pro Tag", subtitle: "Minuten · Ziel \(goal) Min") {
                    FocusPerDayChart(days: days, goal: goal, range: range)
                }
                ChartCard(title: "Erledigte Todos pro Tag", subtitle: "Anzahl") {
                    TodosPerDayChart(days: days, range: range)
                }
                ChartCard(title: "Wann du dich fokussierst", subtitle: "Minuten nach Tageszeit, letzte \(range) Tage") {
                    FocusByHourChart(hours: state.stats.minutesByHour(lastDays: range))
                }
            }
            .padding(24)
        }
        .frame(minWidth: 640, minHeight: 560)
    }

    private func tiles(days: [DayStat], goal: Int) -> some View {
        let today = state.stats.todayFocusMinutes
        let sessions = days.reduce(0) { $0 + $1.sessions }
        let completed = days.reduce(0) { $0 + $1.completedSessions }
        let activeDays = days.filter { $0.focusMinutes > 0 }.count
        let total = days.reduce(0) { $0 + $1.focusMinutes }
        let todos = days.reduce(0) { $0 + $1.todosDone }

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatTile(title: "Heute", value: "\(Int(today))", unit: "/ \(goal) Min",
                     detail: today >= Double(goal) ? "Tagesziel erreicht" : "noch \(goal - Int(today)) Min",
                     progress: min(today / Double(max(goal, 1)), 1))
            StatTile(title: "Serie", value: "\(state.stats.streak)", unit: state.stats.streak == 1 ? "Tag" : "Tage",
                     detail: activeDays == 0 ? "in Folge fokussiert" : "Ø \(Int(total / Double(activeDays))) Min pro aktivem Tag")
            StatTile(title: "Sessions", value: "\(completed)", unit: "/ \(sessions)",
                     detail: "ganz durchgezogen", progress: sessions == 0 ? nil : Double(completed) / Double(sessions))
            StatTile(title: "Todos erledigt", value: "\(todos)", unit: "",
                     detail: "in den letzten \(range) Tagen")
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    let detail: String
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.callout).foregroundStyle(.secondary)
            }
            if let progress {
                ProgressView(value: progress).controlSize(.small)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content.frame(height: 180)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Tooltip shown above the hovered bar.
private struct ValueCallout: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }
}

private func dayLabel(_ day: Date) -> String {
    day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}

private func axisStride(_ range: Int) -> Int { range <= 7 ? 1 : 5 }

private struct FocusPerDayChart: View {
    let days: [DayStat]
    let goal: Int
    let range: Int
    @State private var selected: Date?

    var body: some View {
        let selectedDay = selected.flatMap { s in days.first { Calendar.current.isDate($0.day, inSameDayAs: s) } }
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Tag", day.day, unit: .day), y: .value("Minuten", day.focusMinutes))
                    .foregroundStyle(Color.accentColor.opacity(selectedDay == nil || selectedDay?.day == day.day ? 1 : 0.35))
                    .cornerRadius(4)
            }
            RuleMark(y: .value("Ziel", goal))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Ziel").font(.caption2).foregroundStyle(.secondary)
                }
            if let day = selectedDay {
                RuleMark(x: .value("Tag", day.day, unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ValueCallout(title: dayLabel(day.day),
                                     value: "\(Int(day.focusMinutes)) Min · \(day.sessions) Sessions")
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: axisStride(range))) {
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel(format: range <= 7 ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.defaultDigits))
            }
        }
        .chartYAxis {
            AxisMarks { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() }
        }
    }
}

private struct TodosPerDayChart: View {
    let days: [DayStat]
    let range: Int
    @State private var selected: Date?

    var body: some View {
        let selectedDay = selected.flatMap { s in days.first { Calendar.current.isDate($0.day, inSameDayAs: s) } }
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Tag", day.day, unit: .day), y: .value("Todos", day.todosDone))
                    .foregroundStyle(Color.green.opacity(selectedDay == nil || selectedDay?.day == day.day ? 1 : 0.35))
                    .cornerRadius(4)
            }
            if let day = selectedDay {
                RuleMark(x: .value("Tag", day.day, unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ValueCallout(title: dayLabel(day.day), value: "\(day.todosDone) erledigt")
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: axisStride(range))) {
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel(format: range <= 7 ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.defaultDigits))
            }
        }
        .chartYAxis {
            AxisMarks { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() }
        }
    }
}

private struct FocusByHourChart: View {
    let hours: [(hour: Int, minutes: Double)]
    @State private var selected: Double?

    var body: some View {
        let selectedHour = selected.map { min(max(Int($0.rounded()), 0), 23) }
        Chart {
            ForEach(hours.filter { $0.minutes > 0 }, id: \.hour) { entry in
                bar(hour: entry.hour, minutes: entry.minutes, dimmed: selectedHour != nil && selectedHour != entry.hour)
            }
            if let hour = selectedHour {
                RuleMark(x: .value("Uhrzeit", Double(hour)))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ValueCallout(title: "\(hour):00–\(hour + 1):00 Uhr", value: "\(Int(hours[hour].minutes)) Min")
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0.0, 6, 12, 18]) { value in
                AxisValueLabel { Text("\(Int(value.as(Double.self) ?? 0)) Uhr") }
            }
        }
        .chartYAxis {
            AxisMarks { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() }
        }
    }

    // Explicit start/end on both axes: a width ratio has no effect on a plain numeric x axis.
    private func bar(hour: Int, minutes: Double, dimmed: Bool) -> some ChartContent {
        let x = Double(hour)
        let start: Double = 0
        let mark = RectangleMark(xStart: .value("Uhrzeit", x - 0.35), xEnd: .value("Uhrzeit", x + 0.35),
                           yStart: .value("Minuten", start), yEnd: .value("Minuten", minutes))
        let color = Color.accentColor.opacity(dimmed ? 0.35 : 1)
        return mark.foregroundStyle(color).cornerRadius(CGFloat(3))
    }
}
