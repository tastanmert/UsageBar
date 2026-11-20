import Foundation

/// UsageBar's identity on disk and on the system, spelled once. The app and the `usagebar` CLI both
/// compile this file, so neither can drift to a different state directory, environment prefix or
/// notification name than the other.
///
/// Everything a running process writes, reads or registers under a name comes from here: the
/// state directory (`~/.usagebar`), the bundle id (`app.usagebar.UsageBar`), the command
/// (`usagebar`), the environment prefix (`USAGEBAR_*`), the markers left in an account's config
/// home (`.usagebar-pending-add`, `.usagebar-trust-seed.json`), the MCP server (`usagebar`) and the
/// shims (`~/.usagebar/bin`).
///
/// NOT here, on purpose: the provider's own identities (Claude Code's Keychain service
/// `Claude Code-credentials` and its per-folder hash rule, Codex's `auth.json`, the provider CLIs'
/// arguments). Those belong to the providers and must stay exactly what they are.
enum BrandPaths {
    static let displayName = "UsageBar"
    static let devDisplayName = "UsageBar"

    /// Reverse-DNS root for every system-wide name: notifications, defaults keys, queue labels,
    /// log subsystems.
    static let reverseDNS = "app.usagebar"
    static let appBundleID = "app.usagebar.UsageBar"
    /// Must end in `.dev`: BuildVariant.isDev reads that suffix (Config/Overlay.xcconfig sets it).
    static let devBundleID = "app.usagebar.UsageBar.dev"

    /// The command line tool's file name. The kernel names a process after its file, and the
    /// supervisor registry, reload and worktree teardown recognise supervisors by that name.
    static let cliName = "usagebar"
    /// Where an installed CLI is linked (Settings > Integrations > command line tool).
    static let cliLinkPath = "/usr/local/bin/" + cliName

    /// Prefix of every environment variable UsageBar sets or reads (`USAGEBAR_SUPERVISOR_PID`, ...).
    static let envPrefix = "USAGEBAR_"
    static func env(_ name: String) -> String { envPrefix + name }

    /// The state directory's name under the home directory, and the stem of every marker file
    /// UsageBar leaves in an account's config home (`.usagebar-pending-add`, ...).
    static let slug = "usagebar"
    static let stateDirName = "." + slug
    static let markerPrefix = "." + slug + "-"

    static var stateDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(stateDirName, isDirectory: true)
    }
    static var logDirectory: URL { stateDirectory.appendingPathComponent("logs", isDirectory: true) }
    static var shimDirectory: URL { stateDirectory.appendingPathComponent("bin", isDirectory: true) }

    /// The MCP server name registered with Claude Code and answered to by `usagebar mcp`.
    static let mcpServerName = slug
    /// The name of the block UsageBar would own in a shell profile.
    static let shellBlockName = slug
    /// Where releases are published; the About pane links here.
    static let releasesURL = URL(string: "https://github.com/tastanmert/usagebar/releases")!
    /// The subcommand the `/usagebar` prompt hook runs.
    static let promptHookVerb = "hook-quota"
}

/// Everything that writes outside UsageBar's own state directory on its own, or acts on the
/// user's behalf, starts OFF. Turned off rather than deleted, so each path can be re-enabled on its own once it
/// has been made UsageBar's. Every gate in the code carries a `// BRIM-GATE:` comment.
///
/// Two kinds: the gates UsageBar's own data path needs are open; the ones that would edit the
/// user's shell, a provider's settings or act on the user's behalf stay closed.
enum BrimFeatures {
    // MARK: Open

    /// Claude `/usage`, Codex `app-server`, login status and health: UsageBar reads its accounts itself.
    static let liveProbes = true
    /// Writing into an account's config home on the USER'S action: adding, removing or signing an
    /// account in again, and clearing the pending marker such an add left behind. Nothing at launch
    /// or on a timer writes there (see `backgroundHomeWrites`).
    static let providerHomeMutation = true
    /// Orphan reclaim (signalling a supervisor's leftover children, clearing leases).
    static let orphanReclaim = true
    /// macOS notifications.
    static let userNotifications = true
    /// Spending a Codex reset from the panel or the status menu, always behind the card's
    /// confirmation (Claude's claim: `claudeResetClaim`).
    static let panelResetUse = true
    /// Every CLI verb that acts rather than reports: launching a provider on a shared account
    /// home, adding an account, setting a profile, reaping, redeeming. Four verbs stay refused:
    /// the Keychain repair, the two binary updates and the Chrome step (BrimCLIGate.swift).
    static let cliWrites = true
    /// Shim, PATH block, Claude hooks, status line, MCP registration, Codex hooks, skill, prompt
    /// command, completion and the CLI link, ON THE USER'S PRESS ONLY (Settings > Integrations or
    /// a CLI install verb). Each install writes into its own slot (status line, hooks, Codex hooks,
    /// MCP server, shell block) and backs the file up first
    /// (IntegrationsBackup). Nothing here runs at launch or on a timer: the self-heal, the
    /// auto-follow and the launch-time upkeep stay behind the gates below.
    static let integrationInstall = true
    /// Sparkle updates from the tastanmert/UsageBar releases feed (UpdaterController). Release builds
    /// only: Debug carries no feed URL, so the updater stays dormant there either way.
    static let autoUpdate = true

