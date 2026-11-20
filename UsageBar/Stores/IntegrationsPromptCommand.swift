import Foundation

// The slash commands UsageBar installs beside its skill, and the prompt hooks that make them free.
// Split from the command's own file when a second command arrived: everything here is about "a
// command file plus a hook entry" and nothing about WHICH command, so the descriptor itself
// (`usageBarPromptCommand`, IntegrationsUsageBarCommand.swift) is all that file still holds.
//
// Why each command has both halves:
//
// - The HOOK (`UserPromptExpansion`, matched on the command's own name) runs before any model is
//   woken. It reads what was typed, does the work, and stops the expansion. Cost: zero tokens.
// - The COMMAND FILE (`<home>/commands/<name>.md`) is what runs when the hook does not: it is not
//   registered yet, or shell execution is disabled by policy. A model turn then does the same work.
//
// The command file is the fallback, so it must be able to answer alone - and it is also the ONLY
// half a user can read, so it says what the hook does rather than assuming the hook is there.
//
// settings.json is the user's own file, shared by symlink across accounts on some setups, and holds
// their whole harness. Every write here is therefore read-modify-write over the parsed document,
// touching exactly one array entry: the one whose command runs OUR subcommand. A file that does not
// parse is left alone and reported, never rewritten from an empty dictionary.

/// One slash command UsageBar manages: the file it installs, the hook that pre-empts it, and the
/// manifest keys the two are recorded under.
///
/// A value type rather than a second copy of every function, because the FAILURES this machinery
/// exists to prevent are all about ownership - never clobbering a user's own file, never deleting a
/// hook they put beside ours - and a second copy is a second chance to get one of them wrong. What
/// differs between commands is a name, a subcommand and a body; what must not differ is any of the
/// rest.
struct PromptCommand: Sendable {
    /// The slash command, which is also the command file's basename and the hook's matcher.
    let name: String
    /// The `usagebar` subcommand the hook runs, and the word an entry is recognised as ours by.
    let hookMarker: String
    /// The tool on UsageBar's MCP server that answers this command natively (MCPServe.swift). The
    /// second half of the same registration: the hook calls this tool, and a tool hook naming it is
    /// recognised as ours by it.
    let mcpTool: PromptHookTool
    /// The file's contents, marker line included.
    let markdown: String
    /// Where an install records the command files it wrote, and the settings files it registered in.
    let commandManifest: String
    let hookManifest: String
    /// Subcommands this command's hook used to run. An entry that runs one is ours, and the sync
    /// rewrites it to `hookMarker`.
    var formerHookMarkers: [String] = []
}

extension IntegrationsStore {
    // MARK: - The command file

    /// Where Claude Code looks for one of these in a config home.
    nonisolated static func promptCommandFile(inHome home: URL, command: PromptCommand) -> URL {
        promptCommandFile(inHome: home, named: command.name)
    }

    /// The same path by NAME, which is what a rename needs: the file left behind under a name this
    /// command no longer answers to is still at the place this spelling produces.
    nonisolated static func promptCommandFile(inHome home: URL, named name: String) -> URL {
        home.appendingPathComponent("commands/\(name).md")
    }

    /// The config home a `<home>/skills/<skill>/SKILL.md` path belongs to. The commands follow the
    /// skill's homes rather than discovering their own, which is what keeps them in step even for an
    /// account that has since logged out (its SKILL.md is still on disk, and so are its commands).
    nonisolated static func claudeHome(ofSkillFile file: URL) -> URL {
        file.deletingLastPathComponent()      // the skill folder
            .deletingLastPathComponent()      // skills
            .deletingLastPathComponent()      // the config home
    }

    /// Version marker, shared with the skill on purpose: they ship together, so one number says
    /// whether an install is current and one bump brings all of them up to date.
    nonisolated static var promptCommandMarker: String { "usagebar-command v\(skillVersion)" }

