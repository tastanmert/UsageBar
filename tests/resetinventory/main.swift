import Foundation

// Claude limit-reset inventory, UsageBar's read-only copy of the `mert/feat/claude-reset-inventory`
// branch: the `cedar_ember` parser and Claude Code's kind rule (fixtures from that branch's suite),
// the credential path (expired or expiring token: nothing sent, never refreshed), the request
// (a GET carrying the token only as bearer), the schedule (10 min cadence, 401/403 and 429
// back-offs, held-over readings) and the panel's unknown-versus-zero rule. No network and no
// Keychain: every credential read and every transport is injected.

var passed = 0
var failed = 0
func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() { passed += 1 } else { failed += 1; print("FAIL: \(label)") }
}
func data(_ text: String) -> Data { Data(text.utf8) }
func iso(_ text: String) -> Date { ClaudeResetInventory.date(text)! }

actor Capture {
    private(set) var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
}

let now = iso("2026-11-11T12:00:00+00:00")

// The two grants of a Max account, as the endpoint returned them (2026-11-11).
let fullGrant = """
{"id": "full-reset-2611", "label": "One full limit reset (November 2026)",
 "resets_total": 1, "resets_left": 1,
 "starts_at": "2026-11-10T21:30:00+00:00", "ends_at": "2026-12-10T22:00:00+00:00",
 "clears": ["five_hour","seven_day","seven_day_overage_included"],
 "paused": false, "usable_now": true, "use_requires_limit": false,
 "percent_used": {"five_hour":15,"seven_day":84,"seven_day_overage_included":71},
 "blocking": [], "arm": null, "type": "full", "unavailable_reason": null, "gives_back_weekly": false}
"""
let fableGrant = """
{"id": "launch-2610-fable", "label": "New model launch: one Fable reset for Max, Team Premium and Enterprise Premium",
 "resets_total": 1, "resets_left": 1,
 "starts_at": "2026-11-09T18:00:00+00:00", "ends_at": "2027-03-09T07:59:00+00:00",
 "clears": ["five_hour","seven_day_overage_included"],
 "paused": false, "usable_now": true, "use_requires_limit": false,
 "percent_used": {"five_hour":15,"seven_day_overage_included":71,"seven_day":84},
 "blocking": [], "arm": null, "type": "full", "unavailable_reason": null, "gives_back_weekly": true}
"""
func body(_ grants: [String], eligible: String = "true") -> Data {
    data("""
    {"five_hour": {"utilization": 15}, "cedar_ember": {
      "eligible": \(eligible), "ineligible_reason": null, "at_limit": false, "exhausted": [],
      "grants": [\(grants.joined(separator: ","))],
      "next_grant_id": "full-reset-2611", "weekly_resets_at": "2026-11-11T20:00:00+00:00",
      "cooldown_until": null, "event_props": {}, "paused_held": false}}
    """)
}

// MARK: The Max account: a full reset and a Fable reset whose type also says "full"
let maxRead = ClaudeResetInventory.parse(body([fullGrant, fableGrant]), now: now)
expect(maxRead?.eligible == true, "max: eligible")
expect(maxRead?.grants.map(\.kind) == [.full, .fable], "max: gives_back_weekly wins over type full")
expect(maxRead?.left == 2, "max: two resets left in total")
expect(maxRead?.byKind.map(\.kind) == [.full, .fable], "max: soonest-ending kind first")
expect(maxRead?.byKind.first?.endsAt == iso("2026-12-10T22:00:00+00:00"), "max: the full reset's end")
expect(maxRead?.byKind.last?.endsAt == iso("2027-03-09T07:59:00+00:00"), "max: the Fable reset's end")
expect(maxRead.map { !String(describing: $0).contains("full-reset-2611") && !String(describing: $0).contains("launch-2610") } == true,
       "max: grant ids do not survive the parse")

// MARK: The Pro account: one week-long Fable reset
let proGrant = """
{"id": "launch-2610-fable-week", "resets_total": 1, "resets_left": 1,
 "starts_at": "2026-11-09T18:00:00+00:00", "ends_at": "2026-11-17T07:59:00+00:00",
 "clears": ["five_hour","seven_day_overage_included"], "paused": false, "type": "full",
 "gives_back_weekly": true}
"""
let pro = ClaudeResetInventory.parse(body([proGrant]), now: now)
expect(pro?.byKind.count == 1 && pro?.byKind.first?.kind == .fable && pro?.byKind.first?.left == 1,
       "pro: one Fable reset")

