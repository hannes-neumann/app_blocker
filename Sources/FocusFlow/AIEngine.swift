import Darwin
import Foundation
import Observation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case automatic, apple, ollama, off
    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: L10n.text("providerAutomatic")
        case .apple: "Apple Intelligence"
        case .ollama: L10n.text("providerOllama")
        case .off: L10n.text("providerOff")
        }
    }
}

struct AISettings: Codable, Equatable {
    var provider = AIProvider.automatic
    var ollamaURL = "http://localhost:11434"
    var ollamaModel = "gemma3:4b"
    /// Run a local `ollama serve` only while something needs it.
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
            Analytics.trackChanges(in: "ai", from: oldValue, to: settings)
            if !settings.startOllama { stopOwnedOllama() }
            if settings.provider != oldValue.provider || settings.startOllama != oldValue.startOllama {
                Task { await syncServer() }
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
    /// Who needs the server right now: a batch, the settings page, a download. At zero it stops.
    @ObservationIgnored private var serverHolds = 0
    @ObservationIgnored private var starting: Task<Void, Never>?
    /// Only a safety net if FocusFlow dies mid-batch; normally `withModel` frees the model right away.
    @ObservationIgnored private var keepAlive: String? = "30s"

    static let ollamaExecutable: URL? = [
        "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama",
    ].map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }

    private static let pidFile = Storage.directory.appendingPathComponent("ollama.pid")

    private var ollama: OllamaClient? {
        guard let url = URL(string: settings.ollamaURL), url.scheme != nil else { return nil }
        return OllamaClient(baseURL: url, model: settings.ollamaModel, keepAlive: keepAlive)
    }

    /// The model new notes go to right now, for display.
    var activeDescription: String {
        switch effectiveProvider {
        case .apple: "Apple Intelligence"
        case .ollama: "Ollama · \(settings.ollamaModel)"
        default: L10n.text("heuristicActive")
        }
    }

    var isUsingHeuristic: Bool { effectiveProvider != .apple && effectiveProvider != .ollama }

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
        stopOwnedOllama()
        Task { await checkOllama() }
    }

    func shutdown() {
        stopOwnedOllama()
    }

    // MARK: - Running Ollama on demand

    private var wantsOllama: Bool {
        settings.provider == .ollama || (settings.provider == .automatic && !appleStatus.isAvailable)
    }

    /// Runs `work` with the model available and frees its memory right after, without Ollama's 5 minutes of idling.
    func withModel(_ work: @MainActor () async -> Void) async {
        guard wantsOllama else { await work(); return }
        await holdServer()
        // A model that was loaded before the batch is someone else's, so it stays and keeps its own timeout.
        var isShared = false
        if ollamaStatus.isReady, let loaded = try? await ollama?.loadedModels() {
            isShared = Self.contains(loaded, settings.ollamaModel)
        }
        keepAlive = isShared ? nil : "30s"
        await work()
        if ollamaStatus.isReady && !isShared { try? await ollama?.unload() }
        keepAlive = "30s"
        releaseServer()
    }

    func holdServer() async {
        serverHolds += 1
        await startOllamaIfNeeded()
        await checkOllama()
    }

    func releaseServer() {
        serverHolds = max(serverHolds - 1, 0)
        guard serverHolds == 0, ownedOllamaPID != nil else { return }
        stopOwnedOllama()
        ollamaStatus = .unknown
    }

    private func syncServer() async {
        if serverHolds > 0 { await startOllamaIfNeeded() }
        await checkOllama()
    }

    private func startOllamaIfNeeded() async {
        if let starting {
            await starting.value
            return
        }
        let task = Task { await launchOllama() }
        starting = task
        await task.value
        starting = nil
    }

    /// Starts `ollama serve` unless one is already running (for example the Ollama app).
    private func launchOllama() async {
        guard settings.startOllama, wantsOllama, ownedOllamaPID == nil, let exe = Self.ollamaExecutable,
              let url = URL(string: settings.ollamaURL), ["localhost", "127.0.0.1"].contains(url.host) else { return }
        await checkOllama()
        guard ollamaStatus == .notRunning, serverHolds > 0 else { return }

        let process = Process()
        process.executableURL = exe
        process.arguments = ["serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = "127.0.0.1:\(url.port ?? 11434)"
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let started = Date()
        guard (try? process.run()) != nil else {
            Analytics.track(.ollamaStarted, ["success": false])
            return
        }
        ownedOllamaPID = process.processIdentifier
        try? String(process.processIdentifier).write(to: Self.pidFile, atomically: true, encoding: .utf8)

        // The server needs a moment before it answers.
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            guard ownedOllamaPID != nil else { return }
            await checkOllama()
            if ollamaStatus != .notRunning { break }
        }
        Analytics.track(.ollamaStarted, ["success": .bool(ollamaStatus != .notRunning),
                                         "duration_ms": .int(Int(Date().timeIntervalSince(started) * 1000))])
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
        let model = settings.ollamaModel, started = Date()
        Analytics.track(.modelPullStarted, ["model": .string(model)])
        serverHolds += 1
        Task {
            do {
                try await ollama.pull { [weak self] in self?.pullProgress = $0 }
            } catch {
                pullError = error.localizedDescription
            }
            Analytics.track(.modelPullFinished, ["model": .string(model), "success": .bool(pullError == nil),
                                                 "error": .string(pullError ?? ""),
                                                 "duration_seconds": .int(Int(Date().timeIntervalSince(started)))])
            ollamaStatus = .unknown
            await checkOllama()
            releaseServer()
        }
    }

    /// Classifies visible text with the local Ollama model: the project it is about and the words that
    /// identify it. Nil when no model is ready, no project clearly fits, or the answer is unusable.
    /// The text is never stored.
    func classifyProject(in text: String, projects: [Project]) async -> ProjectClassification? {
        guard settings.provider == .ollama || (settings.provider == .automatic && !appleStatus.isAvailable),
              ollamaStatus.isReady, !projects.isEmpty, let client = ollama else { return nil }
        let request = ProjectClassifier.request(text: text, projects: projects)
        guard let reply = try? await client.chat(system: request.system, user: request.user, schema: request.schema)
        else { return nil }
        return ProjectClassifier.parse(reply, text: text, projects: projects)
    }

    func refine(_ note: String) async -> (todos: [RefinedTodo], usedAI: Bool) {
        let provider = effectiveProvider, started = Date()
        var todos: [RefinedTodo]?
        switch provider {
        case .apple: todos = await TodoRefiner.refineWithApple(note)
        case .ollama: if let ollama { todos = await TodoRefiner.refineWithOllama(note, client: ollama) }
        default: break
        }
        if provider != .off {
            Analytics.track(.aiRequest, [
                "provider": .string(provider.rawValue),
                "model": .string(provider == .ollama ? settings.ollamaModel : "apple"),
                "success": .bool(todos != nil),
                "duration_ms": .int(Int(Date().timeIntervalSince(started) * 1000)),
            ])
        }
        if let todos { return (todos, true) }
        return ([TodoRefiner.heuristic(note)], false)
    }

    /// Ollama lists "llama3" as "llama3:latest".
    private static func contains(_ installed: [String], _ model: String) -> Bool {
        installed.contains(model) || (!model.contains(":") && installed.contains(model + ":latest"))
    }
}
