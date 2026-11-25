import Foundation
import Testing
@testable import FocusFlow

@Suite("Context privacy filtering")
struct ContextFilterTests {
    init() { TestSupport.isolate() }

    @Test func excludedBundleIDsAreDenied() {
        let excluded = Set(ContextFilter.defaultExcludedBundleIDs)

        #expect(!ContextFilter.isAllowed(bundleID: "com.1password.1password", excluded: excluded))
        #expect(!ContextFilter.isAllowed(bundleID: "net.whatsapp.WhatsApp", excluded: excluded))
        #expect(ContextFilter.isAllowed(bundleID: "com.google.Chrome", excluded: excluded))
    }

    @Test func customExclusionListIsApplied() {
        let excluded: Set<String> = ["com.example.SecretApp"]

        #expect(!ContextFilter.isAllowed(bundleID: "com.example.SecretApp", excluded: excluded))
        #expect(ContextFilter.isAllowed(bundleID: "com.apple.Notes", excluded: excluded))
    }

    @Test func secureTextFieldsAreFilteredBySubrole() {
        #expect(ContextFilter.isSecure(subrole: "AXSecureTextField"))
        #expect(!ContextFilter.isSecure(subrole: "AXTextField"))
        #expect(!ContextFilter.isSecure(subrole: nil))
    }

    @Test func defaultExclusionsIncludePasswordManagersAndWhatsApp() {
        #expect(ContextFilter.defaultExcludedBundleIDs.contains("com.1password.1password"))
        #expect(ContextFilter.defaultExcludedBundleIDs.contains("com.bitwarden.desktop"))
        #expect(ContextFilter.defaultExcludedBundleIDs.contains("net.whatsapp.WhatsApp"))
    }

    @Test func trackedSegmentsDoNotContainRawContextTextFields() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let segment = ActivitySegment(
            start: now,
            end: now.addingTimeInterval(5),
            bundleID: "com.example.App",
            appName: "Example",
            title: nil,
            address: nil
        )

        let mirror = Mirror(reflecting: segment)
        let fieldNames = Set(mirror.children.compactMap(\.label))
        #expect(!fieldNames.contains("rawText"))
        #expect(!fieldNames.contains("windowText"))
        #expect(!fieldNames.contains("contextText"))
        #expect(!fieldNames.contains("body"))
    }
}
