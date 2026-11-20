import Foundation

/// What the UsageBar panel, the status glyph and the status menu show, worked out from the published
/// published snapshot. Pure: no UI, no store, no clock of its own, so the fixtures in
/// tests/brimpanel can pin every state. Words are left to the views (they localize); numbers,
/// durations and clock times are formatted here.
///
/// "Headroom" is what an account can actually spend now: the smaller of its 5h and weekly
/// remaining. A 5h window at 100% under a weekly at 13% is 13% of work, so the best pick and the
/// glyph read headroom, while the rows still show each window as reported.
struct BrimPanelModel: Equatable {
    enum Level: Equatable { case plenty, low, critical, limit }

    enum Window: Equatable {
        case fiveHour, weekly
        case model(String)
    }

    struct Cell: Equatable {
        /// nil = the snapshot does not report this window for the account.
        var remaining: Double?
        var level: Level?
        /// "62%", "Limit" is a word and left to the view, "—" for no reading.
        var percentText: String
        /// 0...1, the bar's fill (remaining, not used).
        var fill: Double

        func displayed(used: Bool, format: Format = Format()) -> Cell {
            guard let remaining else { return self }
            let value = used ? 100 - remaining : remaining
            var result = self
            result.percentText = format.percent(value)
            result.fill = value / 100
            return result
        }
    }

    struct ResetTime: Equatable {
        /// "2h 14m" ("2 sa 14 dk"); nil when the reset time has already passed (the reading predates it).
        var relative: String?
        /// Within a day: the countdown is worth reading. Beyond it the weekday clock says more.
        var withinDay: Bool
        /// "16:28", or "Thu 09:00" ("Per 09:00") beyond a day.
        var clock: String
    }

    struct ModelLine: Equatable {
        var name: String
        var cell: Cell
        var reset: ResetTime?
    }

    /// What a banked reset gives back. Codex banks one kind; Claude names its grants.
    enum ResetKind: Hashable {
        case codex, full, fable, session, weekly
        case other(String)
    }

    /// One reset, on a line of its own under the account (two Fable resets are two lines).
    struct ResetLine: Equatable {
        var kind: ResetKind
        var count: Int
        /// "12 Dec", or nil when undated.
        var expires: String?
        /// "28d" ("28 g") until it lapses, nil when undated or already past.
        var expiresIn: String? = nil
        /// May be spent now (Codex always; Claude per the server's flags and a bound reading).
        var usable: Bool = true
        /// What clicking the line does; set by `make`, which knows the mode and what is in flight.
        var action: LineAction = .none
        var grantID: String? = nil
    }

    /// What clicking a reset line does.
    enum LineAction: Equatable {
        /// Plain words: nothing to spend from here right now.
        case none
        /// Opens the confirm card for the line's kind.
        case confirm
        /// Says on the card why it cannot be spent from here (for example, the login needs renewing).
        case explain(ResetRefusal)
    }

    struct ResetCredit: Equatable {
        var id: String
        var count: Int
        /// One line per kind with resets left, soonest-ending first (Claude: full and Fable apart).
        var lines: [ResetLine] = []
        /// "12 Dec", or nil when undated.
        var expires: String?
        var expiryUnknown: Bool
        /// The latest read failed: the count is the last good reading (shown dimmed, `note` says why).
        var heldOver: Bool = false
        var note: ResetUnknown? = nil
    }

    /// Why an account's reset count is not known. Never drawn as "0".
    enum ResetUnknown: Equatable {
        /// No read has finished for it yet.
        case notReadYet
        /// The login's token has expired or is about to; nothing is sent until the login is renewed.
        case loginExpiring
        /// A Keychain item exists that cannot be read without a prompt.
        case loginUnreadable
        /// No credential found for the account's home.
        case loginMissing
        /// The server refused the token (401/403); asked again after a back-off.
        case rejected
        /// Rate limited (429); asked again after a back-off.
        case rateLimited
        /// Network error or an unreadable answer.
        case failed
        /// The server says this login is not in the reset program. A cached flag on its side can
        /// say so too, so it does not prove the login holds no reset.
        case notInProgram
    }

    /// Why a confirmed reset was not spent.
    enum ResetRefusal: Equatable {
        /// The reading, the login or the account changed after the confirm card opened.
        case changed
        case notLimited, alreadyUsed, cooldown, ineligible, rateLimited, loginRejected, noCredit
        /// The login's token has expired or runs out within two minutes: nothing is sent, and
        /// UsageBar never refreshes a token itself.
        case loginExpiring
        /// Codex: the home is signed in to another account, user or workspace than the one the
        /// confirm card was opened for. Nothing was sent.
        case accountChanged
        /// Codex: the latest read named no account, user and workspace to bind the consent to.
        case accountUnverified
    }

    /// A reset being spent, or just spent, on one account (the card's reset line says it).
    enum ResetUse: Equatable {
        case working
        /// Measuring again: `spent` true after a confirmed reset, nil when the answer was unclear.
        case checking(spent: Bool?)
        case used
        /// An unclear answer, and the reading after it still holds the reset.
        case notApplied
        case refused(ResetRefusal)
        case failed
    }