    // MARK: Closed

    /// The Claude probe's old read in the account's own home, its transcript prune, and the
    /// Claude Code bundle repair. All three run on the refresh timer, never on a user's action.
    static let backgroundHomeWrites = false
    /// The settings-file watcher that rewrites a registration on its own, and the launch-time
    /// install of rows a previous version had authorised: both write without a press.
    static let integrationsSelfHeal = false
    static let integrationsAutoFollow = false
    /// The Keychain partition repair rewrites Claude's credential items.
    static let keychainPartitionRepair = false
    static let earlyStart = false
    /// Typing into a session's composer for the user: the quota knock, automatic input, the
    /// clearance lines and Codex's automatic resume line. The handoff itself still happens.
    static let typesIntoSessions = false
    static let chromeStep = false
    /// Spending a Codex reset on its own. The manual, confirmed path stays.
    static let codexAutoRedeem = false
    /// Reading each Claude login's limit-reset inventory (a GET to Anthropic's usage endpoint with
    /// the login's own token, read from its Keychain item or `.credentials.json`). Read only:
    /// never a refresh or a write; a claim happens only behind the card's confirmation.
    static let claudeResetInventoryRead = true
    /// Spending a Claude reset behind the card's confirmation. The claim is one POST with the
    /// login's own unexpired token (one that runs out within two minutes is not sent), never a
    /// token refresh, never a write to the account's home, and no `claude` process is started.
    /// This path cannot race on token refresh because it never refreshes; the server still decides
    /// whether a grant remains spendable. Afterwards the inventory and the usage are read again,
    /// nothing else. Codex's redeem needs a running `codex` process (`panelResetUse`).
    static let claudeResetClaim = true
    /// Updating the Codex CLI binary on a schedule.
    static let codexCLIAutoUpdate = false
    /// Registering the app as a login item at first launch.
    static let launchAtLoginDefault = false
    /// Seeding MCP grants into each account's `.claude.json` before a launch.
    static let mcpGrantSeeding = false
    /// A Dev launch terminating the older Dev copies still running.
    static let closesOlderDevInstances = false

    /// The Dev build may publish into `~/.usagebar` (snapshot, history): it shares that
    /// directory with no installed release app.
    static let devPublishesOwnState = true

    /// UsageBar asks the providers half as often as a provider's own clients would.
    static let refreshIntervalMultiplier = 2

    /// Every gate by name and its value now, for the table the checks pin.
    static var table: [String: Bool] {
        ["liveProbes": liveProbes, "providerHomeMutation": providerHomeMutation,
         "orphanReclaim": orphanReclaim, "userNotifications": userNotifications,
         "panelResetUse": panelResetUse, "cliWrites": cliWrites,
         "backgroundHomeWrites": backgroundHomeWrites, "integrationInstall": integrationInstall,
         "integrationsSelfHeal": integrationsSelfHeal, "integrationsAutoFollow": integrationsAutoFollow,
         "keychainPartitionRepair": keychainPartitionRepair, "earlyStart": earlyStart,
         "typesIntoSessions": typesIntoSessions,
         "autoUpdate": autoUpdate, "chromeStep": chromeStep, "codexAutoRedeem": codexAutoRedeem,
         "codexCLIAutoUpdate": codexCLIAutoUpdate, "launchAtLoginDefault": launchAtLoginDefault,
         "mcpGrantSeeding": mcpGrantSeeding, "closesOlderDevInstances": closesOlderDevInstances]
    }
}

/// The register of provider children (a `/usage` read, a Codex app server) started on an
/// account's behalf, so they can be stopped together, and the generation ticket a launch must
/// still hold to go ahead. Held behind a lock because probes read it off the main thread.
final class BrimRuntime: @unchecked Sendable {
    static let shared = BrimRuntime()

    private let lock = NSLock()
    private var generation: UInt64 = 0
    /// Child processes started on a provider's behalf, with the way to stop each.
    private var children: [ObjectIdentifier: () -> Void] = [:]

