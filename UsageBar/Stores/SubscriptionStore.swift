import Foundation
import Observation

/// Each account's plan renewal (SubscriptionRenewal), kept between launches. Asked rarely: a
/// renewal moves once a month at most, and the date shown rolls itself forward by the stated
/// period (`SubscriptionRenewal.nextRenewal`), so a claude.ai session that later expires still
/// leaves a right answer on screen. A failed read keeps the last good one.
@MainActor @Observable
final class SubscriptionStore {
    static let shared = SubscriptionStore()

    enum Status: String, Codable { case read, noDate, notConnected, differentAccount, failed }

    private(set) var renewals: [String: SubscriptionRenewal] = [:]
    private(set) var statuses: [String: Status] = [:]
    private var lastAttempt: [String: Date] = [:]
    private var running: Set<String> = []

    /// Between two automatic reads of one account.
    static let interval: TimeInterval = 6 * 3600
    private static let key = "subscriptionRenewals"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: SubscriptionRenewal].self, from: data) {
            renewals = saved
        }
    }

    func isConnectedToClaudeWeb(_ accountID: String) -> Bool {
        SubscriptionFetch.ClaudeConnection.connected().contains(accountID)
    }

    /// One pass over the given accounts; each is skipped inside `interval` unless `force`.
    func refresh(accounts: [ProviderAccount], force: Bool = false) async {
        let now = Date()
        for account in accounts {
            guard let home = account.launchableHome, !running.contains(account.id) else { continue }
            if !force, let last = lastAttempt[account.id], now.timeIntervalSince(last) < Self.interval { continue }
            lastAttempt[account.id] = now
            running.insert(account.id)
            let outcome: SubscriptionFetch.Outcome
            switch account.providerID {
            case CodexAccounts.providerID:
                outcome = await SubscriptionFetch.codex(home: home)
            case ClaudeAccounts.providerID:
                let organization = await Task.detached { ClaudeResetClaim.identity(configHome: home)?.organizationID }.value
                outcome = await SubscriptionFetch.claude(accountID: account.id, organization: organization,
                                                         connected: isConnectedToClaudeWeb(account.id))
            default:
                running.remove(account.id)
                continue
            }
            running.remove(account.id)
            apply(outcome, to: account.id)
        }
        await remind(accounts: accounts, now: Date())
    }

    // MARK: Reminder

    private static let sentKey = "renewalRemindersSent"

    /// A notification a few days before a plan renews or a cancelled plan's access stops
    /// (RenewalReminder). Remembered only once it reached the user, so a refused permission does
    /// not spend the warning.
    private func remind(accounts: [ProviderAccount], now: Date) async {
        let byID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let shown = renewals.filter { byID[$0.key] != nil }
        var sent = UserDefaults.standard.dictionary(forKey: Self.sentKey) as? [String: Double] ?? [:]
        for due in RenewalReminder.due(shown, sent: sent, now: now) {
            guard let account = byID[due.accountID] else { continue }
            let day = due.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: AppLocale.identifier)))
            let body = String(format: due.kind == .renews ? L("Renews on %@") : L("Cancelled, access ends on %@"), day)
            guard await SystemAlert.post(title: account.label, body: body) else { continue }
            sent[due.accountID] = due.stamp
            UserDefaults.standard.set(sent, forKey: Self.sentKey)
        }
    }

    /// After a claude.ai sign-in: read that account now.
    func didConnectClaude(account: ProviderAccount) async {
        SubscriptionFetch.ClaudeConnection.set(true, account: account.id)
        await refresh(accounts: [account], force: true)
    }

    private func apply(_ outcome: SubscriptionFetch.Outcome, to id: String) {
        switch outcome {
        case .read(let renewal):
            renewals[id] = renewal
            statuses[id] = .read
            save()
        case .noDate:
            statuses[id] = .noDate
            if renewals.removeValue(forKey: id) != nil { save() }
        case .notConnected: statuses[id] = .notConnected
        case .differentAccount: statuses[id] = .differentAccount
        case .failed: statuses[id] = .failed
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(renewals) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
