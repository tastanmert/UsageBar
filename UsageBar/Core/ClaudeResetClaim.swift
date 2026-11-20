import Foundation
import CoreFoundation

/// One explicit, confirmation-gated Claude Code reset claim, taken from the
/// `mert/feat/claude-reset-inventory` branch (HEAD 2e02e6a0). The caller must obtain confirmation
/// before setting `confirmed`; tests inject transport and never use the live default.
///
/// A REQUEST WHOSE ANSWER IS UNKNOWN IS NOT SENT AGAIN BLIND. A dropped connection, a 5xx or an
/// unreadable 2xx is `.uncertain`: the request id is kept so a later claim of the same grant is the
/// same request to the server (idempotent), and the caller re-reads the inventory first, which is
/// what says whether the reset went through (BrimClaudeClaim.afterUncertain).
struct ClaudeResetClaim {
    enum Result: String, Equatable {
        case reset, alreadyUsed = "already_used", notLimited = "not_limited", cooldown
        case ineligible, unavailable
    }

    enum Outcome: Equatable {
        case cancelled
        /// Nothing sent: the login's token has expired or runs out within
        /// `ClaudeResetInventoryFetch.expiryMargin`. It is never refreshed here.
        case loginExpiring
        case result(Result, resetsLeft: Int?, cooldownUntil: Date?)
        case rateLimited, authError, error, uncertain
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/organizations")!
    private static let organizationPattern = try! NSRegularExpression(pattern: "^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$")
    private static let grantPattern = try! NSRegularExpression(pattern: "^[a-z0-9_-]{1,40}$")
    private static let requestPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{1,64}$")

    let organizationID: String
    let credential: ClaudeResetInventoryFetch.Credential
    let version: String
    private var requestIDs: [String: String] = [:]
    private var pendingGrantID: String?
    private(set) var pendingRequestID: String?

    struct Identity: Equatable {
        let accountID: String
        let organizationID: String
    }

    /// Non-secret account metadata; called only on a background task, never from a View body.
    static func identity(configHome: String) -> Identity? {
        let file = claudeStateFile(forConfigDir: URL(fileURLWithPath: configHome, isDirectory: true))
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any],
              let id = account["organizationUuid"] as? String,
              matches(id, organizationPattern),
              let user = account["accountUuid"] as? String, !user.isEmpty else { return nil }
        return Identity(accountID: user, organizationID: id)
    }

    struct Context {
        let identity: Identity
        let credential: ClaudeResetInventoryFetch.Credential
    }

    /// The context read's answer: a usable one, a token too close to its end (nothing is sent and
    /// nothing refreshed), or anything else that refuses (no login, a login changing meanwhile).
    enum ContextRead {
        case ready(Context)
        case loginExpiring
        case unavailable
    }

    /// A credential read may suspend while another process replaces the login. Bind the secret to
    /// stable metadata on both sides of the read; a changing or incomplete profile is a refusal.
    static func readContext(home: String, defaultHome: String, now: Date,
                            identityRead: (String) -> Identity?,
                            keychainRead: (String) -> ClaudeLoginExpiry.Source,
                            fileRead: (URL) -> Data?) -> ContextRead {
        guard let before = identityRead(home) else { return .unavailable }
        switch ClaudeResetInventoryFetch.readCredential(home: home, defaultHome: defaultHome, now: now,
                                                         keychainRead: keychainRead, fileRead: fileRead) {
        case .none(.expiring): return .loginExpiring
        case .none: return .unavailable
        case .usable(let credential):
            guard identityRead(home) == before else { return .unavailable }
            return .ready(Context(identity: before, credential: credential))
        }
    }

    init(organizationID: String, credential: ClaudeResetInventoryFetch.Credential, version: String,
         pendingRequestID: String? = nil) {
        self.organizationID = organizationID
        self.credential = credential
        self.version = version
        self.pendingRequestID = pendingRequestID
    }

    /// A claim built and ready to go out: the request and the id it carries.
    struct Prepared {
        let request: URLRequest
        let grantID: String
        let requestID: String
    }

    mutating func perform(grantID: String, confirmed: Bool,
                          transport: ClaudeResetInventoryFetch.Transport = ClaudeResetClaim.liveTransport) async -> Outcome {
        guard confirmed else { return .cancelled }
        guard let prepared = prepare(grantID: grantID) else { return .error }
        return await send(prepared, transport: transport)
    }

    /// Builds the request without sending it or keeping its id, so the caller can take its last
    /// look at the consent between this and `send` (BrimClaudeClaimRunner). Nil for an id or
    /// grant that is not well formed.
    func prepare(grantID: String) -> Prepared? {
        guard Self.matches(organizationID, Self.organizationPattern),
              Self.matches(grantID, Self.grantPattern),
              let url = URL(string: "\(Self.endpoint.absoluteString)/\(organizationID)/reset_rate_limits") else {
            return nil
        }
        let pendingForGrant = pendingGrantID == nil || pendingGrantID == grantID ? pendingRequestID : nil
        let requestID = requestIDs[grantID] ?? pendingForGrant ?? UUID().uuidString
        guard Self.matches(requestID, Self.requestPattern) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpMethod = "POST"
        ClaudeResetInventoryFetch.authorize(&request, credential, version: version)
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "program": "cedar_ember", "grant_id": grantID, "request_id": requestID
        ], options: [.sortedKeys])
        guard request.httpBody != nil else { return nil }
        return Prepared(request: request, grantID: grantID, requestID: requestID)
    }

    /// Sends a prepared claim: the one POST. Its id is kept from here on, whatever the answer.
    mutating func send(_ prepared: Prepared,
                       transport: ClaudeResetInventoryFetch.Transport = ClaudeResetClaim.liveTransport) async -> Outcome {
        let grantID = prepared.grantID, requestID = prepared.requestID, request = prepared.request
        pendingRequestID = requestID
        pendingGrantID = grantID
        let body: Data
        let response: URLResponse
        do {
            (body, response) = try await transport(request)
        } catch {
            requestIDs[grantID] = requestID
            return .uncertain
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            requestIDs[grantID] = requestID
            return .uncertain
        }
        if status == 429 { requestIDs[grantID] = nil; pendingRequestID = nil; return .rateLimited }
        if status == 401 || status == 403 { requestIDs[grantID] = nil; pendingRequestID = nil; return .authError }
        guard (200..<300).contains(status),
              let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let rawResult = json["result"] as? String else {
            if (200..<300).contains(status) || status >= 500 { requestIDs[grantID] = requestID }
            else { requestIDs[grantID] = nil; pendingRequestID = nil }
            return (200..<300).contains(status) || status >= 500 ? .uncertain : .error
        }
        let result = Result(rawValue: rawResult) ?? .unavailable
        if result == .unavailable { requestIDs[grantID] = requestID }
        else { requestIDs[grantID] = nil; pendingRequestID = nil }
        let left = (json["resets_left"] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue }
        let cooldown = (json["cooldown_until"] as? String).flatMap(ClaudeResetInventory.date)
        return .result(result, resetsLeft: left, cooldownUntil: cooldown)
    }

    private static func matches(_ value: String, _ regex: NSRegularExpression) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range)?.range == range
    }

    static let liveTransport: ClaudeResetInventoryFetch.Transport = { request in
        try await ClaudeResetInventoryFetch.liveTransport(request)
    }
}
