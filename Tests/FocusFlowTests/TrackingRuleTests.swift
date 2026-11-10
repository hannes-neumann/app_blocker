import Foundation
import Testing
@testable import FocusFlow

@Suite("Automatic time tracking rules")
@MainActor
struct TrackingRuleTests {
    init() { TestSupport.isolate() }

    func project(_ name: String, _ rules: [TrackingRule]) -> Project {
        var project = Project(name: name)
        project.trackingRules = rules
        return project
    }

    @Test func normalizesAddresses() {
        #expect(TrackingRule.normalizedAddress("https://www.GitHub.com/acme/?tab=1") == "github.com/acme")
        #expect(TrackingRule.normalizedAddress("moodle.uni.de") == "moodle.uni.de")
        #expect(TrackingRule.normalizedAddress("ftp://x.de") == nil)
        #expect(TrackingRule.normalizedAddress("  ") == nil)
    }

    @Test func domainRulesMatchSubdomainsAndPaths() {
        let rule = TrackingRule(kind: .domain, value: "github.com/acme")
        #expect(rule.matches(bundleID: "x", title: nil, address: "github.com/acme/app/pulls"))
        #expect(rule.matches(bundleID: "x", title: nil, address: "gist.github.com/acme"))
        #expect(!rule.matches(bundleID: "x", title: nil, address: "github.com/other"))
        #expect(!rule.matches(bundleID: "x", title: nil, address: "notgithub.com/acme"))
    }

    @Test func titleRulesIgnoreCase() {
        let rule = TrackingRule(kind: .title, value: "Übungsblatt")
        #expect(rule.matches(bundleID: "x", title: "übungsblatt 3.pdf", address: nil))
        #expect(!rule.matches(bundleID: "x", title: nil, address: nil))
    }

    @Test func mostSpecificRuleWins() throws {
        let app = project("App", [TrackingRule(kind: .app, value: "com.google.Chrome")])
        let title = project("Title", [TrackingRule(kind: .title, value: "Analysis")])
        let domain = project("Domain", [TrackingRule(kind: .domain, value: "moodle.uni.de")])
        let all = [app, title, domain]
        let byDomain = try #require(ActivityTracker.match(all, bundleID: "com.google.Chrome", title: "Analysis", address: "moodle.uni.de/course"))
        #expect(byDomain.project == domain.id)
        let byTitle = try #require(ActivityTracker.match(all, bundleID: "com.google.Chrome", title: "Analysis", address: "example.com"))
        #expect(byTitle.project == title.id)
        let byApp = try #require(ActivityTracker.match(all, bundleID: "com.google.Chrome", title: nil, address: nil))
        #expect(byApp.project == app.id)
        #expect(ActivityTracker.match(all, bundleID: "com.apple.Notes", title: nil, address: nil) == nil)
    }

    @Test func sideWindowCountsWhenItIsMoreSpecific() throws {
        let chat = project("Chat", [TrackingRule(kind: .app, value: "com.anthropic.claudefordesktop")])
        let uni = project("Uni", [TrackingRule(kind: .title, value: "Übungsblatt")])
        let pdf = SideWindow(bundleID: "com.apple.Preview", appName: "Vorschau", title: "Übungsblatt 3.pdf", address: nil)
        let result = try #require(ActivityTracker.match([chat, uni], bundleID: "com.anthropic.claudefordesktop", title: "Claude",
                                                        address: nil, side: pdf))
        #expect(result.project == uni.id)
        #expect(result.bySide)
    }

    @Test func frontAppWinsATie() throws {
        let a = project("A", [TrackingRule(kind: .app, value: "front")])
        let b = project("B", [TrackingRule(kind: .app, value: "side")])
        let side = SideWindow(bundleID: "side", appName: "Side", title: nil, address: nil)
        let result = try #require(ActivityTracker.match([a, b], bundleID: "front", title: nil, address: nil, side: side))
        #expect(result.project == a.id)
        #expect(!result.bySide)
    }
}
