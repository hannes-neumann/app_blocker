import Foundation

/// Focus time of one project (or of sessions without one) in a period.
struct ProjectSlice: Identifiable {
    let projectID: UUID?
    let name: String
    let colorIndex: Int?
    var minutes: Double = 0
    var sessions = 0
    var id: String { projectID?.uuidString ?? "none" }
}

/// Focus minutes of one series on one day, for stacked charts.
struct DaySeriesMinutes: Identifiable {
    let day: Date
    let seriesID: String
    let minutes: Double
    var id: String { "\(day.timeIntervalSince1970)-\(seriesID)" }
}

struct Insight: Identifiable {
    enum Tone { case positive, neutral, hint }
    let id = UUID()
    let symbol: String
    let text: String
    var tone = Tone.neutral
}

/// Everything the insight views show for a period, computed once from the raw records.
struct InsightsReport {
    /// Charts show at most this many series; smaller projects fold into "other", so colors never repeat.
    static let maxSeries = 8

    let days: [Date]
    let totalMinutes: Double
    let previousMinutes: Double
    let sessions: Int
    let completedSessions: Int
    let activeDays: Int
    let goalDays: Int
    let slices: [ProjectSlice]
    /// The series charts draw: the biggest projects, plus "other" and "no project" if needed.
    let series: [ProjectSlice]
    let daily: [DaySeriesMinutes]
    let minutesByHour: [Double]
    /// Monday first.
    let minutesByWeekday: [Double]
    /// Median of actual focus time / estimate over finished tasks with both, e.g. 1.3.
    let estimateRatio: Double?
    let estimateSamples: Int
    let records: [FocusRecord]

    var averageSessionMinutes: Double { sessions == 0 ? 0 : totalMinutes / Double(sessions) }
    var completionRate: Double? { sessions == 0 ? nil : Double(completedSessions) / Double(sessions) }
    var trend: Double? { previousMinutes < 1 ? nil : (totalMinutes - previousMinutes) / previousMinutes }
    var unassignedMinutes: Double { slices.first { $0.projectID == nil }?.minutes ?? 0 }

