import Foundation
import Observation

@MainActor @Observable
final class ProjectStore {
    private(set) var projects: [Project] = Storage.load([Project].self, from: "projects.json") ?? []

    func add(_ name: String) {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let project = Project(name: text)
        projects.insert(project, at: 0)
        save()
        Analytics.track(.projectCreated, ["project_id": .string(project.id.uuidString), "count": .int(projects.count)],
                        content: ["name": text])
    }

    func rename(_ id: UUID, name: String) {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let old = projects[index].name
        projects[index].name = text
        save()
        Analytics.track(.projectRenamed, ["project_id": .string(id.uuidString)], content: ["old_name": old, "new_name": text])
    }

    func setBlockedApps(_ apps: [BlockedApp]?, for id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].blockedApps = apps
        save()
        Analytics.track(.projectBlockedAppsChanged, ["project_id": .string(id.uuidString), "custom": .bool(apps != nil),
                                                     "bundle_ids": .string(apps?.map(\.bundleID).joined(separator: ",") ?? "")])
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
