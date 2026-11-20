import Foundation

// The BrimBar -> UsageBar carry-over against a scratch home and a scratch defaults domain; the
// real home directory and the app's own domain are never touched.

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}

let fm = FileManager.default
func scratchHome() -> URL {
    let url = fm.temporaryDirectory.appendingPathComponent("brandmigration-\(UUID().uuidString)", isDirectory: true)
    try! fm.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func write(_ text: String, to url: URL) {
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.write(to: url, atomically: true, encoding: .utf8)
}

// MARK: state directory

do {
    let home = scratchHome(); defer { try? fm.removeItem(at: home) }
    let old = home.appendingPathComponent(".brimbar")
    write("{}", to: old.appendingPathComponent("snapshot.json"))
    write("x", to: old.appendingPathComponent("logs/app.log"))
    check(LegacyBrandMigration.migrateStateDirectory(home: home) == .moved, "old dir only: moved")
    check(!fm.fileExists(atPath: old.path), "old dir gone after move")
    check(fm.fileExists(atPath: home.appendingPathComponent(".usagebar/snapshot.json").path), "snapshot under new dir")
    check(fm.fileExists(atPath: home.appendingPathComponent(".usagebar/logs/app.log").path), "log under new dir")
    check(LegacyBrandMigration.migrateStateDirectory(home: home) == .nothingToMove, "second run: nothing to move")
}

do {
    let home = scratchHome(); defer { try? fm.removeItem(at: home) }
    check(LegacyBrandMigration.migrateStateDirectory(home: home) == .nothingToMove, "fresh home: nothing to move")
}

do {
    let home = scratchHome(); defer { try? fm.removeItem(at: home) }
    write("old", to: home.appendingPathComponent(".brimbar/snapshot.json"))
    write("new", to: home.appendingPathComponent(".usagebar/snapshot.json"))
    check(LegacyBrandMigration.migrateStateDirectory(home: home) == .bothExist, "both exist: reported")
    check(try! String(contentsOf: home.appendingPathComponent(".brimbar/snapshot.json"), encoding: .utf8) == "old", "both exist: old untouched")
    check(try! String(contentsOf: home.appendingPathComponent(".usagebar/snapshot.json"), encoding: .utf8) == "new", "both exist: new untouched")
}

do {
    // A target whose parent cannot be written to: the move fails and the old directory stays.
    let home = scratchHome(); defer { chmod(home.path, 0o755); try? fm.removeItem(at: home) }
    write("old", to: home.appendingPathComponent(".brimbar/snapshot.json"))
    chmod(home.path, 0o555)
    let outcome = LegacyBrandMigration.migrateStateDirectory(home: home)
    var failed = false
    if case .failed = outcome { failed = true }
    check(failed, "unwritable home: failure reported, not swallowed (\(outcome))")
    check(fm.fileExists(atPath: home.appendingPathComponent(".brimbar/snapshot.json").path), "unwritable home: old dir left in place")
    check(!fm.fileExists(atPath: home.appendingPathComponent(".usagebar").path), "unwritable home: no new dir")
}

do {
    let home = scratchHome(); defer { try? fm.removeItem(at: home) }
    write("old", to: home.appendingPathComponent(".brimbar/snapshot.json"))
    write("history", to: home.appendingPathComponent(".brimbar/history.jsonl"))
    try! fm.createDirectory(at: home.appendingPathComponent(".usagebar/probe"), withIntermediateDirectories: true)
    write("legacy temp", to: home.appendingPathComponent(".brimbar/probe/legacy"))
    write("new temp", to: home.appendingPathComponent(".usagebar/probe/current"))
    check(LegacyBrandMigration.migrateStateDirectory(home: home) == .moved, "disposable probe directory permits migration")
    check(fm.fileExists(atPath: home.appendingPathComponent(".usagebar/probe/legacy").path), "nested legacy entries merged")
    check(try! String(contentsOf: home.appendingPathComponent(".usagebar/probe/current"), encoding: .utf8) == "new temp", "existing temporary entry kept")
    check(!fm.fileExists(atPath: home.appendingPathComponent(".brimbar").path), "merged legacy directory removed")
    check(try! String(contentsOf: home.appendingPathComponent(".usagebar/snapshot.json"), encoding: .utf8) == "old", "snapshot preserved in merge")
}
do {
    let home = scratchHome(); defer { try? fm.removeItem(at: home) }
    write("old", to: home.appendingPathComponent(".brimbar/snapshot.json"))
    write("old temp", to: home.appendingPathComponent(".brimbar/probe/same"))
    write("new temp", to: home.appendingPathComponent(".usagebar/probe/same"))
    let result = LegacyBrandMigration.migrateStateDirectory(home: home)
    if case .failed = result { check(true, "conflict reported") } else { check(false, "conflict must be reported") }
    check(try! String(contentsOf: home.appendingPathComponent(".usagebar/probe/same"), encoding: .utf8) == "new temp", "destination collision never overwritten")
    check(fm.fileExists(atPath: home.appendingPathComponent(".brimbar/probe/same").path), "unmoved legacy data retained")
}
for filename in ["history.jsonl", "settings.json"] {
    let home = scratchHome(); defer { try? fm.removeItem(at: home) }
    write("old", to: home.appendingPathComponent(".brimbar/snapshot.json"))
    write("new", to: home.appendingPathComponent(".usagebar/" + filename))
    check(LegacyBrandMigration.migrateStateDirectory(home: home) == .bothExist, "destination \(filename) blocks merge")
}

// MARK: defaults

let suite = "app.usagebar.brandmigration.test-\(UUID().uuidString)"
let oldDomain = suite + ".old"
let newDomain = suite + ".new"
final class MemoryDefaults: UserDefaults {
    var domains: [String: [String: Any]] = [:]
    override func persistentDomain(forName name: String) -> [String: Any]? { domains[name] }
    override func setPersistentDomain(_ domain: [String: Any], forName name: String) { domains[name] = domain }
    override func removePersistentDomain(forName name: String) { domains[name] = nil }
}
let store = MemoryDefaults(suiteName: suite)!
func cleanDefaults() { store.domains.removeAll() }


check(LegacyBrandMigration.renameKey("app.brimbar.lastGoodUsage") == "app.usagebar.lastGoodUsage", "prefixed key renamed")
check(LegacyBrandMigration.renameKey("brimAppearance") == "brimAppearance", "unprefixed key kept")
check(LegacyBrandMigration.legacyDomain(for: "app.usagebar.UsageBar.dev") == "app.brimbar.BrimBar.dev", "dev maps to dev")
check(LegacyBrandMigration.legacyDomain(for: "app.usagebar.UsageBar") == "app.brimbar.BrimBar", "release maps to release")

store.setPersistentDomain(["app.brimbar.lastGoodUsage": "u", "brimAppearance": "dark", "refreshIntervalMinutes": 5],
                          forName: oldDomain)
check(LegacyBrandMigration.migrateDefaults(from: oldDomain, to: newDomain, store: store) == .copied(3), "empty new domain: all keys copied")
let copied = store.persistentDomain(forName: newDomain) ?? [:]
check(copied["app.usagebar.lastGoodUsage"] as? String == "u", "prefixed key arrives renamed")
check(copied["app.brimbar.lastGoodUsage"] == nil, "old prefix not carried")
check(copied["brimAppearance"] as? String == "dark", "plain key copied")
check(copied["refreshIntervalMinutes"] as? Int == 5, "number copied")
check(copied[LegacyBrandMigration.defaultsDoneKey] as? Bool == true, "done marker set")
check((store.persistentDomain(forName: oldDomain) ?? [:]).count == 3, "old domain left as it was")

store.setPersistentDomain(["extra": 1], forName: oldDomain)
check(LegacyBrandMigration.migrateDefaults(from: oldDomain, to: newDomain, store: store) == .alreadyDone, "second run: already done")
check((store.persistentDomain(forName: newDomain) ?? [:])["extra"] == nil, "second run copies nothing")

// A new domain that already has a key of its own, but was never migrated: it keeps its value and
// gains the rest.
store.removePersistentDomain(forName: newDomain)
store.setPersistentDomain(["brimAppearance": "light"], forName: newDomain)
store.setPersistentDomain(["brimAppearance": "dark", "refreshIntervalMinutes": 5], forName: oldDomain)
check(LegacyBrandMigration.migrateDefaults(from: oldDomain, to: newDomain, store: store) == .copied(1), "partial new domain: only missing keys copied")
check((store.persistentDomain(forName: newDomain) ?? [:])["brimAppearance"] as? String == "light", "new value wins")

store.removePersistentDomain(forName: newDomain)
store.removePersistentDomain(forName: oldDomain)
check(LegacyBrandMigration.migrateDefaults(from: oldDomain, to: newDomain, store: store) == .nothingToCopy, "no old domain: nothing to copy")
check(LegacyBrandMigration.migrateDefaults(from: oldDomain, to: newDomain, store: store) == .alreadyDone, "no old domain: marked done")

// MARK: account markers

do {
    let home = scratchHome(); defer { try? fm.removeItem(at: home) }
    let a = home.appendingPathComponent(".claude-a", isDirectory: true)
    let b = home.appendingPathComponent(".claude-b", isDirectory: true)
    let c = home.appendingPathComponent(".codex-c", isDirectory: true)
    write("{\"paths\":[]}", to: a.appendingPathComponent(".brimbar-trust-seed.json"))
    write("", to: a.appendingPathComponent(".brimbar-pending-add"))
    write("old", to: b.appendingPathComponent(".brimbar-trust-seed.json"))
    write("new", to: b.appendingPathComponent(".usagebar-trust-seed.json"))
    try! fm.createDirectory(at: c, withIntermediateDirectories: true)
    let outcomes = LegacyBrandMigration.migrateAccountMarkers(configHomes: [a, b, c])
    check(outcomes == [.moved(a.appendingPathComponent(".brimbar-trust-seed.json").path),
                       .bothExist(b.appendingPathComponent(".brimbar-trust-seed.json").path)],
          "markers: one moved, one twin reported, empty home silent (\(outcomes))")
    check(fm.fileExists(atPath: a.appendingPathComponent(".usagebar-trust-seed.json").path), "trust seed renamed")
    check(!fm.fileExists(atPath: a.appendingPathComponent(".brimbar-trust-seed.json").path), "old trust seed gone")
    check(fm.fileExists(atPath: a.appendingPathComponent(".brimbar-pending-add").path), "pending-add left alone")
    check(try! String(contentsOf: b.appendingPathComponent(".usagebar-trust-seed.json"), encoding: .utf8) == "new", "twin: new kept")
}

if failures > 0 { print("\(failures) failure(s)"); cleanDefaults(); exit(1) }
print("brandmigration: all checks passed")
