import Testing
@testable import FocusFlow

@Suite("Turning notes into todos")
struct TodoRefinerTests {
    init() { TestSupport.isolate() }

    @Test func typedDurationWins() {
        #expect(TodoRefiner.explicitMinutes(in: "Steuer (30 min)") == 30)
        #expect(TodoRefiner.explicitMinutes(in: "Umzug planen 2h") == 120)
        #expect(TodoRefiner.explicitMinutes(in: "Anna anrufen") == nil)
    }

    @Test func heuristicCleansTitleAndGuesses() {
        let mail = TodoRefiner.heuristic("mail an anna schreiben")
        #expect(mail.title == "Mail an anna schreiben")
        #expect(mail.minutes == 3)
        let typed = TodoRefiner.heuristic("präsentation vorbereiten (40 min)")
        #expect(typed.title == "Präsentation vorbereiten")
        #expect(typed.minutes == 40)
        #expect(TodoRefiner.heuristic("irgendwas").minutes == 10)
    }

    @Test func modelAnswerIsSummedFromItsSteps() throws {
        let answer = """
            Sure: {"todos": [{"name": "Rechnung schicken", "parts": [{"description": "a", "minutes": 2},
            {"description": "b", "minutes": 3}]}, {"name": " ", "parts": [{"description": "c", "minutes": 4}]}]}
            """
        let todos = try #require(TodoRefiner.parse(answer))
        #expect(todos.count == 1)
        #expect(todos[0].title == "Rechnung schicken")
        #expect(todos[0].minutes == 5)
        #expect(TodoRefiner.parse("no json here") == nil)
    }

    @Test func promptNamesTheLanguage() {
        #expect(TodoRefiner.prompt(for: "PR reviewen und Anna anrufen").hasPrefix("Schreibe die Todos auf Deutsch"))
        #expect(TodoRefiner.prompt(for: "Call the landlord about the broken heating").hasPrefix("Write the todo names"))
    }
}
