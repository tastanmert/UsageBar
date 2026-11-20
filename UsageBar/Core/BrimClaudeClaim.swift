import Foundation

/// The confirmed Claude reset claim as UsageBar runs it, with every outside read injected so
/// tests/brimlive drives it against a fake transport. The rules are the
/// `mert/feat/claude-reset-inventory` branch's (ClaudeResetClaim, ClaudeResetClaimGate):
///
/// - Nothing is sent without `confirmed`, and the panel's Cancel is the default.
/// - The consent is bound to the login (`oauthAccount.accountUuid`), its organisation, the grant
///   and the reading's time, taken when the confirm card opened. A new reading, another login in
///   the home, a removed account or an expired grant between that moment and the request cancels.
/// - The credential read is bracketed by two identity reads; a login changing during it cancels.
/// - A token that has expired, or runs out within two minutes, is not sent (`loginExpiring`), and
///   it is never refreshed here: the card says the session needs renewing.
/// - The last look comes after the last await, right before the POST: the account is still
///   listed with the same home, the reading still backs the same consent (login, organisation,
///   grant, reading time), the home is still signed in to that login, the grant has not ended and
///   the token is still good for more than two minutes. Anything else sends nothing.
/// - One claim at a time across every panel and menu: the runner is the store's one gate.
///
/// NO PROVIDER PROCESS, ON PURPOSE (`BrimFeatures.claudeResetClaim`). A claim is one POST with the
/// token Claude Code already holds; it never refreshes a token and starts no provider process, so
/// it cannot race anything over an OAuth refresh, and the process register (BrimRuntime) has
/// nothing of it to stop: the login and consent checks above are what guard it.
/// - An answer that is not known (`uncertain`) keeps its request id for that login and grant, and
///   the caller re-reads the inventory before anything else (`afterUncertain`); a later claim of
///   the same grant then goes out under the same id, which the server treats as the same request.
@MainActor
final class BrimClaudeClaimRunner {
    /// What the user saw and agreed to on the confirm card.
    struct Approval: Equatable {
        var accountID: String
        var home: String
        var kind: ClaudeResetInventory.Kind
        var consent: ClaudeResetClaimGate.Consent
        /// Resets of this kind the reading held, to tell afterwards whether one was spent.
        var leftBefore: Int
    }

    struct Environment {
        /// The schedule's entry for the account right now.
        var currentEntry: () -> BrimClaudeResetSchedule.Entry?
        /// The account is still listed, with the same home.
        var stillListed: () -> Bool
        /// Identity, credential, identity (ClaudeResetClaim.readContext), off the main thread.
        var readContext: () async -> ClaudeResetClaim.ContextRead
        var version: String
        var transport: ClaudeResetInventoryFetch.Transport
        var now: () -> Date = Date.init
        /// The home's login as it stands right before the POST (ClaudeResetClaim.identity, off the
        /// main thread). Nil skips that read (tests that do not exercise it).
        var identityNow: (() async -> ClaudeResetClaim.Identity?)? = nil
    }

    private var gate = ClaudeResetClaimGate()
    /// Request ids kept after an uncertain answer, by account, login, organisation and grant.
    private var pending: [String: String] = [:]
    var isBusy: Bool { gate.isBusy }

    init() {}

    /// The consent the confirm card binds to, and the grant it would spend; nil when this kind may
    /// not be offered from this reading (stale, unbound, not usable, gone).
    nonisolated static func consent(accountID: String, kind: ClaudeResetInventory.Kind,
                                    entry: BrimClaudeResetSchedule.Entry?, now: Date, grantID: String? = nil)
        -> (consent: ClaudeResetClaimGate.Consent, grant: ClaudeResetInventory.Grant)? {
        guard let entry, entry.problem == nil,
              let reading = entry.reading, reading.eligible, let checkedAt = entry.checkedAt,
              let identity = entry.identity, let organization = entry.organizationID,
              kind != .other, let grant = pick(kind, grantID: grantID, in: reading), grant.left > 0, grant.usableNow,
              grant.endsAt > now, !grant.useRequiresLimit || reading.atLimit else { return nil }
        return (.init(accountID: accountID, identity: identity, organizationID: organization,
                      grantID: grant.id, checkedAt: checkedAt), grant)
    }

    /// The line's own grant when the panel named one (two Fable resets are two grants), else the
    /// soonest-ending usable grant of that kind. A named grant that is gone picks nothing.
    nonisolated static func pick(_ kind: ClaudeResetInventory.Kind, grantID: String?,
                                 in reading: ClaudeResetInventory) -> ClaudeResetInventory.Grant? {
        guard let grantID else { return reading.claimable(kind) }
        return reading.grants.first(where: { $0.id.raw == grantID && $0.kind == kind })
    }

