import Foundation
import os

/// Carries the state a copy named BrimBar left behind over to the UsageBar name, once, before
/// anything else at launch reads or writes it. The old names live only here; every other file
/// spells the current ones through BrandPaths.
///
/// Three things are moved: the state directory (`~/.brimbar` -> `~/.usagebar`), the app's own
/// defaults domain (`app.brimbar.BrimBar[.dev]` -> the current bundle id, with `app.brimbar.`
/// key prefixes rewritten), and the permanent marker files UsageBar left in an account's config
/// home (`.brimbar-trust-seed.json`). Nothing of the old copy is deleted: the old defaults domain
/// stays, a pending-add marker stays (it belongs to an add that never finished), and a state
/// directory with entries that cannot be moved keeps those entries for a later attempt.
///
/// Every outcome is reported rather than swallowed: a move that fails must not look like "no old
/// state", because the launch that follows would then write an empty state over nothing and the
/// user would see their accounts gone.
enum LegacyBrandMigration {
    static let legacySlug = "brimbar"
    static let legacyStateDirName = "." + legacySlug
    static let legacyMarkerPrefix = "." + legacySlug + "-"
    static let legacyReverseDNS = "app.brimbar"
    static let legacyAppBundleID = legacyReverseDNS + ".BrimBar"
    static let legacyDevBundleID = legacyAppBundleID + ".dev"
    /// The key the defaults migration leaves in the new domain so it runs once, even when the new
    /// domain already had keys of its own (a launch under the new name before the copy).
    static let defaultsDoneKey = BrandPaths.reverseDNS + ".legacyBrandMigration.defaultsDone"
    /// The marker files that outlive the login they belong to and so move with the account.
    static let permanentMarkerNames = ["trust-seed.json"]

    nonisolated private static let log = Logger(subsystem: BrandPaths.appBundleID, category: "migration")

    enum DirectoryOutcome: Equatable {
        case moved
        /// No old directory: a fresh machine, or one already migrated.
        case nothingToMove
        /// Both contain persistent data, or the legacy directory has nothing to recover.
        case bothExist
        case failed(String)
    }

