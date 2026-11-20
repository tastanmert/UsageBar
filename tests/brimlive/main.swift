import Foundation

// Always-on gates, confirmed reset claims through fake transports, and panel formatting.
// No app, network, Keychain or user preferences: every outside read is injected.

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}
func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

let runtime = BrimRuntime.shared

let opensInLive = ["liveProbes", "providerHomeMutation", "orphanReclaim", "userNotifications",
                   "panelResetUse", "cliWrites", "integrationInstall", "autoUpdate"]
let closedAlways = ["backgroundHomeWrites", "integrationsSelfHeal",
                    "integrationsAutoFollow", "keychainPartitionRepair", "earlyStart", "typesIntoSessions",
                    "chromeStep", "codexAutoRedeem",
                    "codexCLIAutoUpdate", "launchAtLoginDefault", "mcpGrantSeeding", "closesOlderDevInstances"]
check("the gate table names every gate once", Set(BrimFeatures.table.keys) == Set(opensInLive + closedAlways)
      && BrimFeatures.table.count == opensInLive.count + closedAlways.count)

for gate in opensInLive { check("\(gate) is always open", BrimFeatures.table[gate] == true) }
for gate in closedAlways { check("\(gate) stays closed", BrimFeatures.table[gate] == false) }
check("reset inventory and confirmed claim are enabled", BrimFeatures.claudeResetInventoryRead && BrimFeatures.claudeResetClaim)
check("provider children are tracked by the runner", source("UsageBar/Core/CLIRunner.swift").contains("BrimRuntime.shared.launch(process"))
check("Codex app server tracks its child", source("UsageBar/Providers/Codex/CodexAppServerClient.swift").contains("BrimRuntime.shared.launch(process"))

// MARK: - Claude reset claim (fake transport)

let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)
let organization = "0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b"
func grant(_ kind: ClaudeResetInventory.Kind, id: String, left: Int = 1, usable: Bool = true,
           requiresLimit: Bool = false) -> ClaudeResetInventory.Grant {
    .init(id: .init(raw: id), kind: kind, name: kind.rawValue, left: left, total: 1,
          endsAt: checkedAt.addingTimeInterval(20 * 86400), usableNow: usable, useRequiresLimit: requiresLimit)
}
func entry(_ grants: [ClaudeResetInventory.Grant], identity: String? = "user-1", at: Date = checkedAt,
           atLimit: Bool = true, problem: BrimPanelModel.ResetUnknown? = nil) -> BrimClaudeResetSchedule.Entry {
    .init(reading: ClaudeResetInventory(eligible: true, grants: grants, atLimit: atLimit), checkedAt: at,
          problem: problem, identity: identity, organizationID: identity == nil ? nil : organization)
}
let full = grant(.full, id: "full-reset-2611")
let held = entry([full, grant(.fable, id: "fable-2611")])
let when = checkedAt.addingTimeInterval(60)
let approval = BrimClaudeClaimRunner.approval(accountID: "claude:.claude3", home: "/h/.claude3", kind: .full,
                                              entry: held, now: when)
check("a bound, usable reading gives a consent", approval != nil && approval?.leftBefore == 1)
check("…bound to the login, organisation, grant and reading time",
      approval?.consent.identity == "user-1" && approval?.consent.organizationID == organization
          && approval?.consent.grantID.raw == "full-reset-2611" && approval?.consent.checkedAt == checkedAt)
check("no consent from a reading that names no login",
      BrimClaudeClaimRunner.approval(accountID: "a", home: "/h", kind: .full, entry: entry([full], identity: nil), now: when) == nil)
check("…from a held-over reading",
      BrimClaudeClaimRunner.approval(accountID: "a", home: "/h", kind: .full, entry: entry([full], problem: .failed), now: when) == nil)
check("…for a grant the server says is not usable now",
      BrimClaudeClaimRunner.approval(accountID: "a", home: "/h", kind: .full,
                                     entry: entry([grant(.full, id: "f", usable: false)]), now: when) == nil)
