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
if failures > 0 {
    print("brimsettings: \(failures) of \(checks) checks FAILED")
    exit(1)
}
print("PASS: brimsettings \(checks) checks")
