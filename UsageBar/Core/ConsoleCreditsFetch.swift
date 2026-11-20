import Foundation
import OSLog
import WebKit

/// Reads the Anthropic Console's "Organization credits" with the session the user created by
/// signing in to https://platform.claude.com inside UsageBar (ConsoleSignInWindowController).
/// The Claude Code OAuth token is rejected by these endpoints (403 `oauth_token_not_accepted`) and
/// there is no Admin API for the balance, so the Console's own same-origin GETs are the source:
/// `/api/organizations`, then per organization `/prepaid/credits`, `/current_spend`, `/spend_limits`.
///
/// THE ONE PLACE USAGEBAR TOUCHES CONSOLE COOKIES, so its rules are here:
/// - Each Claude account has its own persistent `WKWebsiteDataStore` (`Connection.storeID(for:)`),
///   separate from the system browser, from the user's other web views and from the other
///   accounts' stores. Nothing else reads its cookie store; the sign-in window only uses the store
///   as its web view's data store.
/// - A Cookie header is built in memory for one request and never logged, written to disk or put
///   in an error. Logs carry the path kind and the HTTP status only.
/// - Reads are GETs, always, to `platform.claude.com` only. Redirects are refused, so the cookies
///   cannot be sent to another host.
/// - Cookies the Console sets in an answer (session refresh, Cloudflare) go back to the same
///   store, nowhere else.
/// - Disconnect removes everything in that account's store and clears its connected flag.
enum ConsoleCreditsFetch {
    static let host = "platform.claude.com"
    static let origin = URL(string: "https://platform.claude.com")!
    static let loginURL = URL(string: "https://platform.claude.com/login")!

    /// The fixed identifier of the single Console data store the first version used. Never change
    /// it: the one account that owns it (`Connection.migrateLegacy`) keeps it, so nobody signs in again.
    static let legacyDataStoreID = UUID(uuidString: "6F1D7A52-3B8E-4C0A-9D41-5A2E7C93B0D8")!

    /// A browser-like client name: the Console sits behind Cloudflare, which rejects bare clients.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// Whether the sign-in window may load `url`: https (the Console, claude.ai and whichever
    /// identity provider the account uses: Google, Apple, Microsoft, SSO) and the blank pages
    /// those flows use. The window never hands a navigation to the system browser: Google's
    /// consent step breaks outside the web view that holds the opener. The fetcher below stays on
    /// `host`.
    static func isSignInURLAllowed(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "about" || scheme == "blob" || scheme == "data"
    }

    /// The Safari user agent for the sign-in web views. Google refuses sign-in in embedded web
    /// views by their user agent; Safari freezes the OS and WebKit parts, and its version follows
    /// the macOS version.
    static func signInUserAgent(osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> String {
        let safari = osVersion.majorVersion >= 11 ? "\(osVersion.majorVersion).\(osVersion.minorVersion)" : "18.0"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safari) Safari/605.1.15"
    }

    /// At most this many organizations are asked for a balance.
    static let maxOrganizations = 6

    // MARK: Connection

    /// What the app remembers per Claude account, all in UserDefaults and none of it secret:
    /// - which accounts completed a Console sign-in (without it no request is made: a never
    ///   connected account has Cloudflare cookies at most, and must read "not connected", not
    ///   "session expired");
    /// - which data store an account uses, when that is not the one derived from its id (only the
    ///   account that inherited the old single store);
    /// - which accounts signed in to a Console login that is not their own email;
    /// - the one-time move from the old single store (`consoleCreditsConnected`).
    enum Connection {
        static let legacyKey = "consoleCreditsConnected"
        static let accountsKey = "consoleCreditsConnectedAccounts"
        static let storeMapKey = "consoleCreditsStoreMap"
        static let mismatchKey = "consoleCreditsDifferentAccount"
        static let migratedKey = "consoleCreditsPerAccountMigrated"
        static let attemptsKey = "consoleCreditsMigrationAttempts"

