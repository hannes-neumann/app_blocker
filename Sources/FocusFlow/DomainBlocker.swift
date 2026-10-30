import Foundation

/// Blocks domains through /etc/hosts.
///
/// Editing /etc/hosts needs root, so FocusFlow installs a tiny launch daemon once (one admin
/// password prompt). The daemon polls two files owned by the app: `block-state` ("on" during focus)
/// and `blocked-domains` (one domain per line). It only applies the block while the state is "on"
/// *and* a FocusFlow process is running, so quitting or crashing the app lifts the block, and it
/// strips any leftover block when it starts at boot.
@MainActor
final class DomainBlocker {
    static let beginMarker = "# >>> FocusFlow block"
    static let endMarker = "# <<< FocusFlow block"

    private static let label = "com.hannesneumann.FocusFlow.blocker"
    private static let helperPath = "/Library/PrivilegedHelperTools/\(label)"
    private static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    private let stateURL = Storage.directory.appendingPathComponent("block-state")
    private let domainsURL = Storage.directory.appendingPathComponent("blocked-domains")

    /// True when /etc/hosts holds a block although nothing should be blocked right now.
    static var hostsHasBlock: Bool {
        (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8))?.contains(beginMarker) ?? false
    }

    /// Installed and identical to the helper this build ships (an older helper counts as not installed).
    var isHelperInstalled: Bool {
        (try? String(contentsOfFile: Self.helperPath, encoding: .utf8)) == helperScript
    }

    /// Accepts "https://www.youtube.com/watch?v=…" as well as "youtube.com".
    static func normalize(_ input: String) -> String? {
        var host = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: host.contains("://") ? host : "https://\(host)"), let h = url.host { host = h }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let valid = host.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)+$"#, options: .regularExpression) != nil
        return valid ? host : nil
    }

    /// Changing the list takes effect within seconds, also in the middle of a focus phase.
    func setDomains(_ domains: [String]) {
        let lines = domains.compactMap(Self.normalize).joined(separator: "\n")
        try? (lines + "\n").write(to: domainsURL, atomically: true, encoding: .utf8)
    }

    func setBlocking(_ on: Bool) {
        try? (on ? "on" : "off").write(to: stateURL, atomically: true, encoding: .utf8)
    }

    /// Asks for the admin password once and installs (or updates) the helper daemon.
    func installHelper() async -> Bool {
        let script = Data(helperScript.utf8).base64EncodedString()
        let plist = Data(helperPlist.utf8).base64EncodedString()
        return await runPrivileged("""
            set -e
            /bin/mkdir -p /Library/PrivilegedHelperTools
            echo \(script) | /usr/bin/base64 -D > "\(Self.helperPath)"
            /usr/sbin/chown root:wheel "\(Self.helperPath)"
            /bin/chmod 755 "\(Self.helperPath)"
            echo \(plist) | /usr/bin/base64 -D > "\(Self.plistPath)"
            /usr/sbin/chown root:wheel "\(Self.plistPath)"
            /bin/chmod 644 "\(Self.plistPath)"
            /bin/launchctl bootout system/\(Self.label) 2>/dev/null || true
            /bin/launchctl bootstrap system "\(Self.plistPath)"
            """, prompt: "FocusFlow möchte einmalig einen Helfer installieren, um während deiner Fokuszeit Webseiten zu blockieren.")
    }

    func uninstallHelper() async -> Bool {
        await runPrivileged("""
            /bin/launchctl bootout system/\(Self.label) 2>/dev/null
            /bin/rm -f "\(Self.plistPath)" "\(Self.helperPath)"
            \(Self.stripAndFlush)
            exit 0
            """, prompt: "FocusFlow möchte den Webseiten-Helfer entfernen.")
    }

    /// One-off cleanup for a block left behind while no helper is installed.
    func removeStaleBlock() async -> Bool {
        await runPrivileged("\(Self.stripAndFlush)\nexit 0",
                            prompt: "FocusFlow möchte eine alte Webseiten-Sperre aufheben.")
    }

    private static let stripAndFlush = """
        /usr/bin/sed -i "" "/^\(beginMarker)$/,/^\(endMarker)$/d" /etc/hosts
        /usr/bin/dscacheutil -flushcache
        /usr/bin/killall -HUP mDNSResponder 2>/dev/null
        """

    private var helperPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/sh</string>
                <string>\(Self.helperPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }

    /// The root daemon. It only trusts regular files owned by the installing user (no symlinks into
    /// root-only files) and only writes lines of the form "0.0.0.0 <validated domain>".
    var helperScript: String {
        """
        #!/bin/sh
        # FocusFlow hosts helper v1. Installed by FocusFlow.app, removable in its settings.
        HOSTS=/etc/hosts
        BEGIN="\(Self.beginMarker)"
        END="\(Self.endMarker)"
        STATE="\(stateURL.path)"
        DOMAINS="\(domainsURL.path)"
        OWNER=\(getuid())
        trusted() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(/usr/bin/stat -f %u "$1")" = "$OWNER" ]; }
        strip() { /usr/bin/sed -i "" "/^$BEGIN$/,/^$END$/d" "$HOSTS"; }
        flush() { /usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder 2>/dev/null; }
        desired() {
          trusted "$STATE" && trusted "$DOMAINS" || return
          [ "$(/bin/cat "$STATE")" = on ] || return
          /usr/bin/pgrep -x FocusFlow >/dev/null || return
          /usr/bin/grep -E "^[a-z0-9-]+([.][a-z0-9-]+)+$" "$DOMAINS" | /usr/bin/head -n 500 | while read -r d; do
            echo "0.0.0.0 $d"; echo "0.0.0.0 www.$d"; echo "::1 $d"; echo "::1 www.$d"
          done
        }
        strip; flush
        current=""
        while true; do
          want="$(desired)"
          if [ "$want" != "$current" ]; then
            strip
            if [ -n "$want" ]; then
              [ -n "$(/usr/bin/tail -c1 "$HOSTS")" ] && echo >> "$HOSTS"
              { echo "$BEGIN"; echo "$want"; echo "$END"; } >> "$HOSTS"
            fi
            flush
            current="$want"
          fi
          /bin/sleep 2
        done

        """
    }

    /// Runs a shell script as root via the standard macOS admin password dialog.
    /// The script travels base64-encoded so no quoting can break the AppleScript string.
    private func runPrivileged(_ script: String, prompt: String) async -> Bool {
        let encoded = Data(script.utf8).base64EncodedString()
        let command = #"/bin/sh -c \"$(echo \#(encoded) | /usr/bin/base64 -D)\""#
        let appleScript = #"do shell script "\#(command)" with administrator privileges with prompt "\#(prompt)""#

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }
}
