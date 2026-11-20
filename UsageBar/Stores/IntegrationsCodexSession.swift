import Foundation

extension IntegrationsStore {
    static var codexSessionRoot: URL { UsageSnapshot.directory }

    static func codexSessionHomes() -> [String] {
        CodexAccounts.discover().compactMap(\.launchHome)
    }

    static func detectCodexSessionHooks(homes: [String]) -> Status {
        do {
            if try CodexSessionHooks.installed(homes: homes, root: codexSessionRoot) {
                return .installed
            }
            return try CodexSessionHooks.receipt(root: codexSessionRoot) == nil
                ? .notInstalled : .broken(L("Codex session status installation needs attention."))
        } catch { return .broken(error.localizedDescription) }
    }

    /// The registered command, through whichever program runs (`integrationCLIPath`).
    static func codexSessionHookCommand() -> String {
        "\(integrationCLIPath()) codex-session-hook"
    }

    func installCodexSessionHooks() {
        guard guardNotDev(), guardCLIDeliverable() else { return }
        lastError = nil
        do {
            try CodexSessionHooks.install(homes: Self.codexSessionHomes(), root: Self.codexSessionRoot,
                                          command: Self.codexSessionHookCommand(),
                                          beforeWrite: { try IntegrationsBackup.save(URL(fileURLWithPath: $0)) })
        } catch { lastError = error.localizedDescription }
        // Keep a partial installation visible and removable after a failed write.
        if let receipt = try? CodexSessionHooks.receipt(root: Self.codexSessionRoot) {
            recordManifest(CodexSessionHooks.component,
                           paths: receipt.paths + [CodexSessionHooks.receiptURL(root: Self.codexSessionRoot).path])
        }
        refresh()
    }

    func removeCodexSessionHooks() {
        guard guardNotDev() else { return }
        lastError = nil
        do {
            try CodexSessionHooks.remove(root: Self.codexSessionRoot,
                                         beforeWrite: { try IntegrationsBackup.save(URL(fileURLWithPath: $0)) })
            recordManifest(CodexSessionHooks.component, paths: nil)
        } catch { lastError = error.localizedDescription }
        refresh()
    }
}
