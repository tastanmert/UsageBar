import Foundation
import os

/// Reads Claude usage through the official CLI (`claude -p "/usage"`), so the CLI talks to
/// Anthropic with its own first-party identity. This usage reader does not read tokens, and an
/// expired token heals itself (the CLI refreshes it as part of the run).
enum ClaudeUsageCLI {
    /// Same channel as the round's probe lines (ProbeCadence.log), so one predicate reads both.
    private static let log = Logger(subsystem: BrandPaths.appBundleID, category: "poll")

    /// Dedicated probe cwd: a `-p` run from a CLI older than `--no-session-persistence` writes a
    /// session transcript under the account's `projects/<cwd-slug>/`, so giving the probe its own
    /// cwd both isolates that noise and makes it safe to prune.
    static let probeDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("\(BrandPaths.stateDirName)/probe", isDirectory: true)

    /// Where each account's isolated probe home lives (one directory per account, 0700).
    ///
    /// WHY: in print mode `/usage` also builds "What's contributing to your limits usage?" by reading
    /// every transcript written in the last 7 days under `CLAUDE_CONFIG_DIR/projects`, and the
    /// UsageBar-managed homes share that directory through a symlink (3,695 files, 5.07 GB measured
    /// 2026-09-27). UsageBar never shows that section. Pointing `CLAUDE_CONFIG_DIR` at an empty home
    /// while `CLAUDE_SECURESTORAGE_CONFIG_DIR` keeps the Keychain lookup on the real account gives the
    /// same three windows in a fraction of the CPU (0.6 CPU seconds instead of 7 to 15 on CC 2.1.283,
    /// though under load the wall clock is 64 to 89 seconds, measured 2026-11-04).
    /// `CLAUDE_SECURESTORAGE_CONFIG_DIR` is not documented (found in the 2.1.283 binary, where the CLI
    /// uses it for agent-team teammates), so every isolated read has the old read behind it.
    /// The CLI writes `.claude.json` here (it carries `oauthAccount`: email and organisation, no
    /// token), which is why the directory is private to the user. UsageBar does not read the file. Its
    /// only write is a manual refresh removing `cachedUsageUtilization` (Claude Code 2.1.285 answers a
    /// `/usage` asked within 60 seconds from that snapshot), so the manual read really asks the
    /// endpoint. If the key is renamed, the refresh falls back to the snapshot; nothing breaks.
    static let probeHomeRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("\(BrandPaths.stateDirName)/probe-home", isDirectory: true)

