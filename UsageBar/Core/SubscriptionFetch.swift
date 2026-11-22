import CryptoKit
import Foundation
import OSLog
import WebKit

/// Reads when each account's plan renews (SubscriptionRenewal). Two GETs, never a write:
///
/// CODEX: the access token comes from the official CLI's own app-server (`getAuthStatus` with
/// `includeToken`), held in memory for one request to `chatgpt.com/backend-api/subscriptions` and
/// dropped. `auth.json` is still never opened. The token is never logged, stored or put in an error.
///
/// CLAUDE: the claude.ai web session the user created by signing in inside UsageBar
/// (ClaudeWebSignIn, one persistent WebKit store per account, separate from the Console's).
/// A Cookie header is built in memory for one request to `claude.ai` only; redirects are refused,
/// so it cannot reach another host. Cookies claude.ai sets in an answer go back to the same store.
enum SubscriptionFetch {
    enum Outcome: Equatable, Sendable {
        case read(SubscriptionRenewal)
        /// The provider answered and named no renewal (a free login, an App Store plan).
        case noDate
        /// Claude only: no claude.ai sign-in for this account yet, or it has expired.
        case notConnected
        /// Claude only: the claude.ai login is another account than this Claude Code login.
        case differentAccount
        case failed
    }

    private static let log = Logger(subsystem: BrandPaths.appBundleID, category: "subscription")

    // MARK: Codex

    static func codex(home: String, now: Date = Date()) async -> Outcome {
        guard let binary = CLIRunner.resolve("codex") else { return .failed }
        let generation = BrimRuntime.shared.liveGeneration
        let token: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: codexToken(binary: binary, home: home, generation: generation))
            }
        }
        guard let token, let account = chatGPTAccountID(fromAccessToken: token) else { return .failed }
        var components = URLComponents(string: "https://chatgpt.com/backend-api/subscriptions")!
        components.queryItems = [URLQueryItem(name: "account_id", value: account)]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
        guard let (body, reply) = try? await session.data(for: request, delegate: NoRedirects()),
              let http = reply as? HTTPURLResponse else {
            log.info("codex subscriptions status=none")
            return .failed
        }
        log.info("codex subscriptions status=\(http.statusCode, privacy: .public)")
        guard http.statusCode == 200 else { return .failed }
        return SubscriptionRenewal.chatGPT(body, now: now).map(Outcome.read) ?? .noDate
    }

    /// `getAuthStatus` over one short app-server session. Nil on any failure.
    private static func codexToken(binary: String, home: String, generation: UInt64) -> String? {
        guard let rpc = RPCSession(binary: binary, codexHome: home, generation: generation) else { return nil }
        defer { rpc.close() }
        let deadline = Date().addingTimeInterval(15)
        rpc.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"UsageBar","version":"1.0"}}}"#)
        guard rpc.awaitLine(id: 1, until: deadline) != nil else { return nil }
        rpc.send(#"{"jsonrpc":"2.0","method":"initialized","params":{}}"#)
        rpc.send(#"{"jsonrpc":"2.0","id":2,"method":"getAuthStatus","params":{"includeToken":true,"refreshToken":true}}"#)
        guard let line = rpc.awaitLine(id: 2, until: deadline),
              let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let token = result["authToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// The workspace id inside the access token's claims (`https://api.openai.com/auth`).
    static func chatGPTAccountID(fromAccessToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = claims["https://api.openai.com/auth"] as? [String: Any],
              let id = auth["chatgpt_account_id"] as? String, !id.isEmpty else { return nil }
        return id
    }

    // MARK: Claude

    static let claudeHost = "claude.ai"
    static let claudeOrigin = URL(string: "https://claude.ai")!
    static let claudeLoginURL = URL(string: "https://claude.ai/login")!

    /// Accounts that finished a claude.ai sign-in. Without it nothing is sent.
    enum ClaudeConnection {
        static let key = "claudeWebConnectedAccounts"
        static func connected(_ defaults: UserDefaults = .standard) -> Set<String> {
            Set(defaults.stringArray(forKey: key) ?? [])
        }
        static func set(_ isOn: Bool, account: String, defaults: UserDefaults = .standard) {
            var ids = connected(defaults)
            if isOn { ids.insert(account) } else { ids.remove(account) }
            defaults.set(ids.sorted(), forKey: key)
        }
    }

    /// Each account's own claude.ai store, apart from its Console store and the user's browser.
    static func claudeStoreID(for accountID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("usagebar.claude-web-store.v1:" + accountID).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    @MainActor static func claudeDataStore(forAccount accountID: String) -> WKWebsiteDataStore {
        ConsoleCreditsFetch.dataStore(id: claudeStoreID(for: accountID))
    }

    private enum Answer {
        case json(Data)
        case unauthorized
        case other
    }

    private static func claudeGet(_ path: String, store: UUID) async -> Answer {
        let jar = ConsoleCreditsFetch.WebKitJar(storeID: store)
        let now = Date()
        let usable = await jar.cookies().filter { cookie in
            let domain = (cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain).lowercased()
            guard domain == claudeHost || claudeHost.hasSuffix("." + domain) else { return false }
            if let expires = cookie.expiresDate, expires <= now { return false }
            return true
        }
        guard !usable.isEmpty, let cookie = HTTPCookie.requestHeaderFields(with: usable)["Cookie"] else { return .unauthorized }
        var request = URLRequest(url: URL(string: claudeOrigin.absoluteString + path)!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(ConsoleCreditsFetch.signInUserAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue(claudeOrigin.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        guard let (body, reply) = try? await session.data(for: request, delegate: NoRedirects()),
              let http = reply as? HTTPURLResponse else {
            log.info("claude \(path.split(separator: "/").last.map(String.init) ?? "", privacy: .public) status=none")
            return .other
        }
        log.info("claude \(path.split(separator: "/").last.map(String.init) ?? "", privacy: .public) status=\(http.statusCode, privacy: .public)")
        let fields = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        let fresh = HTTPCookie.cookies(withResponseHeaderFields: fields, for: claudeOrigin)
        if !fresh.isEmpty { await jar.save(fresh) }
        switch http.statusCode {
        case 200: return .json(body)
        case 401, 403: return .unauthorized
        default: return .other
        }
    }

    /// The organizations the claude.ai session belongs to (`uuid`s). Nil when the session is not
    /// signed in.
    static func claudeOrganizations(store: UUID) async -> [String]? {
        guard case .json(let body) = await claudeGet("/api/organizations", store: store),
              let list = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]] else { return nil }
        let ids = list.compactMap { $0["uuid"] as? String }
        return ids.isEmpty ? nil : ids
    }

    /// `organization`: the Claude Code login's own organization (from its `.claude.json`); the
    /// claude.ai session must belong to it, or the date would be another account's.
    static func claude(accountID: String, organization: String?, connected: Bool, now: Date = Date()) async -> Outcome {
        guard connected else { return .notConnected }
        let store = claudeStoreID(for: accountID)
        guard let orgs = await claudeOrganizations(store: store) else { return .notConnected }
        guard let organization, orgs.contains(where: { $0.caseInsensitiveCompare(organization) == .orderedSame }) else {
            return organization == nil ? .failed : .differentAccount
        }
        switch await claudeGet("/api/organizations/\(organization)/subscription_details", store: store) {
        case .json(let body): return SubscriptionRenewal.claude(body, now: now).map(Outcome.read) ?? .noDate
        case .unauthorized: return .notConnected
        case .other: return .failed
        }
    }

    // MARK: Transport

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