    /// Writes one command file. Anything at that path which is not ours is never clobbered, exactly
    /// as the skill treats a foreign skill file: existence and readability stay distinct, so an
    /// unreadable file throws rather than being overwritten unseen. Returns true when it changed.
    static func upsertPromptCommand(in file: URL, command: PromptCommand) throws -> Bool {
        if FileManager.default.fileExists(atPath: file.path) {
            let existing = try String(contentsOf: file, encoding: .utf8)
            if existing == command.markdown { return false }   // already ours - idempotent
            guard existing.contains("usagebar-command v") else {
                throw NSError(domain: BrandPaths.cliName, code: 4, userInfo: [
                    // The FILE NAME is an argument, never part of the key: interpolating it built
                    // a key that only exists in the catalog for whatever the command was called
                    // that day, so renaming the command silently dropped all four translations
                    // back to English (which is exactly what the /usagebar rename did).
                    NSLocalizedDescriptionKey:
                        String(format: L("A different command occupies commands/%@"),
                               file.lastPathComponent),
                ])
            }
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try IntegrationsBackup.save(file)
        try command.markdown.write(to: file, atomically: true, encoding: .utf8)
        return true
    }

    /// Reverses `upsertPromptCommand`: removes only a file that IS ours, then the commands folder
    /// when nothing else lives in it. A user's own file of the same name survives untouched.
    static func removePromptCommand(in file: URL) throws {
        guard let existing = try? String(contentsOf: file, encoding: .utf8),
              existing.contains("usagebar-command v") else { return }
        try IntegrationsBackup.save(file)
        try FileManager.default.removeItem(at: file)
        let dir = file.deletingLastPathComponent()
        if let leftovers = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
           leftovers.isEmpty {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Installed as one unit with the skill

    /// What one group's sync came to: what changed, what is now installed, and what went wrong.
    /// A result rather than a throw, because a group that fails must not stop the next one.
    struct PromptCommandSync {
        var changed = false
        /// The command files that are ours now, one per home that accepted one.
        var commands: [URL] = []
        /// The settings file whose hook is, or may still be, ours: just registered, or left in
        /// place by a write that failed. This is what the manifest records, so an uninstall can
        /// always reach what an install left. Nil means nothing of ours is in that file - either
        /// the hook was never registered, or it was just stood down.
        var settings: URL?
        var error: String?
    }

    /// The homes sharing ONE physical settings.json, synced together. Static and file-driven so it
    /// is testable without the singleton, whose manifest lives in the real `~/.usagebar`.
    ///
    /// THE GROUP IS THE UNIT, and that is the whole reason this takes a list. The hook lives in the
    /// settings file, and it intercepts the command and exits 2, which STOPS the expansion. A shared
    /// settings.json therefore speaks for EVERY home pointing at it: registering the hook because
    /// home B is clean would take home A's own command file away from them, since A's sessions read
    /// the same hook. So the hook goes in only when every home in the group has a command file UsageBar
    /// may manage.
    ///
    /// The command files themselves are still installed wherever they can be. That is the honest
    /// half of the answer: a home with no command of its own gains a working one (the model-turn
    /// path, one turn slower), and the home that has its own keeps running it. Skipping those too
    /// would punish the clean homes for their neighbour's file without protecting anyone.
    ///
    /// AND IT IS A DECISION, NOT A SKIP. The answer can change under a registration that is already
    /// there: a home whose command was UsageBar's until the user wrote their own is a group that WAS
    /// manageable and is not any more, and the hook left behind goes on intercepting the command
    /// they just took back. So the unmanageable branch stands the registration down rather than
    /// returning early, which is the same instruction as never registering, applied late.
    static func syncPromptCommand(inHomes homes: [URL], hooks: [[String: Any]],
                                  command: PromptCommand) -> PromptCommandSync {
        var result = PromptCommandSync()
        var manageable = true
        for home in homes {
            let file = promptCommandFile(inHome: home, command: command)
            do {
                result.changed = try upsertPromptCommand(in: file, command: command) || result.changed
                result.commands.append(file)
            } catch {
                result.error = result.error ?? error.localizedDescription
                manageable = false
            }
        }
        guard let settings = homes.first?.appendingPathComponent("settings.json") else { return result }
        do {
            if manageable {
                result.changed = try upsertPromptHook(in: settings, hooks: hooks,
                                                      hook: command) || result.changed
                result.settings = settings
            } else if try removePromptHook(in: settings, hook: command) {
                result.changed = true
            }
        } catch {
            result.error = result.error ?? error.localizedDescription
            // The file could not be acted on, so whatever is in it is still in it. Tracked
            // deliberately: a manifest that forgets it can never reach the hook we failed to reach
            // today, and an uninstall would leave it interposed forever.
            result.settings = settings
        }
        return result
    }

    /// Every home the skill is installed in, drawn from the whole account POPULATION rather than
    /// from the deduplicated skill files alone.
    ///
    /// `claudeSkillFiles()` deduplicates by physical SKILL.md, because one edit to a shared skills
    /// tree must not be counted twice. A home whose skills tree is symlinked at another's therefore
    /// never appears in `files` at all - while its commands folder is entirely its own, and so is
    /// anything it may hold. Grouping on the survivor of that dedup asks the ownership question
    /// about one home and answers it for two.
    ///
    /// Homes named by `files` are kept even when the population does not list them: an account that
    /// logged out since install is no longer discovered, and its SKILL.md is still on disk.
    nonisolated static func homesCarrying(_ files: [URL], population: [URL]) -> [URL] {
        let wanted = Set(files.map { $0.resolvingSymlinksInPath().path })
        let sharing = population.filter {
            wanted.contains(claudeSkillFile(inHome: $0).resolvingSymlinksInPath().path)
        }
        var seen = Set<String>()
        return (files.map(claudeHome(ofSkillFile:)) + sharing).filter {
            seen.insert($0.resolvingSymlinksInPath().path).inserted
        }
    }

    /// Those homes grouped by the physical settings.json they share, in a stable order. A group is
    /// what the hook decision is made for (above).
    private static func settingsGroups(ofSkillFiles files: [URL], population: [URL]) -> [[URL]] {
        var groups: [String: [URL]] = [:]
        var order: [String] = []
        for home in homesCarrying(files, population: population) {
            let key = home.appendingPathComponent("settings.json").resolvingSymlinksInPath().path
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(home)
        }
        return order.compactMap { groups[$0] }
    }

    /// Bring every command file and hook up to date for every home the skill is installed in.
    /// Returns true when anything on disk changed.
    ///
    /// Called on install AND at every launch (`autoUpdateSkill`), which is what repairs a hook whose
    /// binary path moved with the app. Failures land in `lastError` like every other integration:
    /// they never stop the skill itself from being installed.
    @discardableResult
    func syncPromptCommands(forSkillFiles files: [URL]) -> Bool {
        var changed = false
        let population = Self.claudeHomes()
        let groups = Self.settingsGroups(ofSkillFiles: files, population: population)
        // Asked ONCE per sync, and the same answer is what the self-heal gate reads: a sync that
        // registered the native pair while the heal expected the plain command would repair a file
        // that was already correct, on every filesystem event, forever.
        let nativePicker = Self.nativePickerIsSupported
        for command in Self.promptCommands {
            var commands: [String] = []
            var settingsFiles: [String] = []
            let hooks = Self.promptHookEntries(Self.bundledCLIURL, command: command,
                                               nativePicker: nativePicker)
            // One pass per PHYSICAL settings file. The manifest therefore records each shared file
            // once, which is also what it means: one registration, however many homes read it.
            for group in groups {
                let result = Self.syncPromptCommand(inHomes: group, hooks: hooks, command: command)
                changed = result.changed || changed
                if let error = result.error { lastError = error }
                commands.append(contentsOf: result.commands.map(\.path))
                if let file = result.settings { settingsFiles.append(file.path) }
            }
            recordManifest(command.commandManifest, paths: commands.isEmpty ? nil : commands)
            recordManifest(command.hookManifest, paths: settingsFiles.isEmpty ? nil : settingsFiles)
        }
        // PER HOME, not per settings group: `.claude.json` is the one file a shared setup does NOT
        // share (IntegrationsMCPServer.swift). A home missed here has hooks that call a server
        // nobody started, which the user meets as "it asks on one account and not on the other".
        let servers = Self.syncMCPServer(inHomes: Self.homesCarrying(files, population: population),
                                         binary: Self.bundledCLIURL, nativePicker: true)
        changed = servers.changed || changed
        if let error = servers.error { lastError = error }
        recordManifest(Self.mcpServerManifest,
                       paths: servers.files.isEmpty ? nil : servers.files.map(\.path))
        // The manifest just moved, and it is what says where to watch: an install performed in a
        // running app has to be watched from now, not from the next launch (IntegrationsSelfHeal).
        // A no-op whenever the set is unchanged, which is every heal.
        refreshSettingsWatcher()
        return changed
    }

    /// Everywhere one half of a pair can be, deduplicated by physical path: the homes the skill is
    /// in now, plus every path the manifest remembers. The manifest is what makes an account that
    /// logged out since install reachable at all, exactly as it is for the skill itself
    /// (`installedSkillFiles`).
    private static func installedFiles(_ derived: [URL], manifest component: String) -> [URL] {
        var seen = Set<String>()
        return (derived + manifestPaths(component).map { URL(fileURLWithPath: $0) })
            .filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
    }

    /// Take every half back out.
    func removePromptCommands(forSkillFiles files: [URL]) {
        let homes = Self.homesCarrying(files, population: [])
        for command in Self.promptCommands {
            for file in Self.installedFiles(homes.map {
                Self.promptCommandFile(inHome: $0, command: command)
            }, manifest: command.commandManifest) {
                do { try Self.removePromptCommand(in: file) } catch {
                    lastError = error.localizedDescription
                }
            }
            for file in Self.installedFiles(homes.map { $0.appendingPathComponent("settings.json") },
                                            manifest: command.hookManifest) {
                do { _ = try Self.removePromptHook(in: file, hook: command) } catch {
                    lastError = error.localizedDescription
                }
            }
            recordManifest(command.commandManifest, paths: nil)
            recordManifest(command.hookManifest, paths: nil)
        }
        // The server the hooks called, from every state file an install could have reached. Through
        // the same manifest union as the halves above, and for the same reason: an account that
        // logged out since install is no longer discovered, and its registration is still on disk
        // naming a bundle that is about to be gone.
        for file in Self.installedFiles(homes.map { claudeStateFile(forConfigDir: $0) },
                                        manifest: Self.mcpServerManifest) {
            do { try Self.removeMCPServer(in: file) } catch {
                lastError = error.localizedDescription
            }
        }
        recordManifest(Self.mcpServerManifest, paths: nil)
        // Nothing left to watch: the same call stops the stream rather than leaving one running
        // over a directory this app has no business in any more.
        refreshSettingsWatcher()
    }

    /// Whether every home with the skill also has a current file and a registered hook for EVERY
    /// command. Detection only, so Settings can offer to fix an install from an older app version -
    /// including one that predates a command entirely, which is exactly what a second command makes
    /// possible.
    ///
    /// Through the same population the sync uses, and for the same reason: a home whose skills tree
    /// is symlinked at another's is absent from the deduplicated file list while its commands folder
    /// is its own. Judging on the survivors alone reported an install complete while a home was
    /// missing its half of it. Injected rather than discovered so the tests never touch a real
    /// config home (`claudeHomes()` enumerates the machine's).
    nonisolated static func promptCommandsAreCurrent(forSkillFiles files: [URL], population: [URL]) -> Bool {
        promptCommands.allSatisfy {
            promptCommandIsCurrent(forSkillFiles: files, population: population, command: $0)
        }
    }

    /// The same question about ONE command. Separate because they are separate answers: an app that
    /// gained a second command leaves every existing install current in the first and missing the
    /// second, and telling those apart is what makes the repair reportable.
    nonisolated static func promptCommandIsCurrent(forSkillFiles files: [URL], population: [URL],
                                       command: PromptCommand) -> Bool {
        homesCarrying(files, population: population).allSatisfy { home in
            let text = try? String(contentsOf: promptCommandFile(inHome: home, command: command),
                                   encoding: .utf8)
            return text?.contains(promptCommandMarker) == true
                && settingsCarryPromptHook(home.appendingPathComponent("settings.json"),
                                           hook: command)
        }
    }
}
