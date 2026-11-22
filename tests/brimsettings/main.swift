import Foundation

// UsageBar settings model: menu bar text modes, the accounts table and the read-only integration
// check, against fixtures and a pretend disk. Never reads user data.

var failures = 0
var checks = 0
func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

let format = BrimPanelModel.Format(timeZone: TimeZone(identifier: "UTC")!)
let now = BrimFixtures.now
typealias F = BrimSettingsFixtures

// MARK: Menu bar text

do {
    let snapshot = BrimFixtures.normal()
    let glyph = BrimPanelModel.make(snapshot: snapshot, readFailed: false, loaded: true, now: now, format: format).glyph
    expect(BrimMenuBarText.text(.glyph, glyph: glyph, snapshot: snapshot, now: now, format: format) == nil,
           "glyph-only shows no text")
    expect(BrimMenuBarText.text(.percent, glyph: glyph, snapshot: snapshot, now: now, format: format) == glyph.text,
           "percent shows the glyph's percentage")
    // Spare has the most headroom (min(94, 73) = 73); its 5h resets in 291 min.
    expect(BrimMenuBarText.bestAccount(snapshot)?.id == "claude:.claude3", "best account is Spare")
    expect(BrimMenuBarText.text(.countdown, glyph: glyph, snapshot: snapshot, now: now, format: format) == "4:51",
           "countdown is the best account's 5h reset")

    let limited = BrimFixtures.allLimited
    let wall = BrimPanelModel.make(snapshot: limited, readFailed: false, loaded: true, now: now, format: format).glyph
    expect(wall.kind == .allLimited && wall.text != nil, "fixture is all-limited with a countdown")
    for mode in BrimMenuBarText.allCases {
        expect(BrimMenuBarText.text(mode, glyph: wall, snapshot: limited, now: now, format: format) == wall.text,
               "all-limited keeps its countdown in \(mode)")
    }

    // No 5h reset known: countdown falls back to the percentage.
    let shape = BrimFixtures.noFiveHourCodex
    let shapeGlyph = BrimPanelModel.make(snapshot: shape, readFailed: false, loaded: true, now: now, format: format).glyph
    expect(BrimMenuBarText.text(.countdown, glyph: shapeGlyph, snapshot: shape, now: now, format: format) == shapeGlyph.text,
           "countdown without a 5h reset falls back to the percentage")
    expect(BrimMenuBarText.text(.countdown, glyph: BrimPanelModel.Glyph(kind: .empty, fill: 0, dashed: true, text: nil),
                                snapshot: nil, now: now, format: format) == nil, "no snapshot, no text")
}

// MARK: Accounts table

do {
    let probe = F.probe(F.usageBarInstalled)
    let table = BrimAccountsTable.make(snapshot: BrimFixtures.normal(), folders: F.folders, home: F.home, probe: probe)
    expect(table.groups.map(\.id) == ["claude", "codex"], "groups by provider, Claude first")
    expect(table.count == 5, "five accounts")
    expect(table.groups[0].rows.map(\.folder) == ["~/.claude", "~/.claude2", "~/.claude3"], "folders from ids")
    expect(table.groups[0].rows.allSatisfy { $0.login == .signedIn }, "fresh rows read as signed in")
    expect(table.untracked == ["~/.claude-old"], "only account-shaped untracked folders: \(table.untracked)")

    let empty = BrimAccountsTable.make(snapshot: nil, folders: [], home: F.home, probe: probe)
    expect(empty.groups.isEmpty && empty.count == 0, "no snapshot, no rows")

    expect(table.groups.flatMap(\.rows).allSatisfy { !$0.strandedCodexAttempt }, "no stranded Codex attempt by default")
    let codexID = table.groups[1].rows[0].id
    let stranded = BrimAccountsTable.make(snapshot: BrimFixtures.normal(), folders: F.folders, home: F.home, probe: probe,
                                          strandedCodexAttempts: [codexID])
    expect(stranded.groups.flatMap(\.rows).filter(\.strandedCodexAttempt).map(\.id) == [codexID],
           "only the named Codex row offers clearing its stranded attempt")

    var account = BrimFixtures.normal().accounts[0]
    account.launchHome = "/Users/demo/.claude-main"
    expect(BrimAccountsTable.folder(account, home: F.home) == "~/.claude-main", "launch home wins, tilde-shortened")
    account.error = "Not logged in · Please run /login"
    expect(BrimAccountsTable.login(account) == .needsSignIn, "auth error reads as sign-in needed")
    account.error = "timed out"
    expect(BrimAccountsTable.login(account) == .error, "other error stays an error")
    account.error = nil
    account.lastRefreshFailed = true
    expect(BrimAccountsTable.login(account) == .heldOver, "failed poll reads as held over")
}

