import SwiftUI

/// Start, pause, skip and stop, shared by the menu and the dashboard.
struct TimerControls: View {
    @Environment(AppState.self) private var state
    var large = false
    @State private var durationText = ""
    @State private var invalid = false

    var body: some View {
        HStack {
            if state.phase == .idle {
                TextField("Min", text: $durationText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .controlSize(.large)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.red, lineWidth: invalid ? 1 : 0))
                    .help("Fokuszeit, z. B. 25, 50 min, 1h oder 1:30. Enter startet.")
                    .onSubmit { start(source: "enter") }
                    .onChange(of: durationText) {
                        invalid = false
                        if let minutes = parseDuration(durationText) { state.settings.focusMinutes = min(minutes, 180) }
                    }
                    .onChange(of: state.settings.focusMinutes, initial: true) { _, minutes in
                        // Keep what the user is typing; only refresh when the value came from elsewhere.
                        if parseDuration(durationText) != minutes { durationText = formatMinutes(minutes) }
                    }
                Button { start(source: "button") } label: {
                    Label(L10n.text("startFocus"), systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button { state.togglePause() } label: {
                    Label(state.isPaused ? L10n.text("resume") : L10n.text("pause"), systemImage: state.isPaused ? "play.fill" : "pause.fill")
                }
                Button { state.skipPhase() } label: {
                    Label(L10n.text("skip"), systemImage: "forward.end.fill")
                }
                Spacer()
                Button(role: .destructive) { state.stop() } label: {
                    Label(L10n.text("stop"), systemImage: "stop.fill")
                }
            }
        }
        .controlSize(large ? .large : .regular)
    }

    private func start(source: String) {
        guard parseDuration(durationText) != nil else {
            invalid = true
            Analytics.track(.focusDurationInvalid, content: ["text": durationText])
            return
        }
        state.startFocus(source: source)
    }
}

/// Problems with the website block that need the user's attention.
struct BlockingWarnings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let error = state.domainBlockError, !state.isHelperInstalled {
            VStack(alignment: .leading, spacing: 6) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Helfer installieren (einmalig)") { state.installHelper() }
                    .controlSize(.small)
            }
        }
        if state.hasStaleHostsBlock && state.phase == .idle {
            HStack {
                Label("Alte Webseiten-Sperre aktiv", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Aufheben") { state.removeStaleHostsBlock() }
                    .controlSize(.small)
            }
        }
    }
}

/// The estimate badge of a todo: pick a common duration or type your own.
struct EstimateControl: View {
    @Environment(AppState.self) private var state
    let todo: Todo
    @State private var editing = false
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    private static let options = [5, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        if editing {
            TextField("Min", text: $text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.caption)
                .frame(width: 64)
                .focused($focused)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.red, lineWidth: invalid ? 1 : 0))
                .help("z. B. 25, 45 min, 1h, 1,5h oder 1:30")
                .onSubmit(commit)
                .onExitCommand { editing = false }
                .onChange(of: focused) { _, isFocused in
                    // Clicking elsewhere saves a valid entry and drops an invalid one.
                    if !isFocused, editing {
                        if parseDuration(text) != nil { commit() } else { editing = false }
                    }
                }
                .onChange(of: text) { invalid = false }
                .onAppear {
                    text = todo.estimatedMinutes.map(String.init) ?? ""
                    invalid = false
                    DispatchQueue.main.async { focused = true }
                }
        } else {
            Menu {
                ForEach(Self.options, id: \.self) { minutes in
                    Button(formatMinutes(minutes)) { state.todos.setEstimate(todo.id, minutes: minutes, method: "menu") }
                }
                Divider()
                Button(L10n.text("customDuration")) { editing = true }
            } label: {
                EstimateBadge(minutes: todo.estimatedMinutes ?? 0)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Geschätzte Dauer anpassen")
        }
    }

    private func commit() {
        guard let minutes = parseDuration(text) else {
            invalid = !text.isEmpty
            if text.isEmpty { editing = false }
            return
        }
        state.todos.setEstimate(todo.id, minutes: min(minutes, 480), method: "typed")
        editing = false
    }
}

/// A minutes value that can be typed or stepped.
struct NumberField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit = "Min"

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text(unit).foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range, step: step).labelsHidden()
            }
        }
    }

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }
}
