import SwiftUI

struct TimerEntryView: View {
    let defaultMinutes: Int
    let onStart: (Int) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var invalid = false
    @FocusState private var focused: Bool

    init(defaultMinutes: Int, onStart: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.defaultMinutes = defaultMinutes
        self.onStart = onStart
        self.onCancel = onCancel
        _text = State(initialValue: "\(defaultMinutes)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField(L10n.text("durationPlaceholder"), text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(start)
                    .onChange(of: text) { invalid = false }
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(invalid ? Color.red : Color.secondary.opacity(0.3))
                            .frame(height: 1)
                    }
            }
            HStack(spacing: 8) {
                ForEach([15, 25, 45, 60], id: \.self) { minutes in
                    Button(formatMinutes(minutes)) {
                        text = "\(minutes)"
                        start()
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text(L10n.text("timerEntryFooter"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onExitCommand(perform: onCancel)
        .onAppear { focused = true }
    }

    private func start() {
        guard let minutes = parseDuration(text), minutes <= 480 else {
            invalid = true
            return
        }
        onStart(minutes)
    }
}
