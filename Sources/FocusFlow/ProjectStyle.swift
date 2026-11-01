import AppKit
import SwiftUI

/// Project colors: eight categorical hues checked for color-blind separation, each with its own
/// light and dark step. A project keeps its slot, so its color never shifts when others change.
enum ProjectPalette {
    private static let slots: [(light: UInt32, dark: UInt32)] = [
        (0x2A78D6, 0x3987E5), // blue
        (0xEB6834, 0xD95926), // orange
        (0x1BAF7A, 0x199E70), // aqua
        (0xEDA100, 0xC98500), // yellow
        (0xE87BA4, 0xD55181), // magenta
        (0x008300, 0x008300), // green
        (0x6250D6, 0x9085E9), // violet
        (0xE34948, 0xE66767), // red
    ]

    static var count: Int { slots.count }

    static func color(_ index: Int) -> Color {
        let slot = slots[((index % count) + count) % count]
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: dark ? slot.dark : slot.light)
        })
    }

    /// Time without a project: neutral, so it never reads as one of the projects.
    static let none = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: 0x5E5D59) : NSColor(hex: 0xB5B3AC)
    })

    static let symbols = [
        "folder.fill", "book.fill", "graduationcap.fill", "briefcase.fill", "hammer.fill", "chevron.left.forwardslash.chevron.right",
        "paintbrush.fill", "pencil", "chart.bar.fill", "heart.fill", "dumbbell.fill", "house.fill",
        "music.note", "camera.fill", "globe", "lightbulb.fill",
    ]
}

extension Project {
    var color: Color { ProjectPalette.color(colorIndex) }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