    /// One Claude account's reset inventory as UsageBar read it (BrimClaudeResetSchedule), the
    /// panel's input beside the snapshot.
    /// Extra usage amounts normalized to hundredths of the reported currency. Nil at the call site means unreadable.
    struct Credit: Equatable, Sendable {
        var usedCents: Double
        var limitCents: Double?
        var enabled: Bool
        var currency: String = "USD"
        var utilization: Double? = nil
        var spendLimitReached = false
        var disabledReason: String? = nil
        var userDisabled = false
        var codex: CodexCredit? = nil
        static let zero = Credit(usedCents: 0, limitCents: nil, enabled: false)

        func text(used: Bool, format: Format, localize: (String) -> String = { $0 }) -> String {
            if let codex {
                if codex.unlimited { return localize("Unlimited") }
                guard let balance = codex.balance else { return "$0" }
                return String(format: localize("%@ credits"), format.number(balance))
            }
            guard enabled else { return "$0" }
            if let limitCents {
                let amount = used ? usedCents : max(0, limitCents - usedCents)
                return format.money(amount / 100, currency: currency) + " / " + format.money(limitCents / 100, currency: currency)
            }
            return String(format: localize("%@ used"), format.money(usedCents / 100, currency: currency))
        }

        func status(localize: (String) -> String = { $0 }) -> String {
            if spendLimitReached { return localize("Credit limit reached") }
            return enabled ? "" : localize("Off")
        }

        func tableText(used: Bool, format: Format, localize: (String) -> String = { $0 }) -> String {
            let value = text(used: used, format: format, localize: localize)
            let state = status(localize: localize)
            return state.isEmpty ? value : value + " · " + state
        }

        func remainingPercent() -> Double? {
            guard enabled, let limitCents, limitCents > 0 else { return nil }
            if let utilization { return 100 - utilization }
            return max(0, min(100, (limitCents - usedCents) / limitCents * 100))
        }
    }

    struct Promotion: Equatable, Sendable {
        var amount: Double?
        var currency = "USD"
        var expiresAt: Date?
        var expiresIn: String? = nil
        func text(format: Format, localize: (String) -> String) -> String {
            amount.map { format.money($0, currency: currency) } ?? localize("Promotional credit available")
        }
    }

    struct WindowSpend: Equatable, Sendable {
        var limit: Double
        var used: Double
        func text(used showUsed: Bool, format: Format) -> String {
            format.money(showUsed ? used : max(0, limit - used), currency: "USD") + " / " + format.money(limit, currency: "USD")
        }
    }

    struct ClaudeResets: Equatable {
        struct Grant: Equatable {
            var kind: ResetKind
            var left: Int
            var endsAt: Date
            /// May be spent now, after confirmation.
            var usable: Bool = false
            var grantID: String? = nil
        }
        enum State: Equatable {
            /// The server answered for a login in the program; `grants` may all be spent (0).
            case read([Grant])
            case unknown
        }
        var remaining: [String: Double] = [:]
        var resetsAt: [String: Date] = [:]
        var checkedAt: Date? = nil
        var promotions: [Promotion] = []
        var windowSpend: [String: WindowSpend] = [:]
        var credit: Credit? = nil
        var state: State
        /// Set when the latest attempt did not give a reading (with `.read`, the count is held over).
        var problem: ResetUnknown?
    }

    struct Row: Equatable, Identifiable {
        var id: String
        var provider: String
        /// The label plus the home folder when two accounts share a label; menus use this.
        var name: String
        /// The label as the snapshot names it, and the home folder that tells duplicates apart (the panel
        /// row puts it on the plan line, where it fits).
        var label: String
        var home: String?
        var plan: String?
        var isBest: Bool
        var fiveHour: Cell
        var weekly: Cell
        var fiveHourReset: ResetTime?
        var weeklyReset: ResetTime?
        /// The reset the panel's last column shows: the 5h window's, or the weekly one when the
        /// account reports no 5h window (Codex today). `resetWindow` names which.
        var resetWindow: Window
        var reset: ResetTime?
        var model: ModelLine?
        var headroom: Double?
        /// nil = the provider reports no reset data for this account (do not show a count).
        var resetCredits: ResetCredit?
        /// Set when reset data is expected but the count is not known: the panel shows no reset
        /// line, Settings > Accounts says why.
        var resetUnknown: ResetUnknown? = nil
        var hasNoResetCredits: Bool {
            resetCredits?.count == 0 && resetCredits?.heldOver == false && resetCredits?.note == nil
                && resetUnknown == nil && !heldOver
        }
        /// The row is marked stale or its last poll failed: numbers are held over.
        var heldOver: Bool
        var refreshFailed = false
        var refreshReading: String? = nil
        var refreshProblem: String? = nil
        /// At least one reset line opens the confirm card (`ResetLine.action == .confirm`).
        var resetUsable: Bool = false
        /// A reset being spent or just spent here.
        var resetUse: ResetUse? = nil
        var promotions: [Promotion] = []
        var windowSpend: [String: WindowSpend] = [:]
        var credit: Credit? = nil
        var creditHeldOver = false
    }

    struct Group: Equatable, Identifiable {
        var id: String
        var rows: [Row]
        /// No account in the group reports a 5h window: the list leaves the 5h column out.
        var weeklyOnly: Bool
        /// The model window column's title ("Fable"), nil when no account reports one. Accounts
        /// naming different windows share it as "Model"; each cell's tooltip names its own.
        var modelColumn: String? = nil

