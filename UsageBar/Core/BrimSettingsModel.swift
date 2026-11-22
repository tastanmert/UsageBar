import Foundation

/// What the UsageBar settings window shows, worked out from the published snapshot and a
/// read-only look at the disk. Pure like `BrimPanelModel`: no UI, no store, and every file read
/// goes through `BrimFileProbe`, so tests/brimsettings pins each state without touching user data.
/// Nothing here writes; the window's live-mode controls stay off (BrimFeatures).

/// The text beside the menu bar mark.
enum BrimMenuBarText: String, CaseIterable, Identifiable {
    case glyph, percent, countdown, selected
    var id: String { rawValue }

    static let defaultsKey = "brimMenuBarText"
    static let fallback: BrimMenuBarText = .percent

    /// The glyph's text for `mode`. All-limited keeps its countdown in every mode: that state is
    /// the one where the time is the whole message. Countdown is the best account's 5h reset; with
    /// none known it falls back to the percentage rather than showing nothing.
    static func text(_ mode: BrimMenuBarText, glyph: BrimPanelModel.Glyph, snapshot: UsageSnapshot?,
                     now: Date, format: BrimPanelModel.Format = BrimPanelModel.Format()) -> String? {
        if glyph.kind == .allLimited { return glyph.text }
        switch mode {
        case .glyph, .selected: return nil
        case .percent: return glyph.text
        case .countdown:
            guard let best = bestAccount(snapshot), let resets = best.sessionResetsAt, resets > now else {
                return glyph.text
            }
            return format.countdown(resets, now: now)
        }
    }

    static func showsCup(_ mode: BrimMenuBarText, segments: [BrimMenuSelection.Segment]) -> Bool {
        mode != .selected || segments.isEmpty
    }

    /// The mark always shows remaining quota, including when the text shows used quota.
    static func face(_ mode: BrimMenuBarText, model: BrimPanelModel,
                     selection: BrimMenuSelection, used: Bool,
                     format: BrimPanelModel.Format = .init()) -> BrimPanelModel.Glyph {
        var glyph = model.glyph
        let remaining = mode == .selected
            ? selection.tightestRemaining(rows: model.groups.flatMap(\.rows)) : model.tightest?.remaining
        glyph.text = mode == .glyph || mode == .selected ? nil
            : BrimPanelModel.cell(remaining).displayed(used: used, format: format).percentText
        if mode != .glyph {
            glyph.fill = BrimPanelModel.cell(remaining).fill
            if remaining == nil { glyph.kind = .empty }
        }
        if let remaining {
            glyph.kind = switch BrimPanelModel.level(remaining) {
            case .plenty: .normal
            case .low: .low
            case .critical: .critical
            case .limit: mode == .glyph && model.glyph.kind == .allLimited ? .allLimited : .critical
            }
        }
        if mode == .percent || mode == .countdown {
            let row = model.groups.flatMap(\.rows).first { $0.id == model.tightest?.accountID }
            glyph.fiveHourFill = row?.fiveHour.remaining.map { BrimPanelModel.cell($0).fill }
            glyph.weeklyFill = row?.weekly.remaining.map { BrimPanelModel.cell($0).fill }
        }
        return glyph
    }

    /// The account with the most headroom, the one the icon mode shows.
    static func bestAccount(_ snapshot: UsageSnapshot?) -> UsageSnapshot.Account? {
        guard let snapshot else { return nil }
        return BrimPanelModel.ordered(snapshot)
            .compactMap { account in BrimPanelModel.headroom(account).map { (account, $0) } }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
    }
}

enum BrimAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    static let defaultsKey = "brimAppearance"
}

/// Reads used by the settings window, injected so a test can stand in for the disk.
struct BrimFileProbe {
    enum Read { case missing, unreadable, data(Data) }

    /// lstat semantics: a dangling symlink still counts as present (an install left behind).
    var exists: (String) -> Bool
    var read: (String) -> Read

    static var live: BrimFileProbe {
        BrimFileProbe(
            exists: { path in
                var info = stat()
                return lstat(path, &info) == 0
            },
            read: { path in
                var info = stat()
                guard lstat(path, &info) == 0 else { return .missing }
                guard let data = FileManager.default.contents(atPath: path) else { return .unreadable }
                return .data(data)
            })
    }
}

/// "~/.claude" for a path under the home directory.
func brimTildePath(_ path: String, home: URL) -> String {
    let root = home.path
    if path == root { return "~" }
    return path.hasPrefix(root + "/") ? "~" + path.dropFirst(root.count) : path
}

