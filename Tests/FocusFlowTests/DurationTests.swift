import Testing
@testable import FocusFlow

@Suite("Durations")
struct DurationTests {
    init() { TestSupport.isolate() }

    @Test("Typed durations", arguments: [
        ("45", 45), ("45 min", 45), ("1h", 60), ("1,5 h", 90), ("1.5h", 90), ("1:30", 90), ("1h 30", 90), ("  25  ", 25),
    ])
    func parses(_ input: String, _ minutes: Int) {
        #expect(parseDuration(input) == minutes)
    }

    @Test("Nonsense is rejected", arguments: ["", "abc", "min"])
    func rejects(_ input: String) {
        #expect(parseDuration(input) == nil)
    }

    @Test("Focus durations use minutes unless formatted as hours and minutes", arguments: [
        ("45", 45), ("1:05", 65), ("  25  ", 25), ("0:30", 30),
    ])
    func parsesFocusDuration(_ input: String, _ minutes: Int) {
        #expect(parseFocusDuration(input) == minutes)
    }

    @Test("Focus durations reject explicit units", arguments: ["45 min", "1h", "1,5", "1:60", "0"])
    func rejectsFocusDuration(_ input: String) {
        #expect(parseFocusDuration(input) == nil)
    }

    @Test func formatsMinutes() {
        L10n.language = .german
        #expect(formatMinutes(25) == "25 Min")
        #expect(formatMinutes(90) == "1:30 h")
    }
}