    init(records allRecords: [FocusRecord], todos: [Todo], projects: [Project], days count: Int,
         dailyGoal: Int, projectFilter: UUID? = nil, now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: today)!
        let previousStart = calendar.date(byAdding: .day, value: -count, to: start)!
        let filtered = allRecords.filter { projectFilter == nil || $0.projectID == projectFilter }
        let records = filtered.filter { $0.start >= start }.sorted { $0.start > $1.start }
        self.records = records
        days = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start)! }

        totalMinutes = records.reduce(0) { $0 + $1.focusedSeconds / 60 }
        previousMinutes = filtered.filter { $0.start >= previousStart && $0.start < start }
            .reduce(0) { $0 + $1.focusedSeconds / 60 }
        sessions = records.count
        completedSessions = records.filter(\.completed).count

        var perDay: [Date: Double] = [:]
        var hours = Array(repeating: 0.0, count: 24)
        var weekdays = Array(repeating: 0.0, count: 7)
        var byProject: [String: ProjectSlice] = [:]
        let projectsByID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for record in records {
            let minutes = record.focusedSeconds / 60
            let day = calendar.startOfDay(for: record.start)
            perDay[day, default: 0] += minutes
            hours[calendar.component(.hour, from: record.start)] += minutes
            weekdays[(calendar.component(.weekday, from: record.start) + 5) % 7] += minutes
            // A deleted project's sessions count as unassigned.
            let project = record.projectID.flatMap { projectsByID[$0] }
            let key = project?.id.uuidString ?? "none"
            if byProject[key] == nil {
                byProject[key] = ProjectSlice(projectID: project?.id, name: project?.name ?? L10n.text("noProject"),
                                              colorIndex: project?.colorIndex)
            }
            byProject[key]!.minutes += minutes
            byProject[key]!.sessions += 1
        }
        minutesByHour = hours
        minutesByWeekday = weekdays
        activeDays = perDay.values.filter { $0 > 0 }.count
        goalDays = perDay.values.filter { $0 >= Double(dailyGoal) }.count

        let sorted = byProject.values.sorted { a, b in
            // "No project" always last, so the projects come first in legends.
            if (a.projectID == nil) != (b.projectID == nil) { return b.projectID == nil }
            return a.minutes > b.minutes
        }
        slices = sorted

        let named = sorted.filter { $0.projectID != nil }
        let unassigned = sorted.first { $0.projectID == nil }
        let room = Self.maxSeries - (unassigned == nil ? 0 : 1)
        var series = Array(named.prefix(named.count > room ? room - 1 : room))
        if named.count > room {
            let rest = named.dropFirst(room - 1)
            var other = ProjectSlice(projectID: nil, name: L10n.text("otherProjects"), colorIndex: nil)
            other.minutes = rest.reduce(0) { $0 + $1.minutes }
            other.sessions = rest.reduce(0) { $0 + $1.sessions }
            series.append(other)
        }
        if let unassigned { series.append(unassigned) }
        self.series = series

        let shown = Set(series.compactMap(\.projectID))
        var daily: [DaySeriesMinutes] = []
        var cells: [String: Double] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.start)
            let project = record.projectID.flatMap { projectsByID[$0] }
            let seriesID = project.map { shown.contains($0.id) ? $0.id.uuidString : "other" } ?? "none"
            cells["\(day.timeIntervalSince1970)|\(seriesID)", default: 0] += record.focusedSeconds / 60
        }
        for (key, minutes) in cells {
            let parts = key.split(separator: "|")
            daily.append(DaySeriesMinutes(day: Date(timeIntervalSince1970: Double(parts[0])!), seriesID: String(parts[1]),
                                          minutes: minutes))
        }
        self.daily = daily

        // Estimates: only tasks that are done, had an estimate and got focus time.
        var focusPerTask: [UUID: Double] = [:]
        for record in filtered { if let id = record.taskID { focusPerTask[id, default: 0] += record.focusedSeconds / 60 } }
        let ratios = todos.compactMap { todo -> Double? in
            guard todo.isDone, let estimate = todo.estimatedMinutes, estimate > 0,
                  let actual = focusPerTask[todo.id], actual >= 1 else { return nil }
            return actual / Double(estimate)
        }.sorted()
        estimateSamples = ratios.count
        estimateRatio = ratios.isEmpty ? nil : ratios[ratios.count / 2]
    }

    func seriesID(of slice: ProjectSlice) -> String {
        if let id = slice.projectID { return id.uuidString }
        return slice.name == L10n.text("otherProjects") ? "other" : "none"
    }

    // MARK: - Insights

    /// Short observations, most useful first.
    var insights: [Insight] {
        var result: [Insight] = []
        guard totalMinutes >= 1 else { return result }

        if let trend, abs(trend) >= 0.1 {
            let percent = Int((abs(trend) * 100).rounded())
            result.append(trend > 0
                ? Insight(symbol: "arrow.up.right", text: L10n.text("insightTrendUp", percent, days.count), tone: .positive)
                : Insight(symbol: "arrow.down.right", text: L10n.text("insightTrendDown", percent, days.count), tone: .hint))
        }

        let unassignedShare = unassignedMinutes / totalMinutes
        if unassignedShare >= 0.25, slices.contains(where: { $0.projectID != nil }) || unassignedMinutes >= 30 {
            result.append(Insight(symbol: "tray.full", text: L10n.text("insightUnassigned", Int((unassignedShare * 100).rounded())),
                                  tone: .hint))
        }

        if let top = slices.first(where: { $0.projectID != nil }), totalMinutes >= 30 {
            let share = Int((top.minutes / totalMinutes * 100).rounded())
            result.append(Insight(symbol: "folder.fill", text: L10n.text("insightTopProject", top.name, share)))
        }

        if totalMinutes >= 60, let window = bestWindow {
            result.append(Insight(symbol: "sun.max", text: L10n.text("insightBestHours", window, window + 2)))
        }

        if let rate = completionRate, sessions >= 3 {
            let percent = Int((rate * 100).rounded())
            result.append(rate >= 0.7
                ? Insight(symbol: "checkmark.seal", text: L10n.text("insightCompletionHigh", percent), tone: .positive)
                : Insight(symbol: "scissors", text: L10n.text("insightCompletionLow", percent), tone: .hint))
        }

        if let ratio = estimateRatio, estimateSamples >= 3, abs(ratio - 1) >= 0.15 {
            let factor = ratio.formatted(.number.precision(.fractionLength(1)).locale(L10n.locale))
            result.append(Insight(symbol: "hourglass", text: ratio > 1
                ? L10n.text("insightEstimateLong", factor)
                : L10n.text("insightEstimateShort", factor), tone: .hint))
        }

        if days.count >= 14, let best = minutesByWeekday.indices.max(by: { minutesByWeekday[$0] < minutesByWeekday[$1] }),
           minutesByWeekday[best] > 0 {
            result.append(Insight(symbol: "calendar", text: L10n.text("insightBestWeekday", Self.weekdayName(best))))
        }
        return result
    }

    /// Start hour of the two consecutive hours with the most focus time.
    private var bestWindow: Int? {
        let sums = (0..<23).map { minutesByHour[$0] + minutesByHour[$0 + 1] }
        guard let best = sums.indices.max(by: { sums[$0] < sums[$1] }), sums[best] > 0 else { return nil }
        return best
    }

    /// 0 = Monday.
    static func weekdayName(_ index: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = L10n.locale
        return calendar.weekdaySymbols[(index + 1) % 7]
    }

    static func shortWeekdayName(_ index: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = L10n.locale
        return calendar.shortWeekdaySymbols[(index + 1) % 7]
    }
}
