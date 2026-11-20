import Foundation

// UsageBar panel model: UsageBar snapshot -> rows, tightest, thresholds, resets, glyph, layout, Turkish formats.
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}

let now = BrimFixtures.now
let utc = BrimPanelModel.Format(timeZone: TimeZone(identifier: "UTC")!)
func model(_ snapshot: UsageSnapshot?, failed: Bool = false, loaded: Bool = true,
           claudeResets: [String: BrimPanelModel.ClaudeResets] = [:]) -> BrimPanelModel {
    BrimPanelModel.make(snapshot: snapshot, readFailed: failed, loaded: loaded, now: now,
                        claudeResets: claudeResets, format: utc)
}
func row(_ m: BrimPanelModel, _ name: String) -> BrimPanelModel.Row? {
    m.groups.flatMap(\.rows).first { $0.name == name }
}

var zeroRow = row(model(BrimFixtures.normal()), "Backoffice")!
check(zeroRow.hasNoResetCredits, "known zero credits")
zeroRow.resetCredits = nil
check(!zeroRow.hasNoResetCredits, "unknown credits are not zero")
zeroRow.resetCredits = .init(id: zeroRow.id, count: 0, expires: nil, expiryUnknown: false, heldOver: true)
check(!zeroRow.hasNoResetCredits, "failed read of previous zero is unknown")

let usedCell = BrimPanelModel.cell(9).displayed(used: true)
check(usedCell.percentText == "91%" && usedCell.fill == 0.91 && usedCell.level == .critical,
      "used percentage and fill preserve remaining severity")
check(usedCell.displayed(used: false).percentText == "9%", "display conversion is reversible")
check(BrimPanelModel.cell(nil).displayed(used: true).remaining == nil, "missing data stays missing")
print("thresholds")
check(BrimPanelModel.level(31) == .plenty && BrimPanelModel.level(30) == .low
          && BrimPanelModel.level(10) == .low && BrimPanelModel.level(9.5) == .critical
          && BrimPanelModel.level(0) == .limit, ">30 plenty, 10-30 low, <10 critical, 0 limit")

print("normal fleet")
let normal = model(BrimFixtures.normal())
check(normal.updated == "14:13" && normal.banner == nil && !normal.dimmed && normal.body == .accounts,
      "fresh snapshot: updated time, no banner, not dimmed")
check(normal.groups.map(\.id) == ["claude", "codex"], "Claude group, then Codex")
check(normal.groups.map { $0.rows.count } == [3, 2], "three and two accounts")
let main = row(normal, "Main")!
check(main.fiveHour.percentText == "62%" && main.fiveHour.level == .plenty && main.fiveHour.fill == 0.62,
      "5h cell shows remaining with the bar filled to it")
check(main.fiveHourReset == .init(relative: "2h 14m", withinDay: true, clock: "16:28"), "5h reset relative + clock")
check(main.weeklyReset?.withinDay == false && main.label == "Main" && main.home == nil, "weekly beyond a day; unique label has no home")
check(main.weeklyReset?.clock.hasPrefix("Thu") == true || main.weeklyReset?.clock.contains(" ") == true,
      "a reset beyond a day carries its weekday (\(main.weeklyReset?.clock ?? "nil"))")
check(main.model?.name == "Fable" && main.model?.cell.percentText == "28%", "model window line")
check(main.resetCredits == nil, "Claude: no reset data, so no count")
check(row(normal, "Work")!.fiveHour.level == .critical && row(normal, "Work")!.fiveHourReset?.relative == "47m",
      "Work 9% is critical")
check(row(normal, "Spare")!.isBest && !main.isBest, "best Claude is Spare (most headroom)")
check(row(normal, "Info")!.isBest, "best Codex is Info")
let backoffice = row(normal, "Backoffice")!
check(backoffice.fiveHour.level == .limit && backoffice.fiveHour.percentText == "0%" && backoffice.headroom == 0,
      "Backoffice at its 5h limit is a limit cell (the view says Limit)")
check(row(normal, "Info")!.resetCredits?.count == 2 && row(normal, "Info")!.resetCredits?.expires == "12 Dec",
      "Codex reset bank: count and expiry")
check(backoffice.resetCredits?.count == 0, "a reported empty bank is zero, not missing")
check(normal.tightest?.accountName == "Backoffice" && normal.tightest?.window == .fiveHour
          && normal.tightest?.remaining == 0 && normal.tightest?.level == .limit,
      "tightest: the window with least left anywhere")
