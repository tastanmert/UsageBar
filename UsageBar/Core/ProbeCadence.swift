import Darwin
import Foundation
import os

// Which Claude accounts a background refresh round probes, and in what order (2026-09-27, owner
// report: five `claude -p /usage` running at once, each 23-42% CPU and about 340 MB).
//
// WHY ONE PROBE IS EXPENSIVE: in print mode `/usage` also builds its "What's contributing to your
// limits usage?" section by scanning every session transcript written in the last 7 days under the
// account's `projects` directory, and the UsageBar-managed homes usually share that directory through
// a symlink. Measured on CC 2.1.283: 6.4 to 7.5 CPU seconds per probe at load 40, against 0.7 for a
// start that signs in and runs no command. No flag keeps the three windows and drops the scan
// (`--bare` never reads OAuth, `--disable-slash-commands` disables `/usage` itself); what does is an
// empty config home with the Keychain lookup kept on the account (`ClaudeUsageCLI.probeHomeRoot`,
// about 0.6 CPU seconds, 2026-09-27). The cadence below still decides how many probes run and how
// many run at once: five at once cost 56.7 CPU seconds and 1.7 GB
// together, the same five one after another 40.8 seconds and one process's worth of memory. A
// live account is read every 5 minutes, not every tick, even after its status line goes quiet (the
// status line stops redrawing while a session waits on background subagents; see `isDue` below).
enum ProbeCadence {
    /// The refresh's own channel (B-1745): one line per probe here, one per round in the store.
    /// `log show --predicate 'subsystem == "app.usagebar.UsageBar" AND category == "poll"'` then answers
    /// which account held a round, for how long, and what asked for it. Ids only ("claude:.claude3",
    /// the config dir's name); never an email or anything from a credential.
    static let log = Logger(subsystem: BrandPaths.appBundleID, category: "poll")

    /// How often an account with no live session is read. Its numbers only move when a window
    /// resets (handled separately below) or when something off this machine spends it: claude.ai,
    /// the Desktop app, another computer. A manual refresh always reads every account.
    static let idleInterval: TimeInterval = 15 * 60

    /// Whether this round probes one account.
    static func isDue(userInitiated: Bool, previous: AccountUsage?, now: Date,
                      idleInterval: TimeInterval = idleInterval) -> Bool {
        if userInitiated { return true }
        // Never read, or the last read did not land: the failure-retry ladder sets the pace then.
        guard let previous, landed(previous) else { return true }
        if now.timeIntervalSince(previous.refreshedAt) >= idleInterval { return true }
        return resetPassed(since: previous, now: now)
    }

    /// Whether a previous row is a reading that landed, so the cadence may skip the account.
    static func landed(_ previous: AccountUsage) -> Bool {
        previous.error == nil && !previous.lastRefreshFailed && !previous.isStale
            && !previous.metrics.isEmpty
    }

    /// A window whose reset time fell between the last reading and now reads 0% today while the
    /// card still shows the old number.
    static func resetPassed(since previous: AccountUsage, now: Date) -> Bool {
        previous.metrics.contains { metric in
            guard let resets = metric.resetsAt else { return false }
            return resets > previous.refreshedAt && resets <= now
        }
    }

    /// Account ids that a live supervised session is running on (`readLiveSessions`). An unknown
    /// read keeps whatever it could read: this only orders and paces probes, it never fills an account.
    static func liveAccountIDs(dir: URL = supervisorStateDir,
                               isAlive: (pid_t) -> Bool = { supervisorPresenceIsLive(pid: $0) })
        -> Set<String> {
        Set(readLiveSessions(dir: dir, isAlive: isAlive).counts.keys)
    }