        init(id: String, rows: [Row]) {
            self.id = id
            self.rows = rows
            weeklyOnly = rows.allSatisfy { $0.fiveHour.remaining == nil }
            let modelNames = Set(rows.compactMap { $0.model?.name })
            modelColumn = modelNames.count > 1 ? "Model" : modelNames.first
        }
    }

    /// The groups the panel draws: one per provider, or every account in one untitled group
    /// (id "all") when grouping by provider is off.
    func sections(groupByProvider: Bool) -> [Group] {
        guard !groupByProvider, !groups.isEmpty else { return groups }
        return [Group(id: "all", rows: groups.flatMap(\.rows))]
    }

    struct Tightest: Equatable {
        var accountID: String
        var accountName: String
        var window: Window
        var remaining: Double
        var level: Level
        var reset: ResetTime?
    }

    enum Banner: Equatable {
        /// The snapshot could not be read; anything shown is the last good copy.
        case unavailable
        /// The snapshot is this many minutes old.
        case stale(minutes: Int)
    }

    enum Body: Equatable {
        /// No read has finished yet this launch.
        case loading
        /// No snapshot was ever read and the last read failed.
        case noData
        /// A snapshot was read and lists no accounts.
        case noAccounts
        case accounts
    }

    struct Glyph: Equatable {
        enum Kind: Equatable { case normal, low, critical, allLimited, empty }
        var kind: Kind
        /// 0...1 remaining headroom, retained for text and severity.
        var fill: Double
        /// Dimmed tracks and fills: readings are stale or the source is unreadable.
        var dashed: Bool
        /// "62%", a countdown "1:32" when all are limited, nil with nothing to say.
        var text: String?
        var fiveHourFill: Double? = nil
        var weeklyFill: Double? = nil
    }

    var updated: String?
    var banner: Banner?
    var body: Body
    /// The window with the least left anywhere: the status item's tooltip and menu say it; the
    /// panel does not.
    var tightest: Tightest?
    var groups: [Group]
    var glyph: Glyph
    /// Every number on screen is held over (unreadable source or stale snapshot).
    var dimmed: Bool

    var accountCount: Int { groups.reduce(0) { $0 + $1.rows.count } }

    /// A snapshot older than this gets the "UsageBar data N min old" line and a dashed glyph. UsageBar
    /// rewrites it every refresh round (1-15 min by its setting), so ten minutes is two missed
    /// rounds at the default.
    static let staleAfter: TimeInterval = 10 * 60

    static let providerOrder = ["claude", "codex"]

    static func level(_ remaining: Double) -> Level {
        if remaining <= 0 { return .limit }
        if remaining < 10 { return .critical }
        if remaining <= 30 { return .low }
        return .plenty
    }

    // MARK: - Building

    /// - Parameters:
    ///   - snapshot: the last published snapshot, nil if none was published yet.
    ///   - readFailed: the latest read failed (`snapshot`, if any, is the last good copy).
    ///   - loaded: a read has finished at least once.
    ///   - claudeResets: UsageBar's own read of each Claude account's reset inventory, by account
    ///     id; empty when that read is off (no reset data shown for Claude then).
    ///   - resetUses: resets being spent or just spent, by account id.
    static func make(snapshot: UsageSnapshot?, readFailed: Bool, loaded: Bool, now: Date,
                     claudeResets: [String: ClaudeResets] = [:], resetUses: [String: ResetUse] = [:],
                     format: Format = Format()) -> BrimPanelModel {
        guard let snapshot else {
            let body: Body = readFailed ? .noData : (loaded ? .noAccounts : .loading)
            return BrimPanelModel(updated: nil, banner: readFailed ? .unavailable : nil, body: body,
                                  tightest: nil, groups: [],
                                  glyph: Glyph(kind: .empty, fill: 0, dashed: readFailed, text: nil),
                                  dimmed: readFailed)
        }
        let age = now.timeIntervalSince(snapshot.generatedAt)
        let banner: Banner? = readFailed ? .unavailable
            : age > staleAfter ? .stale(minutes: Int(age / 60)) : nil
        let dimmed = banner != nil
        let names = displayNames(snapshot.accounts)
        let ordered = ordered(snapshot)
        var rows = ordered.map {
            row(for: $0, name: names[$0.id] ?? $0.label, now: now, claudeResets: claudeResets[$0.id], format: format)
        }
        for index in rows.indices {
            let use = resetUses[rows[index].id]
            rows[index].resetUse = use
            // Not while one is out for this account, nor from held-over numbers.
            let busy = use == .working || { if case .checking = use { return true } else { return false } }()
            guard var credits = rows[index].resetCredits else { continue }
            let open = !busy && !dimmed && !rows[index].heldOver
            for line in credits.lines.indices {
                credits.lines[line].action = open
                    ? lineAction(credits.lines[line], provider: rows[index].provider, credits: credits)
                    : .none
            }
            rows[index].resetCredits = credits
            rows[index].resetUsable = credits.lines.contains { $0.action == .confirm }
        }
        // Best per provider: most headroom, and only when there is something to pick between.
        for provider in Set(rows.map(\.provider)) {
            let peers = rows.indices.filter { rows[$0].provider == provider }
            guard peers.count > 1,
                  let best = peers.filter({ (rows[$0].headroom ?? 0) > 0 })
                      .max(by: { rows[$0].headroom! < rows[$1].headroom! }) else { continue }
            rows[best].isBest = true
        }
        let providers = providerOrder.filter { p in rows.contains { $0.provider == p } }
            + Set(rows.map(\.provider)).subtracting(providerOrder).sorted()
        let groups = providers.map { provider in Group(id: provider, rows: rows.filter { $0.provider == provider }) }
        return BrimPanelModel(
            updated: format.clock(snapshot.generatedAt, now: now, dayless: true),
            banner: banner,
            body: rows.isEmpty ? .noAccounts : .accounts,
            tightest: makeTightest(ordered, names: names, now: now, format: format),
            groups: groups,
            glyph: makeGlyph(ordered, dashed: dimmed, now: now, format: format),
            dimmed: dimmed)
    }