check(normal.glyph == .init(kind: .normal, fill: 0.73, dashed: false, text: "73%",
                           fiveHourFill: 0.94, weeklyFill: 0.73),
      "glyph: best account's headroom (\(normal.glyph))")

print("one account at its limit, the rest fine")
let oneLimit = model(BrimFixtures.normal(backofficeFive: 0))
check(oneLimit.glyph.kind == .normal && oneLimit.tightest?.level == .limit, "one wall does not empty the mark")

print("every account limited")
let limited = model(BrimFixtures.allLimited)
check(limited.glyph.kind == .allLimited && limited.glyph.fill == 0,
      "empty mark when no account has headroom")
check(limited.glyph.text == "1:32", "countdown to the earliest account that opens (\(limited.glyph.text ?? "nil"))")
check(limited.groups.allSatisfy { group in group.rows.allSatisfy { !$0.isBest } }, "no best pick among walls")

print("stale snapshot")
let stale = model(BrimFixtures.normal(generatedMinutesAgo: 14))
check(stale.banner == .stale(minutes: 14) && stale.dimmed && stale.glyph.dashed && stale.glyph.text == "73%",
      "stale: banner with age, dimmed, dashed glyph keeps the last value")
check(model(BrimFixtures.normal(generatedMinutesAgo: 9)).banner == nil, "nine minutes is still fresh")

print("unreadable snapshot")
let unreadable = model(nil, failed: true)
check(unreadable.banner == .unavailable && unreadable.body == .noData && unreadable.groups.isEmpty,
      "never read: error banner, no rows")
check(unreadable.glyph == .init(kind: .empty, fill: 0, dashed: true, text: nil), "glyph: dashed, no number")
let lastGood = model(BrimFixtures.normal(), failed: true)
check(lastGood.banner == .unavailable && lastGood.dimmed && lastGood.groups.count == 2,
      "read failed after a good read: last values kept, dimmed")
let loading = model(nil, loaded: false)
check(loading.body == .loading && loading.banner == nil, "before the first read: loading, no error")

print("reset data present / absent")
let usageBarShape = model(BrimFixtures.noFiveHourCodex)
let codexGroup = usageBarShape.groups.first { $0.id == "codex" }!
check(codexGroup.rows.map(\.name) == ["Codex 100 (.codex)", "Codex 100 (.codex2)"], "duplicate labels get their home")
check(codexGroup.rows.map(\.label) == ["Codex 100", "Codex 100"] && codexGroup.rows.map(\.home) == [".codex", ".codex2"],
      "…and the row keeps label and home apart")
check(codexGroup.rows.allSatisfy { $0.fiveHour.remaining == nil && $0.fiveHour.percentText == "—" && $0.fiveHourReset == nil },
      "no 5h reading is a dash, never 0%")
check(codexGroup.weeklyOnly && !usageBarShape.groups[0].weeklyOnly,
      "Codex with no 5h anywhere is a weekly-only group; Claude is not")
check(codexGroup.rows.allSatisfy { $0.resetWindow == .weekly && $0.reset != nil && $0.reset == $0.weeklyReset },
      "no 5h window: the reset column shows the weekly reset")
check(codexGroup.rows[0].reset == .init(relative: "1d 22h", withinDay: false, clock: "Mon 12:54"),
      "weekly reset beyond a day: relative on top, weekday clock below (\(String(describing: codexGroup.rows[0].reset)))")
check(usageBarShape.groups[0].rows[0].resetWindow == .fiveHour, "an account with a 5h window keeps the 5h reset column")
check(normal.groups.allSatisfy { !$0.weeklyOnly } && main.resetWindow == .fiveHour && main.reset == main.fiveHourReset,
      "fleet with 5h windows: 5h reset column, not weekly-only")
let mixed = model(BrimFixtures.snapshot([
    BrimFixtures.codex(".codex", "A", plan: "Pro", five: 50, fiveIn: 60, weekly: 40, weeklyIn: 3000, credits: nil),
    BrimFixtures.codex(".codex2", "B", plan: "Pro", weekly: 30, weeklyIn: 4000, credits: nil),
]))
check(!mixed.groups[0].weeklyOnly && row(mixed, "B")?.resetWindow == .weekly && row(mixed, "A")?.resetWindow == .fiveHour,
      "mixed group: per-row reset window, group keeps its 5h column")
check(usageBarShape.groups[0].rows[0].resetCredits == nil, "Claude row: no reset button data")
check(usageBarShape.tightest?.window == .weekly && usageBarShape.tightest?.remaining == 5
          && usageBarShape.tightest?.accountName == "Codex 100 (.codex2)",
      "tightest tie on 5% goes to the window that stays shut longer")