    /// Debug-only stand-in for `claude` on the usage read (B-1745): lets a Dev.app run against a
    /// scratch wrapper that makes one account slow, so the timeout path can be watched for real.
    static var devStandIn: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "UsageBarClaudeUsageCLI").flatMap { $0.isEmpty ? nil : $0 }
        #else
        nil
        #endif
    }

    /// How long an account whose isolated read proved unusable goes straight to the old read.
    static let legacyHold: TimeInterval = 60 * 60

    /// How long an account whose old read also failed skips the old read after an isolated miss
    /// (B-1745): the old read costs 17 to 35 seconds on a large home, and while the account itself
    /// cannot be read (a vendor-side outage, a sign-out) it fails again every round. The isolated
    /// read still runs each round, so a recovery shows on the next one.
    static let legacySkip: TimeInterval = 10 * 60

    /// How long one read may take before the watchdog ends it. Measured answers took up to 88.8
    /// seconds under load (2026-11-04, B-3918), so this leaves about a third on top of that; it only
    /// bounds a read that never answers, because an answered read returns as soon as it answers.
    static let readTimeout: TimeInterval = 120

    /// The old read that follows an isolated read which failed without timing out gets this much,
    /// so one round cannot cost two full `readTimeout`s.
    static let legacyAfterMissTimeout: TimeInterval = 60

    /// `configDir` nil = the default `~/.claude` account, which must run with CLAUDE_CONFIG_DIR
    /// UNSET on the old read (the CLI namespaces its Keychain item by the exact env value; explicitly
    /// passing the default path makes it look up a hashed item that doesn't exist - "Not logged in").
    /// On the isolated read the same rule is expressed as `CLAUDE_SECURESTORAGE_CONFIG_DIR=""`.
    static func fetchUsageText(configDir: String?, userInitiated: Bool = false, executable: String? = nil,
                               probeHomeRoot: URL = probeHomeRoot, timeout: TimeInterval = readTimeout,
                               now: Date = Date()) async -> String? {
        await fetchUsage(configDir: configDir, userInitiated: userInitiated, executable: executable,
                         probeHomeRoot: probeHomeRoot, timeout: timeout, now: now).text
    }

    /// `fetchUsageText` plus whether the miss was the watchdog's: a nil text with `timedOut` means
    /// the machine was too slow to answer, not that the CLI said no (B-3918). `serverWait` is the
    /// wait the CLI reported after an HTTP 429 on the usage endpoint (see `rateLimitWait`).
    static func fetchUsage(configDir: String?, userInitiated: Bool = false, executable: String? = nil,
                           probeHomeRoot: URL = probeHomeRoot, timeout: TimeInterval = readTimeout,
                           now: Date = Date()) async -> (text: String?, timedOut: Bool, serverWait: TimeInterval?, unreachable: Bool) {
        let debugFile = probeHomeRoot.deletingLastPathComponent()
            .appendingPathComponent("probe", isDirectory: true)
            .appendingPathComponent("\(probeHomeName(configDir: configDir)).usage-debug.log")
        try? FileManager.default.removeItem(at: debugFile)
        let result = await fetchUsageReading(configDir: configDir, userInitiated: userInitiated,
                                             executable: executable, probeHomeRoot: probeHomeRoot,
                                             timeout: timeout, now: now, debugFile: debugFile)
        let debugText = (try? String(contentsOf: debugFile, encoding: .utf8)) ?? ""
        let wait = rateLimitWait(debugText: debugText)
        let unreachable = wait == nil && usageUnreachable(debugText: debugText)
        try? FileManager.default.removeItem(at: debugFile)
        if let wait {
            log.notice("probe rate-limited account=\(probeHomeName(configDir: configDir), privacy: .public) serverWaitS=\(Int(wait), privacy: .public)")
        } else if unreachable {
            log.notice("probe unreachable account=\(probeHomeName(configDir: configDir), privacy: .public)")
        }
        return (result.text, result.timedOut, wait, unreachable)
    }

    /// The server's wait from the CLI's debug log after a 429 on `GET /api/oauth/usage`. Claude Code
    /// 2.1.x writes "fetchUtilization: 429 remembered for this bearer; not asking again for 1184s"
    /// (2026-11-17). Only that line is read; the log never leaves the private probe directory and is
    /// removed after each read. nil when the line is missing or its wording changes.
    static func rateLimitWait(debugLog file: URL) -> TimeInterval? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return rateLimitWait(debugText: text)
    }

    ///
    /// Any status the CLI holds off for counts, not only 429: Claude Code 2.1.323 treats a 403 the
    /// same way ("fetchUtilization: 403 remembered ... not asking again for 3600s"), and a run that
    /// replays an answer it already holds says "the endpoint answered 429 12s ago; not asked again
    /// for 3588s". Reading only 429 left a 403 spell without a hold, asked again every few minutes.
    static func rateLimitWait(debugText text: String) -> TimeInterval? {
        for line in text.split(separator: "\n") where line.contains("fetchUtilization") || line.contains("the endpoint answered") {
            guard let range = line.range(of: #"not ask(ing|ed) again for (\d+)s"#, options: .regularExpression) else { continue }
            let digits = line[range].filter(\.isNumber)
            if let seconds = Double(digits), seconds > 0 { return seconds }
        }
        return nil
    }

    /// The usage request never reached Anthropic: the CLI logged the failure with no HTTP status
    /// ("Failed to load usage data:" with nothing after it, the shape a dropped network gives,
    /// measured 2026-11-25), or a DNS or socket error. On 2026-11-24 and 25 the Mac's resolver
    /// (Tailscale's MagicDNS) answered ENOTFOUND for hours; the card said Anthropic was limiting
    /// reads, and the user went looking for a rate limit that was not there.
    static func usageUnreachable(debugText text: String) -> Bool {
        let markers = ["ENOTFOUND", "EAI_AGAIN", "ECONNREFUSED", "ECONNRESET", "ETIMEDOUT", "ENETUNREACH", "EHOSTUNREACH"]
        for line in text.split(separator: "\n") {
            if line.contains("Failed to load usage data") {
                if markers.contains(where: line.contains) { return true }
                if line.range(of: #"status code \d{3}"#, options: .regularExpression) == nil,
                   line.trimmingCharacters(in: .whitespaces).hasSuffix("Failed to load usage data:") { return true }
            }
            if line.contains("fetchUtilization") && markers.contains(where: line.contains) { return true }
        }
        return false
    }

    private static func fetchUsageReading(configDir: String?, userInitiated: Bool, executable: String?,
                                          probeHomeRoot: URL, timeout: TimeInterval, now: Date,
                                          debugFile: URL) async -> (text: String?, timedOut: Bool) {
        // BRIM-GATE: mirror mode must not refresh the shared Claude OAuth login.
        guard BrimFeatures.liveProbes else { return (nil, false) }
        guard let binary = executable ?? devStandIn ?? CLIRunner.resolve("claude") else { return (nil, false) }
        let directory = probeHomeRoot.deletingLastPathComponent().appendingPathComponent("probe", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { log.error("could not create probe directory: \(error.localizedDescription)"); return (nil, false) }
        let key = configDir ?? ""
        guard await routes.isolatedAllowed(key, now: now),
              let home = prepareProbeHome(root: probeHomeRoot, name: probeHomeName(configDir: configDir))
        else { return await legacyRead(binary: binary, configDir: configDir, timeout: timeout, directory: directory) }

        if userInitiated { dropUsageSnapshot(home: home) }
        let isolated = await read(binary: binary, environment: [
            "CLAUDE_CONFIG_DIR": home.path,
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": configDir ?? "",
        ], timeout: timeout, directory: directory, debugFile: debugFile)
        // A 429 is the server refusing this bearer for a stated time. The old read uses the same
        // bearer, so asking it as well only spends a second request inside the same window.
        // Unreachable is the same: the old read would only fail the same way a second time.
        if let text = try? String(contentsOf: debugFile, encoding: .utf8),
           rateLimitWait(debugText: text) != nil || usageUnreachable(debugText: text) {
            return (isolated.text, isolated.timedOut)
        }
        let verdict = isolatedVerdict(isolated.text, shapeVerified: await routes.shapeVerified(key))
        switch verdict {
        case .accept(let sawModelWindow):
            if sawModelWindow { await routes.apply(.shapeVerified, key: key, now: now) }
            return (isolated.text, isolated.timedOut)
        case .fallBack(let reason):
            // A read that ran out the clock is not tried the old way inside the same round
            // (B-1745): that was a second full timeout on the one account the round was already
            // waiting for. The failure-retry ladder asks again, and nothing is learned about the
            // route, the same as any other transient miss (`memoryUpdate(.noOutput)` is `.none`).
            if isolated.timedOut {
                log.notice("probe timed out account=\(probeHomeName(configDir: configDir), privacy: .public) legacy=skipped")
                // The answer that did arrive before the clock ran out still counts, even when its
                // shape is not yet confirmed: asking again the old way would cost a second timeout.
                return (reason == .unconfirmedModelWindow ? isolated.text : nil, true)
            }
            // Keep the isolated diagnosis and metrics when account-home probes are disabled.
            // A skipped legacy read cannot confirm a route failure or replace a valid answer.
            guard BrimFeatures.backgroundHomeWrites else { return isolated }
            if await routes.legacySkipped(key, now: now) {
                log.notice("probe failed account=\(probeHomeName(configDir: configDir), privacy: .public) legacy=skipped-recent-failure")
                return (isolated.text, false)
            }
            let legacy = await legacyRead(binary: binary, configDir: configDir,
                                          timeout: min(timeout, legacyAfterMissTimeout), directory: directory)
            await routes.apply(memoryUpdate(reason: reason, legacy: legacy.text), key: key, now: now)
            return legacy
        }
    }

    /// Removes the CLI's cached `/usage` snapshot from the probe home's `.claude.json`. Any read,
    /// parse or shape problem leaves the file exactly as it was.
    static func dropUsageSnapshot(home: URL) {
        let file = home.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: file),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object.removeValue(forKey: "cachedUsageUtilization") != nil,
              let updated = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        let mode = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions]
        guard (try? updated.write(to: file, options: .atomic)) != nil else { return }
        if let mode { try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path) }
    }

    // MARK: - The two reads

    /// The read as it was before the isolated home: the account's own config dir, and the
    /// secure-storage override explicitly removed so an inherited value cannot redirect it.
    private static func legacyRead(binary: String, configDir: String?,
                                   timeout: TimeInterval, directory: URL = probeDirectory) async -> (text: String?, timedOut: Bool) {
        // BRIM-GATE: never probe the real account home or prune its transcripts on a timer (both modes).
        guard BrimFeatures.backgroundHomeWrites else { return (nil, false) }
        let result = await read(binary: binary, environment: [
            "CLAUDE_CONFIG_DIR": configDir,
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": nil,
        ], timeout: timeout, directory: directory)
        if result.timedOut {
            log.notice("probe timed out account=\(probeHomeName(configDir: configDir), privacy: .public) legacy=true")
        }
        pruneProbeTranscripts(configDir: configDir)
        return result
    }

    /// One `/usage` run. Returns stdout on success, "Not logged in" on an authentication rejection
    /// (which commonly exits nonzero), nil otherwise. The run ends the moment the all-models week is
    /// printed (B-3918): `claude -p /usage` printed its answer 63.8 and 88.8 seconds in under load
    /// (measured 2026-11-04) and the pipes stayed open about 90 to 100 seconds longer, mostly held by
    /// grandchildren since the CLI itself exits sooner. The watchdog only ever cuts a read that has
    /// printed nothing, and a run it did cut with the week already in hand still counts.
    // --strict-mcp-config: the probe must never load MCP servers (fork-bomb guard + speed).
    // --safe-mode: nor the user's hooks and plugins. This runs once a minute per account, and
    // without it every run fired the whole SessionStart hook set of ~/.claude/settings.json
    // (seen in the probe transcripts as hook_success / hook_additional_context lines). Auth is
    // untouched by it; EarlyStartCommand.swift carries the same flag and the reasoning in full.
    // --no-session-persistence: the run leaves no transcript (print mode only), which kept about
    // 300 files in the probe directory at steady state. The prune in `legacyRead` stays for the
    // files an older CLI, or a run from before this flag, still leaves behind.
    // --debug-file (isolated read only): the one place the CLI says how long a 429 lasts.
    static func read(binary: String, environment: [String: String?],
                     timeout: TimeInterval, directory: URL = probeDirectory,
                     debugFile: URL? = nil) async -> (text: String?, timedOut: Bool) {
        // BRIM-GATE: mirror mode must not refresh the shared Claude OAuth login.
        guard BrimFeatures.liveProbes else { return (nil, false) }
        let output = await CLIRunner.run(
            binary,
            arguments: ["-p", "/usage", "--strict-mcp-config", "--safe-mode",
                        "--no-session-persistence"] + (debugFile.map { ["--debug-file", $0.path] } ?? []),
            environment: environment,
            currentDirectory: directory,
            timeout: timeout,
            // Not the runner's utility default: under load the read sat in the queue for most of a
            // minute while it needs about 0.6 CPU seconds (B-3918).
            qualityOfService: .userInitiated,
            answerComplete: { windows(in: $0).main }
        )
        guard let output else { return (nil, false) }
        let first = output.firstByteSeconds.map { String(Int($0 * 1000)) } ?? "none"
        let cpu = output.cpuSeconds.map { String(Int($0 * 1000)) } ?? "none"
        log.notice("probe read account=\(probeHomeName(configDir: environment["CLAUDE_CONFIG_DIR"] ?? nil), privacy: .public) firstByteMs=\(first, privacy: .public) cpuMs=\(cpu, privacy: .public) answered=\(output.answered, privacy: .public) timedOut=\(output.timedOut, privacy: .public)")
        let combined = output.stdout + "\n" + output.stderr
        // An authentication rejection commonly exits nonzero. Preserve that diagnosis only;
        // network failures and arbitrary stderr are not successful usage readings.
        if authenticationRejected(combined) { return ("Not logged in", false) }
        guard output.exitCode == 0 || output.answered || (output.timedOut && windows(in: output.stdout).main) else {
            return (nil, output.timedOut)
        }
        return (output.stdout, output.timedOut)
    }

    // MARK: - Deciding whether the isolated read counts (pure, tested directly)

    enum FallbackReason: Equatable {
        /// Nonzero exit or timeout with no authentication wording: may be transient.
        case noOutput
        /// The CLI found no login from the isolated home: the override is not honoured.
        case notLoggedIn
        /// Signed in, but the all-models week is missing.
        case incomplete
        /// The all-models week is present, no model window, and this account's shape is not yet confirmed.
        case unconfirmedModelWindow
    }

    enum IsolatedVerdict: Equatable {
        case accept(sawModelWindow: Bool)
        case fallBack(FallbackReason)
    }

    static func isolatedVerdict(_ text: String?, shapeVerified: Bool) -> IsolatedVerdict {
        guard let text else { return .fallBack(.noOutput) }
        if authenticationRejected(text) { return .fallBack(.notLoggedIn) }
        let found = windows(in: text)
        guard found.main else { return .fallBack(.incomplete) }
        if !found.model && !shapeVerified { return .fallBack(.unconfirmedModelWindow) }
        return .accept(sawModelWindow: found.model)
    }

    /// Which windows a reading carries: the main one (the all-models week; accounts without a
    /// 5-hour window print no session line), and any model week.
    private static func windows(in text: String) -> (main: Bool, model: Bool) {
        let ids = Set(ClaudeUsageTextMapper.map(text: text).map(\.id))
        return (ids.contains("weekly_all"),
                ids.contains { $0.hasPrefix("weekly_model:") })
    }

    enum MemoryUpdate: Equatable { case none, holdLegacy, shapeVerified, skipLegacy }

    /// What one fallback teaches about the account. Only an old read that DID produce both main
    /// windows can convict the isolated read; a transient failure convicts nothing. An old read that
    /// failed as well says the account itself cannot be read right now, so the next rounds skip it.
    static func memoryUpdate(reason: FallbackReason, legacy: String?) -> MemoryUpdate {
        guard let legacy, !authenticationRejected(legacy) else { return .skipLegacy }
        let found = windows(in: legacy)
        guard found.main else { return .skipLegacy }
        switch reason {
        case .noOutput: return .none
        case .notLoggedIn, .incomplete: return .holdLegacy
        case .unconfirmedModelWindow: return found.model ? .holdLegacy : .shapeVerified
        }
    }

    // MARK: - The isolated home

    /// `~/.claude` → "claude", `~/.claude3` → "claude3". Accounts are discovered only as direct
    /// children of the home directory (`accountConfigDirs`), so the last component is unique.
    static func probeHomeName(configDir: String?) -> String {
        guard let configDir else { return "claude" }
        let last = URL(fileURLWithPath: configDir).lastPathComponent
        return last.hasPrefix(".") ? String(last.dropFirst()) : last
    }

    /// Create or repair `<root>/<name>` as a private directory. nil (use the old read) when either
    /// level is not a real directory or cannot be made 0700.
    static func prepareProbeHome(root: URL, name: String) -> URL? {
        let fm = FileManager.default
        let dir = root.appendingPathComponent(name, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            for url in [root, dir] {
                let attributes = try fm.attributesOfItem(atPath: url.path)  // lstat: a symlink fails
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { return nil }
                if (attributes[.posixPermissions] as? NSNumber)?.intValue != 0o700 {
                    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                }
            }
            return dir
        } catch {
            return nil
        }
    }

    // MARK: - Per-account memory (process lifetime)

    private static let routes = ProbeRoutes()

    private actor ProbeRoutes {
        struct Entry { var legacyUntil: Date?; var shapeVerified = false; var legacySkipUntil: Date? }
        var entries: [String: Entry] = [:]

        func isolatedAllowed(_ key: String, now: Date) -> Bool {
            guard let until = entries[key]?.legacyUntil else { return true }
            return now >= until
        }
        func shapeVerified(_ key: String) -> Bool { entries[key]?.shapeVerified ?? false }
        func legacySkipped(_ key: String, now: Date) -> Bool {
            guard let until = entries[key]?.legacySkipUntil else { return false }
            return now < until
        }
        func apply(_ update: MemoryUpdate, key: String, now: Date) {
            switch update {
            case .none: break
            case .holdLegacy: entries[key, default: Entry()].legacyUntil = now.addingTimeInterval(legacyHold)
            case .shapeVerified: entries[key, default: Entry()].shapeVerified = true
            case .skipLegacy: entries[key, default: Entry()].legacySkipUntil = now.addingTimeInterval(legacySkip)
            }
        }
    }

    static func authenticationRejected(_ text: String) -> Bool {
        let plain = text.replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#,
                                             with: "", options: .regularExpression)
        return plain.split(separator: "\n").contains { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return value == "not logged in" || value.hasPrefix("not logged in ·")
                || value.hasPrefix("not logged in. please run /login")
                || value == "please run /login" || value == "authentication_failed"
        }
    }

    /// Delete the probe's own stale session transcripts (ours, minutes old, zero value) so polling
    /// never accumulates thousands of files. Only the dedicated probe slug is ever touched.
    private static func pruneProbeTranscripts(configDir: String?) {
        // BRIM-GATE: never probe the real account home or prune its transcripts on a timer (both modes).
        guard BrimFeatures.backgroundHomeWrites else { return }
        let home = configDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude").path
        let slug = probeDirectory.path
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let dir = URL(fileURLWithPath: home).appendingPathComponent("projects/\(slug)")
        let cutoff = Date().addingTimeInterval(-3600)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "jsonl" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            if modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}

