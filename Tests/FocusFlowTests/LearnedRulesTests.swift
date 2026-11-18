import Foundation
import Testing
@testable import FocusFlow

@Suite("Learned rules and tracking settings")
@MainActor
struct LearnedRulesTests {
    init() { TestSupport.isolate() }

    private func store(with projects: [Project]) -> ProjectStore {
        TestSupport.remove("projects.json")
        Storage.save(projects, to: "projects.json")
        return ProjectStore()
    }

    @Test func learningAddsRulesAndSkipsConflictsAndDuplicates() {
        let otherID = UUID()
        var other = Project(name: "Other")
        other.id = otherID
        other.trackingRules = [TrackingRule(kind: .learned, value: "shared")]

        var project = Project(name: "Project")
        let store = store(with: [other, project])

        store.learnKeywords(["alpha", "shared", "alpha", "beta"], for: project.id)

        let learned = store.project(project.id)!.trackingRules
            .filter { $0.kind == .learned }
            .map(\.value)
        #expect(learned == ["alpha", "beta"])
        #expect(store.project(otherID)!.trackingRules.count == 1)
    }

    @Test func learningIgnoresUnknownProject() {
        let project = Project(name: "Project")
        let store = store(with: [project])

        store.learnKeywords(["alpha"], for: UUID())

        #expect(store.project(project.id)!.trackingRules.isEmpty)
    }

    @Test func learningCapsOnlyLearnedRulesAndDropsOldest() {
        var project = Project(name: "Project")
        let oldRules = (0..<ProjectStore.maxLearnedRules).map {
            TrackingRule(kind: .learned, value: "old-\($0)")
        }
        project.trackingRules = [
            TrackingRule(kind: .app, value: "com.example.App"),
            TrackingRule(kind: .title, value: "Keep this"),
        ] + oldRules
        let store = store(with: [project])

        store.learnKeywords(["new"], for: project.id)

        let rules = store.project(project.id)!.trackingRules
        let learned = rules.filter { $0.kind == .learned }.map(\.value)
        #expect(learned.count == ProjectStore.maxLearnedRules)
        #expect(!learned.contains("old-0"))
        #expect(learned.last == "new")
        #expect(rules.contains { $0.kind == .app && $0.value == "com.example.App" })
        #expect(rules.contains { $0.kind == .title && $0.value == "Keep this" })
    }

    @Test func oldTrackingSettingsFillNewFieldsAndRoundTrip() throws {
        TestSupport.remove("tracking.json")
        let oldJSON = #"{"enabled":true,"windowTitles":false,"browserAddresses":true,"idleMinutes":7,"sideWindow":false}"#
        try Data(oldJSON.utf8).write(to: Storage.directory.appendingPathComponent("tracking.json"))

        let loaded = try #require(Storage.load(TrackingSettings.self, from: "tracking.json"))
        #expect(loaded.enabled)
        #expect(!loaded.windowTitles)
        #expect(loaded.browserAddresses)
        #expect(loaded.idleMinutes == 7)
        #expect(!loaded.sideWindow)
        #expect(loaded.detectFromText)
        #expect(loaded.excludedApps == ContextFilter.defaultExcludedBundleIDs)

        var saved = TrackingSettings()
        saved.enabled = true
        saved.detectFromText = false
        saved.excludedApps = ["com.example.Private"]
        let decoded = try JSONDecoder().decode(TrackingSettings.self, from: JSONEncoder().encode(saved))
        #expect(decoded == saved)
    }

    @Test func learnedRulesHaveFixedWeightAndNeverMatch() {
        let rule = TrackingRule(kind: .learned, value: "alpha")

        #expect(rule.weight == 150)
        #expect(!rule.matches(bundleID: "com.example.App", title: "alpha", address: "alpha.example"))
    }

    @Test func activityMatchingIgnoresLearnedRules() {
        let learned = Project(name: "Learned", colorIndex: 0, symbol: "folder.fill")
        var project = learned
        project.trackingRules = [TrackingRule(kind: .learned, value: "alpha")]

        #expect(ActivityTracker.match([project], bundleID: "com.example.App", title: "alpha", address: nil) == nil)
    }
}
