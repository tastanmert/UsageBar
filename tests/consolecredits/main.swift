import Foundation

// Console organization credits: parser fixtures from the Console's own answers (2026-11-15),
// answer classification, cookie header, the fetch sequence and the state machine. No network, no
// WebKit store: jar and transport are injected.

var passed = 0
var failed = 0
func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() { passed += 1 } else { failed += 1; print("FAIL: \(label)") }
}
@MainActor func expectA(_ condition: @autoclosure () async -> Bool, _ label: String) async {
    if await condition() { passed += 1 } else { failed += 1; print("FAIL: \(label)") }
}
func data(_ text: String) -> Data { Data(text.utf8) }
func iso(_ text: String) -> Date { ConsoleCredits.date(text)! }

let prepaidBody = """
{"amount": 10000, "currency": "USD",
 "balance": {"credits": {"amount_minor": 10000, "exponent": 2}, "money": null},
 "balance_credits": 100, "amount_without_scoped_credits": 0, "auto_reload_settings": null,
 "tranches": [],
 "promo_tranches": [{"remaining_amount_minor_units": 10000, "expires_at": "2026-12-11T00:00:00Z",
   "name": "API credit (Max)", "program_id": "p1",
   "scope": {"kind": "scoped", "applies_to": [{"product": "agent_sdk"}, {"product": "claude_code"}]}}],
 "next_expires_at": "2026-12-11T00:00:00.000000Z"}
"""

// MARK: prepaid
let prepaid = ConsoleCredits.prepaid(from: data(prepaidBody))
expect(prepaid?.balance == 100, "balance = amount_minor / 10^exponent")
expect(prepaid?.currency == "USD", "currency")
expect(prepaid?.promos.count == 1, "one promo tranche")
expect(prepaid?.promos.first?.name == "API credit (Max)", "promo name")
expect(prepaid?.promos.first?.remainingMinor == 10000, "promo remaining in minor units")
expect(prepaid?.promos.first?.expiresAt == iso("2026-12-11T00:00:00Z"), "promo expiry")
expect(prepaid?.promos.first?.products == ["agent_sdk", "claude_code"], "promo scope products")
expect(prepaid?.nextExpiresAt == iso("2026-12-11T00:00:00Z"), "fractional-seconds next_expires_at")