check(usageBarShape.glyph.text == "35%", "glyph caps a full 5h by the weekly behind it")
let noResets = model(BrimFixtures.noResetData)
check(noResets.groups.flatMap(\.rows).allSatisfy { $0.resetCredits == nil },
      "no reset data anywhere: no reset data on any row")


print("model window column and Claude resets")
check(normal.groups[0].modelColumn == "Fable" && normal.groups[1].modelColumn == nil,
      "Claude group gets a Fable column, Codex none")
check(row(normal, "Work")!.model == nil && main.model?.cell.percentText == "28%",
      "an account without the window has an empty cell")
let withResets = model(BrimFixtures.normal(), claudeResets: BrimFixtures.claudeResets)
let mainResets = row(withResets, "Main")!.resetCredits
check(mainResets?.count == 2 && mainResets?.lines.map(\.kind) == [.full, .fable]
          && mainResets?.lines.map(\.expires) == ["10 Dec", "9 Mar"],
      "Claude: full and Fable listed apart with their expiry")
check(row(withResets, "Work")!.resetCredits?.count == 0 && row(withResets, "Work")!.resetUnknown == nil,
      "Claude: the server said 0, so 0")
check(row(withResets, "Spare")!.resetCredits == nil && row(withResets, "Spare")!.resetUnknown == .loginExpiring,
      "Claude: unknown is not 0 (no count, a reason)")
check(row(withResets, "Info")!.resetCredits?.lines.map(\.kind) == [.codex, .codex], "Codex: one line per reset credit")
check(row(normal, "Main")!.resetCredits == nil && row(normal, "Main")!.resetUnknown == nil,
      "without UsageBar's read, Claude rows show no reset data")
let mixedModels = model(BrimFixtures.snapshot([
    BrimFixtures.claude(".claude", "A", plan: "Max", five: 50, fiveIn: 60, weekly: 40, weeklyIn: 3000, fable: 30, fableIn: 3000),
    BrimFixtures.claude(".claude2", "B", plan: "Max", five: 50, fiveIn: 60, weekly: 40, weeklyIn: 3000, fable: 20,
                        fableIn: 3000, modelName: "Opus"),
]))
check(mixedModels.groups[0].modelColumn == "Model", "two different model windows share a Model column")

print("zero accounts")
let empty = model(BrimFixtures.empty)
check(empty.body == .noAccounts && empty.groups.isEmpty && empty.tightest == nil,
      "valid empty snapshot: empty state, no tightest")
check(empty.glyph == .init(kind: .empty, fill: 0, dashed: false, text: nil), "glyph: outline only, no 0%")

print("formatting")
check(utc.duration(until: now.addingTimeInterval(47 * 60), now: now) == "47m", "under an hour: 47m")
check(utc.duration(until: now.addingTimeInterval(134 * 60), now: now) == "2h 14m", "2h 14m")
check(utc.duration(until: now.addingTimeInterval(-60), now: now) == nil, "a passed reset has no countdown")
check(utc.duration(until: now.addingTimeInterval(47 * 3600), now: now) == "1d 23h", "beyond a day: 1d 23h")
check(utc.countdown(now.addingTimeInterval(92 * 60), now: now) == "1:32", "menu bar countdown h:mm")

