import Foundation
import Testing
@testable import FocusFlow

@MainActor
struct ProjectClassifierTests {
    private let thesis = Project(name: "Thesis")
    private let shop = Project(name: "Shop")

    @Test("A known project and words from the text are accepted")
    func parsesAnAnswer() {
        let text = "Thesis outline, chapter two: literature review"
        let reply = #"{"project": "Thesis", "keywords": ["literature", "outline"]}"#
        let result = ProjectClassifier.parse(reply, text: text, projects: [thesis, shop])
        #expect(result == ProjectClassification(projectID: thesis.id, keywords: ["literature", "outline"]))
    }

    @Test("Answers naming no known project or 'none' are rejected")
    func rejectsUnknownAnswers() {
        let text = "Thesis outline"
        #expect(ProjectClassifier.parse(#"{"project": "none", "keywords": []}"#, text: text, projects: [thesis]) == nil)
        #expect(ProjectClassifier.parse(#"{"project": "Garden", "keywords": ["outline"]}"#, text: text, projects: [thesis]) == nil)
        #expect(ProjectClassifier.parse("not json", text: text, projects: [thesis]) == nil)
    }

    @Test("Keywords the text does not contain, names, stopwords and short words are dropped")
    func keywordsMustBeInTheText() {
        let text = "Thesis outline with the file open"
        let raw = ["invented", "thesis", "with", "outline", "ok", "outline"]
        #expect(ProjectClassifier.validKeywords(raw, text: text, projects: [thesis]) == ["outline"])
    }

    @Test("At most five keywords are kept")
    func keywordLimit() {
        let text = "alpha bravo charlie delta echo foxtrot golf"
        let raw = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf"]
        #expect(ProjectClassifier.validKeywords(raw, text: text, projects: []).count == ProjectClassifier.maxKeywords)
    }

    @Test("Learned words count like a project name in the detector")
    func learnedWordsDetect() {
        var learned = Project(name: "Garden")
        learned.trackingRules = [TrackingRule(kind: .learned, value: "tomatoes")]
        let text = "Tomatoes need water, tomatoes need sun"
        #expect(ProjectDetector.bestProject(in: text, projects: [learned, shop]) == learned.id)
    }

    @Test("Learned words never match window metadata")
    func learnedWordsAreTextOnly() {
        let rule = TrackingRule(kind: .learned, value: "tomatoes")
        #expect(rule.matches(bundleID: "x", title: "tomatoes", address: nil) == false)
    }
}
