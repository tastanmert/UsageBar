import Foundation

/// Glue between LimitAlertLogic and macOS notifications. Owns the persisted dedup state and posts
/// what the logic returns after each refresh; the refresh loop drives it, so it keeps no timer.
@MainActor
final class LimitAlertNotifier {
    static let shared = LimitAlertNotifier()

    private let stateKey = "\(BrandPaths.reverseDNS).limitAlert.state"
    /// More alerts than this in one round become a single summary (a first launch with several
    /// accounts already past the threshold, say).
    private let summaryAbove = 2

    private init() {}

    func evaluate(accounts: [AccountUsage]) {
        let settings = AlertPrefs.shared.limitSettings
        let current = loadState()
        var (next, alerts) = LimitAlertLogic.advance(
            state: current, windows: Self.windows(accounts), settings: settings, now: Date())
        next = LimitAlertLogic.prune(next, accountIDs: Set(accounts.map(\.id)))
        if next != current { saveState(next) }
        guard !alerts.isEmpty else { return }
        if alerts.count > summaryAbove {
            post(summary: alerts)
        } else {
            alerts.forEach { post($0) }
        }
    }

    /// The windows worth watching: fresh numbers only. A row held over from an earlier round, or a
    /// login counted under another row, says nothing new.
    static func windows(_ accounts: [AccountUsage]) -> [LimitAlertWindow] {
        accounts.flatMap { account -> [LimitAlertWindow] in
            guard !account.isStale, !account.lastRefreshFailed, account.sameAccountAs == nil else { return [] }
            return account.metrics.compactMap { metric in
                let kind: LimitAlertWindow.Kind
                switch metric.kind {
                case .session: kind = .session
                case .weeklyAll: kind = .weekly
                case .weeklyModel: kind = .weeklyModel
                case .other: return nil
                }
                return LimitAlertWindow(accountID: account.id, accountLabel: account.accountLabel,
                                        kind: kind, modelName: metric.modelName,
                                        usedPercent: metric.usedPercent, resetsAt: metric.resetsAt)
            }
        }
    }

    /// `-UsageBarLimitAlertTest YES`: one sample of each alert, no state touched.
    func postSampleNotifications() {
        let reset = Date().addingTimeInterval(2 * 3_600 + 600)
        let session = LimitAlertWindow(accountID: "sample", accountLabel: "Claude 1", kind: .session,
                                       modelName: nil, usedPercent: 91, resetsAt: reset)
        var weekly = session
        weekly.kind = .weekly
        weekly.usedPercent = 35
        weekly.resetsAt = Date().addingTimeInterval(18 * 3_600)
        post(LimitAlert(window: session, reason: .threshold, threshold: 90))
        post(LimitAlert(window: weekly, reason: .unused, threshold: 90))
    }

    // MARK: Words

    static func windowName(_ window: LimitAlertWindow) -> String {
        switch window.kind {
        case .session: L("5-hour window")
        case .weekly: L("Weekly window")
        case .weeklyModel: String(format: L("%@ weekly window"), window.modelName ?? L("Model"))
        }
    }

    static func title(_ alert: LimitAlert) -> String {
        let window = alert.window
        switch alert.reason {
        case .threshold:
            return String(format: L("%1$@: %2$@ is %3$@ used"), window.accountLabel, windowName(window),
                          percent(window.usedPercent.rounded(.down)))
        case .exhausted:
            return String(format: L("%1$@: %2$@ is used up"), window.accountLabel, windowName(window))
        case .unused:
            return String(format: L("%1$@ has %2$@ of its week unused"), window.accountLabel,
                          percent(100 - window.usedPercent))
        }
    }

    /// "90%", "%90" in Turkish: the panel's own rule (BrimPercent).
    static func percent(_ value: Double) -> String {
        BrimPercent.text(Int(value.rounded()), locale: Locale(identifier: AppLocale.identifier))
    }

    static func body(_ alert: LimitAlert, now: Date = Date()) -> String {
        guard let reset = alert.window.resetsAt, reset > now else { return L("Resets soon.") }
        let when = UsageFormat.noticeCountdown(reset, now: now)
        switch alert.reason {
        case .threshold, .exhausted:
            return String(format: L("Resets in %1$@ (%2$@)."), when.countdown, when.clock)
        case .unused:
            return String(format: L("The weekly window resets in %1$@ (%2$@); what is left then is lost."),
                          when.countdown, when.clock)
        }
    }

    private func post(_ alert: LimitAlert) {
        let title = Self.title(alert)
        let body = Self.body(alert)
        Task { _ = await SystemAlert.post(title: title, body: body) }
    }

    private func post(summary alerts: [LimitAlert]) {
        let title = String(format: L("%d limit alerts"), alerts.count)
        let body = alerts.prefix(4).map(Self.title).joined(separator: "\n")
            + (alerts.count > 4 ? "\n…" : "")
        Task { _ = await SystemAlert.post(title: title, body: body) }
    }

    // MARK: State

    private func loadState() -> LimitAlertState {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(LimitAlertState.self, from: data) else {
            return LimitAlertState()
        }
        return state
    }

    private func saveState(_ state: LimitAlertState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }
}