        static func connected(_ defaults: UserDefaults = .standard) -> Set<String> {
            Set(defaults.stringArray(forKey: accountsKey) ?? [])
        }
        static func isConnected(_ accountID: String, defaults: UserDefaults = .standard) -> Bool {
            connected(defaults).contains(accountID)
        }
        static func set(_ isOn: Bool, account accountID: String, defaults: UserDefaults = .standard) {
            var ids = connected(defaults)
            if isOn { ids.insert(accountID) } else { ids.remove(accountID) }
            defaults.set(ids.sorted(), forKey: accountsKey)
        }

        static func mismatched(_ defaults: UserDefaults = .standard) -> Set<String> {
            Set(defaults.stringArray(forKey: mismatchKey) ?? [])
        }
        static func setMismatch(_ isOn: Bool, account accountID: String, defaults: UserDefaults = .standard) {
            var ids = mismatched(defaults)
            if isOn { ids.insert(accountID) } else { ids.remove(accountID) }
            defaults.set(ids.sorted(), forKey: mismatchKey)
        }

        static func storeMap(_ defaults: UserDefaults = .standard) -> [String: String] {
            defaults.dictionary(forKey: storeMapKey) as? [String: String] ?? [:]
        }
        /// The data store of an account: the inherited one when mapped, else the derived one.
        static func storeID(for accountID: String, defaults: UserDefaults = .standard) -> UUID {
            storeMap(defaults)[accountID].flatMap(UUID.init(uuidString:)) ?? ConsoleAccounts.storeID(for: accountID)
        }
        static func assignLegacyStore(to accountID: String, defaults: UserDefaults = .standard) {
            var map = storeMap(defaults)
            map[accountID] = legacyDataStoreID.uuidString
            defaults.set(map, forKey: storeMapKey)
        }
        static func forget(account accountID: String, defaults: UserDefaults = .standard) {
            var map = storeMap(defaults)
            map[accountID] = nil
            defaults.set(map, forKey: storeMapKey)
            set(false, account: accountID, defaults: defaults)
            setMismatch(false, account: accountID, defaults: defaults)
        }

        /// The old single connection still waiting to be handed to an account.
        static func legacyPending(_ defaults: UserDefaults = .standard) -> Bool {
            defaults.bool(forKey: legacyKey) && !defaults.bool(forKey: migratedKey)
        }
        static func finishLegacy(_ defaults: UserDefaults = .standard) {
            defaults.set(true, forKey: migratedKey)
            defaults.removeObject(forKey: legacyKey)
            defaults.removeObject(forKey: attemptsKey)
        }
        /// How many times the old store's identity has been tried without an answer so far.
        static func nextLegacyAttempt(_ defaults: UserDefaults = .standard) -> Int {
            let attempts = defaults.integer(forKey: attemptsKey)
            defaults.set(attempts + 1, forKey: attemptsKey)
            return attempts
        }
    }

    // MARK: Cookies

    /// Where the session cookies are read from and written back to. The live one is WebKit's store.
    protocol CookieJar: Sendable {
        func cookies() async -> [HTTPCookie]
        func save(_ cookies: [HTTPCookie]) async
    }

    /// One WebKit data store per store id, created on first use.
    @MainActor private static var dataStores: [UUID: WKWebsiteDataStore] = [:]
    @MainActor static func dataStore(id: UUID) -> WKWebsiteDataStore {
        if let store = dataStores[id] { return store }
        let store = WKWebsiteDataStore(forIdentifier: id)
        dataStores[id] = store
        return store
    }
    @MainActor static func dataStore(forAccount accountID: String) -> WKWebsiteDataStore {
        dataStore(id: Connection.storeID(for: accountID))
    }