    /// The ticket a launch captures before it is enqueued; `stopAllChildren` invalidates it.
    var liveGeneration: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    /// Launch and registration share the lock. Capture the ticket before enqueueing: work queued
    /// before a `stopAllChildren` never starts after it.
    func launch(_ object: AnyObject, generation expected: UInt64,
                start: () throws -> Void, stop: @escaping () -> Void) rethrows -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard expected == generation else { return false }
        try start()
        children[ObjectIdentifier(object)] = stop
        return true
    }

    /// Registers a provider child with the way to stop it; `release` forgets it again.
    func track(_ object: AnyObject, stop: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        children[ObjectIdentifier(object)] = stop
    }

    func release(_ object: AnyObject) {
        lock.lock(); defer { lock.unlock() }
        children[ObjectIdentifier(object)] = nil
    }

    /// A provider's own CLI (`claude`, `codex`), the children `track` is for.
    static func isProviderExecutable(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name == "claude" || name == "codex"
    }

    var trackedCount: Int { lock.lock(); defer { lock.unlock() }; return children.count }

    /// Stops every tracked provider child and closes the current generation, so a launch still
    /// queued with the old ticket never starts.
    func stopAllChildren() {
        lock.lock()
        generation &+= 1
        let stops = Array(children.values)
        children.removeAll()
        lock.unlock()
        stops.forEach { $0() }
    }
}

/// Provider probes own a process group from spawn, including children which outlive the root.
/// User terminal sessions never use this launcher.
final class BrimProviderProcess: @unchecked Sendable {
    var executableURL: URL?
    var arguments: [String] = []
    var environment: [String: String]?
    var currentDirectoryURL: URL?
    var qualityOfService: QualityOfService = .utility
    var standardInput = Pipe()
    var standardOutput = Pipe()
    var standardError = Pipe()
    private let lock = NSLock()
    private(set) var processIdentifier: pid_t = 0
    private typealias AddChdir = @convention(c) (UnsafeMutablePointer<posix_spawn_file_actions_t?>,
                                                UnsafePointer<CChar>) -> Int32
    private static let addchdir: AddChdir? = {
        let handle = dlopen(nil, RTLD_NOW)
        for name in ["posix_spawn_file_actions_addchdir", "posix_spawn_file_actions_addchdir_np"] {
            if let symbol = dlsym(handle, name) { return unsafeBitCast(symbol, to: AddChdir.self) }
        }
        return nil
    }()
    private var status: Int32?

    func run() throws {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawn_file_actions_adddup2(&actions, standardInput.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, standardOutput.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, standardError.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        if let directory = currentDirectoryURL {
            // Looked up at run time: the `_np` spelling is deprecated from macOS 26 and the
            // replacement does not exist on the macOS 14 this ships for.
            guard let addchdir = Self.addchdir else { throw CocoaError(.featureUnsupported) }
            guard addchdir(&actions, directory.path) == 0 else { throw CocoaError(.fileNoSuchFile) }
        }
        guard let executable = executableURL?.path else { throw CocoaError(.fileNoSuchFile) }
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = (environment ?? ProcessInfo.processInfo.environment).map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        let result = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&processIdentifier, executable, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
        try? standardInput.fileHandleForReading.close()
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        guard processIdentifier > 0, status == nil else { return false }
        var value: Int32 = 0
        if waitpid(processIdentifier, &value, WNOHANG) == processIdentifier { status = value }
        return status == nil
    }
    var terminationStatus: Int32 {
        lock.lock(); defer { lock.unlock() }
        let value = status ?? 0
        return value & 0x7f == 0 ? (value >> 8) & 0xff : value & 0x7f
    }
    func waitUntilExit() { while isRunning { Thread.sleep(forTimeInterval: 0.02) } }
    func terminate() { if processIdentifier > 0 { kill(-processIdentifier, SIGTERM) } }

    /// Each group stops concurrently; many probes cannot multiply the shutdown deadline.
    func stopTree() {
        let group = processIdentifier
        guard group > 0 else { return }
        kill(-group, SIGTERM)
        DispatchQueue.global().async { [self] in
            let grace = Date().addingTimeInterval(2)
            while Date() < grace {
                _ = isRunning // reap the root, so it cannot keep the group alive as a zombie
                if kill(-group, 0) == -1 && errno == ESRCH { return }
                Thread.sleep(forTimeInterval: 0.02)
            }
            kill(-group, SIGKILL)
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                _ = isRunning
                if kill(-group, 0) == -1 && errno == ESRCH { return }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }
}