// MARK: Outside the program
let ineligible = data("""
{"cedar_ember": {"eligible": false, "ineligible_reason": "plan_not_eligible", "grants": []}}
""")
expect(ClaudeResetInventory.parse(ineligible, now: now) == ClaudeResetInventory(eligible: false, grants: []),
       "eligible false: no inventory")
expect(ClaudeResetInventory.parse(body([fullGrant], eligible: "false"), now: now)?.grants.isEmpty == true,
       "eligible false: grants listed anyway are not counted")
expect(ClaudeResetInventory.parse(data("{\"cedar_ember\": null}"), now: now)?.eligible == false,
       "cedar_ember null: no inventory")
expect(ClaudeResetInventory.parse(data("{\"five_hour\": {}}"), now: now)?.eligible == false,
       "cedar_ember missing: no inventory")
expect(ClaudeResetInventory.parse(body([fullGrant], eligible: "\"yes\""), now: now) == nil,
       "eligible not a boolean: cannot tell, not ineligible")
expect(ClaudeResetInventory.parse(data("{\"cedar_ember\": \"on\"}"), now: now) == nil,
       "cedar_ember not an object: cannot tell")
for text in ["", "{", "[]", "null", "\"cedar_ember\"", "<html>rate limited</html>"] {
    expect(ClaudeResetInventory.parse(data(text), now: now) == nil, "unreadable body \(text) is unknown, not empty")
}

// MARK: Grants that do not count
func variant(_ grant: String, _ edits: [(String, String)]) -> String {
    edits.reduce(grant) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
}
let expired = variant(fullGrant, [("\"ends_at\": \"2026-12-10T22:00:00+00:00\"", "\"ends_at\": \"2026-11-11T11:59:59+00:00\"")])
let future = variant(fullGrant, [("\"starts_at\": \"2026-11-10T21:30:00+00:00\"", "\"starts_at\": \"2026-11-12T00:00:00+00:00\"")])
let paused = variant(fullGrant, [("\"paused\": false", "\"paused\": true")])
let endsNow = variant(fullGrant, [("\"ends_at\": \"2026-12-10T22:00:00+00:00\"", "\"ends_at\": \"2026-11-11T12:00:00+00:00\"")])
expect(ClaudeResetInventory.parse(body([expired, fableGrant]), now: now)?.grants.map(\.kind) == [.fable],
       "expired grant dropped, the rest kept")
expect(ClaudeResetInventory.parse(body([endsNow]), now: now)?.grants.isEmpty == true, "a grant ending now is over")
expect(ClaudeResetInventory.parse(body([future]), now: now)?.grants.isEmpty == true, "a grant not started yet is not counted")
expect(ClaudeResetInventory.parse(body([paused]), now: now)?.grants.isEmpty == true, "paused grant not counted")
let broken = [
    variant(fullGrant, [("\"resets_left\": 1", "\"resets_left\": \"one\"")]),
    variant(fullGrant, [("\"resets_left\": 1", "\"resets_left\": true")]),
    variant(fullGrant, [("\"resets_left\": 1", "\"resets_left\": 1.5")]),
    variant(fullGrant, [("\"resets_left\": 1", "\"resets_left\": -1")]),
    variant(fullGrant, [("\"resets_left\": 1,", "")]),
    variant(fullGrant, [("\"ends_at\": \"2026-12-10T22:00:00+00:00\"", "\"ends_at\": \"next month\"")]),
    variant(fullGrant, [("\"starts_at\": \"2026-11-10T21:30:00+00:00\",", "")]),
    variant(fullGrant, [("\"paused\": false", "\"paused\": \"no\"")]),
    variant(fullGrant, [("\"gives_back_weekly\": false", "\"gives_back_weekly\": 0")]),
    variant(fullGrant, [("\"type\": \"full\"", "\"type\": 3")]),
    variant(fullGrant, [("\"type\": \"full\"", "\"type\": null"),
                        ("\"clears\": [\"five_hour\",\"seven_day\",\"seven_day_overage_included\"]", "\"clears\": []")]),
    "\"not an object\"", "17",
]
for grant in broken {
    expect(ClaudeResetInventory.parse(body([grant, fableGrant]), now: now) == nil,
           "one unreadable grant fails the whole read, not a shorter list: \(grant.prefix(60))")
}
// Out of scope is decided from starts_at, ends_at and paused alone: a lapsed grant in some other
// shape is skipped, it does not fail the read.
let lapsedOdd = variant(expired, [("\"resets_left\": 1", "\"resets_left\": \"one\""), ("\"type\": \"full\"", "\"type\": 3")])
let pausedOdd = variant(paused, [("\"gives_back_weekly\": false", "\"gives_back_weekly\": 0")])
expect(ClaudeResetInventory.parse(body([lapsedOdd, pausedOdd, fableGrant]), now: now)?.grants.map(\.kind) == [.fable],
       "out-of-scope grants are skipped even when another field is odd")
