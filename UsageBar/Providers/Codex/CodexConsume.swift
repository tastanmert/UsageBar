import Foundation

/// The store must capture these fields when asking for confirmation. `account/read` names the
/// login by email, plan and login type (codex-cli 0.146.0, see `CodexIdentity`); the account, user
/// and workspace ids are kept too when an app server sends them. A read without an email is never
/// a match. Every field is compared, so a plan, type or workspace change reads as another login.
/// This alone cannot tell two workspaces of one email apart: the consume also requires the
/// approved credit to be listed "available" in the same session right before the write.
struct CodexAccountIdentity: Codable, Equatable, Sendable {
    let home: String
    let email: String
    let planType: String?
    let type: String?
    let accountID: String?
    let userID: String?
    let workspaceID: String?

    init(home: String, email: String, planType: String?, type: String?,
         accountID: String? = nil, userID: String? = nil, workspaceID: String? = nil) {
        self.home = home
        self.email = email
        self.planType = planType
        self.type = type
        self.accountID = accountID
        self.userID = userID
        self.workspaceID = workspaceID
    }

    /// The identity an `account/read` answer names for this home; nil for an error answer or a
    /// login with no email. Empty optional fields count as absent.
    init?(home: String, accountRead data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["error"] == nil, let result = root["result"] as? [String: Any],
              let account = result["account"] as? [String: Any],
              let email = account["email"] as? String, !email.isEmpty else { return nil }
        func field(_ key: String) -> String? { (account[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        self.init(home: home, email: email, planType: field("planType"), type: field("type"),
                  accountID: field("id"), userID: field("userId"), workspaceID: field("workspaceId"))
    }

    func matches(_ data: Data) -> Bool {
        guard !email.isEmpty, let read = CodexAccountIdentity(home: home, accountRead: data) else { return false }
        return read == self
    }
}

/// Who each Codex home was signed in as at its latest read, so the confirm card can bind the
/// consent to the account on screen (BrimCodexApproval). Every read replaces the entry, a read
/// that named no email included (nil): the card then refuses instead of binding to an older answer.
final class CodexIdentityBook: @unchecked Sendable {
    static let shared = CodexIdentityBook()
    private let lock = NSLock()
    private var byHome: [String: CodexAccountIdentity] = [:]

    init() {}

    func record(home: String, accountRead: Data?) {
        let identity = accountRead.flatMap { CodexAccountIdentity(home: home, accountRead: $0) }
        lock.lock(); defer { lock.unlock() }
        byHome[home] = identity
    }

    func identity(home: String) -> CodexAccountIdentity? {
        lock.lock(); defer { lock.unlock() }
        return byHome[home]
    }
}

/// Persist before sending. A dropped response survives app relaunch and can only be settled by
/// an explicit terminal status for that same credit under the same account identity.
final class CodexConsumeCoordinator: @unchecked Sendable {
    struct Attempt: Codable, Equatable {
        let identity: CodexAccountIdentity
        let creditID: String
        let idempotencyKey: String
        var settled: Bool = false
        /// When the attempt was written; nil for one saved before this was recorded.
        var startedAt: Date? = nil
    }
    /// How old an open attempt of an earlier login must be before a new login may drop it.
    static let staleAfter: TimeInterval = 24 * 60 * 60
    static let shared = CodexConsumeCoordinator(
        load: { UserDefaults.standard.data(forKey: "app.usagebar.codexPendingConsumes") },
        save: { UserDefaults.standard.set($0, forKey: "app.usagebar.codexPendingConsumes") })
    private let lock = NSLock()
    private var attempts: [String: Attempt]
    private let save: (Data) -> Void
    private let now: () -> Date

    init(load: () -> Data? = { nil }, save: @escaping (Data) -> Void = { _ in },
         now: @escaping () -> Date = Date.init) {
        attempts = load().flatMap { try? JSONDecoder().decode([String: Attempt].self, from: $0) } ?? [:]
        self.save = save
        self.now = now
    }

    /// An open attempt left by another login than `current`: the one the user may clear by hand
    /// (Settings > Accounts). Nil when there is none, or the current login is unknown.
    func strandedAttempt(home: String, current: CodexAccountIdentity?) -> Attempt? {
        lock.lock(); defer { lock.unlock() }
        guard let current, let open = attempts[home], !open.settled, open.identity != current else { return nil }
        return open
    }

    /// Forgets UsageBar's own record of an open attempt left by another login. Sends nothing to
    /// the provider; whether that request went through stays unknown. False when there is no such
    /// attempt (it settled, or the same login is signed in again).
    @discardableResult
    func clearStranded(home: String, current: CodexAccountIdentity?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let current, let open = attempts[home], !open.settled, open.identity != current else { return false }
        attempts[home] = nil
        persist()
        return true
    }

    func pending(home: String) -> Attempt? {
        lock.lock(); defer { lock.unlock() }
        return attempts[home]
    }

    func consume(expected: CodexAccountIdentity, creditID: String,
                 isCurrent: () -> Bool,
                 request: (String, [String: String]) -> Data?) -> CodexAppServerClient.ConsumeOutcome {
        // A second caller cannot overtake the read which settles the first caller's attempt.
        lock.lock(); defer { lock.unlock() }
        guard isCurrent(), !creditID.isEmpty else { return .unavailable }
        guard let identity = request("account/read", [:]), expected.matches(identity) else {
            return .identityChanged
        }
        if let previous = attempts[expected.home], !previous.settled, previous.identity != expected,
           let started = previous.startedAt, now().timeIntervalSince(started) >= Self.staleAfter {
            // Another login's attempt, open for a day: it cannot be settled under this login, so
            // only UsageBar's record of it is dropped. Nothing is sent for it.
            attempts[expected.home] = nil
            persist()
        }
        if let previous = attempts[expected.home], !previous.settled {
            // The open attempt is settled first, whatever credit this caller asked for: by a
            // completed re-read naming it spent, or by re-sending the SAME request (same credit,
            // same idempotency key) when the re-read shows it still available. Anything else keeps
            // the account locked.
            guard previous.identity == expected else { return .identityChanged }
            guard let data = request("account/rateLimits/read", [:]),
                  let status = Self.creditStatus(previous.creditID, in: data) else { return .uncertain }
            if Self.spent.contains(status) { return settle(previous, .redeemed) }
            guard status == "available", isCurrent() else { return .uncertain }
            return send(previous, request: request)
        }
        if let previous = attempts[expected.home], previous.identity == expected,
           previous.creditID == creditID { return .resolved(.alreadyUsed) }
        guard let data = request("account/rateLimits/read", [:]),
              Self.creditStatus(creditID, in: data) == "available" else { return .unavailable }
        // Re-read immediately before the write, after the inventory round trip.
        guard let identity = request("account/read", [:]), expected.matches(identity) else {
            return .identityChanged
        }
        guard isCurrent() else { return .unavailable }
        let attempt = Attempt(identity: expected, creditID: creditID, idempotencyKey: UUID().uuidString,
                              startedAt: now())
        attempts[expected.home] = attempt
        persist()
        guard isCurrent() else {
            attempts[expected.home] = nil
            persist()
            return .unavailable
        }
        return send(attempt, request: request)
    }

    /// One consume on the wire for a persisted attempt. Only an explicit success settles it; a
    /// dropped answer, a vendor error or an unknown token leaves it open (uncertain).
    private func send(_ attempt: Attempt,
                      request: (String, [String: String]) -> Data?) -> CodexAppServerClient.ConsumeOutcome {
        guard let response = request("account/rateLimitResetCredit/consume",
                                     ["creditId": attempt.creditID, "idempotencyKey": attempt.idempotencyKey]),
              let root = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              root["error"] == nil,
              let result = root["result"] as? [String: Any],
              let token = (result["outcome"] ?? result["status"]) as? String else { return .uncertain }
        let outcome = CodexAppServerClient.classifyRedeem(token)
        switch outcome {
        case .redeemed, .alreadyUsed: return settle(attempt, outcome)
        case .noCredit, .failed: return .uncertain
        }
    }

    private func settle(_ attempt: Attempt, _ outcome: CodexAppServerClient.RedeemOutcome)
        -> CodexAppServerClient.ConsumeOutcome {
        var settled = attempt
        settled.settled = true
        attempts[attempt.identity.home] = settled
        persist()
        return .resolved(outcome)
    }

    private static let spent: Set<String> = ["consumed", "redeemed", "used"]

    private func persist() {
        if let data = try? JSONEncoder().encode(attempts) { save(data) }
    }
    private static func creditStatus(_ id: String, in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["error"] == nil, let result = root["result"] as? [String: Any],
              let bank = result["rateLimitResetCredits"] as? [String: Any],
              let credits = bank["credits"] as? [[String: Any]] else { return nil }
        return credits.first { $0["id"] as? String == id }?["status"] as? String
    }
}
