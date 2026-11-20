import Foundation

/// Records transitions only. Provider prose and diagnostic bodies never reach disk.
struct RefreshFailureLog {
    private var failures: [String: String] = [:]

    mutating func transition(accountID: String, error: String?, failed: Bool, now: Date) -> String? {
        let previous = failures[accountID]
        if failed {
            let fingerprint = error ?? "unknown"
            guard previous != fingerprint else { return nil }
            failures[accountID] = fingerprint
        } else {
            guard previous != nil else { return nil }
            failures[accountID] = nil
        }
        let parts = accountID.split(separator: ":", maxSplits: 1).map(String.init)
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let id = accountID.utf8.count <= 128 && parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(safe.contains) }
            ? accountID : "redacted-account"
        let reason: String
        let message = (error ?? "").lowercased()
        if !failed { reason = "recovered" }
        else if ["login", "sign in", "auth", "401", "403", "oturum"].contains(where: message.contains) { reason = "authentication" }
        else if ["429", "rate limit", "limiting", "sınırlıyor"].contains(where: message.contains) { reason = "rate-limited" }
        else if ["timeout", "timed out", "zaman aş"].contains(where: message.contains) { reason = "timeout" }
        else if ["network", "connection", "ağ"].contains(where: message.contains) { reason = "network" }
        else { reason = "usage-unavailable" }
        return "\(ISO8601DateFormatter().string(from: now)) account=\(id) reason=\(reason)\n"
    }

    static func append(_ line: String, to file: URL, limit: Int = 1024 * 1024) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(line.utf8)
        if fm.fileExists(atPath: file.path) {
            let size = try fm.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
            if size + data.count > limit {
                let older = URL(fileURLWithPath: file.path + ".1")
                if fm.fileExists(atPath: older.path) { try fm.removeItem(at: older) }
                try fm.moveItem(at: file, to: older)
            }
        }
        if !fm.fileExists(atPath: file.path) {
            guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
