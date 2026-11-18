import Foundation
import Testing
@testable import FocusFlow

@MainActor
struct ProjectDetectorTests {
    @Test("The project named most often in the text wins")
    func mostMentionedProjectWins() {
        let thesis = Project(name: "Thesis")
        let shop = Project(name: "Shop")
        let text = "Thesis outline\nThesis chapter 2\nshop cart"
        #expect(ProjectDetector.bestProject(in: text, projects: [thesis, shop]) == thesis.id)
    }

    @Test("A tie leaves the text unassigned")
    func tieIsNotGuessed() {
        let thesis = Project(name: "Thesis")
        let shop = Project(name: "Shop")
        #expect(ProjectDetector.bestProject(in: "Thesis and Shop", projects: [thesis, shop]) == nil)
    }

    @Test("Names shorter than three characters are ignored")
    func shortNamesAreIgnored() {
        let short = Project(name: "AI")
        #expect(ProjectDetector.bestProject(in: "AI tools everywhere", projects: [short]) == nil)
    }
}
