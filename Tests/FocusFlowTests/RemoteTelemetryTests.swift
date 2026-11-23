import Foundation
import Testing
@testable import FocusFlow

@Suite("Remote telemetry", .serialized)
@MainActor
final class RemoteTelemetryTests {
    final class FakeTransport: TelemetryTransport {
        var bodies: [Data] = []
        var pending: [@Sendable (TelemetryResult) -> Void] = []
        var immediate: TelemetryResult?
        var cancels = 0
        func send(_ body: Data, completion: @escaping @Sendable (TelemetryResult) -> Void) {
            bodies.append(body)
            if let immediate { completion(immediate) } else { pending.append(completion) }
        }
        func cancel() { cancels += 1 }
        func batch(_ index: Int) throws -> [[String: Any]] {
            let root = try #require(JSONSerialization.jsonObject(with: bodies[index]) as? [String: Any])
            return try #require(root["batch"] as? [[String: Any]])
        }
    }
    final class SpySink: AnalyticsSink {
        var events: [AnalyticsEvent] = []
        func record(_ event: AnalyticsEvent) { events.append(event) }
        func flush() {}
    }

    let transport = FakeTransport()
    var allowed = true
    var id = UUID()
    var now = Date(timeIntervalSince1970: 1_700_000_045)
    let url: URL
    init() {
        TestSupport.isolate()
        url = TestSupport.dataDirectory.appendingPathComponent("queue-\(UUID().uuidString).json")
    }

    /// Puts the shared analytics state back after a test changed it.
    func restoring(_ body: () -> Void) {
        let settings = Analytics.settings, sinks = Analytics.sinks
        body()
        Analytics.settings = settings
        Analytics.sinks = sinks
        Analytics.remote = nil
    }

    func make() -> RemoteTelemetry {
        RemoteTelemetry(key: "phc_test", transport: transport, queueURL: url, clock: { self.now },
                        isAllowed: { self.allowed }, telemetryID: { self.id })
    }