// MARK: - Accounts

struct BrimAccountsTable: Equatable {
    enum Login: Equatable {
        /// The last read worked, which needs a working login.
        case signedIn
        /// The snapshot reports an auth error for the account.
        case needsSignIn
        /// The numbers are held over from an earlier read.
        case heldOver
        /// The snapshot reports some other error.
        case error
        /// Live mode: the account is switched off (Monitor), so nothing was read for it.
        case notMonitored
    }

    /// An account discovery found that the snapshot does not list (live mode: switched off).
    struct Discovered: Equatable {
        var id: String
        var provider: String
        var label: String
        var home: String?
    }

    struct Row: Equatable, Identifiable {
        var id: String
        var provider: String
        var name: String
        var plan: String?
        var folder: String
        /// Who the account is signed in as (LoginStatusStore's answer, filled in by the app, never
        /// from the snapshot, which carries no identity). Nil shows the folder alone.
        var email: String? = nil
        var login: Login
        /// Read and published (Settings > Accounts' Monitor switch, live mode).
        var monitored = true
        /// Codex: an open reset attempt of an earlier login holds this folder; the ⋯ menu can
        /// clear UsageBar's record of it.
        var strandedCodexAttempt = false
    }

    struct Group: Equatable, Identifiable {
        var id: String
        var rows: [Row]
    }

    var groups: [Group]
    /// Account-shaped profile folders on disk that the snapshot does not list ("~/.claude-old").
    var untracked: [String]
    var count: Int { groups.reduce(0) { $0 + $1.rows.count } }

    /// Puts each account's address on its row; an empty answer leaves the row without one.
    mutating func fillEmails(_ email: (String) -> String?) {
        for g in groups.indices {
            for r in groups[g].rows.indices {
                let value = email(groups[g].rows[r].id)
                groups[g].rows[r].email = value?.isEmpty == false ? value : nil
            }
        }
    }

    /// - Parameter discovered: live mode's whole account list; the ones the snapshot leaves out
    ///   (switched off) follow as not monitored. Empty in mirror mode.
    /// - Parameter strandedCodexAttempts: account ids whose folder holds another login's open
    ///   Codex reset attempt (`CodexConsumeCoordinator.strandedAttempt`).
    static func make(snapshot: UsageSnapshot?, folders: [URL], home: URL, probe: BrimFileProbe,
                     discovered: [Discovered] = [], strandedCodexAttempts: Set<String> = []) -> BrimAccountsTable {
        let accounts = snapshot.map(BrimPanelModel.ordered) ?? []
        let names = BrimPanelModel.displayNames(accounts)
        let listed = Set(accounts.map(\.id))
        let rows = accounts.map { account in
            Row(id: account.id, provider: account.provider, name: names[account.id] ?? account.label,
                plan: account.plan, folder: folder(account, home: home), login: login(account),
                strandedCodexAttempt: strandedCodexAttempts.contains(account.id))
        } + discovered.filter { !listed.contains($0.id) }.map { account in
            Row(id: account.id, provider: account.provider, name: account.label, plan: nil,
                folder: account.home.map { brimTildePath($0, home: home) }
                    ?? account.id.split(separator: ":").last.map { "~/" + $0 } ?? account.id,
                login: .notMonitored, monitored: false,
                strandedCodexAttempt: strandedCodexAttempts.contains(account.id))
        }
        let providers = BrimPanelModel.providerOrder.filter { p in rows.contains { $0.provider == p } }
            + Set(rows.map(\.provider)).subtracting(BrimPanelModel.providerOrder).sorted()
        let groups = providers.map { p in Group(id: p, rows: rows.filter { $0.provider == p }) }
        let tracked = Set(rows.map(\.folder))
        let untracked = folders
            .filter { looksLikeAccount($0, probe: probe) }
            .map { brimTildePath($0.path, home: home) }
            .filter { !tracked.contains($0) }
        return BrimAccountsTable(groups: groups, untracked: untracked)
    }

    static func folder(_ account: UsageSnapshot.Account, home: URL) -> String {
        if let launch = account.launchHome { return brimTildePath(launch, home: home) }
        return account.id.split(separator: ":").last.map { "~/" + $0 } ?? account.id
    }

    static func login(_ account: UsageSnapshot.Account) -> Login {
        if let error = account.error?.lowercased() {
            let auth = ["login", "log in", "sign in", "signed out", "auth", "401", "token", "credential"]
            return auth.contains { error.contains($0) } ? .needsSignIn : .error
        }
        if account.isStale || account.lastRefreshFailed == true { return .heldOver }
        return .signedIn
    }

