import Foundation

/// Minimal client for a local Ollama server (https://ollama.com), which runs open models on this Mac.
struct OllamaClient {
    var baseURL: URL
    var model: String
    /// How long Ollama keeps the model in memory after a chat turn, e.g. "30s". nil is Ollama's default of 5 minutes.
    var keepAlive: String?

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Names of the models that are downloaded, e.g. "gemma3:4b".
    func installedModels() async throws -> [String] {
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        let tags: Tags = try await send(request)
        return tags.models.map(\.name).sorted()
    }

    /// Names of the models that are in memory right now.
    func loadedModels() async throws -> [String] {
        struct Running: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/ps"))
        request.timeoutInterval = 3
        let running: Running = try await send(request)
        return running.models.map(\.name)
    }

    /// Frees the model's memory right away.
    func unload() async throws {
        struct Reply: Decodable {}
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": 0] as [String: Any])
        request.timeoutInterval = 10
        let _: Reply = try await send(request)
    }

    /// One chat turn. `schema` is a JSON schema the answer is constrained to.
    func chat(system: String, user: String, schema: [String: Any], temperature: Double = 0.2) async throws -> String {
        struct Reply: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "format": schema,
            "options": ["temperature": temperature],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        if let keepAlive { body["keep_alive"] = keepAlive }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Sorted keys keep the schema's property order, and with it the order the model writes fields in, stable.
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        // Loading a model into memory the first time can take a while.
        request.timeoutInterval = 120
        let reply: Reply = try await send(request)
        return reply.message.content
    }

    /// Downloads a model and reports progress (0...1) while the data streams in.
    func pull(progress: @escaping @MainActor (Double) -> Void) async throws {
        struct Update: Decodable {
            let status: String?
            let total: Int64?
            let completed: Int64?
            let error: String?
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
        // Applies between received chunks, so a slow but steady download never times out.
        request.timeoutInterval = 120
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure(message: "HTTP \(http.statusCode)")
        }
        var finished = false
        for try await line in bytes.lines {
            guard let update = try? JSONDecoder().decode(Update.self, from: Data(line.utf8)) else { continue }
            if let error = update.error { throw Failure(message: error) }
            if let total = update.total, total > 0, let completed = update.completed {
                await progress(Double(completed) / Double(total))
            }
            if update.status == "success" { finished = true }
        }
        guard finished else { throw Failure(message: "Download abgebrochen") }
    }

    private struct ErrorBody: Decodable { let error: String }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw Failure(message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