    struct WebKitJar: CookieJar {
        let storeID: UUID
        init(storeID: UUID) { self.storeID = storeID }
        init(account accountID: String) { self.init(storeID: Connection.storeID(for: accountID)) }
        func cookies() async -> [HTTPCookie] { await all() }
        func save(_ cookies: [HTTPCookie]) async { await write(cookies) }
        @MainActor private func all() async -> [HTTPCookie] {
            await ConsoleCreditsFetch.dataStore(id: storeID).httpCookieStore.allCookies()
        }
        @MainActor private func write(_ cookies: [HTTPCookie]) async {
            let store = ConsoleCreditsFetch.dataStore(id: storeID).httpCookieStore
            for cookie in cookies { await store.setCookie(cookie) }
        }
    }

    /// The Cookie header for one request: the cookies whose domain, path and expiry fit. Nil when
    /// none do.
    static func cookieHeader(from cookies: [HTTPCookie], path: String, now: Date) -> String? {
        let usable = cookies.filter { cookie in
            guard domainMatches(cookie.domain), path.hasPrefix(cookie.path.isEmpty ? "/" : cookie.path) else { return false }
            if let expires = cookie.expiresDate, expires <= now { return false }
            return true
        }
        guard !usable.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: usable)["Cookie"]
    }

    static func domainMatches(_ domain: String) -> Bool {
        let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        let lowered = bare.lowercased()
        return host == lowered || host.hasSuffix("." + lowered)
    }

    // MARK: Requests

    /// How a request leaves: the ephemeral, cookie-less, redirect-refusing session below. Tests
    /// pass their own.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    static let liveTransport: Transport = { request in
        try await session.data(for: request, delegate: NoRedirects())
    }

    static func request(path: String, cookie: String) -> URLRequest {
        var request = URLRequest(url: URL(string: origin.absoluteString + path)!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(origin.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return request
    }

    /// One GET, classified. Cookies the answer sets go back to the jar.
    private static func get(_ path: String, jar: CookieJar, transport: Transport, now: Date,
                            forbiddenIsAbsent: Bool = false) async -> ConsoleCredits.Answer {
        guard let cookie = cookieHeader(from: await jar.cookies(), path: path, now: now) else {
            return .unauthorized(status: 0)
        }
        guard let (body, reply) = try? await transport(request(path: path, cookie: cookie)),
              let http = reply as? HTTPURLResponse else {
            log.info("get \(kind(path), privacy: .public) status=none")
            return .unreadable(status: nil)
        }
        log.info("get \(kind(path), privacy: .public) status=\(http.statusCode, privacy: .public)")
        let fields = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        let fresh = HTTPCookie.cookies(withResponseHeaderFields: fields, for: origin)
        if !fresh.isEmpty { await jar.save(fresh) }
        return ConsoleCredits.classify(status: http.statusCode, body: body,
                                       location: http.value(forHTTPHeaderField: "Location"),
                                       forbiddenIsAbsent: forbiddenIsAbsent)
    }

    /// A path with the organization id left out, for the log.
    private static func kind(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    // MARK: Reads

    /// One refresh: organizations, then each one's balance, month spend and tier limit.
    /// `connected` false means nothing is sent. The balance is the only required field: spend and
    /// tier limit failing leave them nil and the balance on screen.
    static func fetch(connected: Bool, jar: CookieJar,
                      transport: Transport = liveTransport, now: Date = Date()) async -> ConsoleCredits.Outcome {
        guard connected else { return .notConnected }
        let listAnswer = await get("/api/organizations", jar: jar, transport: transport, now: now)
        let refs: [ConsoleCredits.OrganizationRef]
        switch listAnswer {
        case .json(let body):
            guard let parsed = ConsoleCredits.organizations(from: body) else { return .failed(status: 200) }
            refs = parsed
        case .unauthorized, .loginRedirect: return .needsReconnect
        case .absent(let status): return .failed(status: status)
        case .unreadable(let status): return .failed(status: status)
        }

        var read: [ConsoleCredits.Organization] = []
        var unreadable: Int?? = nil
        for ref in refs.prefix(maxOrganizations) {
            let base = "/api/organizations/\(ref.id)"
            switch await get(base + "/prepaid/credits", jar: jar, transport: transport, now: now, forbiddenIsAbsent: true) {
            case .unauthorized, .loginRedirect:
                return .needsReconnect
            case .absent:
                continue
            case .unreadable(let status):
                unreadable = .some(status)
            case .json(let body):
                guard let prepaid = ConsoleCredits.prepaid(from: body) else { unreadable = .some(200); continue }
                var organization = ConsoleCredits.Organization(id: ref.id, name: ref.name, prepaid: prepaid)
                if case .json(let spend) = await get(base + "/current_spend", jar: jar, transport: transport, now: now),
                   let parsed = ConsoleCredits.currentSpend(from: spend) {
                    organization.monthSpend = parsed.spend
                    organization.spendResetsAt = parsed.resetsAt
                }
                if case .json(let limits) = await get(base + "/spend_limits", jar: jar, transport: transport, now: now) {
                    organization.tierLimit = ConsoleCredits.tierLimit(from: limits)
                }
                read.append(organization)
            }
        }
        if !read.isEmpty { return .read(ConsoleCredits.Snapshot(organizations: read)) }
        if let unreadable { return .failed(status: unreadable) }
        return .noPrepaid
    }

    /// Whether the store holds a working Console session: `/api/organizations` answers with a
    /// list. The sign-in window asks this after each page it lands on.
    static func isSignedIn(jar: CookieJar, transport: Transport = liveTransport,
                           now: Date = Date()) async -> Bool {
        guard case .json(let body) = await get("/api/organizations", jar: jar, transport: transport, now: now),
              let refs = ConsoleCredits.organizations(from: body) else { return false }
        return !refs.isEmpty
    }

    /// The account's refresh: its store's session, or nothing sent when it never connected.
    static func fetch(account accountID: String) async -> ConsoleCredits.Outcome {
        await fetch(connected: Connection.isConnected(accountID), jar: WebKitJar(account: accountID))
    }

    /// The Console login behind a session: the email on `/api/bootstrap`, else `/api/account`.
    /// `.none` when the Console answered but named nobody or refused the session; `.unreadable`
    /// when nothing usable came back at all. The email is compared in memory and never logged.
    static func identity(jar: CookieJar, transport: Transport = liveTransport,
                         now: Date = Date()) async -> ConsoleAccounts.IdentityRead {
        var answered = false
        for path in ["/api/bootstrap", "/api/account"] {
            switch await get(path, jar: jar, transport: transport, now: now) {
            case .json(let body):
                answered = true
                if let email = ConsoleAccounts.email(from: body) { return .email(email) }
            case .unauthorized, .loginRedirect, .absent:
                answered = true
            case .unreadable:
                continue
            }
        }
        return answered ? .none : .unreadable
    }

    static func identity(account accountID: String) async -> ConsoleAccounts.IdentityRead {
        await identity(jar: WebKitJar(account: accountID))
    }

    /// The old single store's login, read through its own fixed store id.
    static func legacyIdentity() async -> ConsoleAccounts.IdentityRead {
        await identity(jar: WebKitJar(storeID: legacyDataStoreID))
    }

    /// Signs one account out: everything in its Console store goes, with its connected flag.
    @MainActor static func disconnect(account accountID: String, defaults: UserDefaults = .standard) async {
        let store = dataStore(id: Connection.storeID(for: accountID, defaults: defaults))
        Connection.forget(account: accountID, defaults: defaults)
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    private static let log = Logger(subsystem: BrandPaths.appBundleID, category: "console-credits")

    /// Nothing written to disk by URLSession, and the Cookie header is ours alone.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}

extension ConsoleCredits.Organization {
    init(id: String, name: String?, prepaid: ConsoleCredits.Prepaid) {
        self.init(id: id, name: name, prepaid: prepaid, monthSpend: nil, spendResetsAt: nil, tierLimit: nil)
    }
}
