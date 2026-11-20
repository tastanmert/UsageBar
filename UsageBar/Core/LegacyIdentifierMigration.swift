import Foundation

/// The one place the names an earlier build left on disk are spelled. Every other file uses the
/// current names; what is here exists so an update does not strand a user's settings, window
/// layout or already-installed integrations.
///
/// Compiled by the app and by the CLI (project.yml): the CLI reads `promptHookVerb` to keep
/// answering the hook command that is still registered in a user's settings.json until the app
/// rewrites it.
///
/// What the app does with these at launch:
/// - `migrateDefaults` copies each old UserDefaults key to its new name when the new one is unset,
///   then removes the old one. It runs once (`defaultsDoneKey`).
/// - `IntegrationsStore.migrateLegacyRegistrations` (IntegrationsLegacyMigration.swift) rewrites the
///   integration entries this app installed: the prompt hook's verb, the manifest component names,
///   and the PATH shims' header.
enum LegacyIdentifierMigration {
    // MARK: Hook verb

    /// The subcommand an earlier build registered for the slash command's prompt hook. The CLI
    /// accepts it silently as an alias of `BrandPaths.promptHookVerb`.
    static let promptHookVerb = "hook-tally"

    // MARK: Integration entries

    /// The manifest components the prompt command and its hook were recorded under.
    static let commandManifest = "claudeTallyCommand"
    static let hookManifest = "claudeTallyHook"
    /// The header line of the PATH shims in `~/.usagebar/bin`.
    static let shimHeader = "# tally-shim v"

    // MARK: Harness

    /// Markers and name of the harness skill and the instruction block an earlier build wrote.
    static let harnessBegin = "<!-- tally-harness:begin -->"
    static let harnessEnd = "<!-- tally-harness:end -->"

    /// The instruction block's first wording, which carried the old product name.
    static func harnessFirstBlock(source: String, begin: String, end: String) -> String {
        "\n" + begin + "\n"
        + "Tally connects this workspace to the user's Claude harness. Read the applicable\n"
        + "source instructions at `" + source + "` when present, alongside existing Codex instructions.\n"
        + "Use the tally-harness skill for tool-specific adaptation, verification, and inbox handling.\n"
        + "Claude framework mechanisms are not Codex tool contracts. Current user authorization takes precedence.\n"
        + end + "\n"
    }

    /// `text` with the old markers replaced by the current ones.
    static func harnessText(_ text: String, begin: String, end: String) -> String {
        text.replacingOccurrences(of: harnessBegin, with: begin)
            .replacingOccurrences(of: harnessEnd, with: end)
    }

    // MARK: UserDefaults

    /// Keys that hold a user's choice or a window's saved layout, old name to new name.
    static let defaultsKeys: [String: String] = [
        "TallyAppearance": "UsageBarAppearance",
        "TallyCardStyle": "UsageBarCardStyle",
        "TallyMenuBarAppearance": "UsageBarMenuBarAppearance",
        "TallyUsageLayout": "UsageBarUsageLayout",
        "TallySessionCardCap": "UsageBarSessionCardCap",
        "TallyChecksForUpdatesAutomatically": "UsageBarChecksForUpdatesAutomatically",
        "TallyMoveToApplicationsDest": "UsageBarMoveToApplicationsDest",
        "TallyMoveToApplicationsFail": "UsageBarMoveToApplicationsFail",
        "TallyMoveToApplicationsAutoMove": "UsageBarMoveToApplicationsAutoMove",
        "tallyInviteDismissed": "usageBarInviteDismissed",
        "NSWindow Frame TallyMainWindow.v3": "NSWindow Frame UsageBarMainWindow.v3",
        "NSToolbar Configuration TallyMainWindowToolbar": "NSToolbar Configuration UsageBarMainWindowToolbar",
        "NSWindow Frame TallyPinnedUsagePanel": "NSWindow Frame UsageBarPinnedUsagePanel",
    ]

    /// Left in the app's own defaults domain once the copy has run, so it never runs twice.
    static let defaultsDoneKey = BrandPaths.reverseDNS + ".legacyIdentifierMigration.defaultsDone"

    /// Copies each old key to its new name when the new one is unset, then removes the old one.
    /// Returns how many keys moved.
    @discardableResult
    static func migrateDefaults(_ defaults: UserDefaults = .standard) -> Int {
        guard !defaults.bool(forKey: defaultsDoneKey) else { return 0 }
        var moved = 0
        for (old, new) in defaultsKeys {
            guard let value = defaults.object(forKey: old) else { continue }
            if defaults.object(forKey: new) == nil {
                defaults.set(value, forKey: new)
                moved += 1
            }
            defaults.removeObject(forKey: old)
        }
        defaults.set(true, forKey: defaultsDoneKey)
        return moved
    }

    /// Runs the parts that touch only this app's own state. Call after `LegacyBrandMigration`.
    static func runAtLaunch() {
        migrateDefaults()
    }
}
