import SwiftUI

private let privacyURL = URL(string: "https://github.com/hannes-neumann/app_blocker/blob/main/PRIVACY.md")!

/// Asks once whether usage data may be sent. Both answers look the same on purpose.
struct TelemetryConsentView: View {
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.text("telemetryAskTitle"), systemImage: "chart.bar.xaxis").font(.headline)
            Text(L10n.text("telemetryAskIntro"))
            Label(L10n.text("telemetrySent"), systemImage: "checkmark.circle")
            Label(L10n.text("telemetryNotSent"), systemImage: "xmark.circle")
            Text(L10n.text("telemetryAskFooter")).font(.caption).foregroundStyle(.secondary)
            Link(L10n.text("privacyPolicy"), destination: privacyURL).font(.caption)
            HStack {
                Button { onAnswer(false) } label: { Text(L10n.text("telemetryNo")).frame(maxWidth: .infinity) }
                Button { onAnswer(true) } label: { Text(L10n.text("telemetryYes")).frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Only in builds that can send anything.
struct TelemetrySection: View {
    @State private var enabled = Analytics.settings.telemetryAllowed
    @State private var id = Analytics.settings.telemetryID

    var body: some View {
        if RemoteTelemetry.bundledKey != nil {
            Section {
                Toggle(L10n.text("telemetryOptIn"), isOn: Binding(
                    get: { enabled },
                    set: { enabled = $0; Analytics.answerTelemetry($0) }
                ))
                LabeledContent(L10n.text("telemetryID")) {
                    Text(id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                }
                HStack {
                    Button(L10n.text("copyTelemetryID")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(id.uuidString, forType: .string)
                    }
                    Button(L10n.text("resetTelemetry")) {
                        Analytics.resetTelemetryID()
                        id = Analytics.settings.telemetryID
                    }
                    Link(L10n.text("privacyPolicy"), destination: privacyURL)
                }
            } header: {
                Text(L10n.text("telemetry"))
            } footer: {
                Text(L10n.text("telemetryFooter")).font(.caption).foregroundStyle(.secondary)
            }
            .onAppear { enabled = Analytics.settings.telemetryAllowed }
        }
    }
}
