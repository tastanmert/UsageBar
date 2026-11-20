import Foundation

/// Reads Codex usage through the official CLI's app-server (JSON-RPC over stdio):
/// `initialize` → `initialized` → `account/rateLimits/read` → `account/read`. The CLI talks to its
/// vendor with its own first-party identity and credentials - UsageBar never reads `auth.json` tokens.
///
/// Response shape verified live (2026-07-17): `result.rateLimits.{primary,secondary}` carry
/// `usedPercent` / `windowDurationMins` / `resetsAt` (epoch s), plus `planType` - camelCase,
/// unlike the old HTTP endpoint's snake_case.
///
/// The second request is who the account is (2026-08-04). It rides in the SAME session rather than
/// in a process of its own: an extra `codex app-server` per account per poll would double the spawn
/// cost of every refresh for one string, and the answer belongs to the login this session already
/// opened.
enum CodexAppServerClient {
    struct Reading: Sendable {
        var metrics: [UsageMetric]
        var plan: String?
        /// Reset banking (verified live 2026-07-19): `result.rateLimitResetCredits.availableCount`.
        var resetCreditsAvailable: Int?
        /// Every credit listed, with its expiry kept even when null (nil = the list was absent or null).
        var resetCredits: [BankedResetCredit]?
        var codexCredit: CodexCredit? = nil
    }

    private struct RPCLine: Decodable {
        let id: Int?
        let result: Result?
        struct Result: Decodable {
            let rateLimits: RateLimits?
            let rateLimitResetCredits: CodexResetBank?
        }
    }

    private struct RateLimits: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            let windowDurationMins: Double?
            let resetsAt: Double?
        }
        let primary: Window?
        let secondary: Window?
        let planType: String?
    }

    /// Distinguishes the failure the user can act on: `cliBroken` means the app-server process
    /// died before answering (a codex too old to know `app-server`, or one that crashes on
    /// launch), where "read failed" would send the user chasing network or login ghosts.
    ///
    /// A read that failed CARRIES WHY where it could tell, for the same reason: the vendor
    /// answering the usage request with an error of its own is not this app being broken, and
    /// three failures under one word left nothing to act on either (`CodexReadFailure`). Nil where
    /// this path could not tell, which no surface treats as a fourth kind.
    enum Outcome {
        case ok(Reading)
        case cliBroken
        case failed(CodexReadFailure?)
    }

    /// What one read came home with. Identity sits BESIDE the outcome rather than inside `Reading`
    /// because the two questions fail apart: a session that could not produce numbers may still
    /// have named its account, and a card whose poll failed still gets to say whose it is - the
    /// same rule Claude's provider already follows.
    struct Answer {
        var outcome: Outcome
        var accountEmail: String?
    }

    static func read(codexHome: String, timeout: TimeInterval = 20) async -> Answer {
        guard let binary = CLIRunner.resolve("codex") else { return Answer(outcome: .failed(nil)) }
        let generation = BrimRuntime.shared.liveGeneration
        let attempt: Exchange = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: readExchange(binary: binary, codexHome: codexHome,
                                                            timeout: timeout, generation: generation))
            }
        }
#if DEBUG
        if let limits = attempt.limits {
            BrimUsageDiagnostics.codex(limits, profileHome: codexHome, method: "account/rateLimits/read")
        }
        if let account = attempt.account {
            BrimUsageDiagnostics.codex(account, profileHome: codexHome, method: "account/read")
        }
