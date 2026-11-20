import CryptoKit
import Foundation

/// Anthropic Console "Organization credits": the prepaid API balance, this month's spend and the
/// tier limit. Separate from the claude.ai "extra usage" credit (BrimPanelModel.Credit), which
/// belongs to a subscription account. A Console organization is not tied to one account.
///
/// This file is the pure half: the model, the tolerant parsing of the Console's own JSON, the
/// classification of an HTTP answer, and the state a refresh moves to. No network, no cookies:
/// ConsoleCreditsFetch reads, ConsoleCreditsStore holds the state.
///
/// Four situations that must never collapse into one another, least of all into zero:
/// - not connected: the user never signed in to the Console inside UsageBar (nothing was sent);
/// - needs reconnect: the Console answered 401/403 with JSON, the session is gone or expired;
/// - read failed: network error, Cloudflare/HTML, 5xx, a body that is not the expected shape.
///   The last good reading stays on screen, marked stale;
/// - a real zero balance: `balance.credits.amount_minor == 0` in a body that parsed.
enum ConsoleCredits {
    /// One promotional grant ("API credit (Max)"), usually scoped to some products and expiring.
    struct Promo: Equatable, Sendable {
        var name: String?
        /// Hundredths of the currency (minor units), as the Console reports them.
        var remainingMinor: Int
        var expiresAt: Date?
        var products: [String] = []
    }

    /// One organization's prepaid balance, from `/prepaid/credits`.
    struct Prepaid: Equatable, Sendable {
        /// In major units (dollars): `credits.amount_minor / 10^exponent`.
        var balance: Double
        var currency: String
        var promos: [Promo]
        var nextExpiresAt: Date?
    }

    /// One organization as the panel shows it. `spend` and `tierLimit` are optional: those two
    /// endpoints failing must not hide a balance that did read.
    struct Organization: Equatable, Sendable {
        var id: String
        var name: String?
        var prepaid: Prepaid
        /// This month's spend in major units, and when the month rolls over.
        var monthSpend: Double?
        var spendResetsAt: Date?
        /// The tier limit in major units (`enforced_limit_usd` is cents, see `tierLimit(from:)`).
        var tierLimit: Double?

        var currency: String { prepaid.currency }

        /// The promo that runs out first, for the "expires Dec 11" suffix.
        var soonestExpiringPromo: Promo? {
            prepaid.promos.filter { $0.expiresAt != nil }.min { $0.expiresAt! < $1.expiresAt! }
        }
    }

    /// What one successful refresh read: every organization that has prepaid credits.
    struct Snapshot: Equatable, Sendable {
        var organizations: [Organization]
        /// The organization the panel leads with: the largest balance.
        var primary: Organization? { organizations.max { $0.prepaid.balance < $1.prepaid.balance } }
    }

    /// What one refresh attempt found.
    enum Outcome: Equatable, Sendable {
        case read(Snapshot)
        /// Signed in, but no organization answered `/prepaid/credits` (403/404 on every one): a
        /// Console login with no prepaid balance, or a role that cannot see billing.
        case noPrepaid
        case notConnected
        case needsReconnect
        /// Nothing usable came back. `status` is the HTTP status when there was one.
        case failed(status: Int?)
    }

    /// What the panel and Settings read.
    enum State: Equatable, Sendable {
        case notConnected
        case needsReconnect
        case noPrepaid
        /// A reading, `stale` when the latest attempt failed and this is the last good one.
        case ready(Snapshot, readAt: Date, stale: Bool)
        /// The first attempt failed and there is no earlier reading.
        case unavailable

        var snapshot: Snapshot? {
            if case .ready(let snapshot, _, _) = self { return snapshot }
            return nil
        }
    }

    /// The state after an attempt. A failed read keeps the last good value (stale); it is never
    /// turned into zero or into "not connected". Reconnect and disconnect states drop the old
    /// reading: showing a balance for a session that is gone would be a lie by age.
    static func next(_ state: State, _ outcome: Outcome, now: Date) -> State {
        switch outcome {
        case .read(let snapshot): return .ready(snapshot, readAt: now, stale: false)
        case .noPrepaid: return .noPrepaid
        case .notConnected: return .notConnected
        case .needsReconnect: return .needsReconnect
        case .failed:
            if case .ready(let snapshot, let readAt, _) = state { return .ready(snapshot, readAt: readAt, stale: true) }
            return state == .notConnected || state == .needsReconnect || state == .noPrepaid ? state : .unavailable
        }
    }