    /// One provider's accounts for this round. `serial` (Claude) probes one account at a time (a
    /// second beside a slow one, see `lanes`), live accounts first and only the ones due; an account skipped here keeps last round's row
    /// through the store's carry (AccountRowCarry.swift). Other providers fetch every account at once.
    static func fetchRound(_ provider: any UsageProvider, active: [ProviderAccount],
                           previous: [AccountUsage], serial: Bool, userInitiated: Bool,
                           live: Set<String>? = nil, facts: [String: LiveRateFact]? = nil,
                           hold: UsageReadHold = .shared,
                           now: Date = Date(), slowAfter: TimeInterval = slowProbeAfter,
                           onResult: (@Sendable (AccountUsage) async -> Void)? = nil) async -> [AccountUsage] {
        guard serial else {
            return await withTaskGroup(of: AccountUsage.self) { group in
                for account in active {
                    group.addTask { await timedFetch(provider, account, userInitiated: userInitiated) }
                }
                var results: [AccountUsage] = []
                for await usage in group {
                    await onResult?(usage)
                    results.append(usage)
                }
                return results
            }
        }
        let live = live ?? liveAccountIDs()
        let facts = facts ?? Dictionary(uniqueKeysWithValues: active.compactMap { account in
            readLiveRateFact(accountID: account.id).map { (account.id, $0) }
        })
        let previous = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let due = ordered(active, live: live).filter {
            // Just out of a 429 window: idle pace, whatever the sessions on it are doing.
            let cooling = hold.cooling($0.id, now: now)
            return !hold.holds($0.id, now: now, userInitiated: userInitiated)
                && isDue(userInitiated: userInitiated, live: !cooling && live.contains($0.id),
                         fact: cooling ? nil : facts[$0.id], previous: previous[$0.id], now: now)
        }
        return await lanes(provider, due, userInitiated: userInitiated, slowAfter: slowAfter,
                           onResult: onResult)
    }

    /// A probe still out after this long is slow: the next account starts beside it (B-1745).
    /// A normal read takes about 2 seconds.
    static let slowProbeAfter: TimeInterval = 10
    /// At most two probes at once, so one slow account never holds the rest while Claude still
    /// never runs many CLIs together (51c3a66d moved it to one at a time for that).
    static let maxLanes = 2

    private enum LaneEvent: Sendable { case done(Int, AccountUsage), slow(Int) }

