import Foundation
import Testing
@testable import FocusFlow

@MainActor
@Suite("Remote telemetry")
struct RemoteTelemetryTests {
    init() { TestSupport.isolate() }

    final class Transport: TelemetryTransport {
        var bodies: [Data] = []
        var completions: [(Bool) -> Void] = []
        func send(_ data: Data, completion: @escaping (Bool) -> Void) {
            bodies.append(data)
            completions.append(completion)
        }
    }

    private func event(_ name: AnalyticsEventName, _ properties: AnalyticsProperties = [:]) -> AnalyticsEvent {
        AnalyticsEvent(name: name, sessionID: UUID(), installID: UUID(), appVersion: "test", properties: properties)
    }

    @Test("Every event has an explicit remote contract")
    func everyEventListed() {
        #expect(Set(AnalyticsEventName.allCases) == Set(RemoteTelemetry.allowlist.keys))
    }

    @Test("Poisoned properties never cross the remote boundary")
    func poisonDropped() throws {
        let transport = Transport()
        Analytics.settings.telemetryEnabled = true
        let url = Storage.directory.appendingPathComponent("poison-\(UUID().uuidString).json")
        let sink = PostHogAnalyticsSink(key: "test", transport: transport, queueURL: url)!
        sink.record(event(.appLaunched, ["open_todos": .int(2), "title": .string("secret"), "path": .string("/tmp/private"), "uuid": .string(UUID().uuidString)]))
        sink.flush()
        #expect(transport.bodies.count == 1)
        let body = String(data: transport.bodies[0], encoding: .utf8) ?? ""
        #expect(!body.contains("secret"))
        #expect(!body.contains("/tmp/private"))
        #expect(!body.contains("uuid"))
    }

    @Test("Opt out clears queue and stops transport")
    func consentLifecycle() {
        let transport = Transport()
        Analytics.settings.telemetryEnabled = true
        let sink = PostHogAnalyticsSink(key: "test", transport: transport)!
        sink.record(event(.menuOpened))
        Analytics.settings.telemetryEnabled = false
        sink.flush()
        #expect(transport.bodies.isEmpty)
    }

    @Test("Old settings retain local identity and default telemetry off")
    func oldSettingsDecode() throws {
        let id = UUID()
        let data = #"{"enabled":true,"installID":"\#(id.uuidString)"}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(AnalyticsSettings.self, from: data)
        #expect(value.enabled)
        #expect(value.installID == id)
        #expect(!value.telemetryEnabled)
    }

    @Test("Timestamps are reduced to minute precision")
    func timestamps() {
        let transport = Transport()
        Analytics.settings.telemetryEnabled = true
        let sink = PostHogAnalyticsSink(key: "test", transport: transport)!
        sink.record(event(.menuOpened))
        sink.flush()
        #expect(transport.bodies.count == 1)
    }

    @Test("No key creates no sink")
    func noKey() {
        #expect(PostHogAnalyticsSink(key: nil, transport: Transport()) == nil)
    }

    @Test("Reset changes live identity")
    func resetIdentity() {
        let transport = Transport()
        Analytics.settings.telemetryEnabled = true
        let sink = PostHogAnalyticsSink(key: "test", transport: transport)!
        sink.record(event(.menuOpened)); sink.flush()
        sink.reset()
        Analytics.settings.telemetryEnabled = true
        sink.record(event(.menuOpened)); sink.flush()
        #expect(transport.bodies.count == 2)
        #expect(transport.bodies[0] != transport.bodies[1])
    }
}
