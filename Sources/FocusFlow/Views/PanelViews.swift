import SwiftUI

struct QuickCaptureView: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField(L10n.text("captureQuestion"), text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { onSubmit(text) }
            }
            Text(L10n.text("captureFooter"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onExitCommand(perform: onCancel)
        .onAppear { focused = true }
    }
}

struct BreakView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: state.phase.symbol)
                    .foregroundStyle(.green)
                Text("\(state.phase.title) · \(state.remainingText)")
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                Button { state.panels.dismissBreak() } label: {
                    // A bigger target, so a near miss does not open the dashboard instead.
                    Image(systemName: "xmark").font(.caption.weight(.bold))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .padding(-8)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if let todo = state.suggestion {
                Text(L10n.text("pauseFit"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(todo.title)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let minutes = todo.estimatedMinutes { EstimateBadge(minutes: minutes) }
                }
                HStack {
                    Button(L10n.text("done")) { state.completeSuggestion() }
                        .keyboardShortcut(.defaultAction)
                    Button(L10n.text("nextSuggestion")) { state.nextSuggestion() }
                }
            } else {
                Text(L10n.text("noPauseTask"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        // The buttons inside keep their own clicks.
        .onTapGesture { openDashboard() }
        .help(L10n.text("openDashboard"))
        .accessibilityAction(named: Text(L10n.text("openDashboard"))) { openDashboard() }
    }

    private func openDashboard() {
        state.panels.showDashboard(.focus, source: "break_panel")
    }
}

struct BlockedHUDView: View {
    let appName: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(L10n.text("appBlockedTitle", appName))
                .font(.headline)
            Text(L10n.text("appBlockedText"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct EstimateBadge: View {
    let minutes: Int

    var body: some View {
        Text(formatMinutes(minutes))
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}
