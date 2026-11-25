import Foundation
import Testing
@testable import FocusFlow

@Suite("Localization")
struct LocalizationTests {
    init() { TestSupport.isolate() }

    @Test("Every text exists in German and English")
    func bothLanguages() {
        for (key, values) in L10n.translations {
            for language in [AppLanguage.german, .english] {
                let text = values[language] ?? ""
                #expect(!text.trimmingCharacters(in: .whitespaces).isEmpty, "\(key) has no \(language) text")
            }
        }
    }

    @Test("German and English take the same placeholders")
    func samePlaceholders() throws {
        let regex = try NSRegularExpression(pattern: #"%(\d+\$)?[@dlfsu]+"#)
        func placeholders(_ text: String) -> [String] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }.sorted()
        }
        for (key, values) in L10n.translations {
            #expect(placeholders(values[.german] ?? "") == placeholders(values[.english] ?? ""), "\(key)")
        }
    }

    @Test("Address label is localized")
    func addressLabel() {
        #expect(L10n.translations["address"]?[.german] == "Adresse")
        #expect(L10n.translations["address"]?[.english] == "Address")
    }
}
