import AppKit

/// Signing in to Claude Code is an interactive terminal flow, so the app never
/// tries to perform it. It prepares the exact command and hands the user a
/// Terminal window already running it.
enum Reauth {
    static let installURL = URL(string: "https://claude.com/product/claude-code")!

    static func launch() {
        guard let bin = OfficialUsage.binaryPath(), let script = writeScript(for: bin) else {
            NSWorkspace.shared.open(installURL)
            return
        }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Terminal", script.path]
        try? open.run()
    }

    /// Terminal runs an executable file it is asked to open, which gets us an
    /// interactive session without requesting Automation permission for AppleScript.
    private static func writeScript(for binary: String) -> URL? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenBurnrate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("claude-sign-in.command")

        let script = """
        #!/bin/sh
        echo "Signing in to Claude Code. TokenBurnrate picks up usage once this finishes."
        echo
        \(quoted(binary)) auth login
        status=$?
        echo
        if [ $status -eq 0 ]; then
          echo "Done. You can close this window."
        else
          echo "Sign-in did not complete (exit $status)."
        fi
        """
        guard let data = script.data(using: .utf8),
              (try? data.write(to: url, options: .atomic)) != nil,
              (try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)) != nil
        else { return nil }
        return url
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
