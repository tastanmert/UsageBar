import Foundation

// Assertion harness for LimitAlertLogic (compiled with LimitAlertLogic.swift and DryPoolLogic.swift).

var failures = 0
func expect(_ condition: Bool, _ name: String) {
    if condition { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
let cycle1 = now.addingTimeInterval(3 * 3_600)
let cycle2 = now.addingTimeInterval(8 * 3_600)
let on = LimitAlertSettings(threshold: 90, unusedWeekly: true)

func window(_ used: Double, kind: LimitAlertWindow.Kind = .session, reset: Date? = cycle1,
            account: String = "claude:a", model: String? = nil) -> LimitAlertWindow {
    LimitAlertWindow(accountID: account, accountLabel: "Claude 1", kind: kind, modelName: model,
                     usedPercent: used, resetsAt: reset)
}

// 1. Under the threshold nothing fires; at it, the threshold alert fires once.
do {
    let (s1, a1) = LimitAlertLogic.advance(state: .init(), windows: [window(89)], settings: on, now: now)
    expect(a1.isEmpty, "89% does not fire at 90")
    let (s2, a2) = LimitAlertLogic.advance(state: s1, windows: [window(90)], settings: on, now: now)
    expect(a2.map(\.reason) == [.threshold], "90% fires threshold")
    let (_, a3) = LimitAlertLogic.advance(state: s2, windows: [window(93)], settings: on, now: now)
    expect(a3.isEmpty, "threshold fires once per cycle")
}

// 2. Exhausted after the threshold fires separately; jumping straight to 100 says it once.
do {
    let (s1, _) = LimitAlertLogic.advance(state: .init(), windows: [window(91)], settings: on, now: now)
    let (s2, a2) = LimitAlertLogic.advance(state: s1, windows: [window(100)], settings: on, now: now)
    expect(a2.map(\.reason) == [.exhausted], "100% after threshold fires exhausted")
    let (_, a3) = LimitAlertLogic.advance(state: s2, windows: [window(100)], settings: on, now: now)
    expect(a3.isEmpty, "exhausted fires once")
    let (s4, a4) = LimitAlertLogic.advance(state: .init(), windows: [window(100)], settings: on, now: now)
    expect(a4.map(\.reason) == [.exhausted], "straight to 100 fires exhausted only")
    let (_, a5) = LimitAlertLogic.advance(state: s4, windows: [window(100)], settings: on, now: now)
    expect(a5.isEmpty, "no threshold alert after exhausted")
}

// 3. A new reset cycle re-arms; reset jitter within the tolerance does not.
do {
    let (s1, _) = LimitAlertLogic.advance(state: .init(), windows: [window(95)], settings: on, now: now)
    let (s2, a2) = LimitAlertLogic.advance(state: s1, windows: [window(95, reset: cycle1.addingTimeInterval(60))],
                                           settings: on, now: now)
    expect(a2.isEmpty, "one minute of jitter is the same cycle")
    let (_, a3) = LimitAlertLogic.advance(state: s2, windows: [window(95, reset: cycle2)], settings: on, now: now)
    expect(a3.map(\.reason) == [.threshold], "a new cycle re-arms")
}

// 4. Falling well under the threshold re-arms within a cycle; hovering just under does not.
do {
    let (s1, _) = LimitAlertLogic.advance(state: .init(), windows: [window(92)], settings: on, now: now)
    let (s2, a2) = LimitAlertLogic.advance(state: s1, windows: [window(85)], settings: on, now: now)
    let (_, a3) = LimitAlertLogic.advance(state: s2, windows: [window(92)], settings: on, now: now)
    expect(a2.isEmpty && a3.isEmpty, "85% is inside the hysteresis band")
    let (s4, _) = LimitAlertLogic.advance(state: s1, windows: [window(10)], settings: on, now: now)
    let (_, a5) = LimitAlertLogic.advance(state: s4, windows: [window(92)], settings: on, now: now)
    expect(a5.map(\.reason) == [.threshold], "a drop to 10% re-arms")
}

// 5. Threshold off silences both threshold alerts.
do {
    let off = LimitAlertSettings(threshold: 0, unusedWeekly: false)
    let (_, a) = LimitAlertLogic.advance(state: .init(), windows: [window(100)], settings: off, now: now)
    expect(a.isEmpty, "threshold 0 is off")
}

// 6. Unused weekly: inside 24 h with half or more left fires once; outside, or used, does not.
do {
    let soon = now.addingTimeInterval(20 * 3_600)
    let later = now.addingTimeInterval(30 * 3_600)
    let (s1, a1) = LimitAlertLogic.advance(state: .init(), windows: [window(40, kind: .weekly, reset: soon)],
                                           settings: on, now: now)
    expect(a1.map(\.reason) == [.unused], "60% left, 20 h to reset fires unused")
    let (_, a2) = LimitAlertLogic.advance(state: s1, windows: [window(40, kind: .weekly, reset: soon)],
                                          settings: on, now: now)
    expect(a2.isEmpty, "unused fires once")
    let (_, a3) = LimitAlertLogic.advance(state: .init(), windows: [window(40, kind: .weekly, reset: later)],
                                          settings: on, now: now)
    expect(a3.isEmpty, "30 h to reset is too early")
    let (_, a4) = LimitAlertLogic.advance(state: .init(), windows: [window(60, kind: .weekly, reset: soon)],
                                          settings: on, now: now)
    expect(a4.isEmpty, "40% left does not fire")
    let (_, a5) = LimitAlertLogic.advance(state: .init(), windows: [window(40, kind: .session, reset: soon)],
                                          settings: on, now: now)
    expect(a5.isEmpty, "the 5-hour window never fires unused")
    let noUnused = LimitAlertSettings(threshold: 90, unusedWeekly: false)
    let (_, a6) = LimitAlertLogic.advance(state: .init(), windows: [window(40, kind: .weekly, reset: soon)],
                                          settings: noUnused, now: now)
    expect(a6.isEmpty, "unused can be switched off")
}

// 7. Windows are independent, by account and by model.
do {
    let windows = [window(95, account: "claude:a"), window(95, account: "claude:b"),
                   window(95, kind: .weeklyModel, model: "Fable")]
    let (_, a) = LimitAlertLogic.advance(state: .init(), windows: windows, settings: on, now: now)
    expect(a.count == 3, "three windows, three alerts")
}

// 8. Prune keeps accounts that still exist, even with no window this round.
do {
    let (s1, _) = LimitAlertLogic.advance(state: .init(), windows: [window(95, account: "claude:a"),
                                                                    window(95, account: "claude:b")],
                                          settings: on, now: now)
    let pruned = LimitAlertLogic.prune(s1, accountIDs: ["claude:a"])
    expect(pruned.entries.count == 1 && pruned.entries.keys.first?.hasPrefix("claude:a|") == true,
           "prune drops a removed account only")
    let (_, a) = LimitAlertLogic.advance(state: pruned, windows: [window(95, account: "claude:a")],
                                         settings: on, now: now)
    expect(a.isEmpty, "a kept account keeps its memory")
}

if failures > 0 { print("\(failures) FAILED"); exit(1) }
print("ALL PASS")
