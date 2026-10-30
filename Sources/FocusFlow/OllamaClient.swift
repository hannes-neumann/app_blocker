import Foundation

/// Minimal client for a local Ollama server (https://ollama.com), which runs open models on this Mac.
struct OllamaClient {
    var baseURL: URL
    var model: String

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

    /// One chat turn. `schema` is a JSON schema the answer is constrained to.
    func chat(system: String, user: String, schema: [String: Any], temperature: Double = 0.2) async throws -> String {
        struct Reply: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "format": schema,
            "options": ["temperature": temperature],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Loading a model into memory the first time can take a while.
        request.timeoutInterval = 120
        let reply: Reply = try await send(request)
        return reply.message.content
    }

    /// Downloads a model. Returns once the download is complete, which can take minutes.
    func pull() async throws {
        struct Status: Decodable { let status: String }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": false])
        request.timeoutInterval = 3600
        let status: Status = try await send(request)
        guard status.status == "success" else { throw Failure(message: status.status) }
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