    func settle() async { await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } }

    @Test func poisonNeverReachesTheBody() throws {
        let poison = ["Geheimprojekt", "/Users/anna/Secret.txt", "https://bank.example/konto", "com.example.secretapp",
                      "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "other;/Users/anna+1", "FocusFlow+1;Geheim+2"]
        let keys = Set(AnalyticsEventName.allCases.flatMap { RemoteContract.properties(of: $0).keys })
            .union(["app_name", "bundle_id", "bundle_ids", "project_id", "todo_id", "todo_ids", "note_id", "record_id", "model",
                    "error", "title", "symbol", "os_version", "kinds", "old_project_id", "distinct_id", "$ip"])
        for text in poison {
            let remote = make()
            for name in AnalyticsEventName.allCases {
                remote.record(name, Dictionary(uniqueKeysWithValues: keys.map { ($0, AnalyticsValue.string(text)) }))
            }
            transport.immediate = .drop
            transport.bodies = []
            remote.flush()
            let items = try transport.batch(0)
            #expect(items.count == AnalyticsEventName.allCases.count)
            #expect(!String(decoding: transport.bodies[0], as: UTF8.self).replacingOccurrences(of: "\\/", with: "/").contains(text))
            remote.clear()
            transport.immediate = nil
        }
    }

    @Test func allowedValuesArrive() throws {
        let remote = make()
        remote.record(.focusEnded, ["phase": "focus", "reason": "completed", "completed": true, "elapsed_seconds": 1500, "wall_seconds": -5])
        remote.record(.appLaunched, ["ai_provider": "apple", "open_todos": 99_999_999, "tracking_enabled": 1])
        remote.flush()
        let batch = try transport.batch(0)
        let ended = try #require(batch[0]["properties"] as? [String: Any])
        #expect(ended["completed"] as? Bool == true)
        #expect(ended["elapsed_seconds"] as? Int == 1500)
        #expect(ended["wall_seconds"] as? Int == 0)
        #expect(ended["reason"] as? String == "completed")
        #expect(ended["$process_person_profile"] as? Bool == false)
        #expect(ended["$geoip_disable"] as? Bool == true)
        #expect(ended["distinct_id"] as? String == id.uuidString)
        let launched = try #require(batch[1]["properties"] as? [String: Any])
        #expect(launched["open_todos"] as? Int == 1_000_000)
        #expect(launched["tracking_enabled"] == nil)
    }

    /// The exact set of common fields, so a new one cannot slip in unnoticed.
    @Test func onlyKnownCommonFields() throws {
        let remote = make()
        remote.record(.dashboardClosed, [:])
        remote.flush()
        let item = try transport.batch(0)[0]
        #expect(Set(item.keys) == ["event", "uuid", "properties", "timestamp"])
        let properties = try #require(item["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["distinct_id", "$session_id", "$process_person_profile", "$geoip_disable", "app_version",
                                         "macos_version", "arch", "language"])
        #expect(properties["$session_id"] as? String != Analytics.sessionID.uuidString)
        #expect((item["timestamp"] as? String)?.hasSuffix(":00Z") == true)
    }

    @Test func nothingIsRecordedOrSentWithoutConsent() {
        allowed = false
        let remote = make()
        remote.record(.menuOpened, [:])
        remote.flush()
        remote.flushOnQuit(timeout: 0.01)
        #expect(remote.queue.isEmpty && transport.bodies.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func leftoversAreDeletedAtLaunchWithoutConsent() {
        make().record(.menuOpened, [:])
        #expect(FileManager.default.fileExists(atPath: url.path))
        allowed = false
        #expect(make().queue.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func withdrawingDuringARequestLeavesNothingAndReEnablingWorks() async {
        let remote = make()
        remote.record(.menuOpened, [:])
        remote.flush()
        allowed = false
        remote.clear()
        #expect(remote.queue.isEmpty && transport.cancels == 1)
        allowed = true
        remote.record(.dashboardClosed, [:])
        // A late failure of the old request must not delay the new queue.
        transport.pending[0](.retry)
        await settle()
        #expect(remote.queue.map(\.event) == ["dashboard_closed"])
        remote.flush()
        #expect(transport.bodies.count == 2)
    }

    @Test func retriesWithGrowingDelay() async {
        let remote = make()
        remote.record(.menuOpened, [:])
        remote.flush()
        remote.flush()
        #expect(transport.bodies.count == 1, "no second request while one is under way")
        transport.pending[0](.retry)
        await settle()
        remote.flush()
        #expect(transport.bodies.count == 1)
        now += 31
        remote.flush()
        #expect(transport.bodies.count == 2)
        transport.pending[1](.retry)
        await settle()
        now += 31
        remote.flush()
        #expect(transport.bodies.count == 2, "the second delay is longer")
        now += 30
        remote.flush()
        transport.pending[2](.success)
        await settle()
        #expect(remote.queue.isEmpty)
    }

    @Test func onlySentEventsAreRemoved() async {
        let remote = make()
        remote.record(.menuOpened, [:])
        remote.flush()
        for _ in 0..<RemoteTelemetry.maxQueued { remote.record(.dashboardClosed, [:]) }
        transport.pending[0](.success)
        await settle()
        #expect(remote.queue.count == RemoteTelemetry.maxQueued)
    }

    @Test func refusedBatchesAreDropped() async {
        let remote = make()
        remote.record(.menuOpened, [:])
        remote.flush()
        transport.pending[0](.drop)
        await settle()
        #expect(remote.queue.isEmpty)
    }

    @Test func statusCodes() {
        #expect(PostHogTransport.result(status: 200) == .success)
        #expect(PostHogTransport.result(status: 400) == .drop)
        #expect(PostHogTransport.result(status: 401) == .drop)
        #expect(PostHogTransport.result(status: 429) == .retry)
        #expect(PostHogTransport.result(status: 503) == .retry)
        #expect(PostHogTransport.result(status: nil) == .retry)
    }

    @Test func queueIsCappedBatchedAndSurvivesARestart() throws {
        let remote = make()
        for _ in 0..<(RemoteTelemetry.maxQueued + 20) { remote.record(.menuOpened, ["phase": "idle"]) }
        #expect(remote.queue.count == RemoteTelemetry.maxQueued)
        let restarted = make()
        #expect(restarted.queue == remote.queue)
        restarted.flush()
        #expect(try transport.batch(0).count == RemoteTelemetry.batchSize)
    }

    @Test func savedQueueIsCheckedAgain() throws {
        let item = RemoteTelemetry.Item(event: "menu_opened", minute: 1, session: UUID(), version: "Geheim", language: "de",
                                        properties: ["phase": "Geheim", "title": "Geheim"])
        let unknown = RemoteTelemetry.Item(event: "Geheim", minute: 1, session: UUID(), version: "1.0", language: "de", properties: [:])
        try JSONEncoder().encode([item, unknown]).write(to: url)
        let remote = make()
        #expect(remote.queue.count == 1)
        #expect(remote.queue[0].properties.isEmpty)
        #expect(remote.queue[0].version == "dev")
    }

    @Test func brokenQueueFileIsIgnored() throws {
        try Data("{".utf8).write(to: url)
        #expect(make().queue.isEmpty)
    }

    @Test func quitSendsOnceAndDoesNotHang() {
        let remote = make()
        remote.record(.appQuit, [:])
        let start = Date()
        remote.flushOnQuit(timeout: 0.05)
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(remote.queue.count == 1, "kept for the next launch")
        transport.immediate = .success
        remote.flushOnQuit(timeout: 1)
        #expect(remote.queue.isEmpty)
    }

    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func localLogAndTelemetryAreIndependent(_ local: Bool, _ telemetry: Bool) {
        restoring {
            let spy = SpySink()
            allowed = telemetry
            let remote = make()
            Analytics.sinks = [spy]
            Analytics.remote = remote
            Analytics.settings.enabled = local
            Analytics.track(.blockedAppAdded, ["bundle_id": "com.example.app", "app_name": "Example"], content: ["text": "note"])
            #expect(spy.events.count == (local ? 1 : 0))
            #expect(remote.queue.count == (telemetry ? 1 : 0))
            if local {
                #expect(spy.events[0].properties == ["bundle_id": "com.example.app", "app_name": "Example"])
                #expect(spy.events[0].content == ["text": "note"])
            }
            #expect(remote.queue.allSatisfy { $0.properties.isEmpty })
        }
    }

    @Test func answeringAndResettingClearTheQueue() {
        restoring {
            let remote = make()
            Analytics.remote = remote
            remote.record(.menuOpened, [:])
            Analytics.answerTelemetry(true)
            #expect(Analytics.settings.telemetryAllowed && remote.queue.isEmpty)
            let old = Analytics.settings.telemetryID
            remote.record(.menuOpened, [:])
            Analytics.resetTelemetryID()
            #expect(Analytics.settings.telemetryID != old && remote.queue.isEmpty)
            Analytics.answerTelemetry(false)
            #expect(!Analytics.settings.telemetryAllowed)
            #expect(Analytics.settings.telemetryPolicy == RemoteTelemetry.policyVersion)
        }
    }

    @Test func aNewPolicyNeedsANewAnswer() {
        var settings = AnalyticsSettings()
        settings.telemetryEnabled = true
        settings.telemetryPolicy = RemoteTelemetry.policyVersion - 1
        #expect(!settings.telemetryAllowed)
        #expect(RemoteTelemetry.shouldAsk(hasKey: true, answeredPolicy: RemoteTelemetry.policyVersion - 1, phase: .idle))
        #expect(!RemoteTelemetry.shouldAsk(hasKey: true, answeredPolicy: RemoteTelemetry.policyVersion, phase: .idle))
        #expect(!RemoteTelemetry.shouldAsk(hasKey: false, answeredPolicy: 0, phase: .idle))
        for phase in [Phase.focus, .shortBreak, .longBreak] {
            #expect(!RemoteTelemetry.shouldAsk(hasKey: true, answeredPolicy: 0, phase: phase))
        }
    }

    @Test func oldSettingsKeepTheirAnswerAndStartOff() throws {
        let install = UUID()
        let data = Data(#"{"enabled":false,"installID":"\#(install.uuidString)"}"#.utf8)
        let settings = try JSONDecoder().decode(AnalyticsSettings.self, from: data)
        #expect(!settings.enabled && settings.installID == install)
        #expect(!settings.telemetryAllowed && settings.telemetryPolicy == 0)
        #expect(settings.telemetryID != install)
    }

    @Test func crashFramesKeepOnlyKnownBinaries() throws {
        let json = #"{"callStacks":[{"threadAttributed":false,"callStackRootFrames":[{"binaryName":"AppKit","offsetIntoBinaryTextSegment":1}]},{"threadAttributed":true,"callStackRootFrames":[{"binaryName":"FocusFlow","offsetIntoBinaryTextSegment":4096,"subFrames":[{"binaryName":"/Users/anna/Secret","offsetIntoBinaryTextSegment":7,"subFrames":[{"binaryName":"dyld","offsetIntoBinaryTextSegment":9}]}]}]}]}"#
        let frames = try #require(CrashFrames.parse(Data(json.utf8)))
        #expect(frames == "FocusFlow+4096;other;dyld+9")
        #expect(CrashFrames.isValid(frames))
        #expect(CrashFrames.parse(Data("no json".utf8)) == nil)
        #expect(CrashFrames.parse(Data("{}".utf8)) == nil)
        #expect(!CrashFrames.isValid("Secret+1"))
        #expect(!CrashFrames.isValid("dyld+1\nSecret"))
        #expect(!CrashFrames.isValid("dyld+1\n"))
        #expect(!CrashFrames.isValid(Array(repeating: "dyld+1", count: 31).joined(separator: ";")))
    }
}