/// Parses the human-readable `/usage` output. Grounded in live output (2026-07-17):
///
///   Current session: 63% used · resets Jul 17 at 3:19am (Asia/Taipei)
///   Current week (all models): 29% used · resets Jul 17 at 12:59am (Asia/Taipei)
///   Current week (Fable): 41% used · resets Jul 17 at 12:59am (Asia/Taipei)
///
/// Unknown lines are ignored, so the local-behavior blurb below those lines never breaks parsing.
enum ClaudeUsageTextMapper {
    static func map(text: String, now: Date = Date()) -> [UsageMetric] {
        var metrics: [UsageMetric] = []
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("Current "), let colon = line.firstIndex(of: ":") else { continue }
            let subject = String(line[line.index(line.startIndex, offsetBy: 8) ..< colon])
            let rest = String(line[line.index(after: colon)...])
            guard let percentRange = rest.range(of: #"\d+(\.\d+)?% used"#, options: .regularExpression),
                  let used = Double(rest[percentRange].dropLast("% used".count)) else { continue }
            let resets = rest.range(of: "resets ").flatMap {
                parseReset(String(rest[$0.upperBound...]), now: now)
            }

            if subject == "session" {
                metrics.append(UsageMetric(
                    id: "session", kind: .session, label: "Session", modelName: nil,
                    usedPercent: used, severity: .fromUsedPercent(used),
                    resetsAt: resets, isActive: false))
            } else if subject.hasPrefix("week") {
                let model = subject.range(of: #"\(([^)]+)\)"#, options: .regularExpression)
                    .map { String(subject[$0].dropFirst().dropLast()) } ?? ""
                if model == "all models" {
                    metrics.append(UsageMetric(
                        id: "weekly_all", kind: .weeklyAll, label: "Weekly", modelName: nil,
                        usedPercent: used, severity: .fromUsedPercent(used),
                        resetsAt: resets, isActive: false))
                } else if !model.isEmpty {
                    metrics.append(UsageMetric(
                        id: "weekly_model:\(model)", kind: .weeklyModel, label: model, modelName: model,
                        usedPercent: used, severity: .fromUsedPercent(used),
                        resetsAt: resets, isActive: false))
                }
            }
        }
        return metrics.uniquingIDs()
    }

    /// "Jul 17 at 3:19am (Asia/Taipei)" → Date. On-the-hour stamps drop the minutes entirely -
    /// "Jul 17 at 4am" (live output, 2026-07-17) - so minutes are optional. The year is inferred
    /// as the occurrence CLOSEST to now, past allowed: a stamp read minutes after its reset
    /// passed must stay "just passed" (stale data, harmless), not jump a year ahead - that jump
    /// made the smart pick score a fresh session as needing to last 8760h (2026-07-19).
    static func parseReset(_ string: String, now: Date = Date()) -> Date? {
        guard let stampRange = string.range(
            of: #"^[A-Z][a-z]{2} \d{1,2} at \d{1,2}(:\d{2})?(am|pm)"#, options: .regularExpression)
        else { return nil }
        // Normalize "4am" → "4:00am" so a single format string parses both variants.
        var stamp = String(string[stampRange])
        if !stamp.contains(":"),
           let meridiem = stamp.range(of: #"(am|pm)$"#, options: .regularExpression) {
            stamp.insert(contentsOf: ":00", at: meridiem.lowerBound)
        }
        let zone = string.range(of: #"\(([^)]+)\)"#, options: .regularExpression)
            .map { String(string[$0].dropFirst().dropLast()) }
            .flatMap(TimeZone.init(identifier:)) ?? .current

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "MMM d 'at' h:mma yyyy"

        let year = Calendar.current.component(.year, from: now)
        return (year - 1 ... year + 1)
            .compactMap { formatter.date(from: "\(stamp) \($0)") }
            .min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
    }
}