for grants in ["{}", "null", "\"none\""] {
    let text = "{\"cedar_ember\": {\"eligible\": true, \"grants\": \(grants)}}"
    expect(ClaudeResetInventory.parse(data(text), now: now) == nil, "eligible with grants \(grants): cannot tell, not empty")
}
expect(ClaudeResetInventory.parse(data("{\"cedar_ember\": {\"eligible\": true}}"), now: now) == nil,
       "eligible with no grants key: cannot tell, not empty")
let spent = variant(fullGrant, [("\"resets_left\": 1", "\"resets_left\": 0")])
let none = ClaudeResetInventory.parse(body([spent]), now: now)
expect(none?.eligible == true && none?.left == 0 && none?.byKind.isEmpty == true && none?.grants.count == 1,
       "eligible with nothing left: in force, zero, no line")
expect(ClaudeResetInventory.parse(body([]), now: now)?.grants.isEmpty == true,
       "eligible with no grants: empty inventory")
let twoFull = variant(fullGrant, [("\"resets_left\": 1", "\"resets_left\": 2"), ("\"resets_total\": 1", "\"resets_total\": 2"),
                                  ("\"ends_at\": \"2026-12-10T22:00:00+00:00\"", "\"ends_at\": \"2026-11-30T00:00:00.500+00:00\"")])
let summed = ClaudeResetInventory.parse(body([fullGrant, twoFull]), now: now)
expect(summed?.byKind.count == 1 && summed?.byKind.first?.left == 3, "same kind: counts summed")
expect(summed?.byKind.first?.endsAt == iso("2026-11-30T00:00:00.500+00:00"), "same kind: soonest end, fractional seconds read")

// MARK: Claude Code's kind rule
typealias K = ClaudeResetInventory
expect(K.kind(givesBackWeekly: true, type: "session", clears: ["five_hour"]) == .fable, "rule: weekly give-back is Fable")
expect(K.kind(givesBackWeekly: false, type: "weekly", clears: ["five_hour"]) == .weekly, "rule: a known type names it")
expect(K.kind(givesBackWeekly: false, type: nil, clears: ["five_hour"]) == .session, "rule: only five_hour is a 5-hour reset")
expect(K.kind(givesBackWeekly: false, type: nil, clears: ["seven_day"]) == .weekly, "rule: no five_hour is weekly")
expect(K.kind(givesBackWeekly: false, type: nil, clears: ["five_hour", "seven_day"]) == .full, "rule: both is full")
expect(K.kind(givesBackWeekly: false, type: nil, clears: []) == .full, "rule: nothing named reads as full")
expect(K.kind(givesBackWeekly: false, type: "renamed", clears: ["five_hour"]) == .other,
       "rule: an unknown type is its own kind, not read off the windows")
expect(K.kind(givesBackWeekly: true, type: "renamed", clears: ["five_hour"]) == .fable,
       "rule: weekly give-back still wins over an unknown type")
let renamed = variant(fullGrant, [("\"type\": \"full\"", "\"type\": \"renamed\""),
                                  ("\"clears\": [\"five_hour\",\"seven_day\",\"seven_day_overage_included\"]", "\"clears\": [\"five_hour\"]")])
