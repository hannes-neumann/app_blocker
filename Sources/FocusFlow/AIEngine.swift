import Foundation
import Observation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case automatic, apple, ollama, off
    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatisch"
        case .apple: "Apple Intelligence"
        case .ollama: "Ollama (lokal)"
        case .off: "Aus (nur Stichwörter)"
        }
    }
}

struct AISettings: Codable, Equatable {
    var provider = AIProvider.automatic
    var ollamaURL = "http://localhost:11434"
    var ollamaModel = "gemma3:4b"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AISettings()
        provider = (try? c.decodeIfPresent(AIProvider.self, forKey: .provider)) ?? d.provider
        ollamaURL = try c.decodeIfPresent(String.self, forKey: .ollamaURL) ?? d.ollamaURL
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? d.ollamaModel
    }
}

enum OllamaStatus: Equatable {
    case unknown
    case checking
    case notRunning
    case modelMissing(installed: [String])
    case pulling
    case ready(installed: [String])

    var isReady: Bool { if case .ready = self { true } else { false } }

    var installed: [String] {
        switch self {
        case .modelMissing(let models), .ready(let models): models
        default: []
        }
    }
}

/// Picks the language model for turning notes into todos: Apple's on-device model, a local Ollama
/// model, or the keyword heuristic as the fallback.
@MainActor @Observable
final class AIEngine {
    var settings: AISettings = Storage.load(AISettings.self, from: "ai.json") ?? AISettings() {
        didSet {
            Storage.save(settings, to: "ai.json")
            if settings.ollamaURL != oldValue.ollamaURL || settings.ollamaModel != oldValue.ollamaModel {
                Task { await checkOllama() }
            }
        }
    }
    private(set) var appleStatus: AIStatus = .unavailable("")
    private(set) var ollamaStatus: OllamaStatus = .unknown
    private(set) var pullError: String?

    private var ollama: OllamaClient? {
        guard let url = URL(string: settings.ollamaURL), url.scheme != nil else { return nil }
        return OllamaClient(baseURL: url, model: settings.ollamaModel)
    }

    /// The model new notes go to right now, for display.
    var activeDescription: String {
        switch effectiveProvider {
        case .apple: "Apple Intelligence"
        case .ollama: "Ollama · \(settings.ollamaModel)"
        default: "Stichwort-Schätzung (keine KI)"
        }
    }

    private var effectiveProvider: AIProvider {
        switch settings.provider {
        case .automatic: appleStatus.isAvailable ? .apple : ollamaStatus.isReady ? .ollama : .off
        case .apple: appleStatus.isAvailable ? .apple : .off
        case .ollama: ollamaStatus.isReady ? .ollama : .off
        case .off: .off
        }
    }

    func refreshStatus() {
        appleStatus = TodoRefiner.appleStatus
        Task { await checkOllama() }
    }

    func checkOllama() async {
        guard let ollama else { ollamaStatus = .notRunning; return }
        ollamaStatus = .checking
        do {
            let installed = try await ollama.installedModels()
            ollamaStatus = Self.contains(installed, settings.ollamaModel) ? .ready(installed: installed) : .modelMissing(installed: installed)
        } catch {
            ollamaStatus = .notRunning
        }
    }

    func pullModel() {
        guard let ollama else { return }
        pullError = nil
        ollamaStatus = .pulling
        Task {
            do { try await ollama.pull() } catch { pullError = error.localizedDescription }
            await checkOllama()
        }
    }

    func refine(_ note: String) async -> (todos: [RefinedTodo], usedAI: Bool) {
        // Ollama may have been started since the last check.
        if !ollamaStatus.isReady && [.automatic, .ollama].contains(settings.provider) && !appleStatus.isAvailable {
            await checkOllama()
        }
        switch effectiveProvider {
        case .apple:
            if let todos = await TodoRefiner.refineWithApple(note) { return (todos, true) }
        case .ollama:
            if let ollama, let todos = await TodoRefiner.refineWithOllama(note, client: ollama) { return (todos, true) }
        default:
            break
        }
        return ([TodoRefiner.heuristic(note)], false)
    }

    /// Ollama lists "llama3" as "llama3:latest".
    private static func contains(_ installed: [String], _ model: String) -> Bool {
        installed.contains(model) || (!model.contains(":") && installed.contains(model + ":latest"))
    }
}