// MARK: Integrations

func status(_ report: BrimIntegrationsReport, _ kind: BrimIntegrationsReport.Kind) -> BrimIntegrationsReport.Status? {
    report.rows.first { $0.kind == kind }?.status
}

do {
    let report = BrimIntegrationsReport.detect(home: F.home, claudeHomes: F.claudeHomes, codexHomes: F.codexHomes,
                                               probe: F.probe(F.usageBarInstalled))
    expect(report.rows.map(\.kind) == BrimIntegrationsReport.Kind.allCases, "one row per integration, in order")
    expect(status(report, .cli) == .installed, "usagebar CLI link")
    expect(status(report, .mcp) == .installed, "usagebar MCP entry in ~/.claude.json")
    expect(status(report, .statusLine) == .installed, "usagebar status line")
    expect(status(report, .hooks) == .installed, "usagebar hooks")
    expect(status(report, .codex) == .installed, "usagebar Codex hooks.json")
    expect(status(report, .shims) == .notInstalled, "no shims")
    expect(report.rows.first { $0.kind == .shims }?.location == "~/.usagebar/bin", "shim folder under the given home")
    expect(report.rows.first { $0.kind == .statusLine }?.location == "~/.claude/settings.json", "tilde location")

    let bare = BrimIntegrationsReport.detect(home: F.home, claudeHomes: F.claudeHomes, codexHomes: F.codexHomes,
                                             probe: F.probe([:]))
    expect(bare.rows.allSatisfy { $0.status == .notInstalled }, "nothing on disk reads as not installed")

    // A file that exists but cannot be read is not "not installed".
    var unreadable = [String: String?]()
    unreadable[F.path(".claude/settings.json")] = .some(nil)
    unreadable[F.path(".claude.json")] = .some("{ not json")
    let blind = BrimIntegrationsReport.detect(home: F.home, claudeHomes: [F.folder(".claude")], codexHomes: [],
                                              probe: F.probe(unreadable))
    expect(status(blind, .statusLine) == .unreadable, "unreadable settings.json")
    expect(status(blind, .mcp) == .unreadable, "unparseable .claude.json")

    // One home is enough for a row to read installed.
    var both = F.usageBarInstalled
    both[F.path(".claude3/settings.json")] = #"{"statusLine": {"command": "~/.usagebar/bin/usagebar statusline"}}"#
    both[F.path(".codex2/config.toml")] = "notify = [\"/usr/local/bin/usagebar\", \"notify\"]\n[mcp_servers.usagebar]\ncommand = \"usagebar\"\n"
    let mixed = BrimIntegrationsReport.detect(home: F.home, claudeHomes: F.claudeHomes, codexHomes: F.codexHomes,
                                              probe: F.probe(both))
    expect(status(mixed, .statusLine) == .installed, "a UsageBar status line in any home")
    expect(status(mixed, .mcp) == .installed, "Codex [mcp_servers.usagebar]")
    expect(status(mixed, .codex) == .installed, "Codex notify line naming usagebar")

    expect(BrimIntegrationsReport.mentionsBrim("/usr/local/bin/usagebar statusline"), "usagebar path")
    expect(BrimIntegrationsReport.mentionsBrim("usagebar mcp"), "bare usagebar")
    expect(!BrimIntegrationsReport.mentionsBrim("/opt/brimstone/run"), "brimstone is not usagebar")
    expect(BrimIntegrationsReport.commandStrings(["a": [["command": "x"], ["b": ["command": "y"]]]]).sorted() == ["x", "y"],
           "command strings at any depth")
}

