import Foundation

/// The per-account limit alerts: a window crossing the user's threshold, the same window running
/// out, and a weekly window about to reset with most of it unused. Foundation only, so the test
/// harness compiles it standalone (tests/run-limitalert-tests.sh); LimitAlertNotifier is the glue.
///
/// Every alert fires at most once per window per reset cycle. A cycle is named by the window's
/// reported reset time, compared with DryPoolLogic's tolerance (the same jitter, the same rule).

/// What one account looks like to the alerts: only the fields they read, so the logic does not
/// depend on the provider model.
struct LimitAlertWindow: Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case session, weekly, weeklyModel }
    var accountID: String
    var accountLabel: String
    var kind: Kind
    /// The model a model-scoped weekly window is for ("Fable"); nil for the other two.
    var modelName: String?
    var usedPercent: Double
    var resetsAt: Date?

    /// One key per window of one account, stable across rounds.
    var key: String { "\(accountID)|\(kind.rawValue)|\(modelName ?? "")" }
}

struct LimitAlert: Equatable, Sendable {
    enum Reason: String, Codable, Sendable {
        /// Used reached the user's threshold.
        case threshold
        /// Used reached 100%.
        case exhausted
        /// A weekly window resets soon with at least `unusedFraction` of it left.
        case unused
    }
    var window: LimitAlertWindow
    var reason: Reason
    var threshold: Int
}

/// The settings the alerts run under.
struct LimitAlertSettings: Equatable, Sendable {
    /// 0 turns the threshold and exhausted alerts off.
    var threshold: Int = 90
    var unusedWeekly = true
}

/// What has already been said, per window key.
struct LimitAlertState: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var resetKey: String?
        var fired: [LimitAlert.Reason] = []
    }
    var entries: [String: Entry] = [:]
}

enum LimitAlertLogic {
    /// The weekly window counts as about to reset inside this many hours.
    static let unusedLead: TimeInterval = 24 * 3_600
    /// And as mostly unused with at least this much of it left.
    static let unusedFraction = 0.5
    /// Used falling this far under the threshold within one cycle re-arms it (a reset the source
    /// reported without a time, or a correction).
    static let rearmGap = 10.0

    static let thresholdChoices = [0, 75, 90, 95]

    /// Fold one round into the state and return the alerts to post, at most one per window (the
    /// most severe). Windows absent from this round keep their entry, so an account whose read
    /// failed once does not re-announce when it comes back.
    static func advance(state: LimitAlertState, windows: [LimitAlertWindow],
                        settings: LimitAlertSettings, now: Date) -> (LimitAlertState, [LimitAlert]) {
        var next = state
        var alerts: [LimitAlert] = []
        for window in windows {
            let key = DryPoolLogic.resetKey(window.resetsAt)
            var entry = next.entries[window.key] ?? .init(resetKey: key)
            if !DryPoolLogic.namesSameCycle(entry.resetKey, key) {
                entry = .init(resetKey: key)
            }
            if settings.threshold > 0, window.usedPercent < Double(settings.threshold) - rearmGap {
                entry.fired.removeAll { $0 == .threshold || $0 == .exhausted }
            }
            if let reason = due(window, settings: settings, fired: entry.fired, now: now) {
                entry.fired.append(reason)
                // Reaching 100% in one step says the threshold too; it is not said again after.
                if reason == .exhausted, !entry.fired.contains(.threshold) { entry.fired.append(.threshold) }
                alerts.append(LimitAlert(window: window, reason: reason, threshold: settings.threshold))
            }
            next.entries[window.key] = entry
        }
        return (next, alerts)
    }

    private static func due(_ window: LimitAlertWindow, settings: LimitAlertSettings,
                            fired: [LimitAlert.Reason], now: Date) -> LimitAlert.Reason? {
        if settings.threshold > 0 {
            if window.usedPercent >= 100, !fired.contains(.exhausted) { return .exhausted }
            if window.usedPercent >= Double(settings.threshold), window.usedPercent < 100,
               !fired.contains(.threshold) { return .threshold }
        }
        if settings.unusedWeekly, window.kind == .weekly, !fired.contains(.unused),
           let reset = window.resetsAt, reset > now, reset.timeIntervalSince(now) <= unusedLead,
           100 - window.usedPercent >= unusedFraction * 100 {
            return .unused
        }
        return nil
    }

    /// Drop the entries of accounts that are gone (removed), keeping the state small. Keyed by
    /// account rather than by window, so an account whose read failed this round keeps its memory.
    static func prune(_ state: LimitAlertState, accountIDs: Set<String>) -> LimitAlertState {
        var next = state
        next.entries = next.entries.filter { entry in
            accountIDs.contains(String(entry.key.prefix { $0 != "|" }))
        }
        return next
    }
}