let renamedRead = ClaudeResetInventory.parse(body([renamed]), now: now)
expect(renamedRead?.grants.first?.kind == .other && renamedRead?.grants.first?.name == "renamed",
       "unknown type: kind other, the raw type kept for the snapshot")
expect(maxRead?.grants.map(\.name) == ["full", "fable"], "known kinds: the snapshot name is the kind")


// MARK: The credential: usable, expiring (nothing sent, never refreshed), missing
let token = "sk-ant-oat01-FIXTURE-SECRET-\(UUID().uuidString)"
func blob(expiresAt: String, token: String = token) -> Data {
    data("{\"claudeAiOauth\":{\"accessToken\":\"\(token)\",\"refreshToken\":\"r-\(token)\",\"expiresAt\":\(expiresAt),\"refreshTokenExpiresAt\":1891617039890}}")
}
func millis(_ offset: TimeInterval) -> String { "\(Int((now.timeIntervalSince1970 + offset) * 1000))" }
typealias F = ClaudeResetInventoryFetch
func usable(_ read: F.CredentialRead) -> F.Credential? {
    if case .usable(let credential) = read { return credential }
    return nil
}
func reason(_ read: F.CredentialRead) -> F.NoCredential? {
    if case .none(let reason) = read { return reason }
    return nil
}
expect(usable(F.credential(from: blob(expiresAt: millis(3600)), now: now)) != nil, "credential: a live token is usable")
expect(reason(F.credential(from: blob(expiresAt: millis(-1)), now: now)) == .expiring, "credential: expired token is not used")
expect(reason(F.credential(from: blob(expiresAt: millis(90)), now: now)) == .expiring,
       "credential: a token inside two minutes of expiry is not used")
expect(usable(F.credential(from: blob(expiresAt: millis(150)), now: now)) != nil, "credential: past the two-minute margin it is")
for value in ["null", "\"\(millis(3600))\"", "true", "1891617039", "1e309"] {
    expect(reason(F.credential(from: blob(expiresAt: value), now: now)) == .missing,
           "credential: undated or oddly dated token \(value) is not used")
}
expect(reason(F.credential(from: blob(expiresAt: millis(3600), token: ""), now: now)) == .missing, "credential: empty token")
expect(reason(F.credential(from: data("{}"), now: now)) == .missing, "credential: no oauth block")

if let credential = usable(F.credential(from: blob(expiresAt: millis(3600)), now: now)) {
    var dumped = ""
    dump(credential, to: &dumped)
    let printed = [String(describing: credential), String(reflecting: credential), "\(credential)", dumped]
    expect(printed.allSatisfy { !$0.contains(token) && !$0.contains("FIXTURE-SECRET") },
           "credential: no description, debug print or dump carries the token")
    let request = F.request(credential, version: "2.1.311")
    expect(request.value(forHTTPHeaderField: "User-Agent") == "claude-cli/2.1.311 (external, cli)",
           "request: Claude Code's own User-Agent")
    expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)", "request: token only as bearer")
    expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage?cedar_ember=1",
           "request: Claude Code's endpoint, token not in the URL")
    expect(request.httpMethod == "GET" && request.httpBody == nil, "request: a GET with no body")
    let others = (request.allHTTPHeaderFields ?? [:]).filter { $0.key != "Authorization" }
    expect(!others.values.contains { $0.contains(token) }, "request: no other header carries the token")
}

// MARK: Which credential is read: the Keychain item wins as a whole
let home = "/tmp/fixture/.claude2"
let defaultHome = "/tmp/fixture-home/.claude"
var fileReads = 0
func read(_ source: ClaudeLoginExpiry.Source, file: Data?) -> F.CredentialRead {
    F.readCredential(home: home, defaultHome: defaultHome, now: now, keychainRead: { _ in source },
                     fileRead: { _ in fileReads += 1; return file })
}
let good = blob(expiresAt: millis(3600))
expect(usable(read(.init(data: good), file: nil)) != nil, "keychain: a readable item is used")
expect(reason(read(.init(data: data("not json")), file: good)) == .missing && fileReads == 0,
       "keychain: a malformed item does not fall back to the file")