#endif
        let email = attempt.account.flatMap(CodexIdentity.email(inAccountRead:))
        // The ids a confirm card binds a reset to (BrimCodexApproval); replaced on every read.
        CodexIdentityBook.shared.record(home: codexHome, accountRead: attempt.account)
        func answer(_ outcome: Outcome) -> Answer {
            Answer(outcome: outcome, accountEmail: email)
        }
        // Asked only where the read has already failed: classifying it reads the line again, and a
        // poll that WORKED must not pay for a question about failure (`CodexReadFailure`).
        func why() -> CodexReadFailure? {
            CodexReadFailure.of(limitsLine: attempt.limits, processDied: attempt.processDied,
                                timeout: timeout)
        }
        guard let raw = attempt.limits else {
            return answer(attempt.processDied ? .cliBroken : .failed(why()))
        }
        guard let line = try? JSONDecoder().decode(RPCLine.self, from: raw),
              let limits = line.result?.rateLimits else { return answer(.failed(why())) }

        var metrics: [UsageMetric] = []
        for window in [limits.primary, limits.secondary].compactMap({ $0 }) {
            guard let used = window.usedPercent else { continue }
            let isWeekly = (window.windowDurationMins ?? 0) >= 1_440
            metrics.append(UsageMetric(
                id: isWeekly ? "weekly_all" : "session",
                kind: isWeekly ? .weeklyAll : .session,
                label: isWeekly ? "Weekly" : "Session",
                modelName: nil,
                usedPercent: used, severity: .fromUsedPercent(used),
                resetsAt: window.resetsAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
                isActive: false))
        }
        let plan = limits.planType?.trimmingCharacters(in: .whitespaces).capitalized
        // The whole list, not its soonest date: a credit whose expiry is null must stay in view
        // as "expiry unknown" rather than be dropped from a min() (`resetCreditsExpiryUnknown`).
        // A missing list stays nil rather than becoming an empty one (`CodexResetBank.listed`).
        let bank = line.result?.rateLimitResetCredits
        let root = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
        let result = root?["result"] as? [String: Any]
        let credit = CodexCredit.parse(rateLimits: result?["rateLimits"])
        return answer(.ok(Reading(
            metrics: metrics.uniquingIDs(), plan: (plan?.isEmpty == false) ? plan : nil,
            resetCreditsAvailable: bank?.availableCount,
            resetCredits: bank?.listed,
            codexCredit: credit)))
    }

    /// Redeems the SOONEST-EXPIRING available banked reset for this account (waste-minimizing
    /// order), via the official app-server's `account/rateLimitResetCredit/consume`. The only
    /// write UsageBar ever performs against a provider: behind an explicit user confirmation, or
    /// automatically once the account's weekly quota is used up if the user left that switch on
    /// (`CodexAutoRedeemStore`). Returns a short outcome token ("redeemed", "noCredit", …); nil =
    /// transport failure before an answer.
    static func consumeSoonestResetCredit(codexHome: String,
                                          timeout: TimeInterval = 30) async -> RedeemOutcome {
        // The legacy caller has no confirmed identity or credit. Fail closed until the store
        // supplies both through consume(expected:credit:); selecting a fresh credit here is unsafe.
        return .failed("Account identity and credit confirmation required")
    }

    enum ConsumeOutcome: Equatable {
        case resolved(RedeemOutcome)
        case uncertain
        case identityChanged
        case unavailable
    }

    static func consume(expected: CodexAccountIdentity, credit: BankedResetCredit,
                        timeout: TimeInterval = 30) async -> ConsumeOutcome {
        guard let binary = CLIRunner.resolve("codex"), let creditID = credit.id, !creditID.isEmpty
        else { return .unavailable }
        let generation = BrimRuntime.shared.liveGeneration
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let session = RPCSession(binary: binary, codexHome: expected.home,
                                               generation: generation) else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                defer { session.close() }
                let deadline = Date().addingTimeInterval(timeout)
                session.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"UsageBar","version":"1.0"}}}"#)
                guard session.awaitLine(id: 1, until: deadline) != nil else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                session.send(#"{"jsonrpc":"2.0","method":"initialized","params":{}}"#)
                var requestID = 1
                let outcome = CodexConsumeCoordinator.shared.consume(expected: expected, creditID: creditID,
                    isCurrent: { BrimRuntime.shared.liveGeneration == generation }, request: { method, params in
                        requestID += 1
                        let object: [String: Any] = ["jsonrpc": "2.0", "id": requestID,
                                                    "method": method, "params": params]
                        guard let data = try? JSONSerialization.data(withJSONObject: object),
                              let json = String(data: data, encoding: .utf8) else { return nil }
                        session.send(json)
                        return session.awaitLine(id: requestID, until: deadline)
                    })
                continuation.resume(returning: outcome)
            }
        }
    }

    /// What a redeem attempt actually did, in the app's own terms. The server answers with a bare
    /// protocol token whose vocabulary is its own ("reset", "redeemed", an error message), and the
    /// panel used to print any token it could not recognise verbatim: a successful redeem answered
    /// with "reset" surfaced as a lowercase English word floating under the card (2026-07-25). A
    /// closed type makes that structurally impossible - no raw token can reach a view again.
    enum RedeemOutcome: Equatable {
        case redeemed
        case alreadyUsed
        case noCredit
        /// The server's own words, kept for the hover tooltip only, never for the row.
        case failed(String?)
    }

    /// Map the server's token onto the closed set. Success is spelled several ways across versions,
    /// so recognition is by vocabulary rather than one exact string, and anything unrecognised is a
    /// failure carrying its detail rather than a mystery word in the UI.
    static func classifyRedeem(_ token: String?) -> RedeemOutcome {
        guard let token, !token.isEmpty else { return .failed(nil) }
        let lowered = token.lowercased()
        if lowered.contains("already") { return .alreadyUsed }
        if lowered == "nocredit" { return .noCredit }
        for word in ["redeem", "reset", "success", "consumed", "ok"] where lowered.contains(word) {
            return .redeemed
        }
        return .failed(token)
    }

    /// How long the identity answer may lag behind the numbers before the session gives up on it.
    private static let identityGrace: TimeInterval = 3

    /// The raw response lines one session came home with.
    private struct Exchange {
        var limits: Data?
        var account: Data?
        var processDied: Bool
    }

    /// Blocking JSON-RPC exchange (runs on a utility queue): the raw response lines for requests 2
    /// and 3. Both are written before either is awaited, so the second question costs a round trip
    /// the server is already answering rather than a second wait.
    private static func readExchange(binary: String, codexHome: String,
                                     timeout: TimeInterval, generation: UInt64) -> Exchange {
        guard let session = RPCSession(binary: binary, codexHome: codexHome, generation: generation) else {
            return Exchange(limits: nil, account: nil, processDied: true)
        }
        defer { session.close() }
        let deadline = Date().addingTimeInterval(timeout)
        session.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"UsageBar","version":"1.0"}}}"#)
        guard session.awaitLine(id: 1, until: deadline) != nil else {
            return Exchange(limits: nil, account: nil, processDied: session.processDied)
        }
        session.send(#"{"jsonrpc":"2.0","method":"initialized","params":{}}"#)
        session.send(#"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#)
        session.send(#"{"jsonrpc":"2.0","id":3,"method":"account/read","params":{}}"#)
        let limits = session.awaitLine(id: 2, until: deadline)
        // Identity is the optional half, and it was asked one line after the numbers: by the time
        // they land its answer is already on the way. So it gets a short grace rather than the
        // whole deadline - a codex that simply never answers it must not hold a refresh open.
        let account = session.awaitLine(id: 3, until: min(deadline,
                                                          Date().addingTimeInterval(identityGrace)))
        return Exchange(limits: limits, account: account, processDied: session.processDied)
    }
}

/// One live app-server process with line-indexed responses: send JSON-RPC strings, await a
/// response id, close. Shared by the read path and the consume flow.
final class RPCSession {
    private let process = BrimProviderProcess()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let buffer = RPCLineBuffer()

    init?(binary: String, codexHome: String, generation: UInt64 = BrimRuntime.shared.liveGeneration) {
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server"]
        var env = CLISearchPath.shared.environment(for: binary)
        // The account's real home, as the probe uses it. A probe home
        // under ~/.usagebar would split the login the CLI keeps there.
        env["CODEX_HOME"] = codexHome
        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        let process = self.process
        do {
            guard try BrimRuntime.shared.launch(process, generation: generation,
                start: { try process.run() }, stop: { process.stopTree() }) else { return nil }
        } catch { return nil }
        stdoutPipe.fileHandleForReading.readabilityHandler = { [buffer] handle in
            buffer.append(handle.availableData)
        }
    }

    /// True when app-server exited on its own (old codex without the subcommand, or a crash),
    /// which callers use to tell "broken CLI" apart from a slow or unresponsive one.
    var processDied: Bool { !process.isRunning }

    func send(_ json: String) {
        stdinPipe.fileHandleForWriting.write(Data((json + "\n").utf8))
    }

    func awaitLine(id: Int, until deadline: Date) -> Data? {
        while buffer.line(withID: id) == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return buffer.line(withID: id)
    }

    func close() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        BrimRuntime.shared.release(process)
        process.stopTree()
    }
}

/// Accumulates app-server stdout and indexes complete JSON-RPC lines by response id.
/// Thread-safe: the readability handler appends from its own queue while the RPC loop polls.
private final class RPCLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var byID: [Int: Data] = [:]

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = Data(pending.prefix(upTo: newline))
            pending.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = object["id"] as? Int else { continue }
            byID[id] = line
        }
    }

    func line(withID id: Int) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return byID[id]
    }
}