let exponent3 = ConsoleCredits.prepaid(from: data(#"{"balance":{"credits":{"amount_minor":12345,"exponent":3}}}"#))
expect(exponent3?.balance == 12.345, "exponent is honoured")
let noExponent = ConsoleCredits.prepaid(from: data(#"{"balance":{"credits":{"amount_minor":250}}}"#))
expect(noExponent?.balance == 2.5, "missing exponent defaults to 2")
let fallback = ConsoleCredits.prepaid(from: data(#"{"amount": 4200, "currency": "EUR", "balance": {"credits": null, "money": null}}"#))
expect(fallback?.balance == 42 && fallback?.currency == "EUR", "falls back to amount / 100")
let zero = ConsoleCredits.prepaid(from: data(#"{"amount": 0, "balance": {"credits": {"amount_minor": 0, "exponent": 2}}, "promo_tranches": null}"#))
expect(zero?.balance == 0, "a real zero balance parses as zero")
expect(zero?.promos.isEmpty == true, "null promo_tranches is empty")
expect(ConsoleCredits.prepaid(from: data(#"{"currency":"USD","balance":null}"#)) == nil, "no balance field is not zero")
expect(ConsoleCredits.prepaid(from: data(#"{"amount":"100","balance":{"credits":{"amount_minor":true}}}"#)) == nil,
       "string amount and boolean minor are not numbers")
expect(ConsoleCredits.prepaid(from: data("<html>blocked</html>")) == nil, "HTML is not a balance")
expect(ConsoleCredits.prepaid(from: data("[]")) == nil, "an array is not a balance")
let badPromo = ConsoleCredits.prepaid(from: data(#"{"amount":100,"promo_tranches":[{"name":"x"},{"remaining_amount_minor_units":500,"expires_at":"not a date"}]}"#))
expect(badPromo?.promos.count == 1 && badPromo?.promos.first?.expiresAt == nil, "a promo with no amount is skipped, a bad date is nil")

// MARK: spend and tier limit
expect(ConsoleCredits.tierLimit(from: data(#"{"spend_limits": [], "enforced_limit_usd": 50000}"#)) == 500,
       "enforced_limit_usd is cents: 50000 -> $500")
expect(ConsoleCredits.tierLimit(from: data(#"{"spend_limits": []}"#)) == nil, "no enforced limit is nil")
expect(ConsoleCredits.tierLimit(from: data(#"{"enforced_limit_usd": null}"#)) == nil, "null enforced limit is nil")
expect(ConsoleCredits.tierLimit(from: data(#"{"enforced_limit_usd": -5}"#)) == nil, "negative limit rejected")
let spend = ConsoleCredits.currentSpend(from: data(#"{"amount": 0, "resets_at": "2026-12-01T00:00:00Z"}"#))
expect(spend?.spend == 0 && spend?.resetsAt == iso("2026-12-01T00:00:00Z"), "zero spend with a reset date")
expect(ConsoleCredits.currentSpend(from: data(#"{"amount": 1234}"#))?.spend == 12.34, "spend assumed in cents")
expect(ConsoleCredits.currentSpend(from: data(#"{"resets_at": "2026-12-01T00:00:00Z"}"#)) == nil, "no amount is not zero spend")

// MARK: organizations
let orgsArray = ConsoleCredits.organizations(from: data("""
[{"uuid":"chat-org","name":"Personal","capabilities":["chat","claude_max"]},
 {"uuid":"api-org","name":"Mert API","capabilities":["api"],"billing_type":"prepaid"},
 {"name":"no id"}]
"""))
expect(orgsArray?.map(\.id) == ["api-org", "chat-org"], "API-looking organizations first, no-id skipped")
expect(orgsArray?.first?.looksLikeAPI == true && orgsArray?.last?.looksLikeAPI == false, "looksLikeAPI")
expect(ConsoleCredits.organizations(from: data(#"{"organizations":[{"id":"o1"}]}"#))?.map(\.id) == ["o1"], "wrapped list, id key")
expect(ConsoleCredits.organizations(from: data("[]"))?.isEmpty == true, "an empty list is a list")
expect(ConsoleCredits.organizations(from: data(#"{"error":"x"}"#)) == nil, "an object with no list is a failed read")
expect(ConsoleCredits.organizations(from: data("<html></html>")) == nil, "HTML is not a list")

// MARK: classification
func cls(_ status: Int?, _ body: String, location: String? = nil, absent: Bool = false) -> ConsoleCredits.Answer {
    ConsoleCredits.classify(status: status, body: data(body), location: location, forbiddenIsAbsent: absent)
}
expect(cls(200, "{}") == .json(data("{}")), "200 JSON")
expect(cls(200, "<!doctype html><html>") == .unreadable(status: 200), "200 HTML is unreadable")
expect(cls(200, "") == .unreadable(status: 200), "200 empty is unreadable")
expect(cls(401, #"{"error":"unauthorized"}"#) == .unauthorized(status: 401), "401 -> reconnect")
expect(cls(401, "<html>") == .unauthorized(status: 401), "401 HTML -> still reconnect")
expect(cls(403, #"{"error":{"type":"permission_error"}}"#) == .unauthorized(status: 403), "403 JSON -> reconnect")
expect(cls(403, "<html><title>Just a moment...</title>") == .unreadable(status: 403), "403 Cloudflare HTML -> read failed")
expect(cls(403, #"{"error":"no"}"#, absent: true) == .absent(status: 403), "403 on one organization -> absent")
expect(cls(403, "<html>", absent: true) == .unreadable(status: 403), "403 HTML on one organization -> still read failed")
expect(cls(404, #"{"error":"not_found"}"#) == .absent(status: 404), "404 -> absent")
expect(cls(404, "<html>") == .unreadable(status: 404), "404 HTML -> read failed")
expect(cls(500, "{}") == .unreadable(status: 500), "500 -> read failed")
expect(cls(429, "{}") == .unreadable(status: 429), "429 -> read failed")
expect(cls(302, "", location: "https://platform.claude.com/login?next=x") == .loginRedirect, "redirect to login")
expect(cls(302, "", location: "https://elsewhere.example/") == .unreadable(status: 302), "other redirect")
expect(cls(nil, "") == .unreadable(status: nil), "no response")

// MARK: cookie header
func cookie(_ name: String, _ value: String, domain: String, path: String = "/", expires: Date? = nil) -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"]
    if let expires { properties[.expires] = expires }
    return HTTPCookie(properties: properties)!
}
let now = iso("2026-11-15T12:00:00Z")
let jarCookies = [
    cookie("sessionKey", "s1", domain: ".claude.com"),
    cookie("host_only", "h1", domain: "platform.claude.com"),
    cookie("other_site", "x", domain: ".claude.ai"),
    cookie("sibling", "y", domain: "docs.claude.com"),
    cookie("expired", "z", domain: ".claude.com", expires: now.addingTimeInterval(-60)),
    cookie("future", "f", domain: ".claude.com", expires: now.addingTimeInterval(3600)),
    cookie("scoped", "p", domain: ".claude.com", path: "/billing"),
]
let header = ConsoleCreditsFetch.cookieHeader(from: jarCookies, path: "/api/organizations", now: now) ?? ""
expect(header.contains("sessionKey=s1") && header.contains("host_only=h1") && header.contains("future=f"), "matching cookies are sent")
expect(!header.contains("other_site") && !header.contains("sibling"), "other domains are not sent")
expect(!header.contains("expired") && !header.contains("scoped"), "expired and other-path cookies are not sent")
expect(ConsoleCreditsFetch.cookieHeader(from: [cookie("a", "b", domain: ".claude.ai")], path: "/", now: now) == nil, "no match is nil")

// MARK: fetch sequence
final class Jar: ConsoleCreditsFetch.CookieJar, @unchecked Sendable {
    var cookies: [HTTPCookie]
    var saved: [HTTPCookie] = []
    init(_ cookies: [HTTPCookie]) { self.cookies = cookies }
    func cookies() async -> [HTTPCookie] { cookies }
    func save(_ cookies: [HTTPCookie]) async { saved += cookies }
}
actor Seen {
    private(set) var requests: [URLRequest] = []
    func add(_ request: URLRequest) { requests.append(request) }
}
struct Reply { var status: Int; var body: String; var headers: [String: String] = [:] }
func transport(_ seen: Seen, _ routes: [String: Reply]) -> ConsoleCreditsFetch.Transport {
    { request in
        await seen.add(request)
        let path = request.url!.path
        let reply = routes.first { path.hasSuffix($0.key) }?.value ?? Reply(status: 404, body: "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }
}
let session = Jar([cookie("sessionKey", "SECRET-SESSION", domain: ".claude.com")])
let orgList = Reply(status: 200, body: #"[{"uuid":"org-1","name":"Mert API","capabilities":["api"]}]"#)
let okRoutes: [String: Reply] = [
    "/api/organizations": orgList,
    "/prepaid/credits": Reply(status: 200, body: prepaidBody),
    "/current_spend": Reply(status: 200, body: #"{"amount": 0, "resets_at": "2026-12-01T00:00:00Z"}"#),
    "/spend_limits": Reply(status: 200, body: #"{"spend_limits": [], "enforced_limit_usd": 50000}"#),
]

func run() async {
    let seen = Seen()
    let outcome = await ConsoleCreditsFetch.fetch(connected: true, jar: session, transport: transport(seen, okRoutes), now: now)
    guard case .read(let snapshot) = outcome, let org = snapshot.primary else {
        expect(false, "fetch reads a snapshot"); return
    }
    expect(org.id == "org-1" && org.name == "Mert API", "organization identity")
    expect(org.prepaid.balance == 100, "balance through fetch")
    expect(org.monthSpend == 0 && org.spendResetsAt == iso("2026-12-01T00:00:00Z"), "month spend and reset")
    expect(org.tierLimit == 500, "tier limit $500 through fetch")
    expect(org.soonestExpiringPromo?.expiresAt == iso("2026-12-11T00:00:00Z"), "soonest promo expiry")
    let requests = await seen.requests
    expect(requests.count == 4, "one list call plus three per organization")
    expect(requests.allSatisfy { $0.httpMethod == "GET" }, "every request is a GET")
    expect(requests.allSatisfy { $0.url?.host == "platform.claude.com" }, "only the Console host")
    expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie")?.contains("sessionKey=SECRET-SESSION") == true }, "cookie attached")
    expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Accept") == "application/json" }, "Accept JSON")
    expect(requests.allSatisfy { ($0.value(forHTTPHeaderField: "User-Agent") ?? "").hasPrefix("Mozilla/5.0") }, "browser-like User-Agent")
    expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil }, "no bearer token")
    expect(requests.allSatisfy { !String(describing: $0.url!).contains("SECRET") }, "no cookie in the URL")

    // Not connected: nothing is sent.
    let none = Seen()
    let notConnected = await ConsoleCreditsFetch.fetch(connected: false, jar: session, transport: transport(none, okRoutes), now: now)
    expect(notConnected == .notConnected, "not connected")
    await expectA(await none.requests.isEmpty, "not connected sends nothing")

    // Flag says connected but the store has no cookies: reconnect, nothing sent.
    let emptySeen = Seen()
    let emptyJar = await ConsoleCreditsFetch.fetch(connected: true, jar: Jar([]), transport: transport(emptySeen, okRoutes), now: now)
    expect(emptyJar == .needsReconnect, "connected flag with no cookies needs reconnect")
    await expectA(await emptySeen.requests.isEmpty, "no cookies sends nothing")

    // 401 and 403 JSON on the list: reconnect.
    for status in [401, 403] {
        var routes = okRoutes
        routes["/api/organizations"] = Reply(status: status, body: #"{"error":"x"}"#)
        let outcome = await ConsoleCreditsFetch.fetch(connected: true, jar: session, transport: transport(Seen(), routes), now: now)
        expect(outcome == .needsReconnect, "\(status) on the list -> needs reconnect")
    }
    // Cloudflare HTML on the list: read failed, not reconnect.
    var cloudflare = okRoutes
    cloudflare["/api/organizations"] = Reply(status: 403, body: "<html>Just a moment</html>")
    await expectA(await ConsoleCreditsFetch.fetch(connected: true, jar: session, transport: transport(Seen(), cloudflare), now: now)
           == .failed(status: 403), "Cloudflare 403 -> read failed")
    // Prepaid 401 mid-way: reconnect. Prepaid 403 JSON on every organization: no prepaid, not reconnect.
    var expired = okRoutes
    expired["/prepaid/credits"] = Reply(status: 401, body: "{}")
    await expectA(await ConsoleCreditsFetch.fetch(connected: true, jar: session, transport: transport(Seen(), expired), now: now)
           == .needsReconnect, "401 on prepaid -> reconnect")
    var forbidden = okRoutes
    forbidden["/prepaid/credits"] = Reply(status: 403, body: #"{"error":"no billing"}"#)
    await expectA(await ConsoleCreditsFetch.fetch(connected: true, jar: session, transport: transport(Seen(), forbidden), now: now)
           == .noPrepaid, "403 JSON on every organization -> no prepaid")
    // Prepaid 500: read failed. Unparsable prepaid body: read failed (never zero).
    var broken = okRoutes
    broken["/prepaid/credits"] = Reply(status: 500, body: "{}")
    await expectA(await ConsoleCreditsFetch.fetch(connected: true, jar: session, transport: transport(Seen(), broken), now: now)
           == .failed(status: 500), "500 on prepaid -> read failed")
    var unparsable = okRoutes
    unparsable["/prepaid/credits"] = Reply(status: 200, body: #"{"unexpected": true}"#)
    await expectA(await ConsoleCreditsFetch.fetch(connected: true, jar: session, transport: transport(Seen(), unparsable), now: now)
           == .failed(status: 200), "unparsable prepaid -> read failed, not zero")
    // Spend and limit failing keep the balance.
    var partial = okRoutes
    partial["/current_spend"] = Reply(status: 500, body: "{}")
    partial["/spend_limits"] = Reply(status: 403, body: "<html>")
    if case .read(let snapshot) = await ConsoleCreditsFetch.fetch(connected: true, jar: session, transport: transport(Seen(), partial), now: now) {
        expect(snapshot.primary?.prepaid.balance == 100 && snapshot.primary?.monthSpend == nil && snapshot.primary?.tierLimit == nil,
               "spend and limit failing keep the balance")
    } else { expect(false, "partial fetch still reads") }
    // A real zero balance is a reading.
    var empty = okRoutes
    empty["/prepaid/credits"] = Reply(status: 200, body: #"{"amount":0,"balance":{"credits":{"amount_minor":0,"exponent":2}}}"#)
    if case .read(let snapshot) = await ConsoleCreditsFetch.fetch(connected: true, jar: session, transport: transport(Seen(), empty), now: now) {
        expect(snapshot.primary?.prepaid.balance == 0, "zero balance is read as zero")
    } else { expect(false, "zero balance is a reading") }
    // Set-Cookie from an answer goes back to the jar.
    let refresh = Jar([cookie("sessionKey", "s", domain: ".claude.com")])
    var withCookie = okRoutes
    withCookie["/api/organizations"] = Reply(status: 200, body: orgList.body,
                                             headers: ["Set-Cookie": "__cf_bm=abc; Path=/; Domain=claude.com; Secure; HttpOnly"])
    _ = await ConsoleCreditsFetch.fetch(connected: true, jar: refresh, transport: transport(Seen(), withCookie), now: now)
    expect(refresh.saved.contains { $0.name == "__cf_bm" }, "Set-Cookie saved back to the jar")
    // isSignedIn
    await expectA(await ConsoleCreditsFetch.isSignedIn(jar: session, transport: transport(Seen(), okRoutes), now: now), "isSignedIn on a list")
    await expectA(!(await ConsoleCreditsFetch.isSignedIn(jar: session, transport: transport(Seen(), cloudflare), now: now)), "not signed in on HTML")
    await expectA(!(await ConsoleCreditsFetch.isSignedIn(jar: session, transport: transport(Seen(), ["/api/organizations": Reply(status: 200, body: "[]")]), now: now)),
           "an empty list is not signed in")

    // MARK: state machine
    let good = ConsoleCredits.Snapshot(organizations: [org])
    var state = ConsoleCredits.State.notConnected
    state = ConsoleCredits.next(state, .failed(status: nil), now: now)
    expect(state == .notConnected, "a failure never turns not connected into anything else")
    state = ConsoleCredits.next(.unavailable, .read(good), now: now)
    expect(state == .ready(good, readAt: now, stale: false), "a read becomes ready")
    let later = now.addingTimeInterval(600)
    let staleState = ConsoleCredits.next(state, .failed(status: 500), now: later)
    expect(staleState == .ready(good, readAt: now, stale: true), "a failure keeps the last good value, stale, with its own time")
    expect(ConsoleCredits.next(staleState, .read(good), now: later) == .ready(good, readAt: later, stale: false), "a read clears stale")
    expect(ConsoleCredits.next(state, .needsReconnect, now: later) == .needsReconnect, "reconnect drops the old reading")
    expect(ConsoleCredits.next(state, .notConnected, now: later) == .notConnected, "disconnect drops the old reading")
    expect(ConsoleCredits.next(.unavailable, .failed(status: 500), now: later) == .unavailable, "first failure is unavailable")
    expect(ConsoleCredits.next(.needsReconnect, .failed(status: nil), now: later) == .needsReconnect, "a failure keeps needs reconnect")
    expect(ConsoleCredits.next(state, .noPrepaid, now: later) == .noPrepaid, "no prepaid replaces the reading")
    let largest = ConsoleCredits.Snapshot(organizations: [
        ConsoleCredits.Organization(id: "a", name: nil, prepaid: ConsoleCredits.Prepaid(balance: 5, currency: "USD", promos: [], nextExpiresAt: nil)),
        ConsoleCredits.Organization(id: "b", name: nil, prepaid: ConsoleCredits.Prepaid(balance: 50, currency: "USD", promos: [], nextExpiresAt: nil)),
    ])
    expect(largest.primary?.id == "b", "primary is the largest balance")

    // MARK: sign-in navigation and user agent
    // The sign-in window keeps every https page in the window (Google consent, SSO) and never
    // hands one to the system browser; only non-web schemes are refused.
    for good in ["https://platform.claude.com/login", "https://accounts.google.com/o/oauth2/v2/auth", "https://claude.ai/login",
                 "https://console.anthropic.com/", "https://www.gstatic.com/x.js", "about:blank", "https://login.microsoftonline.com/a",
                 "https://accounts.google.com/signin/oauth/consent", "https://some-sso.example.org/saml", "blob:https://accounts.google.com/x"] {
        expect(ConsoleCreditsFetch.isSignInURLAllowed(URL(string: good)), "sign-in allows \(good)")
    }
    for bad in ["http://accounts.google.com/", "file:///etc/hosts", "javascript:alert(1)", "mailto:a@b.c", "ftp://example.org/"] {
        expect(!ConsoleCreditsFetch.isSignInURLAllowed(URL(string: bad)), "sign-in refuses \(bad)")
    }
    expect(!ConsoleCreditsFetch.isSignInURLAllowed(nil), "sign-in refuses nil")
    // The fetcher itself stays on the Console host.
    expect(ConsoleCreditsFetch.domainMatches(".claude.com") && !ConsoleCreditsFetch.domainMatches(".claude.ai"), "fetcher cookie domains unchanged")
    expect(ConsoleCreditsFetch.host == "platform.claude.com", "fetcher host unchanged")
    let ua = ConsoleCreditsFetch.signInUserAgent(osVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0))
    expect(ua.contains("Version/26.1 Safari/605.1.15") && ua.hasPrefix("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"), "sign-in user agent is Safari-shaped")

    // MARK: identity
    let bootstrap = Reply(status: 200, body: #"{"account":{"uuid":"u","email_address":"Mert@Example.com"},"organizations":[]}"#)
    let idRead = await ConsoleCreditsFetch.identity(jar: session, transport: transport(Seen(), ["/api/bootstrap": bootstrap]), now: now)
    expect(idRead == .email("Mert@Example.com"), "identity from /api/bootstrap account.email_address")
    let viaAccount = await ConsoleCreditsFetch.identity(jar: session, transport: transport(Seen(), ["/api/account": Reply(status: 200, body: #"{"email":"a@b.co"}"#)]), now: now)
    expect(viaAccount == .email("a@b.co"), "identity falls back to /api/account")
    let noEmail = await ConsoleCreditsFetch.identity(jar: session, transport: transport(Seen(), ["/api/bootstrap": Reply(status: 200, body: "{}")]), now: now)
    expect(noEmail == .none, "an answer without an email is none")
    let refused = await ConsoleCreditsFetch.identity(jar: session, transport: transport(Seen(), ["/api/bootstrap": Reply(status: 401, body: "{}")]), now: now)
    expect(refused == .none, "401 is none")
    let blocked = await ConsoleCreditsFetch.identity(jar: session, transport: transport(Seen(), ["/api/bootstrap": Reply(status: 403, body: "<html>"), "/api/account": Reply(status: 500, body: "{}")]), now: now)
    expect(blocked == .unreadable, "Cloudflare and 5xx are unreadable")
    expect(ConsoleAccounts.email(from: data(#"{"user":{"email":"u@x.io"}}"#)) == "u@x.io", "email under user")
    expect(ConsoleAccounts.email(from: data(#"{"email_address":"top@x.io"}"#)) == "top@x.io", "top-level email_address")
    expect(ConsoleAccounts.email(from: data(#"{"account":{"email_address":"nope"}}"#)) == nil, "not an email")
    expect(ConsoleAccounts.email(from: data("<html>")) == nil, "HTML has no email")

    // MARK: store, per account
    let suite = UserDefaults(suiteName: "consolecredits-tests-\(UUID().uuidString)")!
    let a = "claude:.claude", b = "claude:.claude2"
    let fetches = Seen()
    let store = await MainActor.run {
        ConsoleCreditsStore(fetch: { id in id == a ? .read(good) : .needsReconnect },
                            identity: { id in id == a ? .email("OWNER@example.com") : .email("someone@else.org") },
                            legacyIdentity: { .email("owner@example.com") },
                            claudeEmail: { $0 == a ? "owner@example.com" : "second@example.com" },
                            defaults: suite, clock: { now })
    }
    _ = fetches
    func st(_ store: ConsoleCreditsStore, _ id: String) async -> ConsoleCredits.State { await store.state(for: id) }
    func different(_ store: ConsoleCreditsStore, _ id: String) async -> Bool { await store.isDifferentAccount(id) }
    await expectA(await st(store, a) == .notConnected, "accounts start not connected")
    await expectA(await st(store, b) == .notConnected, "second account starts not connected")
    await store.refresh(accountIDs: [a, b])
    await expectA(await st(store, a) == .notConnected, "refresh without a connection stays not connected")
    await store.didConnect(accountID: a)
    await expectA(await st(store, a) == .ready(good, readAt: now, stale: false), "connected account reads")
    await expectA(await st(store, b) == .notConnected, "the other account is untouched")
    await expectA(await !different(store, a), "matching Console email (case-insensitive) is not a mismatch")
    await store.didConnect(accountID: b)
    await expectA(await st(store, b) == .needsReconnect, "each account has its own state")
    await expectA(await different(store, b), "a different Console email is flagged")
    await expectA(await st(store, a) == .ready(good, readAt: now, stale: false), "the first account keeps its reading")
    expect(ConsoleCreditsFetch.Connection.connected(suite) == [a, b], "connected set persisted per account")
    expect(ConsoleCreditsFetch.Connection.mismatched(suite) == [b], "mismatch persisted per account")
    await store.disconnect(accountID: b)
    await expectA(await st(store, b) == .notConnected, "disconnect clears one account")
    await expectA(await !different(store, b), "disconnect clears the mismatch")
    await expectA(await st(store, a) == .ready(good, readAt: now, stale: false), "disconnect leaves the other account")
    expect(ConsoleCreditsFetch.Connection.connected(suite) == [a], "disconnect clears the flag")

    // The 60 s floor is per account.
    let counter = Seen()
    let countedDefaults = UserDefaults(suiteName: "consolecredits-tests-\(UUID().uuidString)")!
    let counted = await MainActor.run {
        ConsoleCreditsStore(fetch: { id in
            await counter.add(URLRequest(url: URL(string: "https://x.example/\(id)")!)); return .read(good) },
                            identity: { _ in .none }, legacyIdentity: { .none }, claudeEmail: { _ in nil },
                            defaults: countedDefaults, clock: { now })
    }
    ConsoleCreditsFetch.Connection.set(true, account: a, defaults: countedDefaults)
    ConsoleCreditsFetch.Connection.set(true, account: b, defaults: countedDefaults)
    await counted.refresh(accountIDs: [a, b])
    await counted.refresh(accountIDs: [a, b])
    await expectA(await counter.requests.count == 2, "two accounts, one read each inside the 60 s floor")
    await counted.refresh(accountIDs: [a, b], force: true)
    await expectA(await counter.requests.count == 4, "force ignores the floor for every account")

    // MARK: migration from the single store
    let migrationDefaults = UserDefaults(suiteName: "consolecredits-tests-\(UUID().uuidString)")!
    migrationDefaults.set(true, forKey: ConsoleCreditsFetch.Connection.legacyKey)
    expect(ConsoleCreditsFetch.Connection.legacyPending(migrationDefaults), "old flag is pending")
    let migrating = await MainActor.run {
        ConsoleCreditsStore(fetch: { _ in .read(good) }, identity: { _ in .none },
                            legacyIdentity: { .email("Second@Example.com") },
                            claudeEmail: { $0 == a ? "owner@example.com" : "second@example.com" },
                            defaults: migrationDefaults, clock: { now })
    }
    await migrating.refresh(accountIDs: [a, b])
    expect(ConsoleCreditsFetch.Connection.storeID(for: b, defaults: migrationDefaults) == ConsoleCreditsFetch.legacyDataStoreID, "the matching account inherits the old store")
    expect(ConsoleCreditsFetch.Connection.storeID(for: a, defaults: migrationDefaults) == ConsoleAccounts.storeID(for: a), "the other account keeps its derived store")
    expect(ConsoleCreditsFetch.Connection.connected(migrationDefaults) == [b], "only the owner is connected")
    expect(!ConsoleCreditsFetch.Connection.legacyPending(migrationDefaults), "migration happens once")
    await expectA(await st(migrating, b) == .ready(good, readAt: now, stale: false), "the inherited account reads right away")
    await expectA(await st(migrating, a) == .notConnected, "the other account stays not connected")
    expect(!migrationDefaults.bool(forKey: ConsoleCreditsFetch.Connection.legacyKey), "old flag removed")
}

// MARK: pure helpers (no async)
let idA = ConsoleAccounts.storeID(for: "claude:.claude")
expect(idA == ConsoleAccounts.storeID(for: "claude:.claude"), "store id is deterministic")
expect(idA != ConsoleAccounts.storeID(for: "claude:.claude2"), "accounts get different store ids")
expect(idA != ConsoleCreditsFetch.legacyDataStoreID, "derived id differs from the legacy one")
expect(idA.uuidString.count == 36 && idA.uuidString.dropFirst(14).first == "5", "store id carries the version 5 bits")
expect(ConsoleAccounts.storeID(for: "claude:.claude").uuidString == "\(idA.uuidString)", "store id stable across calls")

expect(ConsoleAccounts.emailsMatch("Mert@Example.COM", "mert@example.com") == true, "emails match case-insensitively")
expect(ConsoleAccounts.emailsMatch("a@x.io", "b@x.io") == false, "different emails do not match")
expect(ConsoleAccounts.emailsMatch(nil, "b@x.io") == nil && ConsoleAccounts.emailsMatch("a@x.io", " ") == nil, "a missing email is unknown")
expect(ConsoleAccounts.isMismatch(console: .email("a@x.io"), claudeEmail: "b@x.io"), "differing emails are a mismatch")
expect(!ConsoleAccounts.isMismatch(console: .email("A@x.io"), claudeEmail: "a@X.io"), "same email is no mismatch")
expect(!ConsoleAccounts.isMismatch(console: .unreadable, claudeEmail: "a@x.io"), "unreadable identity is no mismatch")
expect(!ConsoleAccounts.isMismatch(console: .email("a@x.io"), claudeEmail: nil), "unknown Claude email is no mismatch")

let accts = [ConsoleAccounts.Candidate(id: "claude:.claude", email: "one@x.io"), ConsoleAccounts.Candidate(id: "claude:.claude2", email: "two@x.io")]
expect(ConsoleAccounts.legacyOwner(read: .email("TWO@x.io"), accounts: accts, attempts: 0) == .assign(accountID: "claude:.claude2"), "migration: email match wins")
expect(ConsoleAccounts.legacyOwner(read: .email("nobody@x.io"), accounts: accts, attempts: 0) == .assign(accountID: "claude:.claude"), "migration: no match falls back to the default account")
expect(ConsoleAccounts.legacyOwner(read: .none, accounts: accts, attempts: 0) == .assign(accountID: "claude:.claude"), "migration: no identity falls back to the default account")
expect(ConsoleAccounts.legacyOwner(read: .unreadable, accounts: accts, attempts: 0) == .retry, "migration: unreadable waits")
expect(ConsoleAccounts.legacyOwner(read: .unreadable, accounts: accts, attempts: 2) == .assign(accountID: "claude:.claude"), "migration: gives up after three tries")
expect(ConsoleAccounts.legacyOwner(read: .none, accounts: [accts[1]], attempts: 0) == .assign(accountID: "claude:.claude2"), "migration: no default account falls back to the first")
expect(ConsoleAccounts.legacyOwner(read: .none, accounts: [], attempts: 0) == nil, "migration: no accounts yet waits")

// Row text
let en = Locale(identifier: "en_US")
let tr = Locale(identifier: "tr_TR")
func money(_ amount: Double, _ currency: String) -> String { ConsoleAccounts.compactMoney(amount, currency: currency, locale: en) }
expect(ConsoleAccounts.monthText(spend: 0, limit: 500, currency: "USD", locale: en) == "$0 / $500", "month: $0 / $500")
expect(ConsoleAccounts.monthText(spend: 12.5, limit: 500, currency: "USD", locale: en) == "$12.50 / $500", "month: cents kept when not whole")
expect(ConsoleAccounts.monthText(spend: 3, limit: nil, currency: "USD", locale: en) == "$3", "month without a limit")
expect(ConsoleAccounts.monthText(spend: 0, limit: 500, currency: "USD", locale: tr) == "$0 / $500", "month in Turkish")
expect(ConsoleAccounts.expiryText(iso("2026-12-11T00:00:00Z"), locale: Locale(identifier: "tr_TR")).contains("Ara"), "expiry in Turkish: Ara")
let orgNoPromo = ConsoleCredits.Organization(id: "o", name: "Org", prepaid: ConsoleCredits.Prepaid(balance: 100, currency: "USD", promos: [], nextExpiresAt: nil))
let snapNoPromo = ConsoleCredits.Snapshot(organizations: [orgNoPromo])
let plain = ConsoleAccounts.display(state: .ready(snapNoPromo, readAt: now, stale: false), mismatch: false, locale: en) { String(format: "$%.2f", $0) + ($1 == "USD" ? "" : $1) }
expect(plain.balance == "$100.00" && plain.month == nil && !plain.stale, "balance without expiry has no suffix")
var orgFull = orgNoPromo
orgFull.prepaid.nextExpiresAt = iso("2026-12-11T00:00:00Z")
orgFull.monthSpend = 0
orgFull.tierLimit = 500
let full = ConsoleAccounts.display(state: .ready(ConsoleCredits.Snapshot(organizations: [orgFull]), readAt: now, stale: true), mismatch: true, locale: en) { String(format: "$%.2f", $0) + ($1 == "USD" ? "" : $1) }
expect(full.balance == "$100.00 · Dec 11", "balance with next_expires_at: \(full.balance ?? "nil")")
expect(full.month == "$0 / $500" && full.stale && full.mismatch, "month, stale and mismatch carried")
expect(full.remainingPercent == 100 && plain.remainingPercent == nil, "bar: tier limit left, none without spend and limit")
expect(full.help?.contains("$0 / $500") == true, "month spend moves into the tooltip")
var orgSpent = orgFull
orgSpent.monthSpend = 125
let spent = ConsoleAccounts.display(state: .ready(ConsoleCredits.Snapshot(organizations: [orgSpent]), readAt: now, stale: false), mismatch: false, locale: en) { amount, _ in String(format: "$%.2f", amount) }
expect(spent.remainingPercent == 75, "bar: $125 of $500 leaves 75%")
expect(ConsoleAccounts.display(state: .notConnected, mismatch: false, locale: en, money: { _, _ in "" }) == ConsoleAccounts.Display(action: .connect), "not connected shows Connect")
expect(ConsoleAccounts.display(state: .needsReconnect, mismatch: false, locale: en, money: { _, _ in "" }).action == .reconnect, "expired shows Reconnect")
expect(ConsoleAccounts.display(state: .noPrepaid, mismatch: false, locale: en, money: { _, _ in "" }).balance == "$0", "connected without prepaid reads $0")
expect(ConsoleAccounts.display(state: .unavailable, mismatch: false, locale: en, money: { _, _ in "" }).balance == "–", "unread reads a dash")

await run()
print("consolecredits: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
