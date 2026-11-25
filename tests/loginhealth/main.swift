import Foundation

var passed = 0
func expect(_ value: @autoclosure () -> Bool, _ name: String) {
    guard value() else { fatalError("FAIL: " + name) }
    passed += 1
}

let now = Date(timeIntervalSince1970: 1_790_000_000)
let account = "claude:fixture"
let incident = LoginHealthSession(id: "100:101:" + account, accountID: account,
                                 childPid: 101, directory: "/fixture", failedAt: now)
var health = LoginHealthAlerts()
var local = LoginAlertState()
let localSignedIn: [String: LoginStatusCommand.Verdict] = [account: .signedIn]
let known: Set<String> = [account]

let first = health.advance(sessions: [incident], deadlines: [:], known: known, now: now)
expect(first.count == 1 && first.first?.kind == .session, "session failure begins an incident")
(local, _) = LoginAlertLogic.advance(state: local, verdicts: localSignedIn, known: known)
expect(health.sessions.contains(incident.episode), "local signed-in does not clear the session incident")
expect(health.advance(sessions: [incident], deadlines: [:], known: known, now: now).isEmpty,
       "the same session incident is posted once")
health.rearm(first[0])
expect(health.advance(sessions: [incident], deadlines: [:], known: known, now: now).count == 1,
       "a rejected notification can be submitted again")
expect(health.advance(sessions: [], deadlines: [:], known: known, now: now).isEmpty,
       "a recovered session no longer asks for an alert")
expect(health.sessions.isEmpty, "recovery retires the incident")
expect(health.advance(sessions: [incident], deadlines: [:], known: known, now: now).count == 1,
       "a new failure after recovery is armed")
_ = health.advance(sessions: [], deadlines: [:], known: known, now: now)
expect(health.sessions.isEmpty, "ending the session retires the incident")

let deadline = now.addingTimeInterval(4 * 86400)
expect(health.advance(sessions: [], deadlines: [account: deadline], known: known, now: now).isEmpty,
       "a deadline outside the warning window stays quiet")
let warning = health.advance(sessions: [], deadlines: [account: deadline], known: known,
                             now: now.addingTimeInterval(86400))
expect(warning.map(\.kind) == [.expiring], "a refresh at the three-day threshold warns")
expect(health.advance(sessions: [], deadlines: [account: deadline], known: known,
                      now: now.addingTimeInterval(2 * 86400)).isEmpty, "a deadline warns once")
expect(health.advance(sessions: [], deadlines: [:], known: known, now: deadline).isEmpty,
       "unknown metadata does not invent an expiry")
expect(health.advance(sessions: [], deadlines: [account: deadline], known: known,
                      now: now.addingTimeInterval(2 * 86400)).isEmpty,
       "unknown metadata does not rearm the prior deadline")
let expired = health.advance(sessions: [], deadlines: [account: deadline], known: known, now: deadline)
expect(expired.map(\.kind) == [.expired], "expiry has a separate alert after the advance warning")
expect(health.advance(sessions: [], deadlines: [account: deadline], known: known, now: deadline).isEmpty,
       "the expired alert is deduplicated")
let newDeadline = deadline.addingTimeInterval(86400)
expect(health.advance(sessions: [], deadlines: [account: newDeadline], known: known, now: deadline)
    .map(\.kind) == [.expiring], "renewing to a new deadline rearms the warning")
health.rearm(expired[0])
expect(health.advance(sessions: [], deadlines: [account: newDeadline], known: known, now: deadline).isEmpty,
       "an old asynchronous failure cannot rearm the new deadline")
let encoded = try JSONEncoder().encode(health)
health = try JSONDecoder().decode(LoginHealthAlerts.self, from: encoded)
expect(health.advance(sessions: [], deadlines: [account: newDeadline], known: known, now: deadline).isEmpty,
       "accepted submissions remain deduplicated after relaunch")
_ = health.advance(sessions: [], deadlines: [:], known: [], now: now)
expect(health.deadlines.isEmpty && health.expiryKeys.isEmpty, "removed accounts release deadline state")
let oldSignedOut = LoginAlertLogic.advance(state: local, verdicts: [account: .signedOut], known: known)
expect(oldSignedOut.1 == [account], "the original signed-out alert remains independent")