    /// Clicking one reset line. Claude's claim is one POST with the login's own unexpired token and
    /// no refresh; a token about to run out says so instead. Codex redeems through a running
    /// `codex` process.
    static func lineAction(_ line: ResetLine, provider: String, credits: ResetCredit) -> LineAction {
        guard line.count > 0 else { return .none }
        if line.kind == .codex { return line.usable ? .confirm : .none }
        if credits.note == .loginExpiring { return .explain(.loginExpiring) }
        return line.usable && !credits.heldOver ? .confirm : .none
    }

    /// The snapshot's accounts in the published panel order (`accountOrder`), then provider.
    static func ordered(_ snapshot: UsageSnapshot) -> [UsageSnapshot.Account] {
        let order = snapshot.accountOrder ?? []
        let rank = { (id: String) in order.firstIndex(of: id) ?? Int.max }
        return snapshot.accounts.enumerated().sorted { a, b in
            let ra = rank(a.element.id), rb = rank(b.element.id)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// Labels as the snapshot names them; two accounts with one label get their home folder appended,
    /// because "Codex 100" twice tells the user nothing.
    static func displayNames(_ accounts: [UsageSnapshot.Account]) -> [String: String] {
        var counts: [String: Int] = [:]
        for account in accounts { counts[account.label, default: 0] += 1 }
        var names: [String: String] = [:]
        for account in accounts {
            if counts[account.label, default: 0] > 1, let home = account.id.split(separator: ":").last {
                names[account.id] = "\(account.label) (\(home))"
            } else {
                names[account.id] = account.label
            }
        }
        return names
    }

    static func headroom(_ account: UsageSnapshot.Account) -> Double? {
        [account.sessionRemaining, account.weeklyRemaining].compactMap { $0 }.min()
    }

    static func cell(_ remaining: Double?, format: Format = Format()) -> Cell {
        guard let remaining else { return Cell(remaining: nil, level: nil, percentText: "—", fill: 0) }
        let clamped = min(max(remaining, 0), 100)
        return Cell(remaining: clamped, level: level(clamped),
                    percentText: format.percent(clamped), fill: clamped / 100)
    }

    static func row(for account: UsageSnapshot.Account, name: String, now: Date,
                    claudeResets: ClaudeResets? = nil, format: Format) -> Row {
        var account = account
        if account.provider == "claude", let reading = claudeResets, reading.problem == nil,
           let checkedAt = reading.checkedAt, checkedAt > (account.refreshedAt ?? .distantPast) {
            if let value = reading.remaining["five_hour"] {
                account.sessionRemaining = value
                account.sessionResetsAt = reading.resetsAt["five_hour"]
            }
            if let value = reading.remaining["seven_day"] {
                account.weeklyRemaining = value
                account.weeklyResetsAt = reading.resetsAt["seven_day"]
            }
            if let value = reading.remaining["seven_day_fable"] {
                account.modelRemaining = value
                account.modelWindowName = "Fable"
                account.modelResetsAt = reading.resetsAt["seven_day_fable"]
            }
        }
        let reset = { (date: Date?) in date.map { format.resetTime($0, now: now) } }
        let model = account.modelRemaining.map {
            ModelLine(name: account.modelWindowName ?? "Model", cell: cell($0, format: format),
                      reset: reset(account.modelResetsAt))
        }
        // One line per credit. The snapshot dates the soonest one only; the rest show no end.
        var credits = account.resetCreditsAvailable.map { count in
            ResetCredit(id: account.id, count: count,
                        lines: (0..<max(count, 0)).map { index in
                            let end = index == 0 ? account.resetCreditsNextExpiry : nil
                            return ResetLine(kind: .codex, count: 1, expires: end.map(format.day),
                                             expiresIn: end.flatMap { format.span(until: $0, now: now) })
                        },
                        expires: account.resetCreditsNextExpiry.map(format.day),
                        expiryUnknown: account.resetCreditsExpiryUnknown ?? false)
        }
        var resetUnknown: ResetUnknown?
        if account.provider == "claude", credits == nil, let claudeResets {
            (credits, resetUnknown) = claudeCredits(claudeResets, id: account.id, now: now, format: format)
        }
        let fiveHourReset = reset(account.sessionResetsAt)
        let weeklyReset = reset(account.weeklyResetsAt)
        let fiveHourMissing = account.sessionRemaining == nil
        let home = name == account.label ? nil : account.id.split(separator: ":").last.map(String.init)
        let credit: Credit?
        if account.provider == "claude" {
            credit = claudeResets?.credit
        } else if (account.lastRefreshFailed == true || account.error != nil) && account.codexCredit == nil {
            credit = nil
        } else {
            let balance = account.codexCredit ?? CodexCredit(balance: nil)
            credit = Credit(usedCents: 0, enabled: true, spendLimitReached: balance.spendControlReached, codex: balance)
        }
        return Row(id: account.id, provider: account.provider, name: name, label: account.label,
                   home: home, plan: account.plan,
                   isBest: false, fiveHour: cell(account.sessionRemaining, format: format),
                   weekly: cell(account.weeklyRemaining, format: format),
                   fiveHourReset: fiveHourReset, weeklyReset: weeklyReset,
                   resetWindow: fiveHourMissing ? .weekly : .fiveHour,
                   reset: fiveHourMissing ? weeklyReset : fiveHourReset, model: model,
                   headroom: headroom(account), resetCredits: credits, resetUnknown: resetUnknown,
                   heldOver: account.isStale || account.lastRefreshFailed == true || account.error != nil,
                   refreshFailed: account.lastRefreshFailed == true || account.error != nil,
                   refreshReading: account.refreshedAt.map { format.reading($0, now: now) },
                   refreshProblem: [account.lastRefreshError ?? account.error, account.errorDetail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n"),
                   promotions: (claudeResets?.promotions ?? []).map {
                       var promo = $0
                       promo.expiresIn = promo.expiresAt.flatMap { format.span(until: $0, now: now) }
                       return promo
                   }, windowSpend: claudeResets?.windowSpend ?? [:],
                   credit: credit, creditHeldOver: claudeResets?.problem != nil)
    }

    /// A Claude reading as the row's resets: one line per reset (a grant holding two is two lines),
    /// soonest-ending first. Unknown is never a zero.
    static func claudeCredits(_ resets: ClaudeResets, id: String, now: Date,
                              format: Format) -> (ResetCredit?, ResetUnknown?) {
        guard case .read(let grants) = resets.state else { return (nil, resets.problem ?? .notReadYet) }
        let live = grants.filter { $0.left > 0 && $0.endsAt > now }
        var lines: [(line: ResetLine, end: Date)] = []
        for grant in live {
            for _ in 0..<grant.left {
                lines.append((ResetLine(kind: grant.kind, count: 1, expires: format.day(grant.endsAt),
                                        expiresIn: format.span(until: grant.endsAt, now: now), usable: grant.usable, grantID: grant.grantID),
                              grant.endsAt))
            }
        }
        lines = lines.enumerated().sorted { a, b in
            a.element.end != b.element.end ? a.element.end < b.element.end : a.offset < b.offset
        }.map(\.element)
        let credit = ResetCredit(id: id, count: lines.reduce(0) { $0 + $1.line.count }, lines: lines.map(\.line),
                                 expires: lines.first.map { format.day($0.end) }, expiryUnknown: false,
                                 heldOver: resets.problem != nil, note: resets.problem)
        return (credit, nil)
    }

    /// The single window with the least left, across every account and window.
    static func makeTightest(_ accounts: [UsageSnapshot.Account], names: [String: String], now: Date,
                         format: Format) -> Tightest? {
        var best: Tightest?
        var bestReset: Date?
        for account in accounts {
            let windows: [(Window, Double?, Date?)] = [
                (.fiveHour, account.sessionRemaining, account.sessionResetsAt),
                (.weekly, account.weeklyRemaining, account.weeklyResetsAt),
                (.model(account.modelWindowName ?? "Model"), account.modelRemaining, account.modelResetsAt),
            ]
            for (window, remaining, resetsAt) in windows {
                guard let remaining else { continue }
                let value = min(max(remaining, 0), 100)
                if let current = best {
                    if value > current.remaining { continue }
                    // Equal: the one that stays shut longer is the tighter one.
                    if value == current.remaining, (resetsAt ?? .distantPast) <= (bestReset ?? .distantPast) {
                        continue
                    }
                }
                best = Tightest(accountID: account.id, accountName: names[account.id] ?? account.label, window: window,
                                remaining: value, level: level(value),
                                reset: resetsAt.map { format.resetTime($0, now: now) })
                bestReset = resetsAt
            }
        }
        return best
    }

    static func makeGlyph(_ accounts: [UsageSnapshot.Account], dashed: Bool, now: Date,
                      format: Format) -> Glyph {
        var glyph = makeHeadroomGlyph(accounts, dashed: dashed, now: now, format: format)
        if let best = accounts.filter({ headroom($0) != nil })
            .max(by: { headroom($0)! < headroom($1)! }) {
            glyph.fiveHourFill = best.sessionRemaining.map { cell($0).fill }
            glyph.weeklyFill = best.weeklyRemaining.map { cell($0).fill }
        }
        return glyph
    }

    private static func makeHeadroomGlyph(_ accounts: [UsageSnapshot.Account], dashed: Bool, now: Date,
                                         format: Format) -> Glyph {
        let known = accounts.compactMap { account in headroom(account).map { (account, $0) } }
        guard let best = known.map(\.1).max() else {
            return Glyph(kind: .empty, fill: 0, dashed: dashed, text: nil)
        }
        if best <= 0 {
            // Every account is at a wall: count down to the first one that opens again. An
            // account opens when the LAST of its exhausted windows resets.
            let opens = known.compactMap { account, _ -> Date? in
                let walls: [(Double?, Date?)] = [(account.sessionRemaining, account.sessionResetsAt),
                                                 (account.weeklyRemaining, account.weeklyResetsAt)]
                let dates = walls.filter { ($0.0 ?? 1) <= 0 }.map(\.1)
                guard !dates.isEmpty, dates.allSatisfy({ $0 != nil }) else { return nil }
                return dates.compactMap { $0 }.max()
            }.filter { $0 > now }
            return Glyph(kind: .allLimited, fill: 0, dashed: dashed,
                         text: opens.min().map { format.countdown($0, now: now) })
        }
        let value = min(best, 100)
        let kind: Glyph.Kind = switch level(value) {
        case .plenty: .normal
        case .low: .low
        case .critical, .limit: .critical
        }
        return Glyph(kind: kind, fill: value / 100, dashed: dashed, text: format.percent(value))
    }

    // MARK: - Spending a reset

    /// The windows a reset of `kind` gives back on this row, as they read now; each goes to 100%.
    /// Full and Codex: the 5-hour and weekly windows (and Fable for a full one). Fable: the Fable
    /// window and the 5-hour one only (the all-models week keeps its spend). 5-hour, weekly: that
    /// window. A window the row does not report is left out. In window order: Fable, 5h, weekly.
    static func resetEffects(_ row: Row, kind: ResetKind) -> [(window: Window, before: Cell)] {
        var effects: [(window: Window, before: Cell)] = []
        let five = row.fiveHour.remaining != nil
        let model = row.model.map { (Window.model($0.name), $0.cell) }
        switch kind {
        case .codex, .full, .other:
            if kind == .full, let model { effects.append(model) }
            if five { effects.append((.fiveHour, row.fiveHour)) }
            effects.append((.weekly, row.weekly))
        case .fable:
            if let model { effects.append(model) }
            if five { effects.append((.fiveHour, row.fiveHour)) }
        case .session:
            if five { effects.append((.fiveHour, row.fiveHour)) }
        case .weekly:
            effects.append((.weekly, row.weekly))
        }
        return effects
    }

    /// The kinds a row's lines can spend now, soonest-ending first, each once.
    static func usableKinds(_ row: Row) -> [ResetKind] {
        guard let credits = row.resetCredits else { return [] }
        var kinds: [ResetKind] = []
        for line in credits.lines where line.action == .confirm && !kinds.contains(line.kind) {
            kinds.append(line.kind)
        }
        return kinds
    }

    /// A row's windows in the order every surface shows them: the model window (Fable), then
    /// 5 hours (when the account reports one; Codex does not), then weekly.
    static func windows(_ row: Row) -> [(window: Window, cell: Cell, reset: ResetTime?)] {
        var list: [(window: Window, cell: Cell, reset: ResetTime?)] = []
        if let model = row.model { list.append((.model(model.name), model.cell, model.reset)) }
        if row.fiveHour.remaining != nil { list.append((.fiveHour, row.fiveHour, row.fiveHourReset)) }
        list.append((.weekly, row.weekly, row.weeklyReset))
        return list
    }

    /// The row's window with the least left, for the status menu's one line per account. On a
    /// tie the later window in `windows` order wins (weekly over 5 hours): it stays shut longer.
    static func tightestWindow(_ row: Row) -> (window: Window, cell: Cell, reset: ResetTime?)? {
        var best: (window: Window, cell: Cell, reset: ResetTime?)?
        for entry in windows(row) {
            guard let value = entry.cell.remaining else { continue }
            if let current = best?.cell.remaining, value > current { continue }
            best = entry
        }
        return best
    }

    // MARK: - Formatting

    struct Format {
        var calendar: Calendar
        var locale: Locale

        init(timeZone: TimeZone = .current, locale: Locale = Locale(identifier: "en_US_POSIX")) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            calendar.locale = locale
            self.calendar = calendar
            self.locale = locale
        }

        func number(_ value: Double) -> String {
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 8
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }

        func money(_ amount: Double, currency: String) -> String {
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            return (currency == "USD" ? "$" : currency + " ") + (formatter.string(from: NSNumber(value: amount)) ?? String(amount))
        }

        func dollars(_ cents: Double) -> String {
            let number = NumberFormatter()
            number.locale = locale
            number.numberStyle = .decimal
            number.minimumFractionDigits = 2
            number.maximumFractionDigits = 2
            return "$" + (number.string(from: NSNumber(value: cents / 100)) ?? String(cents / 100))
        }

        private func formatter(_ pattern: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.dateFormat = pattern
            return formatter
        }

        /// Day, hour and minute marks in the locale's language: "d h m" in English, "g sa dk" in
        /// Turkish. Other languages keep the English marks (short and unambiguous beside digits).
        private var units: (day: String, hour: String, minute: String, space: String) {
            locale.language.languageCode?.identifier == "tr" ? ("g", "sa", "dk", " ") : ("d", "h", "m", "")
        }

        private func amount(_ value: Int, _ unit: String) -> String { "\(value)\(units.space)\(unit)" }

        /// 24-hour clock, the weekday in the locale's language: "16:28" within a day of now,
        /// "Thu 09:00" ("Per 09:00") beyond it.
        func clock(_ date: Date, now: Date, dayless: Bool = false) -> String {
            let far = abs(date.timeIntervalSince(now)) >= 24 * 3600
            return formatter(far && !dayless ? "EEE HH:mm" : "HH:mm").string(from: date)
        }

        func reading(_ date: Date, now: Date) -> String {
            formatter(calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "d MMM yyyy HH:mm").string(from: date)
        }

        func day(_ date: Date) -> String { formatter("d MMM").string(from: date) }

        /// "96%" in English, "%96" in Turkish: the one percentage spelling of the panel, the menu
        /// and Settings.
        func percent(_ value: Double) -> String { BrimPercent.text(Int(value.rounded()), locale: locale) }

        /// "2h 14m", "47m", "1d 23h" ("2 sa 14 dk", "47 dk", "1 g 23 sa"); nil once the time has passed.
        func duration(until date: Date, now: Date) -> String? {
            let seconds = date.timeIntervalSince(now)
            guard seconds > 0 else { return nil }
            return span(minutes: Int((seconds / 60).rounded(.up)))
        }

        private func span(minutes: Int) -> String {
            if minutes >= 24 * 60 {
                let hours = (minutes % 1440) / 60
                return hours == 0 ? amount(minutes / 1440, units.day)
                    : amount(minutes / 1440, units.day) + " " + amount(hours, units.hour)
            }
            if minutes < 60 { return amount(minutes, units.minute) }
            let rest = minutes % 60
            return rest == 0 ? amount(minutes / 60, units.hour)
                : amount(minutes / 60, units.hour) + " " + amount(rest, units.minute)
        }

        /// Whole days to a date a long way off ("28d", "28 g"); the hours and minutes under a day.
        /// nil once it has passed. For reset credits, whose end is weeks away.
        func span(until date: Date, now: Date) -> String? {
            let seconds = date.timeIntervalSince(now)
            guard seconds > 0 else { return nil }
            if seconds >= 24 * 3600 { return amount(Int(seconds / 86400), units.day) }
            return duration(until: date, now: now)
        }

        func resetTime(_ date: Date, now: Date) -> ResetTime {
            ResetTime(relative: duration(until: date, now: now), withinDay: date.timeIntervalSince(now) < 24 * 3600,
                      clock: clock(date, now: now))
        }

        /// Menu bar countdown: "1:32", or "2d 4h" ("2 g 4 sa") beyond a day.
        func countdown(_ date: Date, now: Date) -> String {
            let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
            if minutes >= 24 * 60 { return span(minutes: minutes) }
            return "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
        }
    }
}

/// The percentage spelling: the sign before the number in Turkish ("%96"), after it otherwise
/// ("96%"). Every UsageBar surface goes through this.
enum BrimPercent {
    static func text(_ value: Int, locale: Locale) -> String {
        locale.language.languageCode?.identifier == "tr" ? "%\(value)" : "\(value)%"
    }
}

/// The panel's sentences built from the model, with the words looked up through `localize` (the
/// app's `L`; tests pass the catalog's Turkish or nothing). Shared by the panel, the status menu
/// and Settings > Accounts so all three say the same thing.
struct BrimPanelText {
    var localize: (String) -> String

    private func L(_ key: String) -> String { localize(key) }

    func window(_ window: BrimPanelModel.Window) -> String {
        switch window {
        case .fiveHour: L("5 hours")
        case .weekly: L("Weekly")
        case .model(let name): name == "Model" ? L("Model") : name
        }
    }

    /// A window's name where room is short (the status menu): "Fable", "5h" ("5 sa"), "Weekly".
    func shortWindow(_ window: BrimPanelModel.Window) -> String {
        switch window {
        case .fiveHour: L("5h")
        case .weekly: L("Weekly")
        case .model(let name): name == "Model" ? L("Model") : name
        }
    }

    /// A percentage, or "Limit" for a window with nothing left: every surface says it this way.
    func left(_ cell: BrimPanelModel.Cell) -> String {
        cell.level == .limit ? L("Limit") : cell.percentText
    }

    /// The status menu's figure for an account, its tightest window: "Fable 28% · 2d 19h",
    /// "5h Limit · 1h 32m"; nil when the account reports no window at all.
    func menuFigure(_ row: BrimPanelModel.Row, used: Bool = false, format: BrimPanelModel.Format = .init()) -> String? {
        guard let (window, cell, reset) = BrimPanelModel.tightestWindow(row) else { return nil }
        let head = shortWindow(window) + " " + cell.displayed(used: used, format: format).percentText
        guard let reset else { return head }
        return head + " · " + resetShort(reset)
    }

    /// "Tightest: Work 9% · 0:47"; "Limit" for a window with nothing left, never "0%".
    func tightest(_ t: BrimPanelModel.Tightest, format: BrimPanelModel.Format) -> String {
        var parts = [t.accountName + " " + (t.level == .limit ? L("Limit") : format.percent(t.remaining))]
        if let reset = t.reset { parts.append(reset.clock) }
        return L("Tightest:") + " " + parts.joined(separator: " · ")
    }

    /// Under a window in the detailed layout: "resets in 3h 47m", "reset due" once it passed.
    func resetsIn(_ reset: BrimPanelModel.ResetTime) -> String {
        reset.relative.map { String(format: L("Resets in %@"), $0) } ?? L("Reset due")
    }

    /// Beside the percentage in the compact layout: "3h 47m", "due" once it passed.
    func resetShort(_ reset: BrimPanelModel.ResetTime) -> String {
        reset.relative ?? L("due")
    }

    /// One reset's line under an account: "Fable reset · expires in 2d", "Reset credit · expires
    /// in 28d" for Codex, the name alone when its end is not known.
    func resetLine(_ line: BrimPanelModel.ResetLine) -> String {
        guard let end = line.expiresIn else { return kindName(line.kind) }
        return kindName(line.kind) + " · " + String(format: L("expires in %@"), end)
    }

    /// Every reset of an account, one line each, soonest-ending first. Empty with no reset left or
    /// no reading: the panel then shows no line at all.
    func resetLines(_ credit: BrimPanelModel.ResetCredit?) -> [String] {
        guard let credit else { return [] }
        return credit.lines.filter { $0.count > 0 }.map(resetLine)
    }

    /// The account's resets as one text, a line each (Settings > Accounts' tooltip). nil with none.
    func resetSummary(_ credit: BrimPanelModel.ResetCredit?) -> String? {
        let lines = resetLines(credit)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// "Data 12 min old".
    func stale(_ minutes: Int) -> String {
        String(format: L("Data %d min old"), minutes)
    }

    /// The card's reset line while a reset is being spent or just was: "Reset · 5 hours 100%" once
    /// the new reading shows the window refilled, "Reset" alone until then, "Checking…" meanwhile.
    func resetUse(_ use: BrimPanelModel.ResetUse, row: BrimPanelModel.Row, used: Bool = false, format: BrimPanelModel.Format = .init()) -> String {
        switch use {
        case .working: return L("Using reset…")
        case .checking: return L("Checking again…")
        case .used:
            let (window, cell) = row.fiveHour.remaining != nil ? (BrimPanelModel.Window.fiveHour, row.fiveHour)
                : (.weekly, row.weekly)
            // A figure from before the reset would read as if it did nothing: say it without one.
            guard let remaining = cell.remaining, remaining >= 99 else { return L("Checking again…") }
            return String(format: L("Reset done · %1$@ %2$@"), self.window(window), used ? cell.displayed(used: true, format: format).percentText : cell.percentText)
        case .notApplied: return L("Not used: the reset is still there.")
        case .failed: return L("Couldn't use the reset.")
        case .refused(let why):
            return switch why {
            case .changed: L("Not used: the account was read again. Confirm once more.")
            case .notLimited: L("Not used: this account is not at a limit.")
            case .alreadyUsed: L("Not used: this reset was already used.")
            case .cooldown: L("Not used: this reset is cooling down.")
            case .ineligible: L("Not used: this login can't use the reset.")
            case .rateLimited: L("Not used: rate limited. Try again later.")
            case .loginRejected: L("Not used: the login was refused. Sign in again.")
            case .noCredit: L("Not used: no reset left.")
            case .loginExpiring: L("Session needs renewing")
            case .accountChanged: L("Account changed, cancelled")
            case .accountUnverified: L("Not used: the account couldn't be verified.")
            }
        }
    }

    func kindName(_ kind: BrimPanelModel.ResetKind) -> String {
        switch kind {
        case .codex: L("Reset credit")
        case .full: L("Full reset")
        case .fable: L("Fable reset")
        case .session: L("5h reset")
        case .weekly: L("Weekly reset")
        case .other(let name): String(format: L("%@ reset"), name)
        }
    }

    /// The kind in a menu entry after the account's name: "Fable", "Full", "Reset credit".
    func shortKindName(_ kind: BrimPanelModel.ResetKind) -> String {
        switch kind {
        case .codex: L("Reset credit")
        case .full: L("Full")
        case .fable: "Fable"
        case .session: L("5h")
        case .weekly: L("Weekly")
        case .other(let name): name
        }
    }

    func unknown(_ reason: BrimPanelModel.ResetUnknown) -> String {
        switch reason {
        case .notReadYet: L("Reset count not read yet.")
        case .loginExpiring: L("Reset count unknown: the session needs renewing.")
        case .loginUnreadable: L("Reset count unknown: the login can't be read without a Keychain prompt.")
        case .loginMissing: L("Reset count unknown: no Claude login found for this account.")
        case .rejected: L("Reset count unknown: Anthropic refused the login. Trying again in an hour.")
        case .rateLimited: L("Reset count unknown: rate limited. Trying again in 30 minutes.")
        case .failed: L("Reset count unknown: the last read failed.")
        case .notInProgram: L("Reset count unknown: Anthropic lists no reset program for this login right now.")
        }
    }

    /// Settings > Accounts' reset column: "2 left", "None", or why it is not known ("Not read yet").
    func accountStatus(_ row: BrimPanelModel.Row) -> String {
        if let credit = row.resetCredits {
            if row.hasNoResetCredits { return L("No reset credits") }
            if credit.count == 0 { return L("Read failed") }
            return String(format: L("%d left"), credit.count)
        }
        guard let reason = row.resetUnknown else { return "—" }
        return switch reason {
        case .notReadYet: L("Not read yet")
        case .loginExpiring: L("Session needs renewing")
        case .loginUnreadable: L("Login locked")
        case .loginMissing: L("No login")
        case .rejected: L("Refused")
        case .rateLimited: L("Rate limited")
        case .failed: L("Read failed")
        case .notInProgram: L("Not offered")
        }
    }
}
