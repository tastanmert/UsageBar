import Foundation

/// The Usage tab's numbers for one range: what was spent and burned, how that compares with the
/// window of equal length just before it, a bar per day (per month for All), and one row per
/// project, model or provider. Pure: it groups priced cells (`tokenStatsCostCells`, one per day,
/// project, provider and model), so it runs in the tests without the Rust library.
struct UsageBreakdown: Equatable, Sendable {
    enum Group: String, CaseIterable, Identifiable, Sendable {
        case project, model, provider
        var id: String { rawValue }
    }

    /// One priced cell. `cost` is nil when the model has no price (every Codex model).
    struct Cell: Equatable, Sendable {
        var day: Int
        var project: String
        var providerID: String
        var model: String
        var cost: Double?
        var tokens: Int64
        var output: Int64
    }

    struct Totals: Equatable, Sendable {
        var cost = 0.0
        var tokens: Int64 = 0
        var output: Int64 = 0
        /// Tokens on a model with no price: counted, never priced as free.
        var unpricedTokens: Int64 = 0

        mutating func add(_ cell: Cell) {
            cost += cell.cost ?? 0
            tokens += cell.tokens
            output += cell.output
            if cell.cost == nil { unpricedTokens += cell.tokens }
        }
    }

    /// A bar: one local day, or the first day of a month for All.
    struct Bar: Equatable, Sendable, Identifiable {
        var day: Int
        var totals = Totals()
        var id: Int { day }
    }

    struct Row: Equatable, Sendable, Identifiable {
        var key: String
        var totals = Totals()
        /// The same key in the previous window; nil for All.
        var previous: Totals?
        var share = 0.0
        /// How many keys the row stands for: more than one only for the pooled row.
        var members = 1
        var id: String { key }
    }

    var totals = Totals()
    /// The window of equal length just before this one; nil for All.
    var previous: Totals?
    var bars: [Bar] = []
    /// Largest first; rows past `rowLimit` are pooled into one row keyed `otherKey`.
    var rows: [Row] = []
    var monthly = false

    static let rowLimit = 10
    static let dailyLimit = 120
    static let otherKey = "\u{0}other"
    /// The Claude desktop app opens a fresh scratch folder per session; dozens of one-off folders
    /// are one place, not dozens of projects.
    static let claudeAppKey = "\u{0}claude-app"
    static let temporaryKey = "\u{0}temporary"

    var isEmpty: Bool { totals.tokens == 0 }

    /// `dayCount` nil: everything on this machine, in monthly bars. `share` is by cost when the
    /// window has a priced cost, else by tokens.
    static func make(cells: [Cell], group: Group, dayCount: Int?, today: Int,
                     calendar: Calendar = Calendar(identifier: .gregorian)) -> UsageBreakdown {
        var result = UsageBreakdown()
        let first = dayCount.map { today - $0 + 1 } ?? Int.min
        let previousFirst = dayCount.map { first - $0 } ?? Int.min
        var rows: [String: Row] = [:]
        var previousRows: [String: Totals] = [:]
        var bars: [Int: Bar] = [:]
        var previous = Totals()
        // All is drawn by day while the history is short (Claude Code keeps 30 days by default),
        // by month only once it spans more than `dailyLimit` days.
        let oldest = cells.lazy.filter { $0.day <= today }.map(\.day).min() ?? today
        result.monthly = dayCount == nil && today - oldest > dailyLimit

        for cell in cells where cell.day <= today {
            let key = Self.key(cell, group)
            if cell.day >= first {
                result.totals.add(cell)
                rows[key, default: Row(key: key)].totals.add(cell)
                let barDay = result.monthly ? monthStart(cell.day, calendar: calendar) : cell.day
                bars[barDay, default: Bar(day: barDay)].totals.add(cell)
            } else if dayCount != nil, cell.day >= previousFirst {
                previous.add(cell)
                previousRows[key, default: Totals()].add(cell)
            }
        }
        // Compared only when the history reaches back to the start of the previous window: Claude
        // Code deletes transcripts after 30 days by default, so a half-empty previous month would
        // turn every row into "+900%". Claude decides when it has any cells (Codex keeps longer).
        let anchor = cells.contains { $0.providerID == "claude" } ? cells.filter { $0.providerID == "claude" } : cells
        let covered = (anchor.map(\.day).min() ?? Int.max) <= previousFirst
        if dayCount != nil, covered {
            result.previous = previous
            for key in rows.keys { rows[key]?.previous = previousRows[key] ?? Totals() }
        }

        // Every day of a daily view gets a bar, an idle one included, so the axis is the range.
        if !result.monthly {
            let start = dayCount == nil ? oldest : first
            if start < today { for day in start...today where bars[day] == nil { bars[day] = Bar(day: day) } }
        }
        result.bars = bars.values.sorted { $0.day < $1.day }

        let byCost = result.totals.cost > 0
        func weight(_ totals: Totals) -> Double { byCost ? totals.cost : Double(totals.tokens) }
        var sorted = rows.values.sorted {
            weight($0.totals) != weight($1.totals) ? weight($0.totals) > weight($1.totals)
                : $0.totals.tokens != $1.totals.tokens ? $0.totals.tokens > $1.totals.tokens : $0.key < $1.key
        }
        // The sessions with no project keep their own row when they weigh something, rather than
        // vanish into the pool.
        let whole = weight(result.totals)
        let unattributed = group == .project
            ? sorted.firstIndex { $0.key == "" && whole > 0 && weight($0.totals) / whole >= 0.01 }.map { sorted.remove(at: $0) }
            : nil
        let limit = rowLimit - (unattributed == nil ? 0 : 1)
        if sorted.count > limit {
            var other = Row(key: otherKey, previous: result.previous == nil ? nil : Totals(), members: 0)
            for row in sorted[(limit - 1)...] {
                other.members += row.members
                other.totals.cost += row.totals.cost
                other.totals.tokens += row.totals.tokens
                other.totals.output += row.totals.output
                other.totals.unpricedTokens += row.totals.unpricedTokens
                if let p = row.previous {
                    other.previous?.cost += p.cost
                    other.previous?.tokens += p.tokens
                    other.previous?.output += p.output
                    other.previous?.unpricedTokens += p.unpricedTokens
                }
            }
            sorted = Array(sorted[..<(limit - 1)]) + [other]
        }
        if let unattributed { sorted.append(unattributed) }
        result.rows = sorted.map { var row = $0; row.share = whole > 0 ? weight(row.totals) / whole : 0; return row }
        return result
    }