expect(brimTildePath("/Users/demo/.claude", home: F.home) == "~/.claude", "tilde")
expect(brimTildePath("/Users/demox/.claude", home: F.home) == "/Users/demox/.claude", "tilde needs a separator")


let selectionRows = BrimPanelModel.make(snapshot: BrimFixtures.normal(), readFailed: false,
    loaded: true, now: BrimFixtures.now).groups.flatMap(\.rows)
var selection = BrimMenuSelection()
let selectedRow = selectionRows[0]
selection.set(selectedRow.id, .fiveHour, enabled: true)
selection.set(selectedRow.id, .weekly, enabled: true)
expect(selection.segments(rows: selectionRows, used: false).first?.text == "62% · 39%",
      "selected menu windows follow remaining mode")
expect(selection.segments(rows: selectionRows, used: true).first?.text == "38% · 61%",
      "selected menu windows follow used mode")
expect(selection.pruned(rows: []).windows.isEmpty, "deleted account drops from selection")
for row in selectionRows { selection.set(row.id, .weekly, enabled: true) }
expect(selectionRows.count > 4 && selection.windows.count == selectionRows.count,
       "all accounts can be selected beyond four")
expect(selection.pruned(rows: selectionRows).windows.count == selectionRows.count,
       "pruning preserves every selected account")
selection.showLabels = true
expect(selection.segments(rows: selectionRows, used: false).first?.label == selectedRow.label,
      "optional account labels")
var missingRow = selectedRow
missingRow.fiveHour = BrimPanelModel.cell(nil)
expect(selection.segments(rows: [missingRow], used: true).first?.text == "61%",
      "missing window has no invented percentage")
var modelSelection = BrimMenuSelection()
modelSelection.set(selectedRow.id, .fable, enabled: true)
missingRow.model = nil
expect(modelSelection.segments(rows: [missingRow], used: false).isEmpty,
       "unavailable selected windows produce no segment")
expect(BrimMenuBarText.showsCup(.selected, segments: modelSelection.segments(rows: [missingRow], used: false)),
       "all unavailable readings fall back to the mark")
expect(modelSelection.pruned(rows: [missingRow]).contains(selectedRow.id, .fable),
       "only deleted accounts lose preferences")
// Menu bar colours: fine from half left, watch from a fifth, low below.
expect(BrimMenuSelection.Part(window: .weekly, value: "", remaining: 50).tone == .fine, "50% left is fine")
expect(BrimMenuSelection.Part(window: .weekly, value: "", remaining: 43).tone == .watch, "43% left is worth a glance")
expect(BrimMenuSelection.Part(window: .weekly, value: "", remaining: 19).tone == .low, "under a fifth is low")
expect(BrimMenuSelection.Part(window: .weekly, value: "").tone == nil, "no reading, no colour")