check("…for a grant that needs a limit while the login is not at one",
      BrimClaudeClaimRunner.approval(accountID: "a", home: "/h", kind: .full,
                                     entry: entry([grant(.full, id: "f", requiresLimit: true)], atLimit: false), now: when) == nil)
check("…for a kind the reading does not hold",
      BrimClaudeClaimRunner.approval(accountID: "a", home: "/h", kind: .session, entry: held, now: when) == nil)

let tokenDocument = Data(#"{"claudeAiOauth":{"accessToken":"fake-token-for-checks","expiresAt":1900000000000}}"#.utf8)
guard case .usable(let credential) = ClaudeResetInventoryFetch.credential(from: tokenDocument, now: when) else {
    fatalError("fixture credential")
}
final class Wire: @unchecked Sendable {
    var requests: [URLRequest] = []
    var answers: [Result<(Int, String), Error>] = []
    func transport() -> ClaudeResetInventoryFetch.Transport {
        { request in
            self.requests.append(request)
            let answer = self.answers.isEmpty ? .success((200, #"{"result":"reset","resets_left":0}"#)) : self.answers.removeFirst()
            let (status, body) = try answer.get()
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
    func body(_ index: Int) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: requests[index].httpBody ?? Data())) as? [String: Any] ?? [:]
    }
}
struct Dropped: Error {}

@MainActor
func environment(_ wire: Wire, current: @escaping () -> BrimClaudeResetSchedule.Entry? = { held },
                 listed: @escaping () -> Bool = { true },
                 identity: String = "user-1", delay: Double = 0) -> BrimClaudeClaimRunner.Environment {
    .init(currentEntry: current, stillListed: listed,
          readContext: {
              if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
              return .ready(ClaudeResetClaim.Context(identity: .init(accountID: identity, organizationID: organization),
                                              credential: credential))
          },
          version: "2.1.311", transport: wire.transport(), now: { when })
}

@MainActor
func claimChecks() async {
    guard let approval else { return }
    var wire = Wire()
    var runner = BrimClaudeClaimRunner()
    let cancelled = await runner.claim(approval, confirmed: false, env: environment(wire))
    check("Cancel (not confirmed) sends nothing", cancelled == .cancelled && wire.requests.isEmpty)

    var expiring = environment(wire)
    expiring.readContext = { .loginExpiring }
    let expiryResult = await runner.claim(approval, confirmed: true, env: expiring)
    check("expiring login sends no POST", expiryResult == .loginExpiring && wire.requests.isEmpty)
    check("expiring login has its own refusal", BrimClaudeClaimRunner.status(expiryResult) == .refused(.loginExpiring))
    // A token read as usable that runs out within the margin by the time of the claim: no POST.
    let soon = Int((when.timeIntervalSince1970 + 60) * 1000)
    if case .usable(let short) = ClaudeResetInventoryFetch.credential(
        from: Data(#"{"claudeAiOauth":{"accessToken":"fake-token-for-checks","expiresAt":\#(soon)}}"#.utf8),
        now: when.addingTimeInterval(-3600)) {
        var nearEnd = environment(wire)
        nearEnd.readContext = { .ready(ClaudeResetClaim.Context(
            identity: .init(accountID: "user-1", organizationID: organization), credential: short)) }
        let nearResult = await runner.claim(approval, confirmed: true, env: nearEnd)
        check("token ending within two minutes sends no POST", nearResult == .loginExpiring && wire.requests.isEmpty)
    } else {
        check("near-expiry fixture credential reads as usable an hour earlier", false)
    }
    let secondGrant = grant(.full, id: "second-full")
    let chosen = BrimClaudeClaimRunner.approval(accountID: approval.accountID, home: approval.home,
        kind: .full, entry: entry([full, secondGrant]), now: when, grantID: "second-full")
    check("a separate line binds its own grant", chosen?.consent.grantID.raw == "second-full")
    if let chosen {
        let chosenWire = Wire()
        _ = await runner.claim(chosen, confirmed: true, env: environment(chosenWire, current: { entry([full, secondGrant]) }))
        check("the selected grant is the POST's grant", chosenWire.body(0)["grant_id"] as? String == "second-full")
    }
    let spent = await runner.claim(approval, confirmed: true, env: environment(wire))
    check("confirmed: one request, and it is spent", wire.requests.count == 1
          && spent == .result(.reset, resetsLeft: 0, cooldownUntil: nil))
    let request = wire.requests[0]
    check("…a POST to the login's organisation", request.httpMethod == "POST"
          && request.url?.absoluteString == "https://api.anthropic.com/api/organizations/\(organization)/reset_rate_limits")
    check("…naming the grant and the program", wire.body(0)["grant_id"] as? String == "full-reset-2611"
          && wire.body(0)["program"] as? String == "cedar_ember" && (wire.body(0)["request_id"] as? String)?.isEmpty == false)
    check("…with the login's token and Claude Code's client name",
          request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-token-for-checks"
              && request.value(forHTTPHeaderField: "User-Agent") == "claude-cli/2.1.311 (external, cli)")
    check("a spent reset is measured again before the card says Used",
          BrimClaudeClaimRunner.status(spent) == .checking(spent: true))

    wire = Wire()
    let reread = await runner.claim(approval, confirmed: true,
                                     env: environment(wire, current: { entry([full, grant(.fable, id: "fable-2611")],
                                                                             at: checkedAt.addingTimeInterval(30)) }))
    check("a newer reading than the one confirmed cancels, nothing sent", reread == .cancelled && wire.requests.isEmpty)
    check("…and the card asks to confirm once more", BrimClaudeClaimRunner.status(reread) == .refused(.changed))

    let otherLogin = await runner.claim(approval, confirmed: true, env: environment(wire, identity: "user-2"))
    check("another login in the home during the credential read cancels, nothing sent",
          otherLogin == .cancelled && wire.requests.isEmpty)
    let changedHands = await runner.claim(approval, confirmed: true,
                                          env: environment(wire, current: { entry([full], identity: "user-2") }))
    check("a reading now under another login cancels", changedHands == .cancelled && wire.requests.isEmpty)
    let removed = await runner.claim(approval, confirmed: true, env: environment(wire, listed: { false }))
    check("an account removed meanwhile cancels", removed == .cancelled && wire.requests.isEmpty)

    // One claim at a time, whichever panel or menu asks.
    wire = Wire()
    runner = BrimClaudeClaimRunner()
    let slow = environment(wire, delay: 0.3)
    let first = Task { await runner.claim(approval, confirmed: true, env: slow) }
    try? await Task.sleep(for: .milliseconds(50))
    check("a claim is out: the runner is busy", runner.isBusy)
    let second = await runner.claim(approval, confirmed: true, env: environment(wire))
    let firstOutcome = await first.value
    check("a second claim while one is out is refused", second == .cancelled)
    check("…and the first one goes through alone", wire.requests.count == 1 && firstOutcome != .cancelled)
    check("…the runner is free again after", !runner.isBusy)

    // An unclear answer: read again first; the next claim of that grant reuses the request id.
    wire = Wire()
    runner = BrimClaudeClaimRunner()
    wire.answers = [.failure(Dropped())]
    let unclear = await runner.claim(approval, confirmed: true, env: environment(wire))
    check("a dropped connection is uncertain", unclear == .uncertain)
    check("…shown as checking, not as used or failed", BrimClaudeClaimRunner.status(unclear) == .checking(spent: nil))
    check("…its request id kept for that login and grant", runner.pendingRequestID(for: approval) != nil)
    check("…nothing settled while no newer reading is in", BrimClaudeClaimRunner.afterUncertain(approval, entry: held) == nil)
    check("a newer reading with one fewer: it was used",
          BrimClaudeClaimRunner.afterUncertain(approval, entry: entry([grant(.full, id: "full-reset-2611", left: 0)],
                                                                    at: checkedAt.addingTimeInterval(90))) == .used)
    check("a newer reading still holding it: not used",
          BrimClaudeClaimRunner.afterUncertain(approval, entry: entry([full], at: checkedAt.addingTimeInterval(90))) == .notApplied)
    _ = await runner.claim(approval, confirmed: true, env: environment(wire))
    check("trying again after the re-read sends the same request id",
          wire.requests.count == 2 && (wire.body(0)["request_id"] as? String) == (wire.body(1)["request_id"] as? String))
    check("…and a settled answer clears it", runner.pendingRequestID(for: approval) == nil)

    wire = Wire()
    wire.answers = [.success((503, "")), .success((429, ""))]
    let busy = await runner.claim(approval, confirmed: true, env: environment(wire))
    check("a 5xx is uncertain too", busy == .uncertain && runner.pendingRequestID(for: approval) != nil)
    let limited = await runner.claim(approval, confirmed: true, env: environment(wire))
    check("a 429 is rate limited, and drops the kept id", limited == .rateLimited && runner.pendingRequestID(for: approval) == nil)
    check("…shown as a refusal", BrimClaudeClaimRunner.status(limited) == .refused(.rateLimited))
    wire.answers = [.success((200, #"{"result":"not_limited"}"#))]
    let notLimited = await runner.claim(approval, confirmed: true, env: environment(wire))
    check("not at a limit: refused, nothing spent", BrimClaudeClaimRunner.status(notLimited) == .refused(.notLimited))
    runner.forget(accountID: approval.accountID)

    // The last look, after the last await and right before the POST.
    final class Box<T>: @unchecked Sendable { var value: T; init(_ value: T) { self.value = value } }
    func lastLook(_ change: @escaping () -> Void, current: Box<BrimClaudeResetSchedule.Entry?> = Box(held),
                  listed: Box<Bool> = Box(true), clock: Box<Date> = Box(when),
                  login: Box<String> = Box("user-1")) -> (BrimClaudeClaimRunner.Environment, Wire) {
        let wire = Wire()
        var env = environment(wire, current: { current.value }, listed: { listed.value })
        env.now = { clock.value }
        env.identityNow = {
            change()
            return .init(accountID: login.value, organizationID: organization)
        }
        return (env, wire)
    }
    runner = BrimClaudeClaimRunner()
    let goodLook = lastLook({})
    let lookOK = await runner.claim(approval, confirmed: true, env: goodLook.0)
    check("last look: the same login, reading and token: one POST", goodLook.1.requests.count == 1
          && lookOK == .result(.reset, resetsLeft: 0, cooldownUntil: nil))
    let otherNow = Box("user-1")
    let swapped = lastLook({ otherNow.value = "user-2" }, login: otherNow)
    let swappedOutcome = await runner.claim(approval, confirmed: true, env: swapped.0)
    check("last look: another login in the home right before the POST cancels, nothing sent",
          swappedOutcome == .cancelled && swapped.1.requests.isEmpty)
    check("…and keeps no request id for it", runner.pendingRequestID(for: approval) == nil)
    let reading = Box<BrimClaudeResetSchedule.Entry?>(held)
    let reRead = lastLook({ reading.value = entry([full], at: checkedAt.addingTimeInterval(45)) }, current: reading)
    let reReadOutcome = await runner.claim(approval, confirmed: true, env: reRead.0)
    check("last look: a newer reading landing meanwhile cancels", reReadOutcome == .cancelled && reRead.1.requests.isEmpty)
    let otherOrg = Box<BrimClaudeResetSchedule.Entry?>(held)
    let moved = lastLook({ otherOrg.value = entry([full], identity: "user-9") }, current: otherOrg)
    let movedOutcome = await runner.claim(approval, confirmed: true, env: moved.0)
    check("last look: the reading now under another login cancels", movedOutcome == .cancelled && moved.1.requests.isEmpty)
    let gone = Box(true)
    let removedLook = lastLook({ gone.value = false }, listed: gone)
    let removedOutcome = await runner.claim(approval, confirmed: true, env: removedLook.0)
    check("last look: the account removed meanwhile cancels", removedOutcome == .cancelled && removedLook.1.requests.isEmpty)
    // The fixture token ends at 1_900_000_000: a clock that reaches within two minutes of it.
    let late = Box(when)
    let expiringLook = lastLook({ late.value = Date(timeIntervalSince1970: 1_900_000_000 - 60) }, clock: late)
    let lateGrant = BrimClaudeClaimRunner.approval(accountID: approval.accountID, home: approval.home, kind: .full,
        entry: entry([ClaudeResetInventory.Grant(id: .init(raw: "full-reset-2611"), kind: .full, name: "full", left: 1,
                                                 total: 1, endsAt: Date(timeIntervalSince1970: 1_950_000_000),
                                                 usableNow: true, useRequiresLimit: false)]), now: when)
    if let lateGrant {
        let longHeld = entry([ClaudeResetInventory.Grant(id: .init(raw: "full-reset-2611"), kind: .full, name: "full",
                                                         left: 1, total: 1, endsAt: Date(timeIntervalSince1970: 1_950_000_000),
                                                         usableNow: true, useRequiresLimit: false)])
        var env = expiringLook.0
        env.currentEntry = { longHeld }
        let expiringOutcome = await runner.claim(lateGrant, confirmed: true, env: env)
        check("last look: a token now within two minutes of its end sends nothing",
              expiringOutcome == .loginExpiring && expiringLook.1.requests.isEmpty)
    } else {
        check("long-lived grant fixture gives a consent", false)
    }
    let ended = Box(when)
    let endedLook = lastLook({ ended.value = checkedAt.addingTimeInterval(21 * 86400) }, clock: ended)
    let endedOutcome = await runner.claim(approval, confirmed: true, env: endedLook.0)
    check("last look: a grant that ended meanwhile cancels", endedOutcome == .cancelled && endedLook.1.requests.isEmpty)
    check("…the runner is free after every refusal", !runner.isBusy)
}
await claimChecks()

check("the app re-reads the login right before the POST",
      source("UsageBar/Stores/BrimResetUseStore.swift").contains("identityNow: {"))

let parts = source("UsageBar/Views/BrimPanelParts.swift")
let confirmView = parts.components(separatedBy: "struct BrimLinkButtonStyle").first ?? ""
let cancelButton = confirmView.range(of: "Button(L(\"Cancel\"), action: onCancel)")
check("the card's Cancel is the default action and takes the focus",
      cancelButton.map { confirmView[$0.upperBound...].prefix(260) }.map {
          $0.contains(".keyboardShortcut(.defaultAction)") && $0.contains(".focused($cancelFocused)")
      } == true && confirmView.contains(".onAppear { cancelFocused = true }"))
check("…and Use is not", confirmView.components(separatedBy: ".keyboardShortcut(.defaultAction)").count == 2
      && confirmView.contains("Button(L(\"Reset now\")) { onUse?() }"))
check("…it says it can't be undone", confirmView.contains("L(\"Can't be undone.\")"))
// MARK: - The panel in live mode

let format = BrimPanelModel.Format(timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "tr_TR"))
let english = BrimPanelModel.Format(timeZone: TimeZone(identifier: "UTC")!)
check("Turkish percentage: %96", BrimPercent.text(96, locale: Locale(identifier: "tr")) == "%96"
      && format.percent(95.6) == "%96")
check("English percentage: 96%", BrimPercent.text(96, locale: Locale(identifier: "en")) == "96%"
      && english.percent(95.6) == "96%")
check("a cell in Turkish reads %62", BrimPanelModel.cell(62, format: format).percentText == "%62")

func snapshot() -> UsageSnapshot {
    let json = """
    {"version":2,"generatedAt":"2027-01-15T08:00:00Z","statuslineFullQuota":false,"accounts":[
      {"id":"claude:.claude3","provider":"claude","label":"Work","plan":"Max","sessionRemaining":12,
       "weeklyRemaining":40,"modelRemaining":30,"modelWindowName":"Fable","isStale":false},
      {"id":"codex:.codex","provider":"codex","label":"Codex","weeklyRemaining":5,"resetCreditsAvailable":1,
       "resetCreditsNextExpiry":"2027-01-30T00:00:00Z","isStale":false}]}
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try! decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
}
let panelNow = ISO8601DateFormatter().date(from: "2027-01-15T08:05:00Z")!
let claude = BrimPanelModel.ClaudeResets(state: .read([
    .init(kind: .full, left: 1, endsAt: panelNow.addingTimeInterval(20 * 86400), usable: true),
    .init(kind: .fable, left: 1, endsAt: panelNow.addingTimeInterval(10 * 86400), usable: true)]), problem: nil)
func panel(uses: [String: BrimPanelModel.ResetUse] = [:]) -> BrimPanelModel {
    .make(snapshot: snapshot(), readFailed: false, loaded: true, now: panelNow,
          claudeResets: ["claude:.claude3": claude], resetUses: uses, format: format)
}
let liveRows = panel().groups.flatMap(\.rows)
check("live mode: Claude's and Codex's reset lines open the card", liveRows.allSatisfy(\.resetUsable))
check("…offering Claude's kinds soonest-ending first",
      BrimPanelModel.usableKinds(liveRows[0]) == [.fable, .full])
check("not while a reset is out on that account",
      !panel(uses: ["claude:.claude3": .working]).groups[0].rows[0].resetUsable
          && !panel(uses: ["claude:.claude3": .checking(spent: nil)]).groups[0].rows[0].resetUsable)
let words = BrimPanelText(localize: { $0 })
check("old data shows its age", words.stale(12) == "Data 12 min old")
let effects = { (kind: BrimPanelModel.ResetKind) in BrimPanelModel.resetEffects(liveRows[0], kind: kind).map(\.window) }
check("a full reset gives back 5 hours, weekly and Fable", effects(.full) == [.model("Fable"), .fiveHour, .weekly])
check("a Fable reset gives back 5 hours and Fable only", effects(.fable) == [.model("Fable"), .fiveHour])
check("a Codex reset without a 5-hour window gives back the week",
      BrimPanelModel.resetEffects(liveRows[1], kind: .codex).map(\.window) == [.weekly])
check("the card shows what each window reads now",
      BrimPanelModel.resetEffects(liveRows[0], kind: .full).first?.before.percentText == "%30")
let used = panel(uses: ["claude:.claude3": .used]).groups[0].rows[0]
check("after use: Used · 5 hours %12 (the measured value)", words.resetUse(.used, row: used) == "Checking again…")
check("while measuring: Checking again…", words.resetUse(.checking(spent: true), row: used) == "Checking again…")
check("a refusal says why", words.resetUse(.refused(.notLimited), row: used) == "Not used: this account is not at a limit.")

check("windows are Fable, five hours, weekly", BrimPanelModel.windows(liveRows[0]).map(\.window) == [.model("Fable"), .fiveHour, .weekly])
let quotaBody = Data(#"{"five_hour":{"utilization":0},"seven_day":{"utilization":20},"seven_day_fable":{"utilization":4}}"#.utf8)
let quota = ClaudeResetInventory.parse(quotaBody, now: panelNow)
check("inventory GET also reads quotas", quota?.remaining == ["five_hour":100,"seven_day":80,"seven_day_fable":96])
var quotaInput = claude
quotaInput.remaining = quota!.remaining
quotaInput.checkedAt = panelNow
let refreshed = BrimPanelModel.make(snapshot: snapshot(), readFailed: false, loaded: true, now: panelNow,
    claudeResets: ["claude:.claude3":quotaInput], format: format).groups[0].rows[0]
check("panel uses newer quota GET", refreshed.fiveHour.remaining == 100 && refreshed.model?.cell.remaining == 96)
check("success names only confirmed full quota", words.resetUse(.used, row: refreshed) == "Reset done · 5 hours %100")
if failures > 0 { print("\(failures) FAILED"); exit(1) }
print("ALL PASS")
