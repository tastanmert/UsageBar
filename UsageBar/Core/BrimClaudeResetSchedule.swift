import Foundation

/// When UsageBar asks Anthropic for each Claude account's reset inventory, and what it keeps from
/// the answers. Pure: no clock, no network, no store, so tests/claudeinventory pins every rule.
///
/// - At most one request per account every `interval` (10 min), whether the timer or a panel
///   opening asks; the panel opening asks only when the last attempt is that old.
/// - 401/403 backs the account off `rejectedBackoff` (60 min), 429 `rateLimitBackoff` (30 min).
/// - No request went out (token expiring, Keychain not readable): looked at again after
///   `credentialRecheck`, which costs a local read only, so a login UsageBar refreshed shows soon.
/// - A failed attempt keeps the last reading, marked held over. Unknown is never a zero.
/// - A reading belongs to the login it was taken under (`identity`, the home's
///   `oauthAccount.accountUuid`, and its organisation), not to the folder: a home now naming
///   another login loses its reading (`note`), and so does one a login just landed in
///   (`invalidate`). A claim's consent is bound to those, so it cannot spend on the next login.
///
/// Held in memory only: nothing here is written to disk, UsageBar's or UsageBar's.
struct BrimClaudeResetSchedule {
    static let interval: TimeInterval = 10 * 60
    static let rejectedBackoff: TimeInterval = 60 * 60
    static let rateLimitBackoff: TimeInterval = 30 * 60
    static let credentialRecheck: TimeInterval = 2 * 60

    struct Entry: Equatable {
        /// The last inventory the server returned for the account.
        var reading: ClaudeResetInventory?
        var checkedAt: Date?
        /// Why the latest attempt gave no reading; nil after a good read.
        var problem: BrimPanelModel.ResetUnknown?
        var lastAttempt: Date?
        /// No request before this (a back-off).
        var notBefore: Date?
        var inFlight = false
        /// The latest attempt sent nothing (no usable credential).
        var sentNothing = false
        /// Whose login `reading` was taken under, and its organisation. In memory only, never
        /// logged or published; nil when the home's config named nobody.
        var identity: String?
        var organizationID: String?
        /// Bumped whenever the home changes hands, so an answer that left before is thrown away.
        var generation = 0
    }

    private(set) var entries: [String: Entry] = [:]

    /// Forgets accounts no longer listed.
    mutating func prune(keeping ids: Set<String>) {
        entries = entries.filter { ids.contains($0.key) }
    }

    func isDue(_ id: String, now: Date) -> Bool {
        guard let entry = entries[id] else { return true }
        if entry.inFlight { return false }
        if let notBefore = entry.notBefore, now < notBefore { return false }
        guard let last = entry.lastAttempt else { return true }
        let wait = entry.sentNothing ? Self.credentialRecheck : Self.interval
        return now.timeIntervalSince(last) >= wait
    }

    /// Marks a request out for `id`; false when it is not due (the caller then sends nothing).
    mutating func begin(_ id: String, now: Date) -> Bool {
        guard isDue(id, now: now) else { return false }
        entries[id, default: Entry()].lastAttempt = now
        entries[id, default: Entry()].inFlight = true
        return true
    }

    /// The generation a request leaving now is filed under.
    func generation(_ id: String) -> Int { entries[id]?.generation ?? 0 }

    /// The home changed hands (a login landed or was renewed there, or a claim spent a grant):
    /// the reading goes, the next tick asks at once, and an answer already out is disowned.
    mutating func invalidate(_ id: String) {
        guard var entry = entries[id] else { return }
        entry = Entry(generation: entry.generation + 1)
        entries[id] = entry
    }

    /// What the home's config names now. Only two different names count as a change: a read that
    /// found nobody (a login half written) says nothing either way.
    mutating func note(_ id: String, identity: String?) {
        guard let held = entries[id]?.identity, let identity, held != identity else { return }
        invalidate(id)
    }

    mutating func land(_ id: String, _ outcome: ClaudeResetInventoryFetch.Outcome, now: Date,
                       identity: String? = nil, organizationID: String? = nil, generation: Int? = nil) {
        guard var entry = entries[id] else { return }
        if let generation, generation != entry.generation { return }
        entry.inFlight = false
        entry.sentNothing = false
        switch outcome {
        case .read(let inventory):
            entry.reading = inventory
            entry.checkedAt = now
            entry.problem = nil
            entry.notBefore = nil
            entry.identity = identity
            entry.organizationID = organizationID
        case .noCredential(let reason):
            entry.sentNothing = true
            entry.problem = switch reason {
            case .expiring: .loginExpiring
            case .unreadable: .loginUnreadable
            case .missing: .loginMissing
            }
        case .failed(let status):
            switch status {
            case 401, 403:
                entry.problem = .rejected
                entry.notBefore = now.addingTimeInterval(Self.rejectedBackoff)
            case 429:
                entry.problem = .rateLimited
                entry.notBefore = now.addingTimeInterval(Self.rateLimitBackoff)
            default:
                entry.problem = .failed
            }
        }
        entries[id] = entry
    }

    /// The panel's input for `id`; nil only when the account was never asked about.
    func panelInput(_ id: String) -> BrimPanelModel.ClaudeResets {
        guard let entry = entries[id] else { return .init(state: .unknown, problem: .notReadYet) }
        guard let reading = entry.reading else {
            return .init(state: .unknown, problem: entry.problem ?? .notReadYet)
        }
        guard reading.eligible else {
            // Not in the program, as far as the server's flags say: not a proven zero.
            return .init(remaining: reading.remaining, resetsAt: reading.resetsAt, checkedAt: entry.checkedAt,
                         promotions: entry.problem == nil ? reading.promotions : [],
                         windowSpend: entry.problem == nil ? reading.windowSpend : [:], credit: reading.credit,
                         state: .unknown, problem: entry.problem ?? .notInProgram)
        }
        // Usable: the server says it can be spent now, the login is at a limit when the grant asks
        // for one, and the reading names the login a claim would be bound to.
        let bound = entry.identity != nil && entry.organizationID != nil
        let grants = reading.grants.map {
            BrimPanelModel.ClaudeResets.Grant(kind: Self.kind($0), left: $0.left, endsAt: $0.endsAt,
                                              usable: bound && $0.usableNow && $0.kind != .other
                                                  && (!$0.useRequiresLimit || reading.atLimit), grantID: $0.id.raw)
        }
        return .init(remaining: reading.remaining, resetsAt: reading.resetsAt, checkedAt: entry.checkedAt,
                     promotions: entry.problem == nil ? reading.promotions : [],
                     windowSpend: entry.problem == nil ? reading.windowSpend : [:], credit: reading.credit,
                     state: .read(grants), problem: entry.problem)
    }

    static func kind(_ grant: ClaudeResetInventory.Grant) -> BrimPanelModel.ResetKind {
        switch grant.kind {
        case .full: .full
        case .fable: .fable
        case .session: .session
        case .weekly: .weekly
        case .other: .other(grant.name)
        }
    }
}
