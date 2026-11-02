import Foundation
import Observation

@MainActor @Observable
final class ProjectStore {
    private(set) var projects: [Project] = Storage.load([Project].self, from: "projects.json") ?? []

    init() {
        // Projects from before colors existed get distinct ones, oldest first.
        guard projects.contains(where: { $0.colorIndex < 0 }) else { return }
        for index in projects.indices.reversed() where projects[index].colorIndex < 0 {
            projects[index].colorIndex = nextColorIndex
        }
        save()
    }

    /// The first palette slot no project uses yet, so new projects get distinct colors.
    var nextColorIndex: Int {
        let used = Set(projects.map(\.colorIndex))
        return (0..<ProjectPalette.count).first { !used.contains($0) } ?? projects.count % ProjectPalette.count
    }

    @discardableResult
    func add(_ name: String, colorIndex: Int? = nil, symbol: String = "folder.fill") -> Project? {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let project = Project(name: text, colorIndex: colorIndex ?? nextColorIndex, symbol: symbol)
        projects.insert(project, at: 0)
        save()
        Analytics.track(.projectCreated, ["project_id": .string(project.id.uuidString), "count": .int(projects.count)],
                        content: ["name": text])
        return project
    }

    func rename(_ id: UUID, name: String) {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let old = projects[index].name
        projects[index].name = text
        save()
        Analytics.track(.projectRenamed, ["project_id": .string(id.uuidString)], content: ["old_name": old, "new_name": text])
    }

    func setStyle(_ id: UUID, colorIndex: Int? = nil, symbol: String? = nil) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        if let colorIndex { projects[index].colorIndex = colorIndex }
        if let symbol { projects[index].symbol = symbol }
        save()
        Analytics.track(.projectStyleChanged, ["project_id": .string(id.uuidString),
                                               "color_index": .int(projects[index].colorIndex),
                                               "symbol": .string(projects[index].symbol)])
    }

    func setWeeklyGoal(_ id: UUID, minutes: Int?) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].weeklyGoalMinutes = minutes
        save()
        Analytics.track(.projectGoalChanged, ["project_id": .string(id.uuidString), "minutes": .int(minutes ?? 0)])
    }

    func setBlockedApps(_ apps: [BlockedApp]?, for id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].blockedApps = apps
        save()
        Analytics.track(.projectBlockedAppsChanged, ["project_id": .string(id.uuidString), "custom": .bool(apps != nil),
                                                     "bundle_ids": .string(apps?.map(\.bundleID).joined(separator: ",") ?? "")])
    }

    func addRule(_ rule: TrackingRule, to id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }),
              !projects[index].trackingRules.contains(where: { $0.kind == rule.kind && $0.value == rule.value }) else { return }
        projects[index].trackingRules.append(rule)
        save()
        Analytics.track(.trackingRuleAdded, ["project_id": .string(id.uuidString), "kind": .string(rule.kind.rawValue),
                                             "count": .int(projects[index].trackingRules.count)],
                        content: ["value": rule.value])
    }

    func removeRule(_ ruleID: UUID, from id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }),
              let rule = projects[index].trackingRules.first(where: { $0.id == ruleID }) else { return }
        projects[index].trackingRules.removeAll { $0.id == ruleID }
        save()
        Analytics.track(.trackingRuleRemoved, ["project_id": .string(id.uuidString), "kind": .string(rule.kind.rawValue)],
                        content: ["value": rule.value])
    }

    func delete(_ id: UUID) {
        projects.removeAll { $0.id == id }
        save()
        Analytics.track(.projectDeleted, ["project_id": .string(id.uuidString), "count": .int(projects.count)])
    }

    func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    private func save() {
        Storage.save(projects, to: "projects.json")
    }
}
