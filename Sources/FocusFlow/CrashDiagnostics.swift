import Foundation
import MetricKit

/// Crash positions as "Binary+offset;Binary+offset", without paths or symbols.
enum CrashFrames {
    static let maxFrames = 30
    /// Other names could reveal what else is installed, e.g. an injected plugin.
    private static let known: Set<String> = [
        "FocusFlow", "Sparkle", "AppKit", "SwiftUI", "SwiftUICore", "AttributeGraph", "Foundation", "CoreFoundation", "HIToolbox", "Carbon",
        "CoreGraphics", "QuartzCore", "Charts", "FoundationModels", "Combine", "MetricKit", "dyld", "libobjc.A.dylib",
        "libdispatch.dylib", "libswiftCore.dylib", "libswift_Concurrency.dylib", "libsystem_kernel.dylib",
        "libsystem_c.dylib", "libsystem_pthread.dylib", "libsystem_malloc.dylib", "libsystem_platform.dylib",
    ]

    static func parse(_ json: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]],
              let stack = stacks.first(where: { $0["threadAttributed"] as? Bool == true }) ?? stacks.first else { return nil }
        var frames: [String] = []
        var next = (stack["callStackRootFrames"] as? [[String: Any]])?.first
        while let frame = next, frames.count < maxFrames {
            let name = frame["binaryName"] as? String ?? ""
            let offset = max(frame["offsetIntoBinaryTextSegment"] as? Int ?? 0, 0)
            frames.append(known.contains(name) ? "\(name)+\(offset)" : "other")
            next = (frame["subFrames"] as? [[String: Any]])?.first
        }
        return frames.isEmpty ? nil : frames.joined(separator: ";")
    }

    static func isValid(_ text: String) -> Bool {
        let frames = text.components(separatedBy: ";")
        return frames.count <= maxFrames && frames.allSatisfy { frame in
            if frame == "other" { return true }
            let parts = frame.components(separatedBy: "+")
            return parts.count == 2 && known.contains(parts[0])
                && parts[1].range(of: #"^[0-9]{1,19}\z"#, options: .regularExpression) != nil
        }
    }
}

/// Reports crashes that macOS hands over, usually after the next launch.
final class CrashDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashDiagnostics()

    func start() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for crash in payloads.flatMap({ $0.crashDiagnostics ?? [] }) {
            var properties: AnalyticsProperties = [:]
            if let type = crash.exceptionType { properties["exception_type"] = .int(type.intValue) }
            if let code = crash.exceptionCode { properties["exception_code"] = .int(code.intValue) }
            if let signal = crash.signal { properties["signal"] = .int(signal.intValue) }
            if let build = Int(crash.metaData.applicationBuildVersion) { properties["crash_build"] = .int(build) }
            if let frames = CrashFrames.parse(crash.callStackTree.jsonRepresentation()) { properties["frames"] = .string(frames) }
            let event = properties
            Task { @MainActor in Analytics.track(.appCrashed, event) }
        }
    }
}
