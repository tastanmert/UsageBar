import Foundation

/// A copy of every user file an integration install or removal is about to rewrite, taken before
/// the write: settings.json, .claude.json, hooks.json, .zshenv, .zshrc. One folder per app process
/// under `~/.usagebar/backups/<stamp>/`, one copy per file in it (the first state this process saw),
/// named by the path with its separators folded so two homes' settings.json cannot collide.
///
/// Nothing here is restored automatically. The removal paths undo their own edits; the copies are
/// for a hand restore when something else went wrong, and `tests` point `root` at a scratch folder.
enum IntegrationsBackup {
    nonisolated(unsafe) static var root = UsageSnapshot.directory.appendingPathComponent("backups", isDirectory: true)

    /// Fixed at first use, so one process writes into one folder.
    nonisolated(unsafe) private static var stamp: String?
    private static let lock = NSLock()

    static func folder() -> URL {
        lock.lock(); defer { lock.unlock() }
        if stamp == nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            stamp = formatter.string(from: Date()) + "-" + UUID().uuidString
        }
        return root.appendingPathComponent(stamp!, isDirectory: true)
    }

    /// Where `file` is copied to. `~/.claude2/settings.json` becomes `.claude2__settings.json`.
    static func copyURL(for file: URL) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = file.standardizedFileURL.path
        if path.hasPrefix(home + "/") { path = String(path.dropFirst(home.count + 1)) }
        let name = path.replacingOccurrences(of: "/", with: "__")
        return folder().appendingPathComponent(name)
    }

    /// Copies `file` if it exists and has not been copied by this process yet. Returns the copy's
    /// path, or nil when there was nothing to copy. Throws when the copy cannot be made: a write
    /// without a backup is exactly what this exists to prevent.
    @discardableResult
    static func save(_ file: URL) throws -> URL? {
        let fm = FileManager.default
        let source = file.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: source.path) else { return nil }
        let copy = copyURL(for: file)
        if fm.fileExists(atPath: copy.path) {
            let next = copy.appendingPathExtension(UUID().uuidString)
            try fm.copyItem(at: source, to: next)
            return next
        }
        let dir = copy.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try fm.copyItem(at: source, to: copy)
        return copy
    }
}
