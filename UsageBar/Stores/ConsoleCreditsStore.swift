import Foundation
import Observation

/// The Console organization credits the panel and Settings read: one state per Claude account,
/// refreshed on the same cycle as the Claude limits (the caller of `refresh(accountIDs:)` is the
/// existing refresh pass) and right after a sign-in. Reads go through ConsoleCreditsFetch, which
/// owns each account's session; this holds only the outcomes. A failed read keeps that account's
/// last good reading, marked stale (ConsoleCredits.next).
@MainActor @Observable
final class ConsoleCreditsStore {
    private(set) var states: [String: ConsoleCredits.State] = [:]
    /// Accounts whose Console login is not their Claude account's email ("Different Console account").
    private(set) var differentAccount: Set<String> = []
    private(set) var isRefreshing = false
    private var lastAttempt: [String: Date] = [:]

    /// A refresh inside this window of the account's previous attempt is skipped, so a refresh pass
    /// that runs often does not hit the Console each time. `force` (sign-in, manual reload) ignores it.
    static let minimumInterval: TimeInterval = 60

    private let fetch: @Sendable (String) async -> ConsoleCredits.Outcome
    private let identity: @Sendable (String) async -> ConsoleAccounts.IdentityRead
    private let legacyIdentity: @Sendable () async -> ConsoleAccounts.IdentityRead
    private let claudeEmail: @MainActor (String) -> String?
    private let defaults: UserDefaults
    private let clock: () -> Date

    init(fetch: @escaping @Sendable (String) async -> ConsoleCredits.Outcome,
         identity: @escaping @Sendable (String) async -> ConsoleAccounts.IdentityRead,
         legacyIdentity: @escaping @Sendable () async -> ConsoleAccounts.IdentityRead,
         claudeEmail: @escaping @MainActor (String) -> String?,
         defaults: UserDefaults = .standard,
         clock: @escaping () -> Date = Date.init) {
        self.fetch = fetch
        self.identity = identity
        self.legacyIdentity = legacyIdentity
        self.claudeEmail = claudeEmail
        self.defaults = defaults
        self.clock = clock
        loadConnections()
    }

    private func loadConnections() {
        for id in ConsoleCreditsFetch.Connection.connected(defaults) { states[id] = .unavailable }
        differentAccount = ConsoleCreditsFetch.Connection.mismatched(defaults)
    }

    func state(for accountID: String) -> ConsoleCredits.State { states[accountID] ?? .notConnected }
    func isDifferentAccount(_ accountID: String) -> Bool { differentAccount.contains(accountID) }

    /// One pass over the accounts, one at a time. The old single connection is handed to its
    /// account first (once), so that account's refresh already reads with the inherited session.
    func refresh(accountIDs: [String], force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await migrateLegacy(accountIDs: accountIDs)
        for id in accountIDs { await refreshOne(id, force: force) }
    }

    private func refreshOne(_ accountID: String, force: Bool) async {
        guard ConsoleCreditsFetch.Connection.isConnected(accountID, defaults: defaults) else {
            if states[accountID] != nil { states[accountID] = nil }
            return
        }
        let now = clock()
        if !force, let last = lastAttempt[accountID], now.timeIntervalSince(last) < Self.minimumInterval { return }
        lastAttempt[accountID] = now
        let outcome = await fetch(accountID)
        let next = ConsoleCredits.next(state(for: accountID), outcome, now: clock())
        if states[accountID] != next { states[accountID] = next }
    }

    /// The old single store goes to the account whose email matches its Console login (the
    /// default account when none does). Runs once; waits, a few refreshes at most, when the
    /// Console cannot be reached.
    private func migrateLegacy(accountIDs: [String]) async {
        let connection = ConsoleCreditsFetch.Connection.self
        guard connection.legacyPending(defaults), !accountIDs.isEmpty else { return }
        let read = await legacyIdentity()
        let candidates = accountIDs.map { ConsoleAccounts.Candidate(id: $0, email: claudeEmail($0)) }
        let attempts = read == .unreadable ? connection.nextLegacyAttempt(defaults) : 0
        guard case .assign(let owner)? = ConsoleAccounts.legacyOwner(read: read, accounts: candidates, attempts: attempts) else { return }
        connection.assignLegacyStore(to: owner, defaults: defaults)
        connection.set(true, account: owner, defaults: defaults)
        connection.setMismatch(ConsoleAccounts.isMismatch(console: read, claudeEmail: claudeEmail(owner)),
                               account: owner, defaults: defaults)
        connection.finishLegacy(defaults)
        states[owner] = .unavailable
        differentAccount = connection.mismatched(defaults)
        lastAttempt[owner] = nil
    }

    /// The sign-in window saw a working session for this account.
    func didConnect(accountID: String) async {
        let connection = ConsoleCreditsFetch.Connection.self
        connection.set(true, account: accountID, defaults: defaults)
        if states[accountID] == nil || states[accountID] == .notConnected { states[accountID] = .unavailable }
        let read = await identity(accountID)
        connection.setMismatch(ConsoleAccounts.isMismatch(console: read, claudeEmail: claudeEmail(accountID)),
                               account: accountID, defaults: defaults)
        differentAccount = connection.mismatched(defaults)
        await refreshOne(accountID, force: true)
    }

    func disconnect(accountID: String) async {
        await ConsoleCreditsFetch.disconnect(account: accountID, defaults: defaults)
        states[accountID] = nil
        differentAccount.remove(accountID)
        lastAttempt[accountID] = nil
    }
}
