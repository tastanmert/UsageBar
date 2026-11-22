import Foundation

/// When an account's paid plan renews, and whether monthly or yearly: Settings > Accounts' second
/// line under the plan. Pure: parsing and date arithmetic only, no I/O (SubscriptionFetch reads).
///
/// Sources, measured 2026-11-22:
/// - Codex: `GET chatgpt.com/backend-api/subscriptions?account_id=` answers `billing_period`
///   ("monthly"/"yearly"), `will_renew`, `active_until`, and `entitlement.renews_at` /
///   `entitlement.cancels_at`.
/// - Claude: `GET claude.ai/api/organizations/{org}/subscription_details` with a claude.ai web
///   session (the OAuth token is refused, 403 `oauth_token_not_accepted`). Field names come from
///   open-source clients (`next_charge_date`, `billing_interval`, `status`; some read
///   `next_charge_at`, `plan_ending_at`), so every one of them is optional here.
struct SubscriptionRenewal: Codable, Equatable, Sendable {
    enum Interval: String, Codable, Sendable { case monthly, yearly }

    /// The next charge as the provider stated it (may lie in the past by the time it is shown).
    var renewsAt: Date?
    var interval: Interval?
    /// False when the plan was cancelled: `endsAt` is then when paid access stops.
    var willRenew: Bool?
    var endsAt: Date?
    /// When the provider last answered.
    var checkedAt: Date

    /// The date to show: the stated renewal moved forward by whole periods until it is in the
    /// future (the provider is asked rarely; a monthly plan renewed on the 8th renews again on the
    /// next 8th). Nil for a cancelled plan, or with no date. Without an interval a past date is
    /// not guessed forward.
    func nextRenewal(now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        guard willRenew != false, var date = renewsAt else { return nil }
        guard date <= now else { return date }
        guard let interval else { return nil }
        let step: DateComponents = interval == .monthly ? DateComponents(month: 1) : DateComponents(year: 1)
        var guardCount = 0
        while date <= now, guardCount < 240, let next = calendar.date(byAdding: step, to: date) {
            date = next
            guardCount += 1
        }
        return date > now ? date : nil
    }

    /// When a cancelled plan's access stops, if it has not already.
    func accessEnds(now: Date) -> Date? {
        guard willRenew == false, let endsAt = endsAt ?? renewsAt, endsAt > now else { return nil }
        return endsAt
    }

    // MARK: Parsing

    /// The ChatGPT subscriptions answer. Nil when it names no date at all (a free login).
    static func chatGPT(_ data: Data, now: Date) -> SubscriptionRenewal? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let entitlement = root["entitlement"] as? [String: Any] ?? [:]
        let renews = date(entitlement["renews_at"]) ?? date(root["active_until"])
        let cancels = date(entitlement["cancels_at"])
        let willRenew = (root["will_renew"] as? Bool)
            ?? ((root["last_active_subscription"] as? [String: Any])?["will_renew"] as? Bool)
            ?? (cancels == nil ? nil : false)
        let interval = Self.interval(root["billing_period"] ?? entitlement["billing_period"])
        guard renews != nil || cancels != nil else { return nil }
        return SubscriptionRenewal(renewsAt: renews, interval: interval, willRenew: willRenew,
                                   endsAt: cancels ?? (willRenew == false ? renews : nil), checkedAt: now)
    }

    /// The claude.ai subscription_details answer. Nil when it names no date at all (an App Store
    /// plan, whose renewal Apple keeps).
    static func claude(_ data: Data, now: Date) -> SubscriptionRenewal? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let renews = date(root["next_charge_date"]) ?? date(root["next_charge_at"])
            ?? date(root["current_period_end"]) ?? date(root["renews_at"])
        let ending = date(root["plan_ending_at"]) ?? date(root["plan_ending_before"]) ?? date(root["cancel_at"])
        let status = (root["status"] as? String)?.lowercased()
        let cancelled = ending != nil || status == "canceled" || status == "cancelled"
            || (root["cancel_at_period_end"] as? Bool) == true
        guard renews != nil || ending != nil else { return nil }
        return SubscriptionRenewal(renewsAt: renews, interval: interval(root["billing_interval"] ?? root["interval"]),
                                   willRenew: cancelled ? false : (renews == nil ? nil : true),
                                   endsAt: ending ?? (cancelled ? renews : nil), checkedAt: now)
    }

    static func interval(_ value: Any?) -> Interval? {
        guard let text = (value as? String)?.lowercased() else { return nil }
        if text.hasPrefix("month") || text == "monthly" { return .monthly }
        if text.hasPrefix("year") || text.hasPrefix("annual") { return .yearly }
        return nil
    }

    /// ISO 8601 with or without fractional seconds, a bare yyyy-MM-dd, or epoch seconds.
    static func date(_ value: Any?) -> Date? {
        if let seconds = value as? Double, seconds > 0 { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int, seconds > 0 { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
        guard let text = value as? String, !text.isEmpty else { return nil }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = full.date(from: text) { return date }
        full.formatOptions = [.withInternetDateTime]
        if let date = full.date(from: text) { return date }
        full.formatOptions = [.withFullDate]
        if let date = full.date(from: text) { return date }
        // Python-style "2026-11-03T09:37:28.897130+00:00": six fractional digits.
        if let dot = text.firstIndex(of: "."), let plus = text[dot...].firstIndex(where: { $0 == "+" || $0 == "Z" || $0 == "-" }) {
            let trimmed = String(text[..<dot]) + String(text[plus...])
            full.formatOptions = [.withInternetDateTime]
            return full.date(from: trimmed)
        }
        return nil
    }
}

/// When to warn about a renewal: a few days before a plan charges again, or before a cancelled
/// plan's paid access stops. Once per account and date; the next period's date is a new warning.
enum RenewalReminder {
    enum Kind: Equatable, Sendable { case renews, ends }

    struct Due: Equatable, Sendable {
        var accountID: String
        var kind: Kind
        var date: Date
        /// The key `sent` remembers this warning by.
        var stamp: Double { date.timeIntervalSince1970.rounded() }
    }

    /// How far ahead the warning comes.
    static let lead: TimeInterval = 3 * 24 * 3600

    /// `sent`: account id to the stamp of the date it was last warned about.
    static func due(_ renewals: [String: SubscriptionRenewal], sent: [String: Double], now: Date) -> [Due] {
        renewals.keys.sorted().compactMap { id in
            guard let renewal = renewals[id] else { return nil }
            let due: Due
            if let ends = renewal.accessEnds(now: now) {
                due = Due(accountID: id, kind: .ends, date: ends)
            } else if let next = renewal.nextRenewal(now: now) {
                due = Due(accountID: id, kind: .renews, date: next)
            } else { return nil }
            guard due.date > now, due.date.timeIntervalSince(now) <= lead, sent[id] != due.stamp else { return nil }
            return due
        }
    }
}