    // MARK: HTTP answers

    /// What an HTTP answer means before any field is read.
    enum Answer: Equatable {
        /// 200 with a JSON body.
        case json(Data)
        /// 401, or 403 with a JSON body (the Console's "not allowed"): the session cannot do this.
        case unauthorized(status: Int)
        /// 404, or 403 on one organization's endpoint: this organization has no such thing.
        /// Only the per-organization calls give it a meaning; see `forbiddenIsAbsent`.
        case absent(status: Int)
        /// Cloudflare or any HTML page, a redirect that is not to the login page, 5xx, 429, a 200
        /// that is not JSON. A failed read, never a reconnect and never zero.
        case unreadable(status: Int?)
        /// A redirect to the login page: the session is gone.
        case loginRedirect
    }

    static func classify(status: Int?, body: Data, location: String? = nil, forbiddenIsAbsent: Bool = false) -> Answer {
        guard let status else { return .unreadable(status: nil) }
        if (300..<400).contains(status) {
            return location?.contains("/login") == true ? .loginRedirect : .unreadable(status: status)
        }
        let isHTML = looksLikeHTML(body)
        switch status {
        case 200:
            return isHTML || !looksLikeJSON(body) ? .unreadable(status: status) : .json(body)
        case 401:
            // Cloudflare does not answer 401; a 401 means the Console refused the session.
            return .unauthorized(status: status)
        case 403:
            // 403 + HTML is the Cloudflare challenge: the request was blocked, not the session.
            if isHTML || !looksLikeJSON(body) { return .unreadable(status: status) }
            return forbiddenIsAbsent ? .absent(status: status) : .unauthorized(status: status)
        case 404:
            return isHTML ? .unreadable(status: status) : .absent(status: status)
        default:
            return .unreadable(status: status)
        }
    }

    static func looksLikeHTML(_ body: Data) -> Bool {
        let head = body.prefix(512)
        guard let text = String(data: head, encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("<") || trimmed.contains("<html") || trimmed.contains("<!doctype")
    }

    static func looksLikeJSON(_ body: Data) -> Bool {
        guard let first = body.first(where: { !" \n\r\t".utf8.contains($0) }) else { return false }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }

    // MARK: Parsing

    /// An organization from `/api/organizations`.
    struct OrganizationRef: Equatable, Sendable {
        var id: String
        var name: String?
        /// True when the organization's capabilities or billing type say "API" / "console".
        var looksLikeAPI: Bool
    }

    /// The organization list: a bare array, or an object holding one under a common key. Nil when
    /// the body has none of those shapes (a failed read, not "no organizations"). Entries with no
    /// id are skipped. API-looking organizations come first, so the fetch asks them first.
    static func organizations(from body: Data) -> [OrganizationRef]? {
        guard let root = try? JSONSerialization.jsonObject(with: body) else { return nil }
        var list: [Any]?
        if let array = root as? [Any] {
            list = array
        } else if let object = root as? [String: Any] {
            for key in ["organizations", "data", "items", "results"] {
                if let array = object[key] as? [Any] { list = array; break }
            }
        }
        guard let list else { return nil }
        let refs: [OrganizationRef] = list.compactMap { item in
            guard let object = item as? [String: Any] else { return nil }
            guard let id = (object["uuid"] as? String) ?? (object["id"] as? String), !id.isEmpty else { return nil }
            let capabilities = (object["capabilities"] as? [Any])?.compactMap { $0 as? String } ?? []
            let billing = (object["billing_type"] as? String) ?? ""
            let apiWords = ["api", "console", "prepaid", "api_individual"]
            let looks = capabilities.contains { cap in apiWords.contains { cap.lowercased().contains($0) } }
                || apiWords.contains { billing.lowercased().contains($0) }
            return OrganizationRef(id: id, name: object["name"] as? String, looksLikeAPI: looks)
        }
        return refs.filter(\.looksLikeAPI) + refs.filter { !$0.looksLikeAPI }
    }

    /// `/prepaid/credits`. The balance is `balance.credits.amount_minor / 10^exponent`; without
    /// that, `amount / 100`. Nil when neither is there: an unreadable body is not a zero balance.
    static func prepaid(from body: Data) -> Prepaid? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        let currency = (root["currency"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "USD"
        var balance: Double?
        if let balanceObject = root["balance"] as? [String: Any],
           let credits = balanceObject["credits"] as? [String: Any],
           let minor = number(credits["amount_minor"]) {
            let exponent = number(credits["exponent"]).map { Int($0) } ?? 2
            if (0...6).contains(exponent) { balance = minor / pow(10, Double(exponent)) }
        }
        if balance == nil, let amount = number(root["amount"]) { balance = amount / 100 }
        guard let balance, balance.isFinite else { return nil }

        let promos: [Promo] = (root["promo_tranches"] as? [Any] ?? []).compactMap { item in
            guard let object = item as? [String: Any],
                  let remaining = number(object["remaining_amount_minor_units"]) else { return nil }
            let scope = object["scope"] as? [String: Any]
            let products = (scope?["applies_to"] as? [Any] ?? []).compactMap { ($0 as? [String: Any])?["product"] as? String }
            return Promo(name: object["name"] as? String, remainingMinor: Int(remaining),
                         expiresAt: date(object["expires_at"]), products: products)
        }
        return Prepaid(balance: balance, currency: currency, promos: promos, nextExpiresAt: date(root["next_expires_at"]))
    }

    /// `/current_spend`: `amount` in minor units (cents). UNVERIFIED against a non-zero month: the
    /// field sat at 0 when read, so the unit is assumed to match `/prepaid/credits` (hundredths).
    static func currentSpend(from body: Data) -> (spend: Double, resetsAt: Date?)? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let amount = number(root["amount"]), amount.isFinite else { return nil }
        return (amount / 100, date(root["resets_at"]))
    }

    /// `/spend_limits`: `enforced_limit_usd` is CENTS despite the name (`50000` while the Console
    /// shows a "$500 tier limit"), so it is divided by 100. Nil when absent.
    static func tierLimit(from body: Data) -> Double? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let cents = number(root["enforced_limit_usd"]), cents.isFinite, cents >= 0 else { return nil }
        return cents / 100
    }

