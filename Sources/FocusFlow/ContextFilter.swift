import ApplicationServices
import Foundation

/// Decides which apps and fields may be read for project detection at all. Runs before any text is read,
/// so excluded apps and secure fields never reach the language model.
enum ContextFilter {
    /// Apps that are never read, out of the box. The user can change this list in Settings.
    static let defaultExcludedBundleIDs: [String] = [
        // Password managers
        "com.1password.1password", "com.1password.1password7", "com.bitwarden.desktop", "com.apple.keychainaccess",
        "com.lastpass.LastPass", "org.keepassxc.keepassxc",
        // Private messaging
        "net.whatsapp.WhatsApp", "com.whatsapp.WhatsApp", "org.whispersystems.signal-desktop",
        "ru.keepcoder.Telegram", "com.apple.MobileSMS", "com.hnc.Discord",
    ]

    /// Subroles that hold secrets. Their values are never read, even in apps that are not excluded.
    static let secureSubroles: Set<String> = ["AXSecureTextField"]

    /// Whether the app may be read at all.
    static func isAllowed(bundleID: String, excluded: Set<String>) -> Bool {
        !excluded.contains(bundleID)
    }

    /// Whether an accessibility element is a secure field, judged by its subrole.
    static func isSecure(subrole: String?) -> Bool {
        guard let subrole else { return false }
        return secureSubroles.contains(subrole)
    }
}

/// Reads visible text from a window through the Accessibility tree. Secure fields are skipped, and the
/// reading is bounded in depth and length, so a huge document cannot slow sampling down.
enum AccessibilityText {
    static let maxDepth = 12
    static let maxCharacters = 4_000

    /// Text of the focused window of the process, or nil when it cannot be read.
    nonisolated static func windowText(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var parts: [String] = []
        var count = 0
        collect(window as! AXUIElement, depth: 0, into: &parts, count: &count)
        let text = parts.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    nonisolated private static func collect(_ element: AXUIElement, depth: Int, into parts: inout [String], count: inout Int) {
        guard depth <= maxDepth, count < maxCharacters else { return }
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        // Never read the value of a secure field, and do not descend into it.
        if ContextFilter.isSecure(subrole: subrole as? String) { return }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if role as? String == kAXStaticTextRole as String || role as? String == kAXTextAreaRole as String {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty {
                let remaining = maxCharacters - count
                let piece = String(text.prefix(remaining))
                parts.append(piece)
                count += piece.count
            }
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return }
        for child in list {
            collect(child, depth: depth + 1, into: &parts, count: &count)
            if count >= maxCharacters { return }
        }
    }
}
