import Foundation

/// The launch-time rewrite of integration entries an earlier build installed, so the machine ends
/// up with the current names and nothing keeps depending on the old ones. The old names themselves
/// live only in LegacyIdentifierMigration.swift.
///
/// Only what this app wrote is touched, found by the manifest it keeps and by what an entry runs:
///
/// - the manifest components of the prompt command and its hook are renamed;
/// - the prompt hook in each recorded settings.json, and the command file beside it, are brought
///   to the current subcommand through the ordinary sync (`syncPromptCommands`), which backs each
///   file up first and leaves every entry that is not ours as it is;
/// - the PATH shims that carry the old header are rewritten with the current script, backed up
///   first.
///
/// Idempotent: with nothing old on disk it reads two files and writes none. A failure keeps the
/// old manifest components, so the next launch tries again; until then the CLI still answers the
/// old subcommand (`LegacyIdentifierMigration.promptHookVerb`).
extension IntegrationsStore {
    /// The skill files of ours among the installed ones. Off the main actor: it reads each file.
    private nonisolated static func ourInstalledSkillFiles() -> [URL] {
        installedSkillFiles().filter {
            (try? String(contentsOf: $0, encoding: .utf8)).map(skillFileIsOurs) == true
        }
    }

    /// Rewrites each shim that carries the old header with the current script, backed up first.
    /// Returns how many were rewritten; failures are appended to `errors`.
    private nonisolated static func rewriteLegacyShims(errors: inout [String]) -> Int {
        var count = 0
        for shim in Shim.allCases {
            guard let script = try? String(contentsOf: shim.scriptURL, encoding: .utf8),
                  script.contains(LegacyIdentifierMigration.shimHeader) else { continue }
            do {
                try IntegrationsBackup.save(shim.scriptURL)
                try shimScript(shim).write(to: shim.scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.scriptURL.path)
                count += 1
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return count
    }

    /// Returns how many files were rewritten.
    @discardableResult
    func migrateLegacyRegistrations() -> Int {
        // Shared state belongs to the installed release app, as for every other integration write.
        guard BrimFeatures.integrationInstall, BuildVariant.ownsIntegrations, !BuildVariant.isUnshipped else { return 0 }
        var rewritten = 0

        let legacyKeys = [LegacyIdentifierMigration.commandManifest, LegacyIdentifierMigration.hookManifest]
        if legacyKeys.contains(where: { Self.manifestDocument()[$0] != nil }) {
            let errorBefore = lastError
            lastError = nil
            let ours = Self.ourInstalledSkillFiles()
            if !ours.isEmpty, syncPromptCommands(forSkillFiles: ours) { rewritten += 1 }
            if lastError == nil {
                for key in legacyKeys { recordManifest(key, paths: nil) }
                lastError = errorBefore
            }
        }

        var shimErrors: [String] = []
        rewritten += Self.rewriteLegacyShims(errors: &shimErrors)
        if let error = shimErrors.first { lastError = error }
        if rewritten > 0 { refresh() }
        return rewritten
    }
}