    /// Renames the legacy state, or merges into a disposable target without overwriting entries.
    static func migrateStateDirectory(home: URL, fileManager: FileManager = .default) -> DirectoryOutcome {
        let old = home.appendingPathComponent(legacyStateDirName, isDirectory: true)
        let new = home.appendingPathComponent(BrandPaths.stateDirName, isDirectory: true)
        guard fileManager.fileExists(atPath: old.path) else { return .nothingToMove }
        if fileManager.fileExists(atPath: new.path) {
            do {
                // Only known disposable directories and empty directories may precede migration.
                guard try isDisposable(new, fileManager: fileManager),
                      !(try isDisposable(old, fileManager: fileManager)) else { return .bothExist }
                var conflicts = false
                func merge(_ source: URL, _ target: URL) throws {
                    for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                        let destination = target.appendingPathComponent(item.lastPathComponent)
                        if !fileManager.fileExists(atPath: destination.path) {
                            try fileManager.moveItem(at: item, to: destination)
                        } else {
                            let a = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                            let b = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                            if a.isDirectory == true && b.isDirectory == true && a.isSymbolicLink != true && b.isSymbolicLink != true {
                                try merge(item, destination)
                                if try fileManager.contentsOfDirectory(atPath: item.path).isEmpty {
                                    try fileManager.removeItem(at: item)
                                }
                            } else { conflicts = true }
                        }
                    }
                }
                try merge(old, new)
                if conflicts { return .failed("destination entries kept; conflicting legacy entries left in place") }
                try fileManager.removeItem(at: old)
                return .moved
            } catch { return .failed(error.localizedDescription) }
        }
        do {
            try fileManager.moveItem(at: old, to: new)
            return .moved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func isDisposable(_ directory: URL, fileManager: FileManager) throws -> Bool {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { return false }
        for item in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return false }
            if ["probe", "probe-home"].contains(item.lastPathComponent) { continue }
            guard try isDisposable(item, fileManager: fileManager) else { return false }
        }
        return true
    }

    enum DefaultsOutcome: Equatable {
        case copied(Int)
        case alreadyDone
        /// The old domain has nothing. Still marked done, so it is not asked again.
        case nothingToCopy
    }

    /// The old domain's keys, renamed where they carried the old reverse-DNS prefix, into the new
    /// domain. A key the new domain already has keeps the new value. The old domain is left as it
    /// was.
    static func migrateDefaults(from oldDomain: String, to newDomain: String,
                                store: UserDefaults = .standard) -> DefaultsOutcome {
        var new = store.persistentDomain(forName: newDomain) ?? [:]
        if new[defaultsDoneKey] as? Bool == true { return .alreadyDone }
        let old = store.persistentDomain(forName: oldDomain) ?? [:]
        var copied = 0
        for (key, value) in old {
            let renamed = renameKey(key)
            guard new[renamed] == nil else { continue }
            new[renamed] = value
            copied += 1
        }
        new[defaultsDoneKey] = true
        store.setPersistentDomain(new, forName: newDomain)
        return old.isEmpty ? .nothingToCopy : .copied(copied)
    }

    static func renameKey(_ key: String) -> String {
        guard key.hasPrefix(legacyReverseDNS + ".") else { return key }
        return BrandPaths.reverseDNS + key.dropFirst(legacyReverseDNS.count)
    }

    /// The legacy domain this build's own domain replaces: Dev to Dev, release to release.
    static func legacyDomain(for bundleID: String) -> String {
        bundleID.hasSuffix(".dev") ? legacyDevBundleID : legacyAppBundleID
    }

    enum MarkerOutcome: Equatable {
        case moved(String)
        case bothExist(String)
        case failed(String, String)
    }

    /// Renames each permanent `.brimbar-*` marker in the given config homes to its `.usagebar-*`
    /// name. Only names are listed; no file inside a home is opened. A temporary marker
    /// (pending-add) is not touched: it records an add that has not landed, and the discovery
    /// that clears it looks for the current name, so an old one simply stays as a note.
    static func migrateAccountMarkers(configHomes: [URL], fileManager: FileManager = .default) -> [MarkerOutcome] {
        var outcomes: [MarkerOutcome] = []
        for home in configHomes {
            for name in permanentMarkerNames {
                let old = home.appendingPathComponent(legacyMarkerPrefix + name)
                let new = home.appendingPathComponent(BrandPaths.markerPrefix + name)
                guard fileManager.fileExists(atPath: old.path) else { continue }
                guard !fileManager.fileExists(atPath: new.path) else {
                    outcomes.append(.bothExist(old.path)); continue
                }
                do {
                    try fileManager.moveItem(at: old, to: new)
                    outcomes.append(.moved(old.path))
                } catch {
                    outcomes.append(.failed(old.path, error.localizedDescription))
                }
            }
        }
        return outcomes
    }

    /// The whole migration for this process, in the order the launch needs it: the state
    /// directory first (everything after reads it), then the defaults, then the account markers.
    static func runAtLaunch() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch migrateStateDirectory(home: home) {
        case .moved: log.notice("moved ~/\(legacyStateDirName) to ~/\(BrandPaths.stateDirName)")
        case .nothingToMove: break
        case .bothExist: log.notice("~/\(legacyStateDirName) and ~/\(BrandPaths.stateDirName) both exist; neither touched")
        case .failed(let reason): log.error("could not move ~/\(legacyStateDirName): \(reason); left in place")
        }

        if let bundleID = Bundle.main.bundleIdentifier {
            let legacy = legacyDomain(for: bundleID)
            switch migrateDefaults(from: legacy, to: bundleID) {
            case .copied(let count): log.notice("copied \(count) defaults keys from \(legacy)")
            case .alreadyDone, .nothingToCopy: break
            }
        }

        let homes = [".claude", ".codex"].flatMap { base -> [URL] in
            let main = home.appendingPathComponent(base, isDirectory: true)
            return [main] + accountConfigDirs(base: base, home: home)
        }
        for outcome in migrateAccountMarkers(configHomes: homes) {
            switch outcome {
            case .moved(let path): log.notice("renamed marker \(path)")
            case .bothExist(let path): log.notice("marker \(path) has a new-name twin; neither touched")
            case .failed(let path, let reason): log.error("could not rename marker \(path): \(reason)")
            }
        }
    }
}