// Plan renewals (SubscriptionRenewal): the shapes measured live on 2026-11-22.
let renewalNow = SubscriptionRenewal.date("2026-11-22T12:00:00Z")!
let chatgptBody = Data(#"{"entitlement":{"renews_at":"2027-01-31T08:32:58+00:00","cancels_at":null,"billing_period":"yearly"},"active_until":"2027-01-31T08:32:58Z","billing_period":"yearly","will_renew":true}"#.utf8)
let chatgpt = SubscriptionRenewal.chatGPT(chatgptBody, now: renewalNow)
expect(chatgpt?.interval == .yearly && chatgpt?.willRenew == true, "ChatGPT: yearly, renewing")
expect(chatgpt?.nextRenewal(now: renewalNow) == SubscriptionRenewal.date("2027-01-31T08:32:58Z"), "ChatGPT: renews_at as stated")
let cancelledBody = Data(#"{"entitlement":{"renews_at":null,"cancels_at":"2026-12-05T00:00:00Z"},"will_renew":false}"#.utf8)
let cancelled = SubscriptionRenewal.chatGPT(cancelledBody, now: renewalNow)
expect(cancelled?.nextRenewal(now: renewalNow) == nil && cancelled?.accessEnds(now: renewalNow) == SubscriptionRenewal.date("2026-12-05T00:00:00Z"),
       "ChatGPT: a cancelled plan shows when it ends, not a renewal")
expect(SubscriptionRenewal.chatGPT(Data(#"{"plan_type":"free"}"#.utf8), now: renewalNow) == nil, "ChatGPT: no date, no renewal")
let claudeBody = Data(#"{"status":"active","next_charge_date":"2026-12-08","billing_interval":"monthly","currency":"USD"}"#.utf8)
let claudeRenewal = SubscriptionRenewal.claude(claudeBody, now: renewalNow)
expect(claudeRenewal?.interval == .monthly && claudeRenewal?.nextRenewal(now: renewalNow) == SubscriptionRenewal.date("2026-12-08"),
       "Claude: next_charge_date and billing_interval")
// Read on 22 Nov, shown on 10 Dec: the 8 Dec charge has happened, so the next one is 8 Jan.
let later = SubscriptionRenewal.date("2026-12-10T00:00:00Z")!
expect(claudeRenewal?.nextRenewal(now: later) == SubscriptionRenewal.date("2027-01-08"), "monthly rolls forward a month")
var noInterval = claudeRenewal!; noInterval.interval = nil
expect(noInterval.nextRenewal(now: later) == nil, "a past date without a period is not guessed forward")
expect(SubscriptionRenewal.claude(Data(#"{"status":"active","plan_ending_at":"2026-12-01T00:00:00Z"}"#.utf8), now: renewalNow)?.accessEnds(now: renewalNow) != nil,
       "Claude: plan_ending_at is an end, not a renewal")
expect(SubscriptionRenewal.date("2026-11-03T09:37:28.897130+00:00") != nil, "six-digit fractions parse")

// Renewal reminders: three days ahead, once per date.
let soon = SubscriptionRenewal.date("2026-12-06T00:00:00Z")!
let reminders = RenewalReminder.due(["max": claudeRenewal!, "gone": cancelled!], sent: [:], now: soon)
expect(reminders.map(\.accountID) == ["max"] && reminders.first?.kind == .renews, "a renewal two days off is due; an end past is not")
expect(RenewalReminder.due(["max": claudeRenewal!], sent: ["max": reminders[0].stamp], now: soon).isEmpty, "warned once per date")
expect(RenewalReminder.due(["max": claudeRenewal!], sent: [:], now: renewalNow).isEmpty, "sixteen days off is not due yet")
let endsSoon = RenewalReminder.due(["gone": cancelled!], sent: [:], now: SubscriptionRenewal.date("2026-12-03T00:00:00Z")!)
expect(endsSoon.first?.kind == .ends, "a cancelled plan warns before access ends")

// Usage tab breakdown.
func usageCell(_ day: Int, _ project: String, _ provider: String = "claude", _ model: String = "claude-opus-5-5",
               cost: Double? = 1, tokens: Int64 = 100) -> UsageBreakdown.Cell {
    UsageBreakdown.Cell(day: day, project: project, providerID: provider, model: model, cost: cost, tokens: tokens, output: tokens / 10)
}
let usageToday = 20_000
let usageCells = [
    usageCell(20_000, "/p/a", cost: 3), usageCell(19_999, "/p/b", cost: 1),
    usageCell(19_996, "/p/a", cost: 2), usageCell(19_993, "/p/a", cost: 9), // 19_993 is outside 7 days, inside the previous 7
    usageCell(20_000, "/p/c", "codex", "gpt-6.2-astra", cost: nil, tokens: 500),
    usageCell(19_987, "/p/z", cost: 0, tokens: 0), // the history reaches the previous window's first day
]
let week = UsageBreakdown.make(cells: usageCells, group: .project, dayCount: 7, today: usageToday)
expect(week.totals.cost == 6 && week.totals.tokens == 800 && week.totals.unpricedTokens == 500, "usage: window totals, unpriced kept apart")
expect(week.previous?.cost == 9, "usage: previous window of equal length")
expect(week.bars.count == 7 && week.bars.last?.day == usageToday, "usage: one bar per day, idle days included")
expect(week.rows.map(\.key) == ["/p/a", "/p/b", "/p/c"] && week.rows.first?.share == 5.0 / 6.0, "usage: rows by cost, share of cost")
expect(UsageBreakdown.change(week.totals.cost, week.previous?.cost) == -33, "usage: change in percent")
let shortHistory = UsageBreakdown.make(cells: Array(usageCells.dropLast()), group: .project, dayCount: 7, today: usageToday)
expect(shortHistory.previous == nil && shortHistory.rows.allSatisfy { $0.previous == nil }, "usage: no comparison when the history is shorter than two windows")
let models = UsageBreakdown.make(cells: usageCells, group: .model, dayCount: nil, today: usageToday)
expect(!models.monthly && models.previous == nil && models.rows.count == 2 && models.bars.count == 14, "usage: a short All is daily, no comparison")
let longAll = UsageBreakdown.make(cells: usageCells + [usageCell(19_700, "/p/a")], group: .model, dayCount: nil, today: usageToday)
expect(longAll.monthly && longAll.bars.count <= 12, "usage: a long All is monthly")
let many = (0..<14).map { usageCell(usageToday, "/p/\($0)", cost: Double($0 + 1)) }
let pooled = UsageBreakdown.make(cells: many, group: .project, dayCount: 1, today: usageToday)
expect(pooled.rows.count == UsageBreakdown.rowLimit && pooled.rows.last?.key == UsageBreakdown.otherKey
       && pooled.rows.reduce(0) { $0 + $1.totals.cost } == pooled.totals.cost, "usage: the tail pools into Other and still adds up")
expect(pooled.rows.last?.members == 14 - UsageBreakdown.rowLimit + 1, "usage: the pooled row counts what it holds")
let scratch = UsageBreakdown.make(cells: [usageCell(usageToday, "/Users/u/Library/Application Support/Claude/x/scratch-1"),
                                          usageCell(usageToday, "/Users/u/Library/Application Support/Claude/y/scratch-2")],
                                  group: .project, dayCount: 1, today: usageToday)
expect(scratch.rows.map(\.key) == [UsageBreakdown.claudeAppKey], "usage: Claude app scratch folders are one row")
expect(UsageBreakdown.modelName("claude-opus-5-5") == "Opus 5.5" && UsageBreakdown.modelName("claude-haiku-4-5-20251001") == "Haiku 4.5"
       && UsageBreakdown.modelName("gpt-6.2-astra") == "GPT-6.2 Astra", "usage: model names")
expect(TokenCount.short(950) == "950" && TokenCount.short(12_400, locale: Locale(identifier: "en")) == "12.4K"
       && TokenCount.short(3_100_000_000, locale: Locale(identifier: "en")) == "3.1B", "usage: short token counts")

if failures > 0 {
    print("brimsettings: \(failures) of \(checks) checks FAILED")
    exit(1)
}
print("PASS: brimsettings \(checks) checks")
