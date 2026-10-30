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
                TextField("Was ist dir gerade eingefallen?", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { onSubmit(text) }
            }
            Text("↩ speichern · esc schließen · wird automatisch zu einem Todo mit Zeitschätzung")
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
                Button { state.panels.hideBreak() } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if let todo = state.suggestion {
                Text("Passt in deine Pause:")
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
                    Button("Erledigt") { state.completeSuggestion() }
                        .keyboardShortcut(.defaultAction)
                    Button("Anderer Vorschlag") { state.nextSuggestion() }
                }
            } else {
                Text("Kein offenes Todo passt in diese Pause. Gönn dir eine echte Pause!")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct BlockedHUDView: View {
    let appName: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("\(appName) ist blockiert")
                .font(.headline)
            Text("Bleib dran, die nächste Pause kommt bestimmt.")
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
