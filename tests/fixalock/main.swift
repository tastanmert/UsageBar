import Foundation
var failures = 0
func check(_ value: Bool, _ name: String) {
    print("\(value ? "PASS" : "FAIL") \(name)")
    if !value { failures += 1 }
}
let runtime = BrimRuntime.shared
let stale = runtime.liveGeneration
runtime.stopAllChildren()
let object = NSObject()
var launched = false
check(!runtime.launch(object, generation: stale, start: { launched = true }, stop: {}) && !launched,
      "queued work from a closed generation never launches after reopening")
var stopped = 0
check(runtime.launch(object, generation: runtime.liveGeneration, start: { launched = true }, stop: { stopped += 1 }),
      "launch and registration succeed together")
runtime.stopAllChildren()
check(stopped == 1 && runtime.trackedCount == 0, "transition finds the launched child exactly once")
let identity = CodexAccountIdentity(home: "/fixture/codex", email: "a@b.c", planType: "plus", type: "chatgpt")
let identityData = Data(#"{"result":{"account":{"email":"a@b.c","planType":"plus","type":"chatgpt"},"requiresOpenaiAuth":true}}"#.utf8)
func bank(_ status: String) -> Data {
    Data("{\"result\":{\"rateLimitResetCredits\":{\"credits\":[{\"id\":\"c1\",\"status\":\"\(status)\"}]}}}".utf8)
}
var disk: Data?
let coordinator = CodexConsumeCoordinator(save: { disk = $0 })
var sends: [[String: String]] = []
var creditStatus = "available"
func wire(_ method: String, _ params: [String: String]) -> Data? {
    if method == "account/read" { return identityData }
    if method == "account/rateLimits/read" { return bank(creditStatus) }
    sends.append(params)
    return nil // server might have consumed; response dropped
}
check(coordinator.consume(expected: identity, creditID: "c1", isCurrent: { true }, request: wire) == .uncertain,
      "dropped consume response is uncertain")
let kept = coordinator.pending(home: identity.home)
check(kept?.creditID == "c1" && sends.count == 1 && kept?.idempotencyKey == sends[0]["idempotencyKey"],
      "credit and request key persisted before sending")
check(coordinator.consume(expected: identity, creditID: "c2", isCurrent: { true }, request: wire) == .uncertain
      && sends.count == 2 && sends.allSatisfy { $0 == sends[0] },
      "a second credit cannot be consumed while the first is uncertain: only the same request is re-sent")
creditStatus = "missing"
check(coordinator.consume(expected: identity, creditID: "c2", isCurrent: { true }, request: { method, params in
    method == "account/rateLimits/read" ? Data(#"{"result":{"rateLimitResetCredits":{"credits":[]}}}"#.utf8) : wire(method, params)
}) == .uncertain && sends.count == 2, "a re-read that cannot name the credit sends nothing and stays uncertain")
creditStatus = "available"
check(coordinator.consume(expected: identity, creditID: "c2", isCurrent: { false }, request: wire) == .unavailable
      && sends.count == 2 && coordinator.pending(home: identity.home) == kept,
      "a closed live generation neither sends nor clears the open attempt")
let restored = CodexConsumeCoordinator(load: { disk })
check(restored.consume(expected: identity, creditID: "c2", isCurrent: { true }, request: wire) == .uncertain
      && restored.pending(home: identity.home) == kept && sends.count == 3 && sends[2] == sends[0],
      "relaunch preserves pending operation and its idempotency key")
creditStatus = "consumed"
check(coordinator.consume(expected: identity, creditID: "c2", isCurrent: { true }, request: wire) == .resolved(.redeemed)
      && sends.count == 3, "completed reread settles original credit without consuming another")
check(coordinator.consume(expected: identity, creditID: "c1", isCurrent: { true }, request: wire) == .resolved(.alreadyUsed),
      "settled credit cannot receive a new UUID")
let retry = CodexConsumeCoordinator()
var retrySends: [[String: String]] = []
var answer = false
func retryWire(_ method: String, _ params: [String: String]) -> Data? {
    if method == "account/read" { return identityData }
    if method == "account/rateLimits/read" { return bank("available") }
    retrySends.append(params)
    return answer ? Data(#"{"result":{"outcome":"redeemed"}}"#.utf8) : nil
}
_ = retry.consume(expected: identity, creditID: "c1", isCurrent: { true }, request: retryWire)
answer = true
check(retry.consume(expected: identity, creditID: "c1", isCurrent: { true }, request: retryWire) == .resolved(.redeemed)
      && retrySends.count == 2 && retrySends[0] == retrySends[1] && retry.pending(home: identity.home)?.settled == true,
      "a credit still available after a dropped answer settles by re-sending the same key")
var calls = 0
let changed = CodexConsumeCoordinator()
check(changed.consume(expected: identity, creditID: "c1", isCurrent: { true }, request: { method, _ in
    calls += 1
    return Data(#"{"result":{"account":{"email":"other@b.c","planType":"plus","type":"chatgpt"}}}"#.utf8)
}) == .identityChanged && calls == 1, "identity mismatch sends no consume")
var reads = 0
check(changed.consume(expected: identity, creditID: "c1", isCurrent: { true }, request: { method, _ in
    if method == "account/rateLimits/read" { return bank("available") }
    reads += 1
    return reads == 1 ? identityData : Data("{}".utf8)
}) == .identityChanged && changed.pending(home: identity.home) == nil,
      "identity changes during inventory read cancel before send")
check(changed.consume(expected: identity, creditID: "c1", isCurrent: { true }, request: { method, _ in
    calls += 1
    if method == "account/read" { return identityData }
    return Data(#"{"result":{"rateLimitResetCredits":{"credits":[{"id":"c9","status":"available"}]}}}"#.utf8)
}) == .unavailable && changed.pending(home: identity.home) == nil,
      "a credit this session does not list as available sends nothing")

// MARK: - An open attempt left by an earlier login
let earlier = CodexAccountIdentity(home: "/fixture/codex", email: "old@b.c", planType: "plus", type: "chatgpt")
let clockStart = Date(timeIntervalSince1970: 1_800_000_000)
var clock = clockStart
var strandedDisk: Data?
let stranded = CodexConsumeCoordinator(save: { strandedDisk = $0 }, now: { clock })
var strandedSends: [[String: String]] = []
var signedIn = Data(#"{"result":{"account":{"email":"old@b.c","planType":"plus","type":"chatgpt"}}}"#.utf8)
func strandedWire(_ method: String, _ params: [String: String]) -> Data? {
    if method == "account/read" { return signedIn }
    if method == "account/rateLimits/read" { return bank("available") }
    strandedSends.append(params)
    return nil
}
_ = stranded.consume(expected: earlier, creditID: "c1", isCurrent: { true }, request: strandedWire)
check(stranded.pending(home: earlier.home)?.startedAt == clockStart && strandedSends.count == 1,
      "stranded: the attempt records when it was written")
signedIn = identityData
clock = clockStart.addingTimeInterval(23 * 3600)
check(stranded.consume(expected: identity, creditID: "c1", isCurrent: { true }, request: strandedWire) == .identityChanged
      && strandedSends.count == 1 && stranded.pending(home: identity.home)?.identity == earlier,
      "stranded: a new login stays locked while the earlier login's attempt is under a day old")
check(stranded.strandedAttempt(home: identity.home, current: identity)?.identity == earlier
      && stranded.strandedAttempt(home: identity.home, current: earlier) == nil
      && stranded.strandedAttempt(home: identity.home, current: nil) == nil,
      "stranded: only another known login's open attempt is offered for clearing")
check(!stranded.clearStranded(home: identity.home, current: earlier) && !stranded.clearStranded(home: identity.home, current: nil)
      && stranded.pending(home: identity.home) != nil,
      "stranded: the same login or an unknown one cannot clear it")
let manual = CodexConsumeCoordinator(load: { strandedDisk }, now: { clock })
var manualSends = 0
check(manual.clearStranded(home: identity.home, current: identity) && manual.pending(home: identity.home) == nil
      && manualSends == 0, "stranded: clearing by hand drops UsageBar's record and sends nothing")
check(manual.consume(expected: identity, creditID: "c1", isCurrent: { true }, request: { method, params in
    if method == "account/rateLimitResetCredit/consume" { manualSends += 1 }
    return strandedWire(method, params)
}) == .uncertain && manualSends == 1, "stranded: after clearing, the new login can use its own credit")
clock = clockStart.addingTimeInterval(24 * 3600)
var staleSends: [[String: String]] = []
check(stranded.consume(expected: identity, creditID: "c1", isCurrent: { true }, request: { method, params in
    if method == "account/rateLimitResetCredit/consume" { staleSends.append(params) }
    return strandedWire(method, params)
}) == .uncertain && staleSends.count == 1
      && stranded.pending(home: identity.home)?.identity == identity
      && staleSends[0]["idempotencyKey"] != strandedSends[0]["idempotencyKey"],
      "stranded: a day later the earlier login's attempt is dropped and the new login sends its own request")
clock = clockStart
let sameLogin = CodexConsumeCoordinator(now: { clock })
signedIn = Data(#"{"result":{"account":{"email":"old@b.c","planType":"plus","type":"chatgpt"}}}"#.utf8)
var resent: [[String: String]] = []
_ = sameLogin.consume(expected: earlier, creditID: "c1", isCurrent: { true }, request: { method, params in
    if method == "account/rateLimitResetCredit/consume" { resent.append(params) }
    return strandedWire(method, params)
})
clock = clockStart.addingTimeInterval(48 * 3600)
_ = sameLogin.consume(expected: earlier, creditID: "c2", isCurrent: { true }, request: { method, params in
    if method == "account/rateLimitResetCredit/consume" { resent.append(params) }
    return strandedWire(method, params)
})
check(resent.count == 2 && resent[1] == resent[0] && sameLogin.pending(home: earlier.home)?.creditID == "c1",
      "stranded: age never clears the same login's own attempt, it re-sends that same request")

// Real local fixtures exercise the process-group boundary; no provider or account is launched.
let child = BrimProviderProcess()
child.executableURL = URL(fileURLWithPath: "/bin/sh")
child.arguments = ["-c", "trap '' TERM; /bin/sh -c 'trap \"\" TERM; while :; do sleep 1; done' & echo ready; wait"]
try child.run()
_ = child.standardOutput.fileHandleForReading.availableData
check(getpgid(child.processIdentifier) == child.processIdentifier, "probe owns a process group from spawn")
let began = Date()
child.stopTree()
while Date().timeIntervalSince(began) < 4.5 {
    _ = child.isRunning
    if kill(-child.processIdentifier, 0) == -1 && errno == ESRCH { break }
    Thread.sleep(forTimeInterval: 0.02)
}
check(!child.isRunning && kill(-child.processIdentifier, 0) == -1 && errno == ESRCH
      && Date().timeIntervalSince(began) < 5, "TERM-ignoring root and descendant die within five seconds")
let located = BrimProviderProcess()
located.executableURL = URL(fileURLWithPath: "/bin/pwd")
located.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
try located.run()
let where_ = String(decoding: located.standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
located.waitUntilExit()
check(where_.hasSuffix("tmp\n") && located.terminationStatus == 0, "a probe starts in the directory it was given")
// MARK: - The Codex confirm card binds identity and credit (BrimCodexApproval)
// The shape codex-cli 0.146.0 answers with (CodexIdentity): email, plan and login type only.
let readLine = Data(#"{"id":3,"result":{"account":{"email":"a@b.c","planType":"pro","type":"chatgpt"},"requiresOpenaiAuth":true}}"#.utf8)
let parsed = CodexAccountIdentity(home: "/h/.codex", accountRead: readLine)
check(parsed == CodexAccountIdentity(home: "/h/.codex", email: "a@b.c", planType: "pro", type: "chatgpt"),
      "identity: a real account/read (email, planType, type) names the login")
let withIDs = CodexAccountIdentity(home: "/h", accountRead: Data(#"{"result":{"account":{"email":"a@b.c","planType":"pro","type":"chatgpt","id":"acct-1","userId":"user-1","workspaceId":"ws-1"}}}"#.utf8))
check(withIDs == CodexAccountIdentity(home: "/h", email: "a@b.c", planType: "pro", type: "chatgpt",
                                      accountID: "acct-1", userID: "user-1", workspaceID: "ws-1"),
      "identity: account, user and workspace ids are kept when sent")
check(withIDs?.matches(Data(#"{"result":{"account":{"email":"a@b.c","planType":"pro","type":"chatgpt","id":"acct-1","userId":"user-1","workspaceId":"ws-2"}}}"#.utf8)) == false
      && withIDs?.matches(Data(#"{"result":{"account":{"email":"a@b.c","planType":"pro","type":"chatgpt"}}}"#.utf8)) == false,
      "identity: another workspace, or a read that drops the ids, does not match")
check(CodexAccountIdentity(home: "/h", accountRead: Data(#"{"result":{"account":{"planType":"pro","type":"chatgpt","id":"a","userId":"u","workspaceId":"w"}}}"#.utf8)) == nil
      && CodexAccountIdentity(home: "/h", accountRead: Data(#"{"result":{"account":{"email":"","planType":"pro","type":"chatgpt"}}}"#.utf8)) == nil,
      "identity: no email, or an empty one, binds nothing")
check(CodexAccountIdentity(home: "/h", accountRead: Data(#"{"error":{"message":"x"},"result":{"account":{"email":"a@b.c","planType":"pro","type":"chatgpt"}}}"#.utf8)) == nil,
      "identity: an error answer binds nothing")
check(parsed?.matches(readLine) == true
      && parsed?.matches(Data(#"{"result":{"account":{"email":"b@b.c","planType":"pro","type":"chatgpt"}}}"#.utf8)) == false
      && parsed?.matches(Data(#"{"result":{"account":{"email":"a@b.c","planType":"plus","type":"chatgpt"}}}"#.utf8)) == false
      && parsed?.matches(Data(#"{"result":{"account":{"email":"a@b.c","planType":"pro","type":"apikey"}}}"#.utf8)) == false,
      "identity: another email, plan or login type does not match")
let book = CodexIdentityBook()
book.record(home: "/h/.codex", accountRead: readLine)
check(book.identity(home: "/h/.codex") == parsed, "book: the latest read's identity is kept by home")
book.record(home: "/h/.codex", accountRead: nil)
check(book.identity(home: "/h/.codex") == nil, "book: a read that named no identity replaces the old one with none")

let dayLater = Date(timeIntervalSince1970: 1_800_086_400), weekLater = Date(timeIntervalSince1970: 1_800_604_800)
let credits = [BankedResetCredit(id: "late", status: "available", expiresAt: weekLater),
               BankedResetCredit(id: "undated", status: "available", expiresAt: nil),
               BankedResetCredit(id: "spent", status: "consumed", expiresAt: Date(timeIntervalSince1970: 1_800_000_000)),
               BankedResetCredit(id: nil, status: "available", expiresAt: Date(timeIntervalSince1970: 1_800_000_000)),
               BankedResetCredit(id: "soon", status: "available", expiresAt: dayLater)]
let bound = BrimCodexApproval.make(accountID: "codex:.codex", home: "/h/.codex", identity: parsed, credits: credits)
check(bound?.credit.id == "soon" && bound?.identity == parsed,
      "approval: bound to the identity and the soonest-ending spendable credit with an id")
check(BrimCodexApproval.make(accountID: "x", home: "/h/.codex", identity: nil, credits: credits) == nil,
      "approval: no identity, no card")
check(BrimCodexApproval.make(accountID: "x", home: "/other", identity: parsed, credits: credits) == nil,
      "approval: an identity read for another home binds nothing")
check(BrimCodexApproval.make(accountID: "x", home: "/h/.codex", identity: parsed,
                             credits: [credits[2], credits[3]]) == nil,
      "approval: spent or id-less credits give no card")
check(BrimCodexApproval.make(accountID: "x", home: "/h/.codex", identity: parsed,
                             credits: [credits[1], credits[0]])?.credit.id == "late",
      "approval: a dated credit before an undated one")
let otherUser = CodexAccountIdentity(home: "/h/.codex", email: "b@b.c", planType: "pro", type: "chatgpt")
check(bound?.stillBound(to: parsed) == true && bound?.stillBound(to: otherUser) == false
      && bound?.stillBound(to: nil) == false, "approval: another login or none since the card opened is not bound")
let statuses: [(CodexAppServerClient.ConsumeOutcome, Bool, BrimPanelModel.ResetUse)] = [
    (.resolved(.redeemed), false, .checking(spent: true)),
    (.resolved(.redeemed), true, .checking(spent: true)),
    (.resolved(.alreadyUsed), false, .refused(.alreadyUsed)),
    (.resolved(.alreadyUsed), true, .checking(spent: true)),
    (.resolved(.noCredit), false, .refused(.noCredit)),
    (.resolved(.failed(nil)), false, .failed),
    (.uncertain, false, .checking(spent: nil)),
    (.identityChanged, false, .refused(.accountChanged)),
    (.unavailable, false, .refused(.changed)),
]
check(statuses.allSatisfy { BrimCodexApproval.status($0.0, settlesEarlier: $0.1) == $0.2 },
      "approval: each consume answer has its card line (spent, checking, account changed, refused)")
let words = BrimPanelText(localize: { $0 })
let spentRow = BrimPanelModel.Row(id: "codex:.codex", provider: "codex", name: "Info", label: "Info", isBest: false,
    fiveHour: .init(remaining: nil, percentText: "—", fill: 0), weekly: .init(remaining: 100, level: .plenty, percentText: "100%", fill: 1),
    resetWindow: .weekly, heldOver: false)
check(words.resetUse(.refused(.accountChanged), row: spentRow) == "Account changed, cancelled"
      && words.resetUse(.checking(spent: nil), row: spentRow) == "Checking again…"
      && words.resetUse(.used, row: spentRow) == "Reset done · Weekly 100%",
      "approval: the card says Reset, Checking, or Account changed")
let storeSource = (try? String(contentsOfFile: "UsageBar/Stores/BrimResetUseStore.swift", encoding: .utf8)) ?? ""
check(!storeSource.contains("RedeemAction.redeem(usage: usage)\n") && storeSource.contains("RedeemAction.redeem(usage: usage, approval: approval)")
      && !storeSource.contains("consumeSoonestResetCredit("),
      "store: the confirm card spends through the identity-bound consume only")
let redeemSource = (try? String(contentsOfFile: "UsageBar/Views/RedeemAction.swift", encoding: .utf8)) ?? ""
check(redeemSource.contains("CodexAppServerClient.consume(expected: approval.identity, credit: approval.credit)"),
      "store: the consume carries the approved identity and credit")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