    /// A folder holds an account when the provider's own files are in it; checked by name only,
    /// nothing is opened. Keeps `~/.claude-server-commander` and the like out of the list.
    static func looksLikeAccount(_ folder: URL, probe: BrimFileProbe) -> Bool {
        let marks = folder.lastPathComponent.hasPrefix(".codex")
            ? ["auth.json", "config.toml"]
            : [".claude.json", ".credentials.json", "settings.json"]
        return marks.contains { probe.exists(folder.appendingPathComponent($0).path) }
    }
}

// MARK: - Integrations

struct BrimIntegrationsReport: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case cli, mcp, statusLine, hooks, codex, shims
        var id: String { rawValue }
    }

    enum Status: Equatable {
        case installed
        case notInstalled
        /// A file that would answer could not be read or parsed; not the same as absent.
        case unreadable
    }

    struct Row: Equatable, Identifiable {
        var kind: Kind
        var status: Status
        var location: String
        var id: String { kind.rawValue }
    }

    var rows: [Row]

    /// - Parameters:
    ///   - claudeHomes / codexHomes: every provider config folder, the default one first.
    static func detect(home: URL, claudeHomes: [URL], codexHomes: [URL], probe: BrimFileProbe) -> BrimIntegrationsReport {
        let tilde = { (path: String) in brimTildePath(path, home: home) }
        var rows: [Row] = []

        rows.append(Row(kind: .cli,
                        status: probe.exists(BrandPaths.cliLinkPath) ? .installed : .notInstalled,
                        location: BrandPaths.cliLinkPath))

        // MCP: the top-level `mcpServers` of each `.claude.json` (the default home keeps its file
        // beside the folder), and Codex's `[mcp_servers.*]` tables.
        var mcp: [Finding] = claudeHomes.map { folder in
            let file = folder.lastPathComponent == ".claude"
                ? home.appendingPathComponent(".claude.json") : folder.appendingPathComponent(".claude.json")
            return json(probe.read(file.path)) { object in
                let servers = (object["mcpServers"] as? [String: Any])?.keys.map { $0.lowercased() } ?? []
                return verdict(servers.contains(BrandPaths.mcpServerName))
            }
        }
        mcp += codexHomes.map { folder in
            text(probe.read(folder.appendingPathComponent("config.toml").path)) { body in
                let headers = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("[mcp_servers.") }
                return verdict(headers.contains { $0.hasPrefix("[mcp_servers.\(BrandPaths.mcpServerName)") })
            }
        }
        rows.append(Row(kind: .mcp, status: fold(mcp), location: "\(BrandPaths.cliName) mcp · stdio"))

        let settings = claudeHomes.map { $0.appendingPathComponent("settings.json").path }
        let statusLine: [Finding] = settings.map { path in
            json(probe.read(path)) { object in
                let command = (object["statusLine"] as? [String: Any])?["command"] as? String ?? ""
                return verdict(mentionsBrim(command))
            }
        }
        rows.append(Row(kind: .statusLine, status: fold(statusLine),
                        location: settings.first.map(tilde) ?? "~/.claude/settings.json"))

        let hooks: [Finding] = settings.map { path in
            json(probe.read(path)) { object in
                let commands = commandStrings(object["hooks"] ?? [:])
                return verdict(commands.contains(where: mentionsBrim))
            }
        }
        rows.append(Row(kind: .hooks, status: fold(hooks),
                        location: settings.first.map(tilde) ?? "~/.claude/settings.json"))

        // Codex session hooks live in each home's hooks.json; an older notify line in config.toml.
        var codex: [Finding] = codexHomes.map { folder in
            json(probe.read(folder.appendingPathComponent("hooks.json").path)) { object in
                let commands = commandStrings(object["hooks"] ?? [:])
                return verdict(commands.contains(where: mentionsBrim))
            }
        }
        codex += codexHomes.map { folder in
            text(probe.read(folder.appendingPathComponent("config.toml").path)) { body in
                let lines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.hasPrefix("#") && !$0.hasPrefix("[mcp_servers.") && $0.hasPrefix("notify") }
                return verdict(lines.contains(where: mentionsBrim))
            }
        }
        rows.append(Row(kind: .codex, status: fold(codex),
                        location: codexHomes.first.map { tilde($0.appendingPathComponent("hooks.json").path) }
                            ?? "~/.codex/hooks.json"))

        let shimNames = ["claude", "codex"]
        let shims = home.appendingPathComponent(BrandPaths.stateDirName).appendingPathComponent("bin")
        let ours = shimNames.contains { probe.exists(shims.appendingPathComponent($0).path) }
        rows.append(Row(kind: .shims, status: ours ? .installed : .notInstalled, location: tilde(shims.path)))
        return BrimIntegrationsReport(rows: rows)
    }

    /// One file's answer: nil = the file is absent, which says nothing either way.
    private typealias Finding = Status?

    private static func verdict(_ usagebar: Bool) -> Status {
        usagebar ? .installed : .notInstalled
    }

    /// An unreadable home must stay visible.
    private static func fold(_ findings: [Finding]) -> Status {
        let known = findings.compactMap { $0 }
        if known.contains(.unreadable) { return .unreadable }
        if known.contains(.installed) { return .installed }
        return .notInstalled
    }

    private static func json(_ read: BrimFileProbe.Read, _ judge: ([String: Any]) -> Status) -> Finding {
        switch read {
        case .missing: return nil
        case .unreadable: return .unreadable
        case .data(let data):
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unreadable
            }
            return judge(object)
        }
    }

    private static func text(_ read: BrimFileProbe.Read, _ judge: (String) -> Status) -> Finding {
        switch read {
        case .missing: return nil
        case .unreadable: return .unreadable
        case .data(let data):
            guard let body = String(data: data, encoding: .utf8) else { return .unreadable }
            return judge(body)
        }
    }

    /// Every `"command"` string anywhere under `value`.
    static func commandStrings(_ value: Any) -> [String] {
        switch value {
        case let dict as [String: Any]:
            return dict.flatMap { key, inner -> [String] in
                if key == "command", let text = inner as? String { return [text] }
                return commandStrings(inner)
            }
        case let list as [Any]:
            return list.flatMap(commandStrings)
        default:
            return []
        }
    }

    /// `usagebar` as a command word or path end, or anything under `~/.usagebar`.
    static func mentionsBrim(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains(BrandPaths.stateDirName + "/") { return true }
        return lower.range(of: #"(^|[\s/"'])usagebar($|[\s"'])"#, options: .regularExpression) != nil
    }
}

