import Foundation
import Testing
@testable import FocusFlow

@Suite("Classifier and context edge cases")
@MainActor
struct ClassifierEdgeCaseTests {
    init() { TestSupport.isolate() }

    @Test("The classifier request describes every project and bounds visible text")
    func requestContainsTheExpectedSchemaAndPrompts() throws {
        let projects = [Project(name: "Thesis"), Project(name: "Shop")]
        let text = "start " + String(repeating: "x", count: 1_600) + " end"
        let request = ProjectClassifier.request(text: text, projects: projects)

        let properties = try #require(request.schema["properties"] as? [String: Any])
        let project = try #require(properties["project"] as? [String: Any])
        let projectNames = try #require(project["enum"] as? [String])
        #expect(Set(projectNames) == Set(["Thesis", "Shop", "none"]))

        let keywords = try #require(properties["keywords"] as? [String: Any])
        #expect(keywords["maxItems"] as? Int == ProjectClassifier.maxKeywords)

        let visibleText = String(text.prefix(ProjectClassifier.maxTextCharacters))
        #expect(request.user.hasSuffix(visibleText))
        #expect(!request.user.contains(String(text.suffix(3))))
        let system = request.system.lowercased()
        #expect(system.contains("text"))
        #expect(system.contains("instructions"))
    }

    @Test("Parsing normalizes keywords and only accepts text in the bounded prefix")
    func parseNormalizesAndBoundsKeywords() throws {
        let project = Project(name: "Thesis")
        let text = "important uppercase " + String(repeating: "x", count: 1_480) + " beyondkeyword"
        let reply = #"{"project":"Thesis","keywords":["  IMPORTANT  ","UPPERCASE","BEYONDKEYWORD"]}"#

        let result = try #require(ProjectClassifier.parse(reply, text: text, projects: [project]))
        #expect(result.projectID == project.id)
        #expect(result.keywords == ["important", "uppercase"])
    }

    @Test("Missing keywords are treated as empty and project names must match exactly")
    func parseRequiresExactProjectName() throws {
        let project = Project(name: "Thesis")
        let missingKeywords = try #require(
            ProjectClassifier.parse(#"{"project":"Thesis"}"#, text: "Thesis notes", projects: [project])
        )
        #expect(missingKeywords.keywords.isEmpty)
        #expect(ProjectClassifier.parse(#"{"project":"thesis","keywords":[]}"#,
                                        text: "Thesis notes", projects: [project]) == nil)
    }

    @Test("Project detection is case insensitive and adds names to learned words")
    func detectorAddsNameAndLearnedWordMatches() throws {
        var project = Project(name: "Thesis")
        project.trackingRules = [TrackingRule(kind: .learned, value: "outline")]
        let other = Project(name: "Shop")

        #expect(ProjectDetector.bestProject(in: "THESIS outline outline", projects: [project, other]) == project.id)
    }

    @Test("Empty context and no projects remain unassigned")
    func detectorReturnsNilWithoutEvidence() {
        let project = Project(name: "Thesis")
        #expect(ProjectDetector.bestProject(in: "", projects: [project]) == nil)
        #expect(ProjectDetector.bestProject(in: "Thesis", projects: []) == nil)
    }

    @Test("A tie between learned words remains unassigned")
    func detectorDoesNotGuessLearnedWordTies() {
        var thesis = Project(name: "Thesis")
        thesis.trackingRules = [TrackingRule(kind: .learned, value: "outline")]
        var shop = Project(name: "Shop")
        shop.trackingRules = [TrackingRule(kind: .learned, value: "cart")]

        #expect(ProjectDetector.bestProject(in: "outline cart", projects: [thesis, shop]) == nil)
    }

    @Test("Context filtering allows an empty exclusion list and only secure fields")
    func contextFilterEdgeCases() {
        #expect(ContextFilter.isAllowed(bundleID: "com.example.App", excluded: []))
        #expect(ContextFilter.isSecure(subrole: "AXSecureTextField"))
        #expect(!ContextFilter.isSecure(subrole: "AXTextField"))
        #expect(!ContextFilter.isSecure(subrole: nil))
    }
}