print("Turkish formats")
let tr = BrimPanelModel.Format(timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "tr"))
check(tr.duration(until: now.addingTimeInterval((3 * 60 + 47) * 60), now: now) == "3 sa 47 dk", "3 sa 47 dk")
check(tr.duration(until: now.addingTimeInterval(47 * 60), now: now) == "47 dk", "47 dk")
check(tr.duration(until: now.addingTimeInterval(47 * 3600), now: now) == "1 g 23 sa", "1 g 23 sa")
check(tr.duration(until: now.addingTimeInterval(48 * 3600), now: now) == "2 g", "whole days: 2 g")
check(tr.countdown(now.addingTimeInterval(52 * 3600), now: now) == "2 g 4 sa", "menu bar countdown beyond a day: 2 g 4 sa")
check(tr.countdown(now.addingTimeInterval(92 * 60), now: now) == "1:32", "menu bar countdown h:mm stays")
// 2026-11-14 is a Saturday; 2026-11-18 a Wednesday.
let wednesday = now.addingTimeInterval(4 * 86400 - (14 * 60 + 14) * 60 + (12 * 60 + 9) * 60)
check(tr.clock(wednesday, now: now) == "Çar 12:09", "Turkish weekday, 24-hour clock: \(tr.clock(wednesday, now: now))")
check(utc.clock(wednesday, now: now) == "Wed 12:09", "English default keeps Wed 12:09")
let weekdays = (0..<7).map { tr.clock(now.addingTimeInterval(Double($0 + 1) * 86400), now: now).split(separator: " ")[0] }
check(Set(weekdays) == ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"], "Turkish weekday abbreviations: \(weekdays)")
check(tr.clock(now.addingTimeInterval(9 * 3600), now: now) == "23:14", "evening is 23:14, never 11:14 PM")
check(tr.day(ISO8601DateFormatter().date(from: "2026-12-10T22:00:00Z")!) == "10 Ara", "Turkish month: 10 Ara")
check(tr.span(until: now.addingTimeInterval(28 * 86400 + 7200), now: now) == "28 g", "credit end in whole days: 28 g")
check(utc.span(until: now.addingTimeInterval(3 * 3600), now: now) == "3h", "under a day the span keeps hours")
check(tr.span(until: now.addingTimeInterval(-1), now: now) == nil, "a lapsed credit has no span")
let trModel = BrimPanelModel.make(snapshot: BrimFixtures.normal(), readFailed: false, loaded: true, now: now,
                                  claudeResets: BrimFixtures.claudeResets, format: tr)
let trRows = trModel.groups.flatMap(\.rows)
let trTexts = trRows.flatMap { [$0.fiveHourReset, $0.weeklyReset, $0.reset].compactMap { $0 }.flatMap { [$0.relative ?? "", $0.clock] } }
check(!trTexts.contains { $0.range(of: #"\d[hmd]\b|Mon|Tue|Wed|Thu|Fri|Sat|Sun|AM|PM"#, options: .regularExpression) != nil },
      "no English unit or weekday left in Turkish reset times: \(trTexts)")

print("reset line")
let english = BrimPanelText(localize: { $0 })
let turkishWords: [String: String] = [
    "Reset credit": "Sıfırlama hakkı", "Full reset": "Tam sıfırlama", "Fable reset": "Fable sıfırlama",
    "1 reset left": "1 sıfırlama hakkı", "%d resets left": "%d sıfırlama hakkı",
    "expires in %@": "%@ sonra sona erer", "%d full": "%d tam", "%d Fable": "%d Fable",
    "Resets in %@": "%@ sonra sıfırlanır", "Reset due": "Sıfırlanma bekleniyor", "5 hours": "5 saat", "Weekly": "Haftalık",
]
let turkishText = BrimPanelText(localize: { turkishWords[$0] ?? $0 })
let trInfo = trRows.first { $0.name == "Info" }!
check(turkishText.resetSummary(trInfo.resetCredits) == "Sıfırlama hakkı · 28 g sonra sona erer\nSıfırlama hakkı",
      "Codex: one plain line with the expiry (\(turkishText.resetSummary(trInfo.resetCredits) ?? "nil"))")
check(english.resetSummary(row(withResets, "Info")!.resetCredits) == "Reset credit · expires in 28d\nReset credit", "English Codex line")
let oneCodex = model(BrimFixtures.noFiveHourCodex)
check(english.resetSummary(oneCodex.groups[1].rows[0].resetCredits)?.hasPrefix("Reset credit · expires in ") == true,
      "singular: 1 reset left")
let trMain = trRows.first { $0.name == "Main" }!
check(turkishText.resetSummary(trMain.resetCredits) == "Tam sıfırlama · 26 g sonra sona erer\nFable sıfırlama · 114 g sonra sona erer",
      "Claude: full and Fable on one line, the soonest end (\(turkishText.resetSummary(trMain.resetCredits) ?? "nil"))")
check(turkishText.resetSummary(trRows.first { $0.name == "Work" }!.resetCredits) == nil, "no reset left: no line")
check(turkishText.resetSummary(trRows.first { $0.name == "Spare" }!.resetCredits) == nil
          && trRows.first { $0.name == "Spare" }!.resetUnknown == .loginExpiring,
      "unknown: no line in the panel, the reason stays on the row for Settings")
check(turkishText.resetSummary(trRows.first { $0.name == "Backoffice" }!.resetCredits) == nil, "Codex bank at 0: no line")
check(turkishText.resetSummary(row(normal, "Main")!.resetCredits) == nil, "no Claude read: no line")
let fableOnly = BrimPanelModel.ResetCredit(id: "x", count: 1, lines: [.init(kind: .fable, count: 1, expires: nil)],
                                           expires: nil, expiryUnknown: true)
check(turkishText.resetSummary(fableOnly) == "Fable sıfırlama", "Fable only, undated: the count alone")
check(english.accountStatus(trRows.first { $0.name == "Spare" }!) == "Session needs renewing"
          && english.accountStatus(trRows.first { $0.name == "Work" }!) == "No reset credits"
          && english.accountStatus(trInfo) == "2 left",
      "Settings > Accounts says where each account stands")
check(turkishText.resetsIn(trMain.fiveHourReset!) == "2 sa 14 dk sonra sıfırlanır", "detailed: 2 sa 14 dk sonra sıfırlanır")
check(turkishText.resetsIn(.init(relative: nil, withinDay: true, clock: "09:00")) == "Sıfırlanma bekleniyor",
      "a passed reset says it is due")
check(turkishText.window(.fiveHour) == "5 saat" && turkishText.window(.weekly) == "Haftalık"
          && turkishText.window(.model("Fable")) == "Fable", "window labels: 5 saat, Haftalık, Fable")

print("removed from the panel")
let panelFields = Mirror(reflecting: normal).children.compactMap(\.label)
let groupFields = Mirror(reflecting: normal.groups[0]).children.compactMap(\.label)
check(!panelFields.contains("resetTotal") && !groupFields.contains { ["poolLeft", "poolKnownCount", "nextFiveHourReset"].contains($0) },
      "no pool, no reset total, no next-reset summary: \(groupFields)")
check(normal.groups.allSatisfy { $0.rows.filter(\.isBest).count <= 1 }, "at most one marked account per provider")

print("layout")
var layout = BrimPanelLayout()
check(layout.arrangement == .cards && layout.columns == .auto && layout.density == .detailed && layout.groupByProvider,
      "defaults: cards, automatic columns, detailed, grouped")
check((1...2).allSatisfy { BrimPanelLayout.autoColumns(accounts: $0) == 1 }
          && (3...6).allSatisfy { BrimPanelLayout.autoColumns(accounts: $0) == 2 }
          && BrimPanelLayout.autoColumns(accounts: 7) == 3 && BrimPanelLayout.autoColumns(accounts: 12) == 3,
      "automatic: 1 column up to 2 accounts, 2 up to 6, 3 beyond")
check(layout.columnCount(accounts: 5, screenWidth: nil) == 2, "five accounts, automatic: 2 columns")
check(layout.panelWidth(accounts: 1, screenWidth: nil) == 400, "one column is 400pt")
check((640...700).contains(BrimPanelLayout.width(columns: 2)), "two columns 640-700pt (\(BrimPanelLayout.width(columns: 2)))")
layout.columns = .four
check(layout.columnCount(accounts: 2, screenWidth: nil) == 4, "a fixed choice ignores the account count")
check(layout.columnCount(accounts: 9, screenWidth: 1280) == 3 && layout.columnCount(accounts: 9, screenWidth: 1000) == 3
          && layout.columnCount(accounts: 9, screenWidth: 900) == 2,
      "four columns drop until the panel fits the screen")
check(BrimPanelLayout.width(columns: layout.columnCount(accounts: 9, screenWidth: 1440)) <= 1440 - 24, "never wider than the screen")
layout.arrangement = .list
check(layout.columnCount(accounts: 9, screenWidth: nil) == 1 && layout.panelWidth(accounts: 9, screenWidth: nil) == BrimPanelLayout.listWidth,
      "the list is one column at the list width")
let chosen = BrimPanelLayout(arrangement: .list, columns: .three, density: .compact, groupByProvider: false)
let stored = chosen.stored
check(BrimPanelLayout.load { stored[$0] } == chosen, "choices read back as stored")
check(Set(stored.keys).allSatisfy { $0.hasPrefix("brimPanel") }, "stored under UsageBar's own brimPanel* keys")
check(BrimPanelLayout.load { _ in nil } == BrimPanelLayout(), "nothing stored: defaults")
check(BrimPanelLayout.load { ["brimPanelColumns": "7", "brimPanelDensity": 3][$0] } == BrimPanelLayout(), "junk: defaults")
let flat = normal.sections(groupByProvider: false)
check(flat.count == 1 && flat[0].id == "all" && flat[0].rows.count == 5 && !flat[0].weeklyOnly && flat[0].modelColumn == "Fable",
      "grouping off: one section with every account")
check(normal.sections(groupByProvider: true).map(\.id) == ["claude", "codex"], "grouping on: one section per provider")
check(empty.sections(groupByProvider: false).isEmpty, "no accounts: no section")

print("status menu figures")
let menuWords = BrimPanelText(localize: { $0 })
let trMenu = BrimPanelModel.make(snapshot: BrimFixtures.normal(), readFailed: false, loaded: true, now: now,
                                 format: BrimPanelModel.Format(timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "tr")))
for r in normal.groups.flatMap(\.rows) {
    let least = BrimPanelModel.windows(r).compactMap(\.cell.remaining).min()
    check(BrimPanelModel.tightestWindow(r)?.cell.remaining == least, "menu: \(r.name) shows its least-left window")
}
if let backoffice = row(normal, "Backoffice") {
    let figure = menuWords.menuFigure(backoffice) ?? ""
    check(figure.contains("0%"), "menu: exhausted window shows zero remaining (\(figure))")
    check(menuWords.menuFigure(backoffice, used: true)?.contains("100%") == true,
          "menu: exhausted window shows full usage")
}
if let tight = trMenu.tightest {
    let line = menuWords.tightest(tight, format: trMenu.groups.isEmpty ? utc : BrimPanelModel.Format(locale: Locale(identifier: "tr")))
    check(tight.level != .limit || (line.contains("Limit") && !line.contains("%0")),
          "menu: the tightest line says Limit at a wall (\(line))")
}
var tie = row(normal, "Main")!
tie.model = nil
tie.fiveHour = BrimPanelModel.Cell(remaining: 0, level: .limit, percentText: "0%", fill: 0)
tie.weekly = BrimPanelModel.Cell(remaining: 0, level: .limit, percentText: "0%", fill: 0)
check(BrimPanelModel.tightestWindow(tie)?.window == .weekly, "menu: a tie goes to the window that stays shut longer")
var fable = row(normal, "Main")!
fable.model = .init(name: "Fable", cell: .init(remaining: 28, level: .low, percentText: "28%", fill: 0.28),
                    reset: .init(relative: "2d 19h", withinDay: false, clock: "Tue 12:14"))
fable.fiveHour = .init(remaining: 60, level: .plenty, percentText: "60%", fill: 0.6)
fable.weekly = .init(remaining: 40, level: .plenty, percentText: "40%", fill: 0.4)
check(menuWords.menuFigure(fable) == "Fable 28% · 2d 19h", "menu: short window name, figure and time left")

let creditFormat = BrimPanelModel.Format(locale: Locale(identifier: "tr"))
let limitedMoney = BrimPanelModel.Credit(usedCents: 541, limitCents: 2000, enabled: true)
check(limitedMoney.text(used: true, format: creditFormat) == "$5,41 / $20,00", "credit used amount")
check(limitedMoney.text(used: false, format: creditFormat) == "$14,59 / $20,00", "credit remaining amount")
check(abs(limitedMoney.remainingPercent()! - 72.95) < 0.001, "credit remaining bar")
check(BrimPanelModel.Credit(usedCents: 541, enabled: true).text(used: false, format: creditFormat,
    localize: { _ in "%@ kullanıldı" }) == "$5,41 kullanıldı", "unlimited credit")
check(BrimPanelModel.Credit.zero.text(used: true, format: creditFormat) == "$0", "disabled credit")
check(BrimPanelModel.Credit(usedCents: 2500, limitCents: 2000, enabled: true).text(used: false, format: creditFormat) == "$0,00 / $20,00", "over limit clamps remaining")
check(row(model(BrimFixtures.normal()), "Backoffice")?.credit?.tableText(used: false, format: creditFormat) == "$0", "Codex missing balance is zero without disabled status")
check(row(model(BrimFixtures.normal()), "Main")?.credit == nil, "Claude unread stays unknown")

let menuMixed = model(BrimFixtures.snapshot([
    BrimFixtures.claude("high", "High", plan: "Max", five: 90, fiveIn: 60, weekly: 95, weeklyIn: 120),
    BrimFixtures.claude("low", "Low", plan: "Max", five: 5, fiveIn: 60, weekly: 20, weeklyIn: 120)
]))
let selected = BrimMenuSelection(windows: ["claude:high": ["fiveHour"], "claude:low": ["weekly"]])
for used in [false, true] {
    let face = BrimMenuBarText.face(.percent, model: menuMixed, selection: selected, used: used)
    check(face.fill == 0.05 && face.kind == .critical && face.text == (used ? "95%" : "5%"),
          "tightest text and mark use the same window; mark stays remaining (used=\(used))")
    let chosen = BrimMenuBarText.face(.selected, model: menuMixed, selection: selected, used: used)
    check(chosen.fill == 0.2 && chosen.kind == .low && chosen.text == nil,
          "selected mark uses the tightest selected window (used=\(used))")
}
let tightFace = BrimMenuBarText.face(.percent, model: menuMixed, selection: selected, used: false)
check(tightFace.fiveHourFill == 0.05 && tightFace.weeklyFill == 0.20,
      "tightest mode draws both windows of the account its text describes")
let usedFace = BrimMenuBarText.face(.percent, model: menuMixed, selection: selected, used: true)
check(usedFace.fiveHourFill == tightFace.fiveHourFill && usedFace.weeklyFill == tightFace.weeklyFill,
      "used text preserves remaining quota in both bars")
let unknownWeekly = model(BrimFixtures.snapshot([
    BrimFixtures.claude("unknown", "Unknown", plan: "Max", five: 35, fiveIn: 60, weekly: nil, weeklyIn: nil)
]))
check(unknownWeekly.glyph.fiveHourFill == 0.35 && unknownWeekly.glyph.weeklyFill == nil,
      "unknown weekly window stays unknown")
let unknownFive = model(BrimFixtures.noFiveHourCodex)
check(BrimMenuBarText.face(.percent, model: unknownFive, selection: .init(), used: false).fiveHourFill == nil,
      "unknown five-hour window stays unknown in tightest mode")
check(unreadable.glyph.fiveHourFill == nil && unreadable.glyph.weeklyFill == nil,
      "unreadable data draws only tracks")
check(model(BrimFixtures.normal(generatedMinutesAgo: 14)).glyph.fiveHourFill == normal.glyph.fiveHourFill,
      "stale readings retain the five-hour length")
let icon = BrimMenuBarText.face(.glyph, model: menuMixed, selection: selected, used: false)
check(icon.fiveHourFill == 0.9 && icon.weeklyFill == 0.95 && icon.fill == 0.9 && icon.kind == .critical && icon.text == nil,
      "icon keeps best headroom but warns about any tight window")
let modelWarning = model(BrimFixtures.snapshot([
    BrimFixtures.claude("model", "Model", plan: "Max", five: 90, fiveIn: 60,
                        weekly: 95, weeklyIn: 120, fable: 0, fableIn: 180),
    BrimFixtures.claude("high", "High", plan: "Max", five: 90, fiveIn: 60, weekly: 95, weeklyIn: 120)
]))
let modelIcon = BrimMenuBarText.face(.glyph, model: modelWarning, selection: .init(), used: false)
check(modelIcon.fill == 0.9 && modelIcon.kind == .critical, "icon warns about an exhausted model window")
let selectedModel = BrimMenuBarText.face(.selected, model: modelWarning,
    selection: .init(windows: ["claude:model": ["fable"]]), used: true)
check(selectedModel.fill == 0 && selectedModel.kind == .critical, "selected model window at zero retains critical metadata")
let noSelection = BrimMenuBarText.face(.selected, model: menuMixed, selection: .init(), used: false)
check(noSelection.fiveHourFill == icon.fiveHourFill && noSelection.weeklyFill == icon.weeklyFill,
      "no selected reading falls back to the icon account and its two windows")
let selectedSegments = selected.segments(rows: menuMixed.groups.flatMap(\.rows), used: false)
check(!BrimMenuBarText.showsCup(.selected, segments: selectedSegments), "selected readings hide the mark")
check(BrimMenuBarText.showsCup(.selected, segments: []), "empty selection falls back to the mark")
check(BrimMenuBarText.showsCup(.glyph, segments: selectedSegments), "icon mode keeps the mark")
check(BrimMenuBarText.showsCup(.percent, segments: selectedSegments), "tightest mode keeps the mark")
let staleFace = BrimMenuBarText.face(.percent, model: model(BrimFixtures.normal(), failed: true), selection: selected, used: false)
check(staleFace.dashed, "menu face preserves stale warning")


let moneyWords: [String: String] = ["Unlimited":"Sınırsız", "%@ credits":"%@ kredi", "Off":"Kapalı", "Credit limit reached":"Limit doldu", "%@ used":"%@ kullanıldı", "Promotional credit available":"Promosyon kredisi var"]
let moneyL: (String) -> String = { moneyWords[$0] ?? $0 }
check(BrimPanelModel.Credit.zero.tableText(used: true, format: creditFormat, localize: moneyL) == "$0 · Kapalı", "disabled credit table status")
let euroCredit = BrimPanelModel.Credit(usedCents: 541, limitCents: 2000, enabled: true, currency: "EUR", utilization: 80, spendLimitReached: true)
check(euroCredit.text(used: true, format: creditFormat) == "EUR 5,41 / EUR 20,00" && euroCredit.remainingPercent() == 20, "EUR and server utilization")
check(euroCredit.status(localize: moneyL) == "Limit doldu", "spend limit warning wording")
check(BrimPanelModel.WindowSpend(limit: 20, used: 5.41).text(used: false, format: creditFormat) == "$14,59 / $20,00", "window dollars follow remaining mode")
check(BrimPanelModel.Promotion(amount: nil, expiresAt: nil).text(format: creditFormat, localize: moneyL) == "Promosyon kredisi var", "unknown promotion amount has no invented value")
for (json, expected) in [
    (#"{"credits":{"balance":null,"hasCredits":false,"unlimited":false}}"#, "$0"),
    (#"{"credits":{"balance":null,"hasCredits":true}}"#, "$0"),
    (#"{"credits":{"balance":5.41,"hasCredits":true}}"#, "5,41 kredi"),
    (#"{"credits":{"balance":"12.75","hasCredits":true}}"#, "12,75 kredi"),
    (#"{"credits":{"balance":"bad","hasCredits":true}}"#, "$0"),
    (#"{"credits":{"balance":50,"hasCredits":false}}"#, "$0"),
    (#"{"credits":{"balance":true,"hasCredits":true}}"#, "$0"),
    (#"{"credits":{"balance":null,"hasCredits":false,"unlimited":true}}"#, "Sınırsız")
] {
    let parsed = CodexCredit.parse(rateLimits: try! JSONSerialization.jsonObject(with: Data(json.utf8)))!
    let credit = BrimPanelModel.Credit(usedCents: 0, enabled: true, codex: parsed)
    check(credit.text(used: false, format: creditFormat, localize: moneyL) == expected, "Codex credit \(json)")
}
var creditSnapshot = BrimFixtures.normal()
let codexIndex = creditSnapshot.accounts.firstIndex { $0.provider == "codex" }!
creditSnapshot.accounts[codexIndex].codexCredit = .init(balance: 12.75, spendControlReached: true)
let creditRoundTrip = try! JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(creditSnapshot))
let codexCreditRow = model(creditRoundTrip).groups.flatMap(\.rows).first { $0.id == creditSnapshot.accounts[codexIndex].id }!
check(codexCreditRow.credit?.text(used: false, format: creditFormat, localize: moneyL) == "12,75 kredi" && codexCreditRow.credit?.spendLimitReached == true, "Codex balance and warning survive snapshot and panel")

creditSnapshot.accounts[codexIndex].lastRefreshFailed = true
check(model(creditSnapshot).groups.flatMap(\.rows).first { $0.id == creditSnapshot.accounts[codexIndex].id }?.credit?.codex?.balance == 12.75, "failed Codex reading keeps the last known balance")

let staleRows = model(BrimFixtures.refreshFailure()).groups.flatMap(\.rows)
let staleClaude = staleRows.first { $0.provider == "claude" }!
check(staleClaude.refreshFailed && staleClaude.heldOver, "error dims first failed refresh")
check(staleClaude.refreshReading == "13:40", "failure row dates last successful reading")
check(staleClaude.refreshProblem?.contains("/login") == true && staleClaude.refreshProblem?.contains("Örnek tanı") == true, "tooltip keeps short and detailed reasons")
check(staleRows.first { $0.provider == "codex" }?.refreshReading?.contains("2026") == true, "previous-day reading includes date")
var errorOnly = BrimFixtures.normal()
errorOnly.accounts[0].error = "failed"
check(model(errorOnly).groups.flatMap(\.rows).first { $0.id == errorOnly.accounts[0].id }?.refreshFailed == true, "error alone exposes failure")
var unknownCredit = creditSnapshot
unknownCredit.accounts[codexIndex].codexCredit = nil
check(model(unknownCredit).groups.flatMap(\.rows).first { $0.id == unknownCredit.accounts[codexIndex].id }?.credit == nil, "failed reading without known credit stays unknown")

var failedInventory = BrimFixtures.claudeResets
failedInventory["claude:.claude"]?.problem = .failed
let inventoryPanel = model(BrimFixtures.normal(), claudeResets: failedInventory)
check(inventoryPanel.groups.flatMap(\.rows).first { $0.id == "claude:.claude" }?.creditHeldOver == true, "failed credit inventory marks retained amount as old")

if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
print("ALL PASS")
