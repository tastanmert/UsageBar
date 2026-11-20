import Foundation

/// What the user agreed to on a Codex confirm card: this account, signed in as this identity
/// (home, email, plan and login type from the latest `account/read`), spending this credit.
/// Taken when the card opens, from the reading on screen; the spend then goes through
/// `CodexAppServerClient.consume(expected:credit:)`, which reads the identity again in the same
/// session right before the write and sends nothing to a login that is not this one.
///
/// Live mode only (a running `codex app-server` spends it) and manual only: no automatic path
/// builds one of these.
struct BrimCodexApproval: Equatable, Sendable {
    var accountID: String
    var identity: CodexAccountIdentity
    var credit: BankedResetCredit

    /// The consent the card binds to; nil when the reading cannot back one: no identity with an
    /// email for this home, or no spendable credit with an id. The soonest-ending credit is the
    /// one spent (the card's lines are in that order and carry no id of their own).
    static func make(accountID: String, home: String, identity: CodexAccountIdentity?,
                     credits: [BankedResetCredit]?) -> BrimCodexApproval? {
        guard let identity, identity.home == home else { return nil }
        let spendable = (credits ?? []).filter {
            ($0.status == nil || $0.status == "available") && !($0.id ?? "").isEmpty
        }
        let soonest = spendable.enumerated().min { a, b in
            switch (a.element.expiresAt, b.element.expiresAt) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }?.element
        guard let soonest else { return nil }
        return BrimCodexApproval(accountID: accountID, identity: identity, credit: soonest)
    }

    /// Still the login the card was opened for: the latest read names the same identity.
    func stillBound(to current: CodexAccountIdentity?) -> Bool { current == identity }

    /// What the card says right after the consume answered.
    ///
    /// `settlesEarlier` is true when an earlier attempt on this home was still open (its answer
    /// was lost): the coordinator then settles THAT attempt first, re-sending the same credit and
    /// idempotency key, and its `.resolved` is about the earlier request, not the credit this
    /// card chose. Either way one reset went through on this account, so the card measures again
    /// and says "Reset" with the new numbers; the chosen credit is not spent and stays listed.
    static func status(_ outcome: CodexAppServerClient.ConsumeOutcome,
                       settlesEarlier: Bool) -> BrimPanelModel.ResetUse {
        switch outcome {
        case .resolved(.redeemed): .checking(spent: true)
        case .resolved(.alreadyUsed): settlesEarlier ? .checking(spent: true) : .refused(.alreadyUsed)
        case .resolved(.noCredit): .refused(.noCredit)
        case .resolved(.failed): .failed
        // Not known whether it went through: the attempt stays open (same credit, same key) and
        // the account is read again before anything else.
        case .uncertain: .checking(spent: nil)
        case .identityChanged: .refused(.accountChanged)
        // Nothing sent: the credit is no longer listed as available, or live mode closed.
        case .unavailable: .refused(.changed)
        }
    }
}
