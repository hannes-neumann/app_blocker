import Foundation
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

/// Turns a quick note into concrete todos with a duration estimate.
/// Uses Apple's on-device Foundation Model when available and a keyword heuristic otherwise.
enum TodoRefiner {
    static var status: AIStatus {
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

    static func refine(_ note: String) async -> (todos: [RefinedTodo], usedAI: Bool) {
        let explicit = explicitMinutes(in: note)
        #if canImport(FoundationModels)
        if #available(macOS 26, *), status.isAvailable,
           var todos = try? await refineWithModel(note), !todos.isEmpty {
            // A duration the user typed themselves beats the model's guess.
            if let explicit, todos.count == 1 { todos[0].minutes = explicit }
            return (todos.map { RefinedTodo(title: $0.title, minutes: clamp($0.minutes)) }, true)
        }
        #endif
        return ([heuristic(note, explicit: explicit)], false)
    }

    #if canImport(FoundationModels)
    private static let instructions = """
        Du verwandelst kurze, spontan notierte Gedanken in konkrete, umsetzbare Todos.
        Regeln:
        - Jedes Todo ist ein klarer nächster Schritt und beginnt mit einem Verb (z. B. "Anna wegen Termin anrufen").
        - Behalte die Sprache der Notiz bei.
        - Enthält die Notiz mehrere Aufgaben, gib mehrere Todos zurück. Erfinde keine zusätzlichen Aufgaben.
        - Schätze realistisch, wie viele Minuten die Aufgabe dauert (ganze Zahl zwischen 1 und 480).
        - Antworte ausschließlich mit einem JSON-Array ohne weiteren Text, z. B.:
          [{"title": "Rechnung an Kunde X schicken", "minutes": 5}]
        """

    @available(macOS 26, *)
    private static func refineWithModel(_ note: String) async throws -> [RefinedTodo]? {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: "Notiz: \(note)",
            options: GenerationOptions(temperature: 0.2)
        )
        return parse(response.content)
    }
    #endif

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

    private static func heuristic(_ note: String, explicit: Int?) -> RefinedTodo {
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
