import Foundation
import Observation

@MainActor @Observable
final class ProjectStore {
    private(set) var projects: [Project] = Storage.load([Project].self, from: "projects.json") ?? []

    func add(_ name: String) {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        projects.insert(Project(name: text), at: 0)
        save()
    }

    func rename(_ id: UUID, name: String) {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = text
        save()
    }

    func setBlockedApps(_ apps: [BlockedApp]?, for id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].blockedApps = apps
        save()
    }

    func delete(_ id: UUID) {
        projects.removeAll { $0.id == id }
        save()
    }

    func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    private func save() {
        Storage.save(projects, to: "projects.json")
    }
}
