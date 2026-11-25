import Foundation
import Testing
@testable import FocusFlow

/// Runs the real classifier against a local Ollama server. Skipped unless FOCUSFLOW_OLLAMA_MODEL names an
/// installed model, e.g. `FOCUSFLOW_OLLAMA_MODEL=gemma3:4b scripts/test.sh --filter Ollama`.
@MainActor
struct OllamaClassifierTests {
    private static let model = ProcessInfo.processInfo.environment["FOCUSFLOW_OLLAMA_MODEL"]

    private let thesis = Project(name: "Thesis")
    private let shop = Project(name: "Shop")
    private let taxes = Project(name: "Steuern")

    @Test("Local model assigns clear screens to the right project",
          .enabled(if: model != nil, "set FOCUSFLOW_OLLAMA_MODEL to run"))
    func classifiesScreens() async throws {
        let client = OllamaClient(baseURL: URL(string: "http://localhost:11434")!, model: Self.model ?? "", keepAlive: nil)
        let projects = [thesis, shop, taxes]
        let samples: [(text: String, expected: UUID)] = [
            ("Thesis outline - chapter 2 literature review\nReferences: Mayer 2019, Sweller 1988", thesis.id),
            ("Shopify order #4411 pending shipment\nInventory: 12 items low stock", shop.id),
            ("Steuerberater: Belege für die Umsatzsteuer-Voranmeldung Q3 hochladen", taxes.id),
        ]
        var correct = 0
        for sample in samples {
            let request = ProjectClassifier.request(text: sample.text, projects: projects)
            let reply = try await client.chat(system: request.system, user: request.user, schema: request.schema)
            let result = ProjectClassifier.parse(reply, text: sample.text, projects: projects)
            print("OLLAMA", Self.model ?? "", "reply:", reply, "→", result?.projectID == sample.expected ? "ok" : "miss")
            if result?.projectID == sample.expected { correct += 1 }
        }
        // A small local model may miss one of three; fewer than two correct means the prompt does not work.
        #expect(correct >= 2)
    }

    @Test("Local model leaves unrelated screens unassigned",
          .enabled(if: model != nil, "set FOCUSFLOW_OLLAMA_MODEL to run"))
    func leavesUnrelatedScreensAlone() async throws {
        let client = OllamaClient(baseURL: URL(string: "http://localhost:11434")!, model: Self.model ?? "", keepAlive: nil)
        let projects = [thesis, shop, taxes]
        let text = "Wetter Berlin: 18 Grad, sonnig\nNachrichten: Fußball Ergebnisse vom Wochenende"
        let request = ProjectClassifier.request(text: text, projects: projects)
        let reply = try await client.chat(system: request.system, user: request.user, schema: request.schema)
        print("OLLAMA", Self.model ?? "", "unrelated reply:", reply)
        #expect(ProjectClassifier.parse(reply, text: text, projects: projects) == nil)
    }
}