    static func key(_ cell: Cell, _ group: Group) -> String {
        switch group {
        case .project: return projectKey(cell.project)
        case .model: return cell.model.isEmpty ? cell.providerID : cell.model
        case .provider: return cell.providerID
        }
    }

    static func projectKey(_ path: String) -> String {
        if path.contains("/Library/Application Support/Claude/") { return claudeAppKey }
        for prefix in ["/private/tmp/", "/tmp/", "/private/var/folders/", "/var/folders/"] where path.hasPrefix(prefix) {
            return temporaryKey
        }
        return path
    }

    /// The local day number of the 1st of the month `day` falls in.
    static func monthStart(_ day: Int, calendar: Calendar) -> Int {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let start = calendar.date(from: parts) else { return day }
        return Int(start.timeIntervalSince1970 / 86_400)
    }

    /// The change against the previous window in percent, nil when there is nothing to compare.
    static func change(_ now: Double, _ before: Double?) -> Int? {
        guard let before, before > 0 else { return nil }
        return Int(((now - before) / before * 100).rounded())
    }

    /// "claude-opus-5-5" as "Opus 5.5", "gpt-6.2-astra" as "GPT-6.2 Astra"; anything else as it is.
    static func modelName(_ id: String) -> String {
        if id.hasPrefix("claude-") {
            var parts = id.dropFirst("claude-".count).split(separator: "-").map(String.init)
            // A trailing date stamp (20260901) is not part of the name.
            if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
            guard let family = parts.first else { return id }
            let version = parts.dropFirst().joined(separator: ".")
            return family.prefix(1).uppercased() + family.dropFirst() + (version.isEmpty ? "" : " " + version)
        }
        if id.hasPrefix("gpt-") {
            let parts = id.split(separator: "-").map(String.init)
            guard parts.count >= 2 else { return id }
            let rest = parts.dropFirst(2).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return (["GPT-" + parts[1]] + rest).joined(separator: " ")
        }
        return id
    }
}

/// Compact token counts for the Usage tab: 950, 12.4K, 3.1M, 1.2B.
enum TokenCount {
    static func short(_ value: Int64, locale: Locale = .current) -> String {
        let v = Double(value)
        let (scaled, unit): (Double, String) = switch abs(v) {
        case 1e9...: (v / 1e9, "B")
        case 1e6...: (v / 1e6, "M")
        case 1e3...: (v / 1e3, "K")
        default: (v, "")
        }
        let digits = unit.isEmpty || scaled >= 100 ? 0 : 1
        return scaled.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + unit
    }
}
