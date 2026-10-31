import Darwin
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
    /// Run a local `ollama serve` only while FocusFlow is open.
    var startOllama = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AISettings()
        provider = (try? c.decodeIfPresent(AIProvider.self, forKey: .provider)) ?? d.provider
        ollamaURL = try c.decodeIfPresent(String.self, forKey: .ollamaURL) ?? d.ollamaURL
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? d.ollamaModel
        startOllama = try c.decodeIfPresent(Bool.self, forKey: .startOllama) ?? d.startOllama
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
            if !settings.startOllama { stopOwnedOllama() }
            if settings.provider != oldValue.provider || settings.startOllama != oldValue.startOllama {
                Task { await startOllamaIfNeeded() }
            } else if settings.ollamaURL != oldValue.ollamaURL || settings.ollamaModel != oldValue.ollamaModel {
                Task { await checkOllama() }
            }
        }
    }
    private(set) var appleStatus: AIStatus = .unavailable("")
    private(set) var ollamaStatus: OllamaStatus = .unknown
    private(set) var pullError: String?
    /// Download progress of the model (0...1) while `ollamaStatus` is `.pulling`.
    private(set) var pullProgress: Double = 0
    /// The `ollama serve` FocusFlow started itself and stops again on quit.
    @ObservationIgnored private var ownedOllamaPID: pid_t?

    static let ollamaExecutable: URL? = [
        "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama",
    ].map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }

    private static let pidFile = Storage.directory.appendingPathComponent("ollama.pid")

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
        adoptLeftoverOllama()
        Task {
            await startOllamaIfNeeded()
            await checkOllama()
        }
    }

    func shutdown() {
        stopOwnedOllama()
    }

    // MARK: - Running Ollama alongside the app

    private var wantsOllama: Bool {
        settings.provider == .ollama || (settings.provider == .automatic && !appleStatus.isAvailable)
    }

    /// Starts `ollama serve` unless one is already running (for example the Ollama app).
    func startOllamaIfNeeded() async {
        guard settings.startOllama, wantsOllama, ownedOllamaPID == nil, let exe = Self.ollamaExecutable,
              let url = URL(string: settings.ollamaURL), ["localhost", "127.0.0.1"].contains(url.host) else { return }
        await checkOllama()
        guard ollamaStatus == .notRunning else { return }

        let process = Process()
        process.executableURL = exe
        process.arguments = ["serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = "127.0.0.1:\(url.port ?? 11434)"
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        ownedOllamaPID = process.processIdentifier
        try? String(process.processIdentifier).write(to: Self.pidFile, atomically: true, encoding: .utf8)

        // The server needs a moment before it answers.
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            await checkOllama()
            if ollamaStatus != .notRunning { break }
        }
    }

    private func stopOwnedOllama() {
        guard let pid = ownedOllamaPID else { return }
        kill(pid, SIGTERM)
        ownedOllamaPID = nil
        try? FileManager.default.removeItem(at: Self.pidFile)
    }

    /// After a crash, the server FocusFlow started is still running. Take it over so quitting stops it.
    private func adoptLeftoverOllama() {
        guard let text = try? String(contentsOf: Self.pidFile, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }
        var name = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &name, UInt32(name.count)) > 0, String(cString: name) == "ollama" {
            ownedOllamaPID = pid
        } else {
            try? FileManager.default.removeItem(at: Self.pidFile)
        }
    }

    func checkOllama() async {
        // A running download owns the status until it is done.
        guard ollamaStatus != .pulling else { return }
        guard let ollama else { ollamaStatus = .notRunning; return }
        ollamaStatus = .checking
        do {
            let installed = try await ollama.installedModels()
            guard ollamaStatus != .pulling else { return }
            ollamaStatus = Self.contains(installed, settings.ollamaModel) ? .ready(installed: installed) : .modelMissing(installed: installed)
        } catch {
            if ollamaStatus != .pulling { ollamaStatus = .notRunning }
        }
    }

    func pullModel() {
        guard let ollama else { return }
        pullError = nil
        ollamaStatus = .pulling
        pullProgress = 0
        Task {
            do {
                try await ollama.pull { [weak self] in self?.pullProgress = $0 }
            } catch {
                pullError = error.localizedDescription
            }
            ollamaStatus = .unknown
            await checkOllama()
        }
    }

    func refine(_ note: String) async -> (todos: [RefinedTodo], usedAI: Bool) {
        // Ollama may have been started since the last check.
        if !ollamaStatus.isReady && wantsOllama {
            await startOllamaIfNeeded()
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