expect(reason(read(.init(data: nil), file: good)) == .unreadable && fileReads == 0,
       "keychain: a locked or denied item does not fall back to the file (and never prompts)")
expect(usable(read(.init(data: nil, isAbsent: true), file: good)) != nil && fileReads == 1,
       "keychain: only an absent item falls back to .credentials.json")
expect(reason(read(.init(data: nil, isAbsent: true), file: nil)) == .missing, "keychain: absent and no file is missing")
var services: [String] = []
_ = F.readCredential(home: home, defaultHome: defaultHome, now: now,
                     keychainRead: { services.append($0); return .init(data: nil) }, fileRead: { _ in nil })
expect(services == [ClaudeLoginExpiry.keychainService(home: home, defaultHome: defaultHome)],
       "keychain: Claude Code's per-folder service name")

// MARK: Version off the launcher's symlink
expect(F.version(executable: nil) == F.fallbackVersion, "version: no CLI found falls back")
expect(F.userAgent(version: F.fallbackVersion) == "claude-cli/2.1.311 (external, cli)", "version: the fallback User-Agent")

// MARK: The fetch with a fake transport: what is sent, and when nothing is
func reply(_ status: Int, _ body: Data = Data()) -> F.Transport {
    { request in
        (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
func run(_ credential: F.CredentialRead, transport: @escaping F.Transport) -> (F.Outcome, [URLRequest]) {
    let capture = Capture()
    let box = OutcomeBox()
    let done = DispatchSemaphore(value: 0)
    Task {
        let outcome = await F.fetch(home: home, now: now, version: "2.1.400",
                                    readCredential: { _, _ in credential },
                                    transport: { request in
                                        await capture.append(request)
                                        return try await transport(request)
                                    })
        box.outcome = outcome
        box.requests = await capture.requests
        done.signal()
    }
    done.wait()
    return (box.outcome!, box.requests)
}
final class OutcomeBox: @unchecked Sendable {
    var outcome: F.Outcome?
    var requests: [URLRequest] = []
}
let neverCalled: F.Transport = { _ in fatalError("a request went out") }
let expiring = run(F.credential(from: blob(expiresAt: millis(-60)), now: now), transport: neverCalled)
expect(expiring.0 == .noCredential(.expiring) && expiring.1.isEmpty, "fetch: an expired token sends nothing")
let soon = run(F.credential(from: blob(expiresAt: millis(100)), now: now), transport: neverCalled)
expect(soon.0 == .noCredential(.expiring) && soon.1.isEmpty, "fetch: a token two minutes from expiry sends nothing")
let locked = run(.none(.unreadable), transport: neverCalled)
expect(locked.0 == .noCredential(.unreadable) && locked.1.isEmpty, "fetch: an unreadable Keychain item sends nothing")
let ok = run(F.credential(from: good, now: now), transport: reply(200, body([fullGrant, fableGrant])))
if case .read(let inventory) = ok.0 {
    expect(inventory.eligible && inventory.left == 2, "fetch: 200 is read")
} else {
    expect(false, "fetch: 200 is read")
}
expect(ok.1.count == 1 && ok.1.first?.httpMethod == "GET", "fetch: exactly one GET")
let refused = run(F.credential(from: good, now: now), transport: reply(401))
expect(refused.0 == .failed(status: 401), "fetch: 401 carries its status")
let limited = run(F.credential(from: good, now: now), transport: reply(429))
expect(limited.0 == .failed(status: 429), "fetch: 429 carries its status")
let offline = run(F.credential(from: good, now: now), transport: { _ in throw URLError(.notConnectedToInternet) })
expect(offline.0 == .failed(status: nil), "fetch: a network error has no status")
let garbled = run(F.credential(from: good, now: now), transport: reply(200, data("<html>")))
expect(garbled.0 == .failed(status: 200), "fetch: an unreadable 200 is a failure, not an empty inventory")
expect(![expiring.0, refused.0, offline.0].contains { String(describing: $0).contains(token) },
       "outcome: no outcome carries the token")

// MARK: The schedule: 10 minutes, back-offs, held-over readings
typealias Schedule = BrimClaudeResetSchedule
let id = "claude:.claude2"
var schedule = Schedule()
expect(schedule.begin(id, now: now), "schedule: a new account is due")
expect(!schedule.begin(id, now: now), "schedule: not twice while a request is out")
schedule.land(id, .read(maxRead!), now: now)
expect(!schedule.isDue(id, now: now.addingTimeInterval(9 * 60 + 59)), "schedule: not again inside 10 minutes")
expect(schedule.isDue(id, now: now.addingTimeInterval(10 * 60)), "schedule: due after 10 minutes")
// 401: an hour's back-off, the last reading held over.
let t1 = now.addingTimeInterval(10 * 60)
expect(schedule.begin(id, now: t1), "schedule: asks again")
schedule.land(id, .failed(status: 401), now: t1)
expect(!schedule.isDue(id, now: t1.addingTimeInterval(59 * 60)), "schedule: 401 backs off for 60 minutes")
expect(schedule.isDue(id, now: t1.addingTimeInterval(60 * 60)), "schedule: due again after the 401 back-off")
let held = schedule.panelInput(id)
if case .read(let grants) = held.state {
    expect(grants.count == 2 && held.problem == .rejected, "schedule: after a 401 the last reading is held over, marked")
} else {
    expect(false, "schedule: after a 401 the last reading is held over, marked")
}
var forbidden = Schedule()
_ = forbidden.begin(id, now: now)
forbidden.land(id, .failed(status: 403), now: now)
expect(!forbidden.isDue(id, now: now.addingTimeInterval(59 * 60)) && forbidden.isDue(id, now: now.addingTimeInterval(3600)),
       "schedule: 403 backs off for 60 minutes")
expect(forbidden.panelInput(id) == .init(state: .unknown, problem: .rejected), "schedule: 403 with nothing read is unknown")
var limitedSchedule = Schedule()
_ = limitedSchedule.begin(id, now: now)
limitedSchedule.land(id, .failed(status: 429), now: now)
expect(!limitedSchedule.isDue(id, now: now.addingTimeInterval(29 * 60))
           && limitedSchedule.isDue(id, now: now.addingTimeInterval(30 * 60)), "schedule: 429 backs off for 30 minutes")
var offlineSchedule = Schedule()
_ = offlineSchedule.begin(id, now: now)
offlineSchedule.land(id, .read(pro!), now: now)
_ = offlineSchedule.begin(id, now: now.addingTimeInterval(600))
offlineSchedule.land(id, .failed(status: nil), now: now.addingTimeInterval(600))
expect(offlineSchedule.panelInput(id).problem == .failed && offlineSchedule.isDue(id, now: now.addingTimeInterval(1200)),
       "schedule: a network error holds the reading over and keeps the 10 minute cadence")
var waiting = Schedule()
_ = waiting.begin(id, now: now)
waiting.land(id, .noCredential(.expiring), now: now)
expect(waiting.panelInput(id) == .init(state: .unknown, problem: .loginExpiring),
       "schedule: an expiring login is unknown, waiting for UsageBar")
expect(!waiting.isDue(id, now: now.addingTimeInterval(119)) && waiting.isDue(id, now: now.addingTimeInterval(120)),
       "schedule: with nothing sent, the login is looked at again after 2 minutes")
expect(Schedule().panelInput(id) == .init(state: .unknown, problem: .notReadYet), "schedule: never asked is unknown")
var pruned = Schedule()
_ = pruned.begin(id, now: now)
pruned.land(id, .read(maxRead!), now: now)
pruned.prune(keeping: [])
expect(pruned.entries.isEmpty, "schedule: a gone account is forgotten")

// MARK: Unknown is not zero (the panel's rule)
let utc = BrimPanelModel.Format(timeZone: TimeZone(identifier: "UTC")!)
func credits(_ input: BrimPanelModel.ClaudeResets) -> (BrimPanelModel.ResetCredit?, BrimPanelModel.ResetUnknown?) {
    BrimPanelModel.claudeCredits(input, id: id, now: now, format: utc)
}
var readMax = Schedule()
_ = readMax.begin(id, now: now)
readMax.land(id, .read(maxRead!), now: now)
let maxCredits = credits(readMax.panelInput(id))
expect(maxCredits.0?.count == 2 && maxCredits.1 == nil, "panel: two resets read")
expect(maxCredits.0?.lines.map(\.kind) == [.full, .fable] && maxCredits.0?.lines.map(\.count) == [1, 1],
       "panel: full and Fable listed apart, soonest-ending first")
expect(maxCredits.0?.lines.first?.expires == "10 Dec" && maxCredits.0?.lines.last?.expires == "9 Mar",
       "panel: each line's expiry")
var readSpent = Schedule()
_ = readSpent.begin(id, now: now)
readSpent.land(id, .read(none!), now: now)
let zero = credits(readSpent.panelInput(id))
expect(zero.0?.count == 0 && zero.0?.lines.isEmpty == true && zero.1 == nil, "panel: the server said 0, so 0")
var readIneligible = Schedule()
_ = readIneligible.begin(id, now: now)
readIneligible.land(id, .read(ClaudeResetInventory.parse(ineligible, now: now)!), now: now)
let notIn = credits(readIneligible.panelInput(id))
expect(notIn.0 == nil && notIn.1 == .notInProgram, "panel: not in the program is unknown, not 0")
expect(credits(waiting.panelInput(id)).0 == nil && credits(waiting.panelInput(id)).1 == .loginExpiring,
       "panel: an expiring login is unknown, not 0")
expect(credits(Schedule().panelInput(id)).1 == .notReadYet, "panel: never read is unknown, not 0")
let heldCredits = credits(held)
expect(heldCredits.0?.count == 2 && heldCredits.0?.heldOver == true && heldCredits.0?.note == .rejected,
       "panel: a held-over count is shown dimmed with its reason")

let limitedCredit = ClaudeResetInventory.parse(data(#"{"extra_usage":{"is_enabled":true,"used_credits":541,"monthly_limit":2000}}"#), now: now)!
expect(limitedCredit.credit == .init(usedCents: 541, limitCents: 2000, enabled: true), "credit: USD cents with limit")
expect(ClaudeResetInventory.parse(data(#"{"extra_usage":{"is_enabled":true,"used_credits":541,"monthly_limit":null}}"#), now: now)?.credit == .init(usedCents: 541, enabled: true), "credit: unlimited")
for json in [#"{}"#, #"{"extra_usage":{"is_enabled":false}}"#] {
    expect(ClaudeResetInventory.parse(data(json), now: now)?.credit == .zero, "credit: absent or disabled is zero")
}
for json in [#"{"is_enabled":true,"used_credits":"541"}"#, #"{"is_enabled":true,"used_credits":true}"#, #"{"is_enabled":true,"used_credits":-1}"#, #"{"is_enabled":true,"used_credits":541,"monthly_limit":"2000"}"#, #"{"is_enabled":"yes"}"#] {
    let reading = ClaudeResetInventory.parse(data("{\"extra_usage\":\(json)}"), now: now)
    expect(reading != nil && reading?.credit == nil, "credit: malformed stays unknown, inventory preserved")
}
var malformedCreditBody = try! JSONSerialization.jsonObject(with: body([fullGrant])) as! [String: Any]
malformedCreditBody["extra_usage"] = ["is_enabled": true, "used_credits": "bad"]
let preservedGrants = ClaudeResetInventory.parse(try! JSONSerialization.data(withJSONObject: malformedCreditBody), now: now)
expect(preservedGrants?.grants.count == 1 && preservedGrants?.credit == nil, "credit: malformed data preserves reset grants")
var creditSchedule = Schedule()
_ = creditSchedule.begin(id, now: now)
creditSchedule.land(id, .read(limitedCredit), now: now)
expect(creditSchedule.panelInput(id).credit == limitedCredit.credit, "credit: published without reset eligibility")
creditSchedule.land(id, .failed(status: 500), now: now)
expect(creditSchedule.panelInput(id).credit == limitedCredit.credit, "credit: failed read retains the last known amount")


let realExtra = #"{"extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null,"currency":null,"decimal_places":null,"disabled_reason":null,"user_disabled":false,"spend_limit_reached":false,"credits_ever_enabled":false,"daily":null,"weekly":null},"promo_credits":null,"five_hour":{"utilization":10.0,"resets_at":"2026-11-12T12:00:00Z","limit_dollars":null,"used_dollars":null,"remaining_dollars":null},"cedar_ember":{"eligible":false,"event_props":{"extra_usage_state":"not_configured"}}}"#
let realReading = ClaudeResetInventory.parse(data(realExtra), now: now)!
expect(realReading.credit == .zero && realReading.promotions.isEmpty && realReading.windowSpend.isEmpty, "real disabled extra_usage response")
let scaled = ClaudeResetInventory.parse(data(#"{"extra_usage":{"is_enabled":true,"used_credits":5410,"monthly_limit":20000,"currency":"EUR","decimal_places":3,"utilization":80,"spend_limit_reached":true,"disabled_reason":"cap","daily":{"unknown":true},"weekly":false}}"#), now: now)!
expect(scaled.credit?.usedCents == 541 && scaled.credit?.limitCents == 2000 && scaled.credit?.currency == "EUR", "currency and decimal scale")
expect(scaled.credit?.remainingPercent() == 20 && scaled.credit?.spendLimitReached == true && scaled.credit?.disabledReason == "cap", "server utilization and spend warning")
for (places, expected) in [(0, 54100.0), (2, 541.0), (3, 54.1)] {
    let reading = ClaudeResetInventory.parse(data("{\"extra_usage\":{\"is_enabled\":true,\"used_credits\":541,\"decimal_places\":\(places)}}"), now: now)!
    expect(abs(reading.credit!.usedCents - expected) < 0.0001, "decimal places \(places)")
}
let oddMetadata = ClaudeResetInventory.parse(data(#"{"extra_usage":{"is_enabled":true,"used_credits":541,"utilization":"bad","currency":false,"decimal_places":"bad","spend_limit_reached":{},"disabled_reason":false}}"#), now: now)!
expect(oddMetadata.credit?.usedCents == 541 && oddMetadata.credit?.currency == "USD", "optional type mismatches preserve credit and inventory")
let promoObject = ClaudeResetInventory.parse(data(#"{"promo_credits":{"remaining":541,"balance":999,"currency":"EUR","decimal_places":2,"expires_at":"2026-12-01T00:00:00Z"}}"#), now: now)!
expect(promoObject.promotions.first?.amount == 5.41 && promoObject.promotions.first?.currency == "EUR" && promoObject.promotions.first?.expiresAt != nil, "promotion key order, currency and expiry")
let promoArray = ClaudeResetInventory.parse(data(#"{"promo_credits":[{"remaining":"bad","balance":250},{"amount":7,"decimal_places":0,"ends_at":"2026-12-02T00:00:00Z"},{"unknown":100}]}"#), now: now)!
expect(promoArray.promotions.map(\.amount) == [2.5, 7, nil], "promotion array and unknown object")
expect(ClaudeResetInventory.parse(data(#"{"promo_credits":"unknown"}"#), now: now)?.promotions.first?.amount == nil, "unknown promotion never invents balance")
expect(ClaudeResetInventory.parse(data(#"{}"#), now: now)?.promotions.isEmpty == true, "missing promotion hidden")
let dollars = ClaudeResetInventory.parse(data(#"{"five_hour":{"limit_dollars":20,"used_dollars":5.41},"seven_day":{"limit_dollars":100,"remaining_dollars":30},"seven_day_fable":{"limit_dollars":null,"used_dollars":2}}"#), now: now)!
expect(dollars.windowSpend["five_hour"] == .init(limit: 20, used: 5.41) && dollars.windowSpend["seven_day"] == .init(limit: 100, used: 70) && dollars.windowSpend["seven_day_fable"] == nil, "window dollar fields independent of utilization")
var realSchedule = Schedule()
_ = realSchedule.begin(id, now: now)
realSchedule.land(id, .read(promoObject), now: now)
expect(realSchedule.panelInput(id).promotions == promoObject.promotions, "promotions survive ineligible reset program")
realSchedule.land(id, .read(dollars), now: now)
expect(realSchedule.panelInput(id).windowSpend == dollars.windowSpend, "window dollars reach panel")

print(failed == 0 ? "ALL \(passed) PASS" : "\(failed) FAILED, \(passed) passed")
exit(failed == 0 ? 0 : 1)
