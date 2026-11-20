import Foundation

/// Whether a project folder's own Claude Code settings replace UsageBar's status line.
///
/// Claude Code merges settings user < project (`.claude/settings.json`) < local
/// (`.claude/settings.local.json`), and a `statusLine` set in a project file wins over the one in
/// the user's `settings.json` that UsageBar installs. Settings → Integrations only reads the user
/// files, so it kept saying "Installed" for a folder whose sessions never call `usagebar statusline`
///.
///
/// One file compiled by both targets (project.yml): the app counts the overridden folders of its
/// running sessions, and `usagebar status --json` names the file per session. The command UsageBar
/// registers lives here for the same reason, so that "ours" has a single spelling.
enum ProjectStatusLine {
    /// What `IntegrationsStore` writes into the user's settings.json as the status line command.
    nonisolated static let ourCommand = "/usr/local/bin/\(BrandPaths.cliName) statusline claude"

    /// The same command through a given program: the public link when it runs, else the CLI
    /// inside the installed app (`IntegrationsStore.integrationCLIPath`).
    nonisolated static func command(at program: String) -> String { "\(program) statusline claude" }

    /// Whether a registered status line is UsageBar's, wherever its program lives: the first word
    /// (quotes stripped) is a program named `usagebar`, followed by `statusline claude`.
    nonisolated static func isOurs(_ command: String) -> Bool {
        program(of: command).map { $0.name == BrandPaths.cliName && $0.rest.hasPrefix("statusline claude") } == true
    }

    /// The first shell word of a command line, with surrounding quotes removed, and the rest.
    nonisolated static func program(of command: String) -> (name: String, rest: String)? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var word = Substring(trimmed)
        var rest = Substring("")
        if let quote = trimmed.first, quote == "\"" || quote == "'" {
            let body = trimmed.dropFirst()
            guard let close = body.firstIndex(of: quote) else { return nil }
            word = body[..<close]
            rest = body[body.index(after: close)...]
        } else if let space = trimmed.firstIndex(of: " ") {
            word = trimmed[..<space]
            rest = trimmed[space...]
        }
        return ((String(word) as NSString).lastPathComponent, rest.trimmingCharacters(in: .whitespaces))
    }

    /// The file that makes a session started in `cwd` ignore UsageBar's status line, or nil.
    ///
    /// Mirrors where Claude Code actually loads project settings from (docs: Settings, "Where
    /// Claude Code keeps the local file in a git repository"). The shared `.claude/settings.json`
    /// is read from the session's folder only, never from a parent. The local
    /// `.claude/settings.local.json` lives at the repository root (a worktree uses the main
    /// checkout's root), except outside a git repository or when the root is the user's home, where
    /// it stays in `cwd`. A local file an older Claude Code left in `cwd` is still read, ranked
    /// below the root's. Candidates in rank order: root local, `cwd` local, `cwd` shared. The first
    /// that carries a `statusLine.command` decides: UsageBar's own command is no override. A missing,
    /// unreadable or unparsable file carries nothing. Read-only, never throws.
    ///
    /// `userHome` is skipped as a project folder: `~/.claude/settings.json` is the USER layer
    /// UsageBar manages.
    ///
    /// Named blind spots: the ownership clause (root, `.git` or `.claude` not owned by the user
    /// keeps the local file in `cwd`), Windows, and a `/cd` mid-session (UsageBar only knows the
    /// supervisor's launch folder).
    nonisolated static func overridingFile(cwd: String, userHome: String = NSHomeDirectory()) -> String? {
        let start = URL(fileURLWithPath: cwd).standardizedFileURL
        let home = URL(fileURLWithPath: userHome).standardizedFileURL.path
        guard start.path != home else { return nil }
        var files: [URL] = []
        if let root = repositoryRoot(of: start), root.path != home, root.path != start.path {
            files.append(root.appendingPathComponent(".claude/settings.local.json"))
        }
        files.append(start.appendingPathComponent(".claude/settings.local.json"))
        files.append(start.appendingPathComponent(".claude/settings.json"))
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let command = (settings["statusLine"] as? [String: Any])?["command"] as? String
            else { continue }
            return isOurs(command) ? nil : file.path
        }
        return nil
    }

    /// The repository root Claude Code keeps the local settings file in: the first folder from
    /// `cwd` up holding a `.git`. A `.git` directory makes that folder the root; a `.git` FILE
    /// (`gitdir: <main>/.git/worktrees/<name>`) is a worktree, whose root is the main checkout, the
    /// parent of the common `.git`. A file pointing elsewhere (a submodule) keeps its own folder.
    private nonisolated static func repositoryRoot(of cwd: URL) -> URL? {
        let fm = FileManager.default
        var dir = cwd
        while true {
            let git = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git.path, isDirectory: &isDir) {
                guard !isDir.boolValue,
                      let text = try? String(contentsOf: git, encoding: .utf8),
                      let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") })
                else { return dir }
                let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                let gitdir = URL(fileURLWithPath: target, relativeTo: dir).standardizedFileURL
                let parts = gitdir.pathComponents
                guard let i = parts.lastIndex(of: "worktrees"), i >= 2, parts[i - 1] == ".git"
                else { return dir }
                return URL(fileURLWithPath: NSString.path(withComponents: Array(parts[..<(i - 1)])))
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }
}
