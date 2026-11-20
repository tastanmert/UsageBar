import Foundation
import OSLog

/// Reads one Claude login's limit-reset inventory from Anthropic's OAuth usage endpoint, the same
/// request Claude Code makes for its own `/usage` (`cedar_ember=1`). Taken from the
/// `mert/feat/claude-reset-inventory` branch. The one other request, the confirmed claim (a POST,
/// live mode only), is ClaudeResetClaim and shares `authorize` and `liveTransport` below.
///
/// THE ONE PLACE USAGEBAR SENDS A CLAUDE TOKEN ANYWHERE (with the claim), so its rules are here:
/// - The token comes from the credential Claude Code keeps, through the prompt-free read the
///   login-expiry check uses (`ClaudeLoginExpiryKeychain.readForResetInventory`, gated by
///   `permitsSecurityRead`), or the home's `.credentials.json` when there is no Keychain item.
///   Both are read only: nothing here writes a credential, an ACL or a partition.
/// - It lives in memory for one request. No log, file or error carries it, and `Credential`
///   prints as redacted, so an interpolation by mistake cannot leak it either.
/// - A token that has expired, or will within `expiryMargin`, is never sent and never refreshed:
///   UsageBar (or Claude Code) owns that login and refreshes it; rotating it here could sign them out.
/// - The read is a GET, always. Redirects are refused, so the Authorization header goes to the one
///   host below.
enum ClaudeResetInventoryFetch {
    struct Credential: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        fileprivate let accessToken: String
        let expiresAt: Date
        var description: String { "Credential(<redacted>)" }
        var debugDescription: String { description }
        var customMirror: Mirror { Mirror(self, children: ["expiresAt": expiresAt]) }
    }

    /// Why no request went out. Nothing was sent in any of these.
    enum NoCredential: Equatable {
        /// The token has expired or is about to: waiting for UsageBar to refresh the login.
        case expiring
        /// A Keychain item exists but cannot be read without a prompt (locked, other ACL).
        case unreadable
        /// No Keychain item and no readable `.credentials.json`, or one with no usable token.
        case missing
    }

    enum CredentialRead {
        case usable(Credential)
        case none(NoCredential)
    }

    enum Outcome: Equatable {
        case read(ClaudeResetInventory)
        case noCredential(NoCredential)
        /// The request went out and no readable body came back. Carries the HTTP status only
        /// (nil: no response at all, a network error).
        case failed(status: Int?)
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1")!

    /// A token this close to its expiry is not sent: it could run out in flight, and the login is
    /// due a refresh by its owner anyway.
    static let expiryMargin: TimeInterval = 120

    /// The access token in a Claude Code credential document.
    static func credential(from document: Data, now: Date) -> CredentialRead {
        guard let root = (try? JSONSerialization.jsonObject(with: document)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty,
              let number = oauth["expiresAt"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return .none(.missing) }
        // Epoch milliseconds, the same bounds `ClaudeLoginExpiry` holds the refresh deadline to.
        let milliseconds = number.doubleValue
        guard milliseconds.isFinite, milliseconds >= 1_000_000_000_000,
              milliseconds <= 253_402_300_799_999 else { return .none(.missing) }
        let expiresAt = Date(timeIntervalSince1970: milliseconds / 1000)
        guard expiresAt.timeIntervalSince(now) > expiryMargin else { return .none(.expiring) }
        return .usable(Credential(accessToken: token, expiresAt: expiresAt))
    }

    /// The Keychain item wins as a whole, as it does for the login deadline: an existing item that
    /// is locked, denied or malformed does not make an older `.credentials.json` the live login.
    static func readCredential(home: String, defaultHome: String, now: Date,
                               keychainRead: (String) -> ClaudeLoginExpiry.Source,
                               fileRead: (URL) -> Data?) -> CredentialRead {
        let keychain = keychainRead(ClaudeLoginExpiry.keychainService(home: home, defaultHome: defaultHome))
        if let data = keychain.data { return credential(from: data, now: now) }
        guard keychain.isAbsent else { return .none(.unreadable) }
        guard let file = fileRead(URL(fileURLWithPath: home).appendingPathComponent(".credentials.json")) else {
            return .none(.missing)
        }
        return credential(from: file, now: now)
    }

    /// Claude Code's version for the User-Agent when the installed one cannot be read.
    static let fallbackVersion = "2.1.311"

    /// Claude Code's own client name. The server answers `cedar_ember` by client: without it the
    /// same token reads as `eligible: false` with no grants.
    static func userAgent(version: String) -> String { "claude-cli/\(version) (external, cli)" }

    /// The version the way Claude Code finds its own: the last component of the path the `claude`
    /// launcher resolves to (`~/.local/bin/claude` -> `~/.local/share/claude/versions/2.1.311`).
    /// Anything that is not a plain x.y.z there gets the fallback, which also keeps whatever the
    /// file system says out of a request header.
    static func version(executable: String?) -> String {
        guard let executable else { return fallbackVersion }
        let last = URL(fileURLWithPath: executable).resolvingSymlinksInPath().lastPathComponent
        return last.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil ? last : fallbackVersion
    }

    static func request(_ credential: Credential, version: String) -> URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.httpMethod = "GET"
        authorize(&request, credential, version: version)
        return request
    }

    /// The headers every request to Anthropic carries: Claude Code's client name, the token, the
    /// OAuth beta. The only place the token is read out of a `Credential`; the read above and the
    /// confirmed claim (ClaudeResetClaim) both go through it.
    static func authorize(_ request: inout URLRequest, _ credential: Credential, version: String) {
        request.setValue(userAgent(version: version), forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    /// How a request leaves: the ephemeral, redirect-refusing session below. Tests pass their own.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    static let liveTransport: Transport = { request in
        try await session.data(for: request, delegate: NoRedirects())
    }

    /// One account's inventory: the credential read, then the request when the token is usable.
    /// `readCredential` is the app's Keychain/file read by default; tests inject theirs.
    static func fetch(home: String, now: Date = Date(), version: String,
                      readCredential read: (String, Date) -> CredentialRead = liveCredential,
                      transport: Transport = liveTransport) async -> Outcome {
        switch read(home, now) {
        case .none(let reason): return .noCredential(reason)
        case .usable(let credential): return await fetch(credential, version: version, transport: transport, profileHome: home)
        }
    }

    /// The app's credential read: Keychain first, `.credentials.json` when no item exists.
    static func liveCredential(home: String, now: Date) -> CredentialRead {
        readCredential(home: home,
                       defaultHome: FileManager.default.homeDirectoryForCurrentUser
                           .appendingPathComponent(".claude").path,
                       now: now,
                       keychainRead: ClaudeLoginExpiryKeychain.readForResetInventory,
                       fileRead: { try? Data(contentsOf: $0) })
    }

    /// The read itself, with the credential in hand. A GET, always.
    static func fetch(_ credential: Credential, version: String,
                      transport: Transport = liveTransport, profileHome: String? = nil) async -> Outcome {
        let response = try? await transport(request(credential, version: version))
        guard let (body, reply) = response else { return .failed(status: nil) }
        let status = (reply as? HTTPURLResponse)?.statusCode
        if status == 200 {
#if DEBUG
            if let profileHome {
                BrimUsageDiagnostics.claude(body, profileHome: profileHome)
            }
#endif
            let seen = ClaudeResetInventory.programFields(body)
            log.info("response status=200 cedar_ember=\(seen.block, privacy: .public) eligible=\(seen.eligible, privacy: .public) ineligible_reason=\(seen.reason, privacy: .public) client=\(version, privacy: .public)")
        }
        guard status == 200, let inventory = ClaudeResetInventory.parse(body, now: Date()) else {
            return .failed(status: status)
        }
        return .read(inventory)
    }

    private static let log = Logger(subsystem: BrandPaths.appBundleID, category: "reset-inventory")

    /// Nothing written to disk: no URL cache, no cookies, no credential store.
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