// Selected windows use snapshot account IDs, never labels or transient row positions.
struct BrimMenuSelection: Equatable {
    enum Window: String, CaseIterable { case fiveHour, weekly, fable }
    var windows: [String: [String]] = [:]
    var showLabels = false

    func contains(_ id: String, _ window: Window) -> Bool {
        windows[id]?.contains(window.rawValue) == true
    }

    mutating func set(_ id: String, _ window: Window, enabled: Bool) {
        var values = windows[id] ?? []
        if enabled {
            if !values.contains(window.rawValue) { values.append(window.rawValue) }
        } else { values.removeAll { $0 == window.rawValue } }
        windows[id] = values.isEmpty ? nil : values
    }

    func pruned(rows: [BrimPanelModel.Row]) -> BrimMenuSelection {
        var result = self
        result.windows = [:]
        for row in rows {
            let valid = (windows[row.id] ?? []).filter {
                Window(rawValue: $0) != nil
            }
            if !valid.isEmpty { result.windows[row.id] = valid }
        }
        return result
    }

    struct Segment: Equatable {
        var id: String
        var provider: String
        var label: String?
        var text: String
    }

    func tightestRemaining(rows: [BrimPanelModel.Row]) -> Double? {
        let selection = pruned(rows: rows)
        return rows.flatMap { row -> [Double] in
            let cells: [(Window, BrimPanelModel.Cell?)] = [
                (.fiveHour, row.fiveHour), (.weekly, row.weekly), (.fable, row.model?.cell)
            ]
            return cells.filter { selection.contains(row.id, $0.0) }.compactMap { $0.1?.remaining }
        }.min()
    }

    func segments(rows: [BrimPanelModel.Row], used: Bool,
                  format: BrimPanelModel.Format = .init()) -> [Segment] {
        let selection = pruned(rows: rows)
        return rows.compactMap { row in
            let cells: [(Window, BrimPanelModel.Cell?)] = [
                (.fiveHour, row.fiveHour), (.weekly, row.weekly), (.fable, row.model?.cell)
            ]
            let values = cells.filter { selection.contains(row.id, $0.0) }.compactMap { _, cell -> String? in
                guard let cell, cell.remaining != nil else { return nil }
                return cell.displayed(used: used, format: format).percentText
            }
            guard !values.isEmpty else { return nil }
            return Segment(id: row.id, provider: row.provider,
                           label: showLabels ? String(row.label.prefix(8)) : nil,
                           text: values.joined(separator: " · "))
        }
    }
}
