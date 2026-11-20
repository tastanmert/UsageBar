import Foundation
import OSLog

/// Captures existing usage responses only. Request headers and credentials never enter here.
enum BrimUsageDiagnostics {
    static var enabled: Bool {
#if DEBUG
        BuildVariant.isDev
#else
        false
#endif
    }

    static func claude(_ body: Data, profileHome: String) {
        guard enabled else { return }
        save(body, name: "claude-usage-\(profile(profileHome)).json")
    }

    static func codex(_ body: Data, profileHome: String, method: String) {
        guard enabled, ["account/rateLimits/read", "account/read"].contains(method) else { return }
        do {
            let data = try redacted(body)
            save(data, name: "codex-\(profile(profileHome))-\(method.replacingOccurrences(of: "/", with: "-")).json")
        } catch {
            log.error("Usage diagnostic JSON could not be redacted")
        }
    }

    static func redacted(_ body: Data) throws -> Data {
        func scrub(_ value: Any) -> Any {
            if let object = value as? [String: Any] {
                return object.reduce(into: [String: Any]()) { result, entry in
                    let sensitive = ["token", "secret", "authorization", "cookie"].contains {
                        entry.key.lowercased().contains($0)
                    }
                    result[entry.key] = sensitive ? "[REDACTED]" : scrub(entry.value)
                }
            }
            if let array = value as? [Any] { return array.map(scrub) }
            return value
        }
        return try JSONSerialization.data(withJSONObject: scrub(JSONSerialization.jsonObject(with: body)),
                                          options: [.sortedKeys, .fragmentsAllowed])
    }

    private static func profile(_ home: String) -> String {
        URL(fileURLWithPath: home).lastPathComponent
    }

    private static let log = Logger(subsystem: BrandPaths.appBundleID, category: "usage-diagnostics")

    private static func save(_ data: Data, name: String) {
#if DEBUG
        guard BuildVariant.isDev else { return }
        do {
            try write(data, name: name, directory: BrandPaths.stateDirectory.appendingPathComponent("debug"))
        } catch {
            // Error details can contain paths. Keep the log free of response content and identity.
            log.error("Usage diagnostic file could not be written")
        }
#endif
    }

#if DEBUG
    /// The temporary file is private from creation; rename publishes it atomically.
    static func write(_ data: Data, name: String, directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? fm.removeItem(at: temporary) }
        try handle.write(contentsOf: data)
        guard rename(temporary.path, directory.appendingPathComponent(name).path) == 0 else {
            throw POSIXError(.EIO)
        }
    }
#endif
}
