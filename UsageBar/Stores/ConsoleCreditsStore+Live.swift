import Foundation

/// The app's one store, wired to the real Console fetcher and to the accounts' own emails. Apart
/// from ConsoleCreditsStore so that file (and its tests) needs nothing from the account models.
extension ConsoleCreditsStore {
    static let shared = ConsoleCreditsStore(
        fetch: { await ConsoleCreditsFetch.fetch(account: $0) },
        identity: { await ConsoleCreditsFetch.identity(account: $0) },
        legacyIdentity: { await ConsoleCreditsFetch.legacyIdentity() },
        claudeEmail: { ConsoleAccountDirectory.email(forAccountID: $0) })
}

/// What the Console features need to know about a Claude account.
@MainActor
enum ConsoleAccountDirectory {
    /// The Claude accounts that exist on this machine, default first.
    static var claudeAccountIDs: [String] {
        UsageStore.shared.discoveredAccounts.filter { $0.providerID == ClaudeAccounts.providerID }.map(\.id)
    }

    /// The account's signed-in email, from the usage reading when there is one, else from the
    /// account's own config file. Compared in memory only.
    static func email(forAccountID id: String) -> String? {
        if let email = UsageStore.shared.accounts.first(where: { $0.id == id })?.accountEmail, !email.isEmpty { return email }
        let known = UsageStore.shared.discoveredAccounts.first { $0.id == id }
        let dir = known?.locator["configDir"] ?? known?.launchHome ?? derivedDir(id)
        return dir.flatMap { ClaudeAccounts.profile(configDir: $0).email }
    }

    /// "claude:.claude2" -> "~/.claude2".
    private static func derivedDir(_ id: String) -> String? {
        guard let name = id.split(separator: ":", maxSplits: 1).last, id.hasPrefix(ClaudeAccounts.providerID + ":") else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(name)).path
    }
}