    /// One account at a time; while every probe in flight is slow, one more starts, up to `maxLanes`.
    static func lanes(_ provider: any UsageProvider, _ due: [ProviderAccount], userInitiated: Bool,
                      slowAfter: TimeInterval,
                      onResult: (@Sendable (AccountUsage) async -> Void)?) async -> [AccountUsage] {
        await withTaskGroup(of: LaneEvent.self) { group in
            var next = 0, running: Set<Int> = [], slow: Set<Int> = [], results: [AccountUsage] = []
            func fill() {
                while next < due.count, running.count < maxLanes, running.isSubset(of: slow) {
                    let index = next, account = due[index]
                    next += 1
                    running.insert(index)
                    if running.count > 1 {
                        log.notice("probe second lane account=\(account.id, privacy: .public)")
                    }
                    group.addTask { .done(index, await timedFetch(provider, account, userInitiated: userInitiated)) }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: UInt64(slowAfter * 1_000_000_000))
                        return .slow(index)
                    }
                }
            }
            fill()
            while !running.isEmpty, let event = await group.next() {
                switch event {
                case .slow(let index):
                    if running.contains(index) { slow.insert(index) }
                case .done(let index, let usage):
                    running.remove(index)
                    slow.remove(index)
                    await onResult?(usage)
                    results.append(usage)
                }
                fill()
            }
            group.cancelAll()  // the timers of probes that came back in time
            return results
        }
    }

    /// One provider's share of a round: which accounts, and whether one at a time (Claude).
    struct ProviderRound: Sendable {
        let provider: any UsageProvider
        let active: [ProviderAccount]
        let serial: Bool
    }

    /// Every provider's round at once (B-1745). Claude's accounts stay one at a time (two beside a
    /// slow one) inside their own round; what changed is that Codex no longer waits for the last of them, so a round lasts
    /// about as long as its slowest provider rather than the sum. Rows come back in provider order,
    /// each also handed to `onResult` the moment its probe returns.
    static func fetchRounds(_ rounds: [ProviderRound], previous: [AccountUsage], userInitiated: Bool,
                            live: Set<String>? = nil, now: Date = Date(),
                            onResult: (@Sendable (AccountUsage) async -> Void)? = nil) async -> [AccountUsage] {
        await withTaskGroup(of: (Int, [AccountUsage]).self) { group in
            for (index, round) in rounds.enumerated() {
                group.addTask {
                    (index, await fetchRound(round.provider, active: round.active, previous: previous,
                                             serial: round.serial, userInitiated: userInitiated,
                                             live: live, now: now, onResult: onResult))
                }
            }
            var byIndex: [Int: [AccountUsage]] = [:]
            for await (index, rows) in group { byIndex[index] = rows }
            return rounds.indices.flatMap { byIndex[$0] ?? [] }
        }
    }

    /// One probe, timed and logged.
    static func timedFetch(_ provider: any UsageProvider, _ account: ProviderAccount,
                           userInitiated: Bool) async -> AccountUsage {
        let start = Date()
        let usage = await provider.fetchUsage(for: account, userInitiated: userInitiated)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        let outcome = usage.error == nil ? "ok" : "error"
        log.notice("probe provider=\(provider.id, privacy: .public) account=\(account.id, privacy: .public) ms=\(ms, privacy: .public) outcome=\(outcome, privacy: .public)")
        return usage
    }

    /// One landed row swapped into what the panel shows, every other row untouched (B-1745): the
    /// same overlay and order the round's commit applies, so the commit lands on what is already there.
    static func landing(_ row: AccountUsage, into rows: [AccountUsage], fact: LiveRateFact?,
                        now: Date) -> [AccountUsage] {
        (rows.filter { $0.id != row.id } + [overlay(row, fact: fact, now: now)])
            .sorted { ($0.providerID, $0.accountLabel) < ($1.providerID, $1.accountLabel) }
    }

    // MARK: - A click is a forced read at most once a minute

    /// How close together two clicks may each force every Claude account to ask the endpoint.
    /// A forced read drops Claude Code's 60-second `/usage` snapshot, so every click was one more
    /// `GET /api/oauth/usage` per account. Seven clicks in 13 minutes on 2026-11-17, beside the reset
    /// inventory's own read of the same endpoint, ended in a 429 on Claude 2 that lasted an hour.
    static let clickFloor: TimeInterval = 60

    /// Whether a click now forces a full read. Inside the floor the click still runs a round, an
    /// ordinary one: accounts that landed a reading minutes ago are not asked again.
    static func clickForcesRead(lastForced: Date?, now: Date, floor: TimeInterval = clickFloor) -> Bool {
        guard let lastForced else { return true }
        return now.timeIntervalSince(lastForced) >= floor || now < lastForced
    }

    // MARK: - Holding off after a read Claude refused to fill

    /// An account whose `/usage` came back without its limits is left alone for a while. Seen
    /// 2026-11-17: the CLI's `GET /api/oauth/usage` got HTTP 429, printed only its header line and
    /// exited 0. The CLI's debug log names the server's wait ("429 remembered for this bearer; not
    /// asking again for 1184s"); measured twice 36 seconds apart it counted down (1184, 1148), so the
    /// server holds a fixed window and asking inside it only spends requests on the same bearer.
    ///
    /// With the server's wait known the hold lasts exactly that long and a manual refresh honours
    /// it too: the owner's refresh clicks every one to three minutes were what kept the account
    /// asking through the window. Without it the wait doubles per refusal in a row (5 to 30 minutes)
    /// and a manual refresh still reads. A landed read clears a ladder hold. Holds are kept in
    /// UserDefaults so an app restart inside the window does not ask again at once.
    ///
    /// AFTER A SERVER WINDOW the account stays at the idle pace for `coolDown` (2026-11-17: Claude 2
    /// came out of a 20-minute window at 02:38, went back to a read every 4 minutes beside its own
    /// sessions and the reset inventory, and at 03:06 the server answered with a 3588-second one).
    final class UsageReadHold: @unchecked Sendable {
        static let shared = UsageReadHold(defaults: .standard)
        static let firstWait: TimeInterval = 5 * 60
        static let longestWait: TimeInterval = 30 * 60
        /// Added to the server's wait so the next read lands after the window, not on its edge.
        static let margin: TimeInterval = 30
        /// How long after a server-stated window the account is read at the idle pace only.
        static let coolDown: TimeInterval = 60 * 60
        private static let key = "UsageReadHolds"

        private struct Hold { var until: Date; var wait: TimeInterval; var firm: Bool }
        private let lock = NSLock()
        private var holds: [String: Hold] = [:]
        private let defaults: UserDefaults?

        init(defaults: UserDefaults? = nil) {
            self.defaults = defaults
            // Only firm holds are stored; a stored one past its time is simply not loaded.
            let stored = defaults?.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
            let now = Date()
            for (id, stamp) in stored where Date(timeIntervalSince1970: stamp) + Self.coolDown > now {
                holds[id] = Hold(until: Date(timeIntervalSince1970: stamp), wait: Self.firstWait, firm: true)
            }
        }

        /// Records a refusal and returns how long the account is left alone. `serverWait` is the
        /// wait the CLI reported for an HTTP 429, nil when it named none.
        @discardableResult
        func refused(_ accountID: String, now: Date, serverWait: TimeInterval? = nil) -> TimeInterval {
            lock.lock(); defer { lock.unlock() }
            let ladder = holds[accountID].map { min($0.wait * 2, Self.longestWait) } ?? Self.firstWait
            let wait: TimeInterval
            if let serverWait, serverWait > 0 {
                wait = serverWait + Self.margin
                holds[accountID] = Hold(until: now.addingTimeInterval(wait), wait: ladder, firm: true)
            } else {
                wait = ladder
                holds[accountID] = Hold(until: now.addingTimeInterval(wait), wait: ladder, firm: false)
            }
            persist()
            return wait
        }

        /// A landed read ends a ladder hold. A server-stated one stays until its cool-down is over.
        func landed(_ accountID: String) {
            lock.lock(); defer { lock.unlock() }
            guard let hold = holds[accountID], !hold.firm else { return }
            holds[accountID] = nil
            persist()
        }

        /// Out of a server-stated window but inside its cool-down.
        func cooling(_ accountID: String, now: Date) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard let hold = holds[accountID], hold.firm else { return false }
            return now >= hold.until && now < hold.until + Self.coolDown
        }

        /// Whether a round leaves the account alone. A manual refresh passes only a hold that has
        /// no server wait behind it.
        func holds(_ accountID: String, now: Date, userInitiated: Bool = false) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard let hold = holds[accountID], now < hold.until else { return false }
            return hold.firm || !userInitiated
        }

        /// When a server-stated hold ends, for the card's "retrying at" line.
        func firmUntil(_ accountID: String, now: Date) -> Date? {
            lock.lock(); defer { lock.unlock() }
            guard let hold = holds[accountID], hold.firm, now < hold.until else { return nil }
            return hold.until
        }

        private func persist() {
            guard let defaults else { return }
            let now = Date()
            let firm = holds.filter { $0.value.firm && $0.value.until + Self.coolDown > now }
                .mapValues { $0.until.timeIntervalSince1970 }
            defaults.set(firm, forKey: Self.key)
        }
    }

    // MARK: - The status-line channel (UsageBarCLI/LiveRates.swift)

    /// A live account whose two main windows are arriving from its own status line is still probed
    /// this often, for the flagship window the status line does not carry.
    static let liveFlagshipInterval: TimeInterval = 5 * 60
    /// A status-line fact counts as current while its sessions keep rendering.
    static let factFreshness: TimeInterval = 3 * 60
    /// Near a wall every reading matters to the picks and the cap handoff, so the probe runs every tick.
    static let nearWallPercent: Double = 90
    /// But never closer together than this for one account: each probe is a `GET /api/oauth/usage`
    /// on the account's bearer, beside the user's own sessions on it (429, 2026-11-17).
    static let liveFloor: TimeInterval = 2 * 60

    /// The full rule with the status-line channel. An account with a live supervisor or a fact
    /// still being rendered is read every 5 minutes, every tick near a wall or on the flagship model;
    /// any other account falls back to the idle cadence of `isDue` above.
    ///
    /// A live account whose fact went stale gets the same 5 minutes rather than every tick: the
    /// status line stops redrawing while the main session waits on background subagents (the official
    /// status line docs say it updates only after assistant messages and a few UI events), so a
    /// stale fact under a live supervisor is the common case, and reading those accounts every tick
    /// was the app's largest CPU cost (two such accounts, 2.47 probes a minute on 2026-09-27).
    static func isDue(userInitiated: Bool, live: Bool, fact: LiveRateFact?, previous: AccountUsage?,
                      now: Date) -> Bool {
        let rendering = fact.map { now.timeIntervalSince($0.observedAt) < factFreshness } ?? false
        guard !userInitiated, live || rendering else {
            return isDue(userInitiated: userInitiated, previous: previous, now: now)
        }
        guard let previous, landed(previous) else { return true }
        if now.timeIntervalSince(previous.refreshedAt) < liveFloor, now >= previous.refreshedAt {
            return resetPassed(since: previous, now: now)
        }
        if let flagshipAt = fact?.flagshipAt, now.timeIntervalSince(flagshipAt) < factFreshness { return true }
        // The last probe counts too: an idle session keeps re-rendering an older, lower header.
        let wallFacts = [fact?.fiveHour, fact?.sevenDay].compactMap { $0 }.filter { $0.resetsAt > now }
            .map(\.usedPercent)
        let wallProbe = previous.metrics.filter {
            ($0.kind == .session || $0.kind == .weeklyAll) && ($0.resetsAt.map { $0 > now } ?? true)
        }.map(\.usedPercent)
        if (wallFacts + wallProbe).contains(where: { $0 >= nearWallPercent }) { return true }
        if now.timeIntervalSince(previous.refreshedAt) >= liveFlagshipInterval { return true }
        return resetPassed(since: previous, now: now)
    }

    /// Lay the status line's numbers over a row's session and weekly windows when they moved after
    /// the row was read. The flagship window and `refreshedAt` are left alone: `refreshedAt` dates
    /// the probe, and the snapshot's readers (CapDetection) read it as that. Only Claude rows ever
    /// have a fact (the status line writes `claude:` ids), so the store passes every row through.
    ///
    /// A row that failed twice and is holding its last good numbers (`error` set by `foldLastGood`)
    /// is laid over like any other (B-3918): the status line is the fresher reading of those two
    /// windows. Its failure flags are left as they are, because the retry ladder and the flagship
    /// window, which the status line does not carry, still depend on them. A row that never loaded
    /// has no metrics, so there is nothing to lay over.
    static func overlay(_ row: AccountUsage, fact: LiveRateFact?, now: Date) -> AccountUsage {
        guard let fact, fact.accountID == row.id, fact.changedAt > row.refreshedAt else { return row }
        var copy = row
        copy.metrics = row.metrics.map { metric in
            let window: LiveRateWindow?
            switch metric.kind {
            case .session: window = fact.fiveHour
            case .weeklyAll: window = fact.sevenDay
            default: window = nil
            }
            guard let window, window.resetsAt > now,
                  (window.changedAt ?? fact.changedAt) > row.refreshedAt else { return metric }
            var updated = metric
            updated.usedPercent = window.usedPercent
            updated.severity = .fromUsedPercent(window.usedPercent)
            updated.resetsAt = window.resetsAt
            return updated
        }
        return copy
    }

    /// Live accounts first, so the accounts being spent are read earliest in a serial round;
    /// otherwise discovery order.
    static func ordered(_ accounts: [ProviderAccount], live: Set<String>) -> [ProviderAccount] {
        accounts.enumerated().sorted { a, b in
            let (la, lb) = (live.contains(a.element.id), live.contains(b.element.id))
            return la != lb ? la : a.offset < b.offset
        }.map(\.element)
    }
}
