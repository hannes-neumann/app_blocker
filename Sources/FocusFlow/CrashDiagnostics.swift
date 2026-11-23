import Foundation
import MetricKit

/// Registers crash diagnostics without collecting user text or file paths.
final class CrashDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashDiagnostics()

    func start() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for diagnostic in payload.crashDiagnostics ?? [] {
                var properties: AnalyticsProperties = [:]
                if let type = diagnostic.exceptionType { properties["exception_type"] = .int(type.intValue) }
                if let code = diagnostic.exceptionCode { properties["exception_code"] = .int(code.intValue) }
                if let signal = diagnostic.signal { properties["signal"] = .int(signal.intValue) }
                properties["frames"] = .int(0)
                Task { @MainActor in Analytics.track(.appCrashed, properties) }
            }
        }
    }
}