    nonisolated static func approval(accountID: String, home: String, kind: ClaudeResetInventory.Kind,
                                     entry: BrimClaudeResetSchedule.Entry?, now: Date, grantID: String? = nil) -> Approval? {
        guard let (consent, _) = consent(accountID: accountID, kind: kind, entry: entry, now: now, grantID: grantID),
              let reading = entry?.reading else { return nil }
        let left = reading.grants.filter { $0.kind == kind }.reduce(0) { $0 + $1.left }
        return Approval(accountID: accountID, home: home, kind: kind, consent: consent, leftBefore: left)
    }

    /// Spends one grant, only for `confirmed` and only while the approval still holds.
    func claim(_ approval: Approval, confirmed: Bool, env: Environment) async -> ClaudeResetClaim.Outcome {
        guard confirmed else { return .cancelled }
        let current = { Self.consent(accountID: approval.accountID, kind: approval.kind,
                                     entry: env.currentEntry(), now: env.now(), grantID: approval.consent.grantID.raw) }
        guard let (now, grant) = current().map({ ($0.consent, $0.grant) }), now == approval.consent,
              let ticket = gate.begin(approval.consent, current: now, grant: grant, stale: false,
                                      confirmed: confirmed, now: env.now())
        else { return .cancelled }
        defer { gate.finish(ticket) }
        let read = await env.readContext()
        if case .loginExpiring = read { return .loginExpiring }
        // A login, refresh, removed account or expired grant during the credential read cancels the
        // consent. Never spend on whichever login now owns the same folder.
        guard env.stillListed(),
              gate.isCurrent(ticket, consent: approval.consent, current: current()?.consent),
              case .ready(let context) = read, context.identity.accountID == approval.consent.identity,
              context.identity.organizationID == approval.consent.organizationID,
              grant.endsAt > env.now() else { return .cancelled }
        guard context.credential.expiresAt.timeIntervalSince(env.now()) > ClaudeResetInventoryFetch.expiryMargin else { return .loginExpiring }
        let key = Self.key(approval)
        var claim = ClaudeResetClaim(organizationID: approval.consent.organizationID,
                                     credential: context.credential, version: env.version,
                                     pendingRequestID: pending[key])
        guard let prepared = claim.prepare(grantID: grant.id.raw) else { return .error }
        let loginNow = await env.identityNow?()
        // The last look: no await between here and the POST. The consent, the login and the token
        // are checked again after everything above that could suspend.
        guard env.stillListed(),
              gate.isCurrent(ticket, consent: approval.consent, current: current()?.consent),
              env.identityNow == nil || loginNow == context.identity,
              grant.endsAt > env.now() else { return .cancelled }
        guard context.credential.expiresAt.timeIntervalSince(env.now()) > ClaudeResetInventoryFetch.expiryMargin else { return .loginExpiring }
        let outcome = await claim.send(prepared, transport: env.transport)
        pending[key] = claim.pendingRequestID
        return outcome
    }

    /// The request id a later claim of this approval's grant would reuse (nil: a fresh one).
    func pendingRequestID(for approval: Approval) -> String? { pending[Self.key(approval)] }

    /// The account changed hands or went away: its kept request ids go with it.
    func forget(accountID: String) {
        pending = pending.filter { !$0.key.hasPrefix(accountID + "|") }
    }

    private static func key(_ approval: Approval) -> String {
        [approval.accountID, approval.consent.identity, approval.consent.organizationID,
         approval.consent.grantID.raw].joined(separator: "|")
    }

    /// What the panel says right after the answer.
    nonisolated static func status(_ outcome: ClaudeResetClaim.Outcome) -> BrimPanelModel.ResetUse {
        switch outcome {
        case .cancelled: .refused(.changed)
        case .loginExpiring: .refused(.loginExpiring)
        case .result(.reset, _, _): .checking(spent: true)
        case .result(.notLimited, _, _): .refused(.notLimited)
        case .result(.alreadyUsed, _, _): .refused(.alreadyUsed)
        case .result(.cooldown, _, _): .refused(.cooldown)
        case .result(.ineligible, _, _): .refused(.ineligible)
        case .rateLimited: .refused(.rateLimited)
        case .authError: .refused(.loginRejected)
        case .error: .failed
        // Not known whether it went through: read again before saying anything (or trying again).
        case .uncertain, .result(.unavailable, _, _): .checking(spent: nil)
        }
    }

    /// After an uncertain answer, the first reading taken later says what happened: fewer of this
    /// kind left than the approval saw is a spent reset. Nil while no newer reading is in.
    nonisolated static func afterUncertain(_ approval: Approval, entry: BrimClaudeResetSchedule.Entry?)
        -> BrimPanelModel.ResetUse? {
        guard let entry, let checkedAt = entry.checkedAt, checkedAt > approval.consent.checkedAt,
              let reading = entry.reading else { return nil }
        guard entry.identity == approval.consent.identity, entry.organizationID == approval.consent.organizationID else { return .refused(.changed) }
        let left = reading.grants.filter { $0.kind == approval.kind }.reduce(0) { $0 + $1.left }
        return left < approval.leftBefore ? .used : .notApplied
    }
}
