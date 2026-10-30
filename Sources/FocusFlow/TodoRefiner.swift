import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

struct RefinedTodo: Codable {
    var title: String
    var minutes: Int
}

enum AIStatus: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }
}

/// Turns a quick note into concrete todos with a duration estimate, with a language model
/// (see `AIEngine`) or a keyword heuristic.
enum TodoRefiner {
    static var appleStatus: AIStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable("Dieser Mac unterstützt Apple Intelligence nicht.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Apple Intelligence ist in den Systemeinstellungen deaktiviert.")
            case .unavailable(.modelNotReady):
                return .unavailable("Das Apple-Modell wird noch geladen.")
            @unknown default:
                return .unavailable("Apple Intelligence ist nicht verfügbar.")
            }
        }
        #endif
        return .unavailable("Benötigt macOS 26 mit Apple Intelligence.")
    }

    private static let instructions = """
        Du verwandelst kurze, spontan notierte Gedanken in konkrete, umsetzbare Todos.
        Regeln:
        - Jedes Todo ist ein klarer nächster Schritt und beginnt mit einem Verb (z. B. "Anna wegen Termin anrufen").
        - Schreibe die Todos in der Sprache, die in der Anfrage genannt ist, und mische keine Sprachen.
        - Ein Todo pro Aufgabe, die in der Notiz steht. Mehrere Todos nur, wenn die Notiz ausdrücklich mehrere
          Aufgaben nennt (z. B. mit "und" oder Kommas). Zerlege eine einzelne Aufgabe nicht in Unterschritte.
        - Verwende nur, was in der Notiz steht. Erfinde keine Namen, Personen, Orte, Adressen oder Details.
        - Schätze realistisch, wie lange eine geübte Person für genau diesen Schritt braucht, in ganzen Minuten.
          Richtwerte: kurze Nachricht oder Mail 5, Anruf oder Termin ausmachen 10, Einkauf 15,
          Logs durchsehen 20, Unterlagen sortieren 30, kleinen Bug beheben 45, Text- oder Blogentwurf 60,
          Präsentation vorbereiten 90, Kapitel einer Abschlussarbeit überarbeiten 120.
        - Antworte ausschließlich mit JSON ohne weiteren Text, z. B.:
          {"todos": [{"title": "Rechnung an Kunde X schicken", "minutes": 5}]}
        """

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "todos": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": ["title": ["type": "string"], "minutes": ["type": "integer"]],
                    "required": ["title", "minutes"],
                ],
            ],
        ],
        "required": ["todos"],
    ]

    static func refineWithApple(_ note: String) async -> [RefinedTodo]? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession(instructions: instructions)
            guard let response = try? await session.respond(to: prompt(for: note), options: GenerationOptions(temperature: 0))
            else { return nil }
            return finish(parse(response.content), note: note)
        }
        #endif
        return nil
    }

    static func refineWithOllama(_ note: String, client: OllamaClient) async -> [RefinedTodo]? {
        // One retry: the first request after a while has to load the model, which can fail on a busy Mac.
        var text = try? await client.chat(system: instructions, user: prompt(for: note), schema: schema, temperature: 0)
        if text == nil { text = try? await client.chat(system: instructions, user: prompt(for: note), schema: schema, temperature: 0) }
        guard let text else { return nil }
        return finish(parse(text), note: note)
    }

    /// Names the note's language explicitly: small models otherwise answer in the language of the instructions.
    private static func prompt(for note: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english, .french, .spanish, .italian, .dutch]
        recognizer.processString(note)
        let language = recognizer.dominantLanguage
            .flatMap { Locale(identifier: "de").localizedString(forLanguageCode: $0.rawValue) } ?? "Deutsch"
        return "Sprache der Todos: \(language)\nNotiz: \(note)"
    }

    /// Clamps the model's estimates. A duration the user typed themselves beats the model's guess.
    private static func finish(_ todos: [RefinedTodo]?, note: String) -> [RefinedTodo]? {
        guard var todos, !todos.isEmpty else { return nil }
        if let explicit = explicitMinutes(in: note), todos.count == 1 { todos[0].minutes = explicit }
        return todos.map { RefinedTodo(title: $0.title, minutes: clamp($0.minutes)) }
    }

    static func parse(_ text: String) -> [RefinedTodo]? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end else { return nil }
        let todos = try? JSONDecoder().decode([RefinedTodo].self, from: Data(text[start...end].utf8))
        return todos?.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Fallback

    private static let keywordEstimates: [(keywords: [String], minutes: Int)] = [
        (["mail", "e-mail", "nachricht", "antworten", "schreib", "whatsapp", "slack"], 5),
        (["anruf", "anrufen", "telefon", "call"], 10),
        (["kaufen", "bestellen", "buchen", "überweis", "bezahl"], 10),
        (["aufräumen", "putzen", "wäsche", "abwasch"], 15),
        (["lesen", "recherch", "nachschauen", "herausfinden", "prüfen"], 20),
        (["entwurf", "konzept", "präsentation", "bericht", "artikel", "planen"], 45),
    ]

    static func heuristic(_ note: String) -> RefinedTodo {
        let explicit = explicitMinutes(in: note)
        // Drop a typed duration like "(20 min)" from the title; it already becomes the estimate.
        let withoutDuration = note
            .replacingOccurrences(of: #"\(?\s*\d+\s*(minuten|minutes|min|m|stunden|std|hours|h)\b\s*\)?"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = withoutDuration.isEmpty ? note.trimmingCharacters(in: .whitespacesAndNewlines) : withoutDuration
        let title = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        let lower = trimmed.lowercased()
        let guess = keywordEstimates.first { entry in entry.keywords.contains { lower.contains($0) } }?.minutes
        return RefinedTodo(title: title, minutes: clamp(explicit ?? guess ?? 10))
    }

    /// Picks up durations typed into the note, e.g. "Steuer (30 min)" or "Umzug planen 2h".
    static func explicitMinutes(in note: String) -> Int? {
        let pattern = #"(\d+)\s*(minuten|minutes|min|m|stunden|std|hours|h)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: note, range: NSRange(note.startIndex..., in: note)),
              let numberRange = Range(match.range(at: 1), in: note),
              let unitRange = Range(match.range(at: 2), in: note),
              let value = Int(note[numberRange]) else { return nil }
        let isHours = ["stunden", "std", "hours", "h"].contains(note[unitRange].lowercased())
        return clamp(isHours ? value * 60 : value)
    }

    private static func clamp(_ minutes: Int) -> Int { min(max(minutes, 1), 480) }
}