// Drive the production usage reader with a real subprocess. No real account or credential is used.
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
let stub = dir.appendingPathComponent("claude-fixture")
func script(_ body: String) throws {
    try ("#!/bin/sh\n" + body + "\n").write(to: stub, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.path)
}
// Exercise the shipped live reader with a local shell fixture.
var usageHealth = LoginUsageHealth()
if BrimFeatures.liveProbes && BrimFeatures.providerHomeMutation {
try script("printf 'Not logged in · Please run /login\\n' >&2\nexit 1")
let failure = await ClaudeUsageCLI.fetchUsageText(configDir: dir.path, executable: stub.path,
                                                    probeHomeRoot: dir.appendingPathComponent("probe-home"))
expect(failure.map(ClaudeUsageCLI.authenticationRejected) == true, "nonzero official usage auth failure survives the reader")
usageHealth.record(accountID: account, authenticated: false)
expect(usageHealth.needsSignIn(account, local: .signedIn), "usage rejection remains visible with local auth status true")
expect(usageHealth.applying(to: localSignedIn)[account] == .signedOut, "local success cannot rearm usage rejection notifications")
for text in ["HTTP 429: rate limited", "Network disconnected", "Visit docs for /login options", ""] {
    expect(!ClaudeUsageCLI.authenticationRejected(text), "unrelated output is not an authentication rejection")
}
try script("printf 'Network disconnected\\n' >&2\nexit 1")
let network = await ClaudeUsageCLI.fetchUsageText(configDir: dir.path, executable: stub.path,
                                                    probeHomeRoot: dir.appendingPathComponent("probe-home"))
expect(network == nil, "nonzero network error remains a read failure")
expect(usageHealth.needsSignIn(account, local: .signedIn), "unknown usage failure does not clear prior authentication failure")
try script("printf 'Current session: 12%% used\\n'\nexit 0")
let success = await ClaudeUsageCLI.fetchUsageText(configDir: dir.path, executable: stub.path,
                                                    probeHomeRoot: dir.appendingPathComponent("probe-home"))
expect(success.map { !ClaudeUsageTextMapper.map(text: $0).isEmpty } == true,
       "successful official usage output produces actual metrics")
let argvFile = dir.appendingPathComponent("argv")
try script("printf '%s\\n' \"$@\" > '\(argvFile.path)'\nprintf 'Current session: 12%% used\\n'\nexit 0")
_ = await ClaudeUsageCLI.fetchUsageText(configDir: dir.path, executable: stub.path,
                                                    probeHomeRoot: dir.appendingPathComponent("probe-home"))
let probeArgv = (try? String(contentsOf: argvFile, encoding: .utf8))?.split(separator: "\n").map(String.init)
expect(probeArgv?.prefix(5) == ["-p", "/usage", "--strict-mcp-config", "--safe-mode", "--no-session-persistence"],
       "the probe runs with MCP isolation, without the user's hooks and plugins, and leaves no transcript (\(probeArgv ?? []))")
expect(probeArgv?.count == 7 && probeArgv?[5] == "--debug-file"
       && probeArgv?[6].hasSuffix("/probe/\(dir.lastPathComponent).usage-debug.log") == true,
       "the isolated probe writes its debug log into the private probe directory, where the 429 wait is read")
// MARK: The isolated probe home, and the old read behind it.
// Inherit an override the way a shell inside an agent team would: the old read must remove it,
// and without this every run would pass whether or not it does.
setenv("CLAUDE_SECURESTORAGE_CONFIG_DIR", "/inherited/override", 1)
let envLog = dir.appendingPathComponent("env.log")
let threeWindows = """
    printf 'Current session: 13%% used · resets Sep 27 at 5:20pm (Asia/Taipei)\\n'
    printf 'Current week (all models): 15%% used · resets Oct 3 at 6pm (Asia/Taipei)\\n'
    printf 'Current week (Fable): 0%% used · resets Oct 3 at 6pm (Asia/Taipei)\\n'
    """
let twoWindows = """
    printf 'Current session: 13%% used · resets Sep 27 at 5:20pm (Asia/Taipei)\\n'
    printf 'Current week (all models): 15%% used · resets Oct 3 at 6pm (Asia/Taipei)\\n'
    """
/// Each run appends "CLAUDE_CONFIG_DIR|CLAUDE_SECURESTORAGE_CONFIG_DIR", with <unset> for absent,
/// so an empty value and a missing one read differently.
func routedStub(isolated: String, legacy: String) throws {
    try script("""
        printf '%s|%s\\n' "${CLAUDE_CONFIG_DIR-<unset>}" "${CLAUDE_SECURESTORAGE_CONFIG_DIR-<unset>}" >> '\(envLog.path)'
        if [ "${CLAUDE_SECURESTORAGE_CONFIG_DIR+x}" = x ]; then
        \(isolated)
        else
        \(legacy)
        fi
        """)
}
func runs() -> [String] {
    ((try? String(contentsOf: envLog, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
}
func resetLog() { try? FileManager.default.removeItem(at: envLog) }
let probeRoot = dir.appendingPathComponent("probe-home")
let notLoggedIn = "printf 'Not logged in · Please run /login\\n' >&2\nexit 1"
func metricIDs(_ text: String?) -> Set<String> {
    Set(text.map { ClaudeUsageTextMapper.map(text: $0).map(\.id) } ?? [])
}
let fullIDs: Set<String> = ["session", "weekly_all", "weekly_model:Fable"]

// T1: a signed-in extra account is read once, from its own private empty home.
resetLog()
let t1 = dir.appendingPathComponent(".claudeT1").path
try routedStub(isolated: threeWindows, legacy: notLoggedIn)
let t1Text = await ClaudeUsageCLI.fetchUsageText(configDir: t1, executable: stub.path, probeHomeRoot: probeRoot)
expect(metricIDs(t1Text) == fullIDs, "the isolated read yields all three windows")
expect(runs() == ["\(probeRoot.path)/claudeT1|\(t1)"],
       "one run, config home in the probe root, Keychain kept on the account (\(runs()))")
let t1Mode = (try? FileManager.default.attributesOfItem(atPath: probeRoot.path + "/claudeT1"))?[.posixPermissions] as? NSNumber
expect(t1Mode?.intValue == 0o700, "the probe home is private to the user")

// T2: the default account keeps the Keychain lookup on ~/.claude through an EMPTY override.
resetLog()
try routedStub(isolated: threeWindows, legacy: notLoggedIn)
_ = await ClaudeUsageCLI.fetchUsageText(configDir: nil, executable: stub.path, probeHomeRoot: probeRoot)
expect(runs() == ["\(probeRoot.path)/claude|"],
       "the default account sets the override to the empty string, not unset (\(runs()))")

// The legacy home stays closed. Preserve the isolated result without launching a second read.
expect(!BrimFeatures.backgroundHomeWrites, "background account-home writes remain disabled")
for (name, output, expectedIDs, rejected) in [
    ("signed-out", notLoggedIn, Set<String>(), true),
    ("incomplete", "printf 'Current session: 12%% used\\n'", Set(["session"]), false),
    ("no-model", twoWindows, Set(["session", "weekly_all"]), false),
    ("network", "printf 'Network disconnected\\n' >&2; exit 1", Set<String>(), false)
] {
    resetLog()
    let config = dir.appendingPathComponent(".claude-" + name).path
    try routedStub(isolated: output, legacy: threeWindows)
    let result = await ClaudeUsageCLI.fetchUsageText(configDir: config, executable: stub.path,
                                                    probeHomeRoot: probeRoot)
    expect(runs().count == 1, "\(name): the account's legacy home is never probed")
    expect(metricIDs(result) == expectedIDs, "\(name): isolated metrics survive")
    expect((result.map(ClaudeUsageCLI.authenticationRejected) ?? false) == rejected,
           "\(name): authentication diagnosis survives")
    if name == "network" { expect(result == nil, "network failure remains a read failure") }
}

// T8: an existing home with loose permissions is tightened before use.
resetLog()
let t8 = dir.appendingPathComponent(".claudeT8").path
let looseRoot = dir.appendingPathComponent("loose-root")
try FileManager.default.createDirectory(at: looseRoot.appendingPathComponent("claudeT8"),
                                        withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: looseRoot.path)
try routedStub(isolated: threeWindows, legacy: notLoggedIn)
_ = await ClaudeUsageCLI.fetchUsageText(configDir: t8, executable: stub.path, probeHomeRoot: looseRoot)
for path in [looseRoot.path, looseRoot.path + "/claudeT8"] {
    let mode = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber
    expect(mode?.intValue == 0o700, "loose permissions are repaired to 0700 (\(path))")
}

// T9: unsafe probe homes never fall back to the account home.
resetLog()
let t9 = dir.appendingPathComponent(".claudeT9").path
let fileRoot = dir.appendingPathComponent("file-root")
try FileManager.default.createDirectory(at: fileRoot, withIntermediateDirectories: true)
try Data().write(to: fileRoot.appendingPathComponent("claudeT9"))
try routedStub(isolated: notLoggedIn, legacy: threeWindows)
let invalidHome = await ClaudeUsageCLI.fetchUsageText(configDir: t9, executable: stub.path, probeHomeRoot: fileRoot)
expect(runs().isEmpty && invalidHome == nil, "a file in the home's place refuses the read")
resetLog()
let t9b = dir.appendingPathComponent(".claudeT9b").path
let linkRoot = dir.appendingPathComponent("link-root")
try FileManager.default.createSymbolicLink(at: linkRoot, withDestinationURL: probeRoot)
let invalidRoot = await ClaudeUsageCLI.fetchUsageText(configDir: t9b, executable: stub.path, probeHomeRoot: linkRoot)
expect(runs().isEmpty && invalidRoot == nil, "a symlinked root refuses the read")

// T14: an isolated read the watchdog ended is not tried the old way in the same round (B-1745).
// `exec` so the sleep IS the child: a forked sleep would hold stdout open past the kill.
resetLog()
let t14 = dir.appendingPathComponent(".claudeT14").path
try routedStub(isolated: "exec sleep 5", legacy: threeWindows)
let t14Text = await ClaudeUsageCLI.fetchUsageText(configDir: t14, executable: stub.path, probeHomeRoot: probeRoot,
                                                  timeout: 1)
expect(t14Text == nil && runs().count == 1, "a timed-out isolated read skips the old read (\(runs()))")
let t14Raw = await CLIRunner.run(stub.path, arguments: [], environment: ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "x"],
                                 timeout: 1)
expect(t14Raw?.timedOut == true, "the runner reports the watchdog's kill as a timeout")

// T15: a nonzero exit remains a failure without a second read or a timeout.
resetLog()
let t15 = dir.appendingPathComponent(".claudeT15").path
try routedStub(isolated: "exit 3", legacy: threeWindows)
let t15Text = await ClaudeUsageCLI.fetchUsageText(configDir: t15, executable: stub.path, probeHomeRoot: probeRoot,
                                                  timeout: 5)
expect(runs().count == 1 && t15Text == nil, "a nonzero exit never probes the account home")
let t15Raw = await CLIRunner.run(stub.path, arguments: [], environment: ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "x"],
                                 timeout: 5)
expect(t15Raw?.exitCode == 3 && t15Raw?.timedOut == false, "an exit of its own is not a timeout")

// T10 to T13: a manual refresh drops the CLI's 60-second `/usage` snapshot from the probe home.
let snapshotJSON = #"{"cachedUsageUtilization":{"fetchedAtMs":1,"utilization":{}},"oauthAccount":{"emailAddress":"a@b.c"},"other":7}"#
func plantSnapshot(_ name: String, _ contents: String?) throws -> URL {
    let home = probeRoot.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let file = home.appendingPathComponent(".claude.json")
    if let contents {
        try Data(contents.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    return file
}
try routedStub(isolated: threeWindows, legacy: notLoggedIn)
let t10 = dir.appendingPathComponent(".claudeT10").path
let t10File = try plantSnapshot("claudeT10", snapshotJSON)
_ = await ClaudeUsageCLI.fetchUsageText(configDir: t10, userInitiated: true, executable: stub.path, probeHomeRoot: probeRoot)
let t10Object = (try? JSONSerialization.jsonObject(with: Data(contentsOf: t10File))) as? [String: Any]
expect(t10Object != nil && t10Object?["cachedUsageUtilization"] == nil, "a manual refresh removes the usage snapshot")
expect(t10Object?["other"] as? Int == 7 && (t10Object?["oauthAccount"] as? [String: Any])?["emailAddress"] as? String == "a@b.c",
       "the other keys survive the snapshot removal")
let t10Mode = (try? FileManager.default.attributesOfItem(atPath: t10File.path))?[.posixPermissions] as? NSNumber
expect(t10Mode?.intValue == 0o600, "the rewritten .claude.json stays 0600")

let t11 = dir.appendingPathComponent(".claudeT11").path
let t11File = try plantSnapshot("claudeT11", snapshotJSON)
_ = await ClaudeUsageCLI.fetchUsageText(configDir: t11, executable: stub.path, probeHomeRoot: probeRoot)
expect((try? Data(contentsOf: t11File)) == Data(snapshotJSON.utf8), "an ordinary tick leaves the snapshot alone")

let t12 = dir.appendingPathComponent(".claudeT12").path
let t12File = try plantSnapshot("claudeT12", nil)
_ = await ClaudeUsageCLI.fetchUsageText(configDir: t12, userInitiated: true, executable: stub.path, probeHomeRoot: probeRoot)
expect(!FileManager.default.fileExists(atPath: t12File.path), "a missing .claude.json is not created")

let t13 = dir.appendingPathComponent(".claudeT13").path
let t13File = try plantSnapshot("claudeT13", "{not json")
_ = await ClaudeUsageCLI.fetchUsageText(configDir: t13, userInitiated: true, executable: stub.path, probeHomeRoot: probeRoot)
expect((try? Data(contentsOf: t13File)) == Data("{not json".utf8), "an unparseable .claude.json is left untouched")

unsetenv("CLAUDE_SECURESTORAGE_CONFIG_DIR")

}

// Pure verdicts, no process.
expect(ClaudeUsageCLI.isolatedVerdict(nil, shapeVerified: true) == .fallBack(.noOutput), "nil is a transient fallback")
// B-3402: an account with no 5-hour window prints only the week; that is a complete reading.
expect(ClaudeUsageCLI.isolatedVerdict("Current week (all models): 2% used", shapeVerified: true) == .accept(sawModelWindow: false),
       "a reading with only the all-models week is complete")
expect(ClaudeUsageCLI.isolatedVerdict("Current session: 1% used", shapeVerified: true) == .fallBack(.incomplete),
       "a reading without the all-models week is still incomplete")
expect(ClaudeUsageCLI.memoryUpdate(reason: .incomplete, legacy: "Current week (all models): 2% used") == .holdLegacy,
       "an old read with only the week can convict the isolated read")
expect(ClaudeUsageCLI.memoryUpdate(reason: .noOutput, legacy: "Current session: 1% used\nCurrent week (all models): 2% used") == .none,
       "a transient failure never holds")
expect(ClaudeUsageCLI.memoryUpdate(reason: .noOutput, legacy: nil) == .skipLegacy
       && ClaudeUsageCLI.memoryUpdate(reason: .notLoggedIn, legacy: "Not logged in") == .skipLegacy
       && ClaudeUsageCLI.memoryUpdate(reason: .incomplete, legacy: "Current session: 1% used") == .skipLegacy,
       "an old read that failed too skips the old read")
expect(ClaudeUsageCLI.probeHomeName(configDir: nil) == "claude"
       && ClaudeUsageCLI.probeHomeName(configDir: "/Users/x/.claude-work") == "claude-work",
       "probe home names drop the leading dot")
usageHealth.record(accountID: account, authenticated: true)
expect(!usageHealth.needsSignIn(account, local: .signedIn), "a genuine usage success clears the failure")
expect(usageHealth.needsSignIn(account, local: .signedOut), "original signed-out verdict still warns")
var generations = LoginProbeGate.Landings()
let beforeRenewal = generations.mark
usageHealth.record(accountID: account, authenticated: true)
generations.land([account])
expect(!usageHealth.recordIfCurrent(accountID: account, authenticated: false,
                                   since: beforeRenewal, landings: generations),
       "usage rejection started before renewal cannot overwrite the renewed login")
expect(!usageHealth.needsSignIn(account, local: .signedIn), "the renewed account stays healthy")
let beforeRemoval = generations.mark
generations.land([account])
expect(!usageHealth.recordIfCurrent(accountID: account, authenticated: false,
                                   since: beforeRemoval, landings: generations),
       "a removed account cannot be revived by an old provider callback")
let afterLanding = generations.mark
expect(usageHealth.recordIfCurrent(accountID: account, authenticated: false,
                                  since: afterLanding, landings: generations),
       "a fresh provider rejection still records its evidence")
var perAccount = LoginAlertState()
let firstCallback = LoginUsageHealth.updateAlert(state: perAccount, accountID: "a", authenticated: false)
perAccount = firstCallback.0
let secondCallback = LoginUsageHealth.updateAlert(state: perAccount, accountID: "b", authenticated: false)
perAccount = secondCallback.0
expect(perAccount.announced == ["a", "b"], "partial provider callbacks preserve both account outages")
expect(LoginUsageHealth.updateAlert(state: perAccount, accountID: "a", authenticated: false).1.isEmpty,
       "the second provider callback cannot rearm the first account")
perAccount = LoginUsageHealth.updateAlert(state: perAccount, accountID: "b", authenticated: true).0
expect(perAccount.announced == ["a"], "a successful provider callback clears only its own outage")
// MARK: A slow read that answers late or lingers, and one that never answers (B-3918).
// `claude -p /usage` printed its answer 63.8 and 88.8 seconds in under load and its pipes stayed open
// about 90 to 100 seconds longer; a fixed 60 second watchdog threw the answer away. Real time here,
// with 3 seconds standing for the 64 to 89 second answers and a 5 second limit for the 120 second one.
if BrimFeatures.liveProbes && BrimFeatures.providerHomeMutation {
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let answered = """
    printf 'Current week (all models): 32%% used · resets Nov 10 at 11:59pm (Asia/Taipei)\\n'
    printf 'Current week (Fable): 0%% used · resets Nov 11 at 12am (Asia/Taipei)\\n'
    """
func hasMainWindow(_ text: String?) -> Bool {
    text.map { ClaudeUsageTextMapper.map(text: $0).contains { $0.id == "weekly_all" } } ?? false
}
func slowAccount(_ name: String) -> String { dir.appendingPathComponent(name).path }
let slowRoot = dir.appendingPathComponent("probe-home")

// (a) The answer is printed at once and the CLI lingers: the read returns when the answer is in,
// not when the CLI exits or the limit arrives, and it is not called a timeout.
try script("\(answered)\nsleep 20")
var clock = Date()
let adopted = await ClaudeUsageCLI.read(binary: stub.path, environment: ["CLAUDE_CONFIG_DIR": dir.path], timeout: 10, directory: dir)
var took = Date().timeIntervalSince(clock)
expect(!adopted.timedOut && hasMainWindow(adopted.text) && took < 5,
       "(a) an answered read returns at once, with its answer, and is not a timeout (\(took)s)")
// (a2) The answer arrives after the old 60 second mark (3 of 5 seconds here) and still counts.
try script("sleep 3\n\(answered)\nsleep 20")
clock = Date()
let late = await ClaudeUsageCLI.fetchUsage(configDir: slowAccount("slow-a2"), executable: stub.path,
                                           probeHomeRoot: slowRoot, timeout: 5)
took = Date().timeIntervalSince(clock)
expect(!late.timedOut && hasMainWindow(late.text) && took > 2.5 && took < 5,
       "(a2) an answer that comes late but inside the limit is read, and the run ends with it (\(took)s)")
print("loginhealth: a2 returned in \(String(format: "%.2f", took))s")
// (a3) The answer comes after the limit: that is the only kind of timeout left.
try script("sleep 4\n\(answered)\nsleep 20")
let tooLate = await ClaudeUsageCLI.fetchUsage(configDir: slowAccount("slow-a3"), executable: stub.path,
                                              probeHomeRoot: slowRoot, timeout: 1)
expect(tooLate.text == nil && tooLate.timedOut, "(a3) an answer after the limit is a timeout")
// (a4) An answer without a model week still counts when the legacy read is disabled.
try script("printf 'Current week (all models): 32%% used\\n'\nsleep 20")
let unconfirmed = await ClaudeUsageCLI.fetchUsage(configDir: slowAccount("slow-a4"), executable: stub.path,
                                                  probeHomeRoot: slowRoot, timeout: 5)
expect(!unconfirmed.timedOut && hasMainWindow(unconfirmed.text), "(a4) an answer without a model week is kept too")

// (b) The CLI ignores SIGTERM and two grandchildren keep the pipes open for 20 seconds.
let pids = dir.appendingPathComponent("grandchildren.pid")
try script("trap '' TERM\n\(answered)\nsleep 20 & echo $! >> '\(pids.path)'\nsleep 20 & echo $! >> '\(pids.path)'\nwait")
let started = Date()
let held = await CLIRunner.run(stub.path, arguments: [], timeout: 1)
let elapsed = Date().timeIntervalSince(started)
expect(held?.timedOut == true && elapsed < 10, "(b) the runner is back within seconds of the timeout, not at the grandchildren's exit (\(elapsed)s)")
expect(held?.stdout.contains("32% used") == true, "(b) what was printed before the kill is still returned")
// (b2) Same CLI, but the answer ends the run: SIGTERM is ignored, so SIGKILL lands after the grace,
// and the grandchildren holding the pipes do not hold the return.
clock = Date()
let heldAnswered = await CLIRunner.run(stub.path, arguments: [], timeout: 10,
                                       answerComplete: { $0.contains("32% used") })
took = Date().timeIntervalSince(clock)
expect(heldAnswered?.answered == true && heldAnswered?.timedOut == false && took < 6
       && heldAnswered?.stdout.contains("32% used") == true && heldAnswered?.firstByteSeconds != nil,
       "(b2) an answered run that ignores SIGTERM is back within the settle and the kill grace (\(took)s)")
for line in ((try? String(contentsOf: pids, encoding: .utf8)) ?? "").split(separator: "\n") {
    if let pid = Int32(line) { kill(pid, SIGKILL) }
}

// (c) Nothing printed before the timeout is a timeout, an exit with an error is not.
try script("sleep 20")
let silent = await ClaudeUsageCLI.fetchUsage(configDir: slowAccount("slow-c"), executable: stub.path,
                                             probeHomeRoot: slowRoot, timeout: 1)
expect(silent.text == nil && silent.timedOut, "(c) no answer before the timeout reports a timeout")
try script("exit 1")
let broken = await ClaudeUsageCLI.fetchUsage(configDir: slowAccount("slow-c2"), executable: stub.path,
                                             probeHomeRoot: slowRoot, timeout: 1)
expect(broken.text == nil && !broken.timedOut, "(c) a failing CLI is still a read failure, not a timeout")
// (r) A 429 on the usage endpoint: the server's wait is read from the CLI's debug log line.
expect(ClaudeUsageCLI.rateLimitWait(debugText: """
2026-11-16T23:18:30.743Z [DEBUG] fetchUtilization: GET /api/oauth/usage (attempt 1)
2026-11-16T23:18:30.798Z [DEBUG] fetchUtilization: 429 remembered for this bearer; not asking again for 1184s
2026-11-16T23:18:30.798Z [ERROR] Failed to load usage data: Request failed with status code 429
""") == 1184, "(r) the 429 wait is read from the debug log")
expect(ClaudeUsageCLI.rateLimitWait(debugText: "fetchUtilization: GET /api/oauth/usage (attempt 1)\n") == nil,
       "(r) a log without a 429 names no wait")
expect(ClaudeUsageCLI.rateLimitWait(debugText: "other: 429 not asking again for 50s\n") == nil,
       "(r) only the usage fetch line counts")
expect(ClaudeUsageCLI.rateLimitWait(debugText: "2026-11-25T10:22:08Z [DEBUG] fetchUtilization: 403 remembered for this bearer; not asking again for 3600s\n") == 3600,
       "(r) a 403 hold names its wait too")
expect(ClaudeUsageCLI.rateLimitWait(debugText: "[ERROR] Failed to load usage data: the endpoint answered 429 12s ago; not asked again for 3588s\n") == 3588,
       "(r) a replayed answer names its remaining wait")
// (u) The read never reached Anthropic (2026-11-25): no status, or a DNS error.
expect(ClaudeUsageCLI.usageUnreachable(debugText: """
2026-11-25T14:37:26.323Z [DEBUG] fetchUtilization: GET /api/oauth/usage (attempt 1)
2026-11-25T14:37:26.340Z [ERROR] Failed to load usage data:
"""), "(u) a usage failure with no status is unreachable")
expect(ClaudeUsageCLI.usageUnreachable(debugText: "[ERROR] Failed to load usage data: getaddrinfo ENOTFOUND api.anthropic.com\n"),
       "(u) a DNS failure is unreachable")
expect(!ClaudeUsageCLI.usageUnreachable(debugText: "[ERROR] Failed to load usage data: Request failed with status code 429\n"),
       "(u) a 429 is not unreachable")
let providerSource = (try? String(contentsOfFile: "UsageBar/Providers/Claude/ClaudeProvider.swift", encoding: .utf8)) ?? ""
expect(providerSource.contains("timedOut ? L(\"This Mac is busy: the read timed out, it will retry next round\")")
       && providerSource.contains(": L(\"Claude CLI read failed\")"), "(c) the provider words a timeout apart from a read failure")
// B-3918: the read asks for a scheduling class and its CPU time is reported beside the wall time.
}

// A child's class cannot be read back here (a harness-clamped process tree answers 17, utility, even to a
// raw posix_spawn QoS attribute), so the pass-through is held by the sources and the run by behaviour.
let runnerSource = (try? String(contentsOfFile: "UsageBar/Core/CLIRunner.swift", encoding: .utf8)) ?? ""
let usageSource = (try? String(contentsOfFile: "UsageBar/Providers/Claude/ClaudeUsageCLI.swift", encoding: .utf8)) ?? ""
expect(runnerSource.contains("if let qualityOfService { process.qualityOfService = qualityOfService }")
       && usageSource.contains("qualityOfService: .userInitiated,\n            answerComplete:"),
       "the /usage read hands userInitiated to the Process it spawns")
expect(usageSource.contains("cpuMs=\\(cpu, privacy: .public)"), "the probe read line carries cpuMs")
let prioritised = await CLIRunner.run("/bin/sh", arguments: ["-c", "echo ok"], timeout: 10, qualityOfService: .userInitiated)
expect(prioritised?.exitCode == 0 && prioritised?.stdout == "ok\n", "a run with a quality of service still returns the child's output")
// A dispatch worker's blocked SIGTERM must not reach the spawned shell.
let terminated = await CLIRunner.run("/bin/sh", arguments: ["-c", "kill -TERM $$; echo survived"], timeout: 5)
expect(terminated?.exitCode == SIGTERM && terminated?.timedOut == false && terminated?.stdout == "",
       "a child handles SIGTERM without waiting for the watchdog's SIGKILL")
let busy = await CLIRunner.run("/bin/sh", arguments: ["-c", "i=0; while [ $i -lt 20000 ]; do i=$((i+1)); done; echo done"],
                               timeout: 30)
expect(busy?.cpuSeconds.map { $0 > 0 && $0 < 30 } == true, "a child's CPU time is reported (\(String(describing: busy?.cpuSeconds)))")
expect(abs(CLIRunner.seconds(ticks: 7_210_935, timebaseNumer: 125, timebaseDenom: 3) - 0.3005) < 0.0005
       && CLIRunner.seconds(ticks: 1_500_000_000, timebaseNumer: 1, timebaseDenom: 1) == 1.5
       && CLIRunner.seconds(ticks: 5, timebaseNumer: 1, timebaseDenom: 0) == 0,
       "rusage ticks are mach absolute time: 125/3 on Apple Silicon, not nanoseconds")
expect(CLIRunner.cpuSeconds(of: 999_999) == nil, "a pid the machine will not answer for has no CPU time (cpuMs=none)")

print("loginhealth: \(passed) passed")
