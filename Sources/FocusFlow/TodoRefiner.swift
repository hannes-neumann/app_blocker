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
                return .unavailable(L10n.text("appleNotSupported"))
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(L10n.text("appleDisabled"))
            case .unavailable(.modelNotReady):
                return .unavailable(L10n.text("appleLoading"))
            @unknown default:
                return .unavailable(L10n.text("appleUnavailable"))
            }
        }
        #endif
        return .unavailable(L10n.text("appleNeedsMacOS26"))
    }

    static let instructions = """
        Du verwandelst kurze, spontan notierte Gedanken in konkrete, umsetzbare Todos.
        Regeln:
        - Jedes Todo ist ein klarer nächster Schritt und beginnt mit einem Verb (z. B. "Anna wegen Termin anrufen").
        - Schreibe die Todos in der Sprache, die in der Anfrage genannt ist, und mische keine Sprachen.
        - Ein Todo pro Aufgabe, die in der Notiz steht. Mehrere Todos nur, wenn die Notiz ausdrücklich mehrere
          Aufgaben nennt (z. B. mit "und" oder Kommas). Zerlege eine einzelne Aufgabe nicht in Unterschritte.
        - Verwende nur, was in der Notiz steht. Erfinde keine Namen, Personen, Orte, Adressen oder Details.
        - Der Titel beschreibt dieselbe Aufgabe wie die Notiz, nur klarer formuliert. Ersetze sie nicht durch
          einen anderen Schritt (aus "Flug buchen" wird "Flug nach Berlin buchen", nicht "Flugpreise vergleichen").
        - Schätze die gesamte Aufgabe für eine geübte Person konservativ und in möglichst wenigen Minuten.
          Zerlege nur dann in mehrere Schritte, wenn die Notiz ausdrücklich mehrere Aufgaben nennt oder die
          Aufgabe ohne Zerlegung nicht verständlich wäre. Erfinde keine Vorbereitung, Wege, Wartezeit oder
          Nachbereitung. Kleine Routinen wie E-Mails prüfen, eine kurze Nachricht schreiben oder kurz anrufen
          dauern meist 1 bis 3 Minuten insgesamt, nicht pro Unterschritt. Runde nicht auf 5er-Schritte auf.
          Größere Aufgaben (Präsentation, Kapitel überarbeiten, Feature bauen) dürfen länger dauern, aber
          schätze nur die konkret genannte Arbeit.
        - Antworte ausschließlich mit JSON ohne weiteren Text, z. B.:
          {"todos": [{"name": "Rechnung an Kunde X schicken", "parts": [
            {"description": "Rechnung im Ordner suchen", "minutes": 2},
            {"description": "Mail mit Anhang schreiben", "minutes": 3},
            {"description": "Abschicken und ablegen", "minutes": 1}]}]}
        """

    // Keys are sent sorted (see OllamaClient), and constrained decoding writes them in that order, so they are
    // named such that the model writes a step's description before its minutes and the name before the parts.
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "todos": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "parts": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "description": ["type": "string"],
                                    "minutes": ["type": "integer", "minimum": 1, "maximum": 240],
                                ],
                                "required": ["description", "minutes"],
                            ],
                        ],
                    ],
                    "required": ["name", "parts"],
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
    static func prompt(for note: String) -> String {
        // Short notes often mix in English terms ("PR reviewen"), so only a clear English note counts as English.
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english]
        recognizer.processString(note)
        let english = (recognizer.languageHypotheses(withMaximum: 2)[.english] ?? 0) > 0.75
        // Small models follow the language of the request more than an instruction naming it.
        return english
            ? "Write the todo names and parts in natural English, not German, starting with the verb (e.g. \"Call Anna about the meeting\").\nNote: \(note)"
            : "Schreibe die Todos auf Deutsch.\nNotiz: \(note)"
    }

    /// Clamps the model's estimates. A duration the user typed themselves beats the model's guess.
    private static func finish(_ todos: [RefinedTodo]?, note: String) -> [RefinedTodo]? {
        guard var todos, !todos.isEmpty else { return nil }
        if let explicit = explicitMinutes(in: note), todos.count == 1 { todos[0].minutes = explicit }
        return todos.map { RefinedTodo(title: $0.title, minutes: clamp($0.minutes)) }
    }

    /// The model's answer. The estimate is the sum of the steps, which comes out more precise than
    /// asking for a single number (small models pick round or example values for that).
    private struct Answer: Decodable {
        struct Item: Decodable {
            struct Part: Decodable { let minutes: Int }
            let name: String
            let parts: [Part]
        }
        let todos: [Item]
    }

    static func parse(_ text: String) -> [RefinedTodo]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let answer = try? JSONDecoder().decode(Answer.self, from: Data(text[start...end].utf8)) else { return nil }
        return answer.todos.compactMap { item in
            let title = item.name.trimmingCharacters(in: .whitespaces)
            let minutes = item.parts.reduce(0) { $0 + min(max($1.minutes, 0), 240) }
            return title.isEmpty || minutes == 0 ? nil : RefinedTodo(title: title, minutes: minutes)
        }
    }

    // MARK: - Fallback

    private static let keywordEstimates: [(keywords: [String], minutes: Int)] = [
        (["mail", "e-mail", "email", "nachricht", "antworten", "schreib", "whatsapp", "slack"], 3),
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