    // MARK: Values

    /// A JSON number as Double. Strings and booleans are not numbers here: a bool must not read
    /// as 1 dollar.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    /// ISO 8601 with or without fractional seconds ("2026-12-11T00:00:00Z", "...00.000000Z").
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        // Fractional digits beyond milliseconds ("...00.123456Z"): drop them.
        if let range = text.range(of: #"\.\d+"#, options: .regularExpression) {
            return plain.date(from: text.replacingCharacters(in: range, with: ""))
        }
        return nil
    }
}

// MARK: Per account

/// One Console connection per Claude account: each account has its own web data store, its own
/// state and its own sign-in. This is the pure half of that: the deterministic store id, the
/// comparison of the Console identity with the Claude account's email, the one-time assignment of
/// the old single store to an account, and the text of the two panel rows.
enum ConsoleAccounts {
    /// The default `~/.claude` account's id, the fallback owner of the old single store.
    static let defaultAccountID = "claude:.claude"

    /// The data store identifier of an account: the first 16 bytes of SHA-256 over a fixed prefix
    /// and the account id, with the version-5 and variant bits set so it reads as a UUID. The same
    /// account always gets the same store; two accounts never share one.
    static func storeID(for accountID: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(("usagebar.console-store.v1:" + accountID).utf8)).prefix(16))
        var bytes = digest
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// What reading the Console's own identity found.
    enum IdentityRead: Equatable, Sendable {
        case email(String)
        /// The Console answered but named nobody (or refused the session).
        case none
        /// No usable answer: network error, Cloudflare, 5xx.
        case unreadable
    }

    /// The signed-in user's email from an account endpoint (`/api/bootstrap`, `/api/account`).
    /// Tolerant: `account.email_address`, `account.email`, then the same two at the top level or
    /// under `user`. Nil when none is a non-empty string.
    static func email(from body: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        let holders: [[String: Any]?] = [root["account"] as? [String: Any], root["user"] as? [String: Any], root]
        for holder in holders {
            guard let holder else { continue }
            for key in ["email_address", "email"] {
                if let value = holder[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.contains("@") { return trimmed }
                }
            }
        }
        return nil
    }

    /// Case-insensitive equality of two emails. Nil when either is missing: unknown is not a mismatch.
    static func emailsMatch(_ lhs: String?, _ rhs: String?) -> Bool? {
        guard let lhs = lhs?.trimmingCharacters(in: .whitespaces), !lhs.isEmpty,
              let rhs = rhs?.trimmingCharacters(in: .whitespaces), !rhs.isEmpty else { return nil }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    /// Whether the card shows "Different Console account": only when both emails are known and differ.
    static func isMismatch(console read: IdentityRead, claudeEmail: String?) -> Bool {
        guard case .email(let consoleEmail) = read else { return false }
        return emailsMatch(consoleEmail, claudeEmail) == false
    }

    struct Candidate: Equatable, Sendable {
        var id: String
        var email: String?
    }

    enum LegacyDecision: Equatable, Sendable {
        /// Keep the old store as this account's store.
        case assign(accountID: String)
        /// The identity could not be read yet: try again on the next refresh.
        case retry
    }

    static let legacyMaxAttempts = 3

    /// Which account owns the old single store: the one whose email matches the Console identity;
    /// failing that (no match, no identity) the default account, else the first. An unreadable
    /// answer waits for the next refresh, `legacyMaxAttempts` times, then falls back as well.
    static func legacyOwner(read: IdentityRead, accounts: [Candidate], attempts: Int) -> LegacyDecision? {
        guard !accounts.isEmpty else { return nil }
        let fallback = (accounts.first { $0.id == defaultAccountID } ?? accounts[0]).id
        switch read {
        case .email(let consoleEmail):
            let match = accounts.first { emailsMatch(consoleEmail, $0.email) == true }
            return .assign(accountID: match?.id ?? fallback)
        case .none:
            return .assign(accountID: fallback)
        case .unreadable:
            return attempts + 1 >= legacyMaxAttempts ? .assign(accountID: fallback) : .retry
        }
    }

    // MARK: Row text

    /// What a card shows for one account.
    struct Display: Equatable {
        enum Action: Equatable { case none, connect, reconnect }
        var action: Action = .none
        /// "$100,00 · 11 Dec", or "$0" with a connection but no prepaid credit, or "–" when unread.
        var balance: String?
        /// "$0 / $500"; nil when the Console reported no spend. Shown in the tooltip.
        var month: String?
        /// How much of this month's tier limit is left, 0...100, for the row's bar. Nil without
        /// both a spend and a limit.
        var remainingPercent: Double?
        var stale = false
        var mismatch = false
        /// The tooltip: organization name and the balance line.
        var help: String?
    }

    static func display(state: ConsoleCredits.State, mismatch: Bool, locale: Locale,
                        money: (Double, String) -> String) -> Display {
        switch state {
        case .notConnected:
            return Display(action: .connect)
        case .needsReconnect:
            return Display(action: .reconnect, mismatch: mismatch)
        case .noPrepaid:
            return Display(balance: compactMoney(0, currency: "USD", locale: locale), mismatch: mismatch)
        case .unavailable:
            return Display(balance: "–", stale: true, mismatch: mismatch)
        case .ready(let snapshot, _, let stale):
            guard let org = snapshot.primary else { return Display(balance: "–", stale: true, mismatch: mismatch) }
            let expiry = (org.soonestExpiringPromo?.expiresAt ?? org.prepaid.nextExpiresAt).map { expiryText($0, locale: locale) }
            let balance = [money(org.prepaid.balance, org.currency), expiry].compactMap { $0 }.joined(separator: " · ")
            var display = Display(balance: balance, stale: stale, mismatch: mismatch)
            display.month = org.monthSpend.map {
                monthText(spend: $0, limit: org.tierLimit, currency: org.currency, locale: locale)
            }
            if let spend = org.monthSpend, let limit = org.tierLimit, limit > 0 {
                display.remainingPercent = max(0, min(100, (limit - spend) / limit * 100))
            }
            display.help = [org.name, balance, display.month].compactMap { $0 }.joined(separator: " · ")
            return display
        }
    }

    /// "11 Dec" / "11 Ara": day and short month in the app's language.
    static func expiryText(_ date: Date, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    /// "$0 / $500": whole amounts without decimals, others with two.
    static func monthText(spend: Double, limit: Double?, currency: String, locale: Locale) -> String {
        guard let limit else { return compactMoney(spend, currency: currency, locale: locale) }
        return compactMoney(spend, currency: currency, locale: locale) + " / " + compactMoney(limit, currency: currency, locale: locale)
    }

    static func compactMoney(_ amount: Double, currency: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let whole = amount.rounded() == amount
        formatter.minimumFractionDigits = whole ? 0 : 2
        formatter.maximumFractionDigits = whole ? 0 : 2
        return (currency == "USD" ? "$" : currency + " ") + (formatter.string(from: NSNumber(value: amount)) ?? String(amount))
    }
}
