import Foundation

/// A pretend disk for the settings window: a home with three Claude and two Codex profiles, one
/// stray Claude folder, and UsageBar's integrations installed. No real path is ever read.
enum BrimSettingsFixtures {
    static let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)

    static func folder(_ name: String) -> URL { home.appendingPathComponent(name, isDirectory: true) }

    static let folders = [".claude", ".claude-old", ".claude-server-commander", ".claude2", ".claude3",
                          ".codex", ".codex2"].map(folder)

    /// path -> file body; a nil body is a file that exists but cannot be read.
    static func probe(_ files: [String: String?]) -> BrimFileProbe {
        BrimFileProbe(
            exists: { files.keys.contains($0) },
            read: { path in
                guard let entry = files[path] else { return .missing }
                guard let body = entry else { return .unreadable }
                return .data(Data(body.utf8))
            })
    }

    static func path(_ relative: String) -> String { home.appendingPathComponent(relative).path }

    /// UsageBar's CLI, MCP entry, status line, hooks and Codex hooks; no shims, nothing of UsageBar's.
    static var usageBarInstalled: [String: String?] {
        [
            "/usr/local/bin/usagebar": "",
            path(".claude.json"): #"{"mcpServers": {"usagebar": {"command": "/usr/local/bin/usagebar", "args": ["mcp"]}}}"#,
            path(".claude/settings.json"): #"""
            {"statusLine": {"type": "command", "command": "/usr/local/bin/usagebar statusline"},
             "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/usr/local/bin/usagebar hook stop"}]}]}}
            """#,
            path(".claude/.credentials.json"): "",
            path(".claude-old/settings.json"): "{}",
            path(".claude2/settings.json"): "{}",
            path(".claude3/settings.json"): "{}",
            path(".codex/auth.json"): "",
            path(".codex/hooks.json"): #"{"hooks": {"SessionStart": [{"hooks": [{"command": "/usr/local/bin/usagebar codex-session-hook"}]}]}}"#,
            path(".codex2/auth.json"): "",
        ]
    }

    static var claudeHomes: [URL] { folders.filter { !$0.lastPathComponent.hasPrefix(".codex") } }
    static var codexHomes: [URL] { folders.filter { $0.lastPathComponent.hasPrefix(".codex") } }
}
