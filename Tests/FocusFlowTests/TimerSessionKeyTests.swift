import AppKit
import Carbon
import SwiftUI
import Testing
@testable import FocusFlow

@MainActor
@Suite("Keyboard in the running timer panel")
struct TimerSessionKeyTests {
    init() { TestSupport.isolate() }

    func key(_ code: Int, _ modifiers: NSEvent.ModifierFlags = [], isRepeat: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: isRepeat,
                                      keyCode: UInt16(code)))
    }

    /// Real arrow key events carry these flags.
    let arrow: NSEvent.ModifierFlags = [.numericPad, .function]

    @Test func keysReachTheSelectionThroughThePanel() throws {
        let panel = FloatingPanel(closesOnResignKey: false)
        let selection = TimerSessionSelection()
        var performed: [TimerSessionAction] = []
        panel.onKey = { selection.handle($0) { performed.append($0) } }
        panel.sendEvent(try key(kVK_Return))
        panel.sendEvent(try key(kVK_RightArrow, arrow))
        panel.sendEvent(try key(kVK_Return))
        panel.sendEvent(try key(kVK_Return, isRepeat: true))
        panel.sendEvent(try key(kVK_Tab))
        panel.sendEvent(try key(kVK_Space))
        #expect(performed == [.pause, .skip, .stop])
    }

    @Test func movesBothWaysAndWraps() throws {
        let selection = TimerSessionSelection()
        #expect(selection.handle(try key(kVK_LeftArrow, arrow)) { _ in })
        #expect(selection.action == .stop)
        #expect(selection.handle(try key(kVK_DownArrow, arrow)) { _ in })
        #expect(selection.action == .pause)
        #expect(selection.handle(try key(kVK_Tab)) { _ in })
        #expect(selection.handle(try key(kVK_Tab, .shift)) { _ in })
        #expect(selection.action == .pause)
    }

    @Test func leavesShortcutsAlone() throws {
        let selection = TimerSessionSelection()
        #expect(!selection.handle(try key(kVK_ANSI_S)) { _ in })
        #expect(!selection.handle(try key(kVK_Escape)) { _ in })
        #expect(!selection.handle(try key(kVK_Delete, .command)) { _ in })
        #expect(!selection.handle(try key(kVK_Return, .command)) { _ in })
    }
}
