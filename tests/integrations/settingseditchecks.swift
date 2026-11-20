import Foundation

@MainActor
func runSettingsEditChecks(tmp: URL) throws {
    let file = tmp.appendingPathComponent("edit-settings.json")
    let user = "printf user-status"
    let wrapped = Data(user.utf8).base64EncodedString()
    func write(_ value: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: value).write(to: file)
    }
    func read() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    }
    func commands(_ value: [String: Any], event: String) -> [String] {
        ((value["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? [])
            .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .compactMap { $0["command"] as? String }
    }
    try write(["statusLine": ["type": "command", "command": user], "user": "keep"])
    let prior = try Data(contentsOf: file)
    let ours = #""/Applications/UsageBar.app/Contents/Helpers/usagebar" statusline claude"#
    _ = try IntegrationsStore.upsertStatusLine(in: file, command: ours)
    check("statusline: the user's own line is carried inside ours",
          ((try read()["statusLine"] as? [String: Any])?["command"] as? String)?.hasPrefix(ours + " --wrap " + wrapped) == true)
    check("statusline: original bytes backed up before rewrite",
          try Data(contentsOf: IntegrationsBackup.copyURL(for: file)) == prior)
    _ = try IntegrationsStore.removeStatusLine(in: file, command: ours)
    check("statusline: uninstall restores user statusline",
          (try read()["statusLine"] as? [String: Any])?["command"] as? String == user)
    check("statusline: unrelated setting survives", try read()["user"] as? String == "keep")

    // The user's other statusLine keys survive install and removal.
    let padded = tmp.appendingPathComponent("padded-settings.json")
    let paddedOurs = #""/Applications/UsageBar.app/Contents/Helpers/usagebar" statusline claude"#
    try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": "printf mine",
                                                               "padding": 2]]).write(to: padded)
    _ = try IntegrationsStore.upsertStatusLine(in: padded, command: paddedOurs)
    var paddedLine = (try JSONSerialization.jsonObject(with: Data(contentsOf: padded)) as! [String: Any])["statusLine"] as! [String: Any]
    check("statusline: install keeps padding", paddedLine["padding"] as? Int == 2
          && (paddedLine["command"] as? String)?.hasPrefix(paddedOurs) == true)
    _ = try IntegrationsStore.removeStatusLine(in: padded, command: paddedOurs)
    paddedLine = (try JSONSerialization.jsonObject(with: Data(contentsOf: padded)) as! [String: Any])["statusLine"] as! [String: Any]
    check("statusline: removal restores command and keeps padding",
          paddedLine["padding"] as? Int == 2 && paddedLine["command"] as? String == "printf mine"
          && paddedLine["type"] as? String == "command")

    // A half-open block in ~/.zshenv is found before anything is written.
    let shimEnv = tmp.appendingPathComponent("shim-zshenv")
    try "export A=1\n\(IntegrationsStore.blockBegin)\nhalf\n".write(to: shimEnv, atomically: true, encoding: .utf8)
    let envBefore = try Data(contentsOf: shimEnv)
    var shimRefused = false
    do { try IntegrationsStore.validateShimShellFiles(zshenv: shimEnv) } catch { shimRefused = true }
    check("shim: half-open block is refused up front, no file changed",
          try shimRefused && Data(contentsOf: shimEnv) == envBefore)
    try "x\n".write(to: shimEnv, atomically: true, encoding: .utf8)
    var shimOK = true
    do { try IntegrationsStore.validateShimShellFiles(zshenv: shimEnv) } catch { shimOK = false }
    check("shim: a well-formed file passes validation", shimOK)

    // Backup folder is private.
    let bakRoot = tmp.appendingPathComponent("bak-root")
    let savedRoot = IntegrationsBackup.root
    try FileManager.default.createDirectory(at: bakRoot, withIntermediateDirectories: true)
    IntegrationsBackup.root = bakRoot
    let copy = try IntegrationsBackup.save(file)
    let mode = try FileManager.default.attributesOfItem(
        atPath: copy!.deletingLastPathComponent().path)[.posixPermissions] as? Int
    IntegrationsBackup.root = savedRoot
    check("backup: folder is 0700", mode == 0o700)

    for (event, verb) in [("PostToolUse", "hook-knock PostToolUse"),
                           ("Stop", "hook-agents Stop"), ("Notification", "hook-notify claude")] {
        let userCommand = "/opt/my-hook " + verb
        var fixture: [String: Any] = [:]
        fixture["hooks"] = [event: [["matcher": "user-matcher", "hooks": [
            ["type": "command", "command": "/usr/local/bin/usagebar " + verb],
            ["type": "command", "command": userCommand]
        ]]]]
        let updated: [String: Any]?
        let cli = "/Applications/UsageBar.app/Contents/Helpers/usagebar " + verb
        switch event {
        case "PostToolUse":
            updated = IntegrationsStore.settingsRegisteringKnockHook(fixture, event: event, command: cli)
        case "Stop":
            updated = IntegrationsStore.settingsRegisteringAgentHook(fixture, event: event, command: cli)
        default:
            updated = IntegrationsStore.settingsRegisteringNotificationHook(fixture, command: cli)
        }
        let result = commands(updated!, event: event)
        check("hooks: \(event) re-registers ours once and preserves the user hook", result == [userCommand, cli])
    }

    let prompt = IntegrationsStore.usageBarPromptCommand
    let formerPrompt: [String: Any] = ["hooks": ["UserPromptExpansion": [["matcher": "usagebar", "hooks": [
        ["type": "command", "command": #""/Applications/UsageBar.app/Contents/Helpers/usagebar" \#(LegacyIdentifierMigration.promptHookVerb) --backstop"#],
        ["type": "command", "command": "echo user"]
    ]]]]]
    let promptResult = IntegrationsStore.settingsRegisteringPromptHook(formerPrompt,
        hooks: IntegrationsStore.promptHookEntries(URL(fileURLWithPath: "/Applications/UsageBar.app/Contents/Helpers/usagebar"),
                                                   command: prompt, nativePicker: false), hook: prompt)!
    let promptCommands = commands(promptResult, event: "UserPromptExpansion")
    check("hooks: the former prompt subcommand is rewritten and the neighboring user hook retained",
          promptCommands.count == 2 && promptCommands.contains("echo user")
          && promptCommands.filter { $0.hasSuffix(" " + BrandPaths.promptHookVerb) }.count == 1
          && !promptCommands.contains { $0.contains(LegacyIdentifierMigration.promptHookVerb) })

    let state = tmp.appendingPathComponent("edit-state.json")
    let mcp: [String: Any] = ["mcpServers": [
        "usagebar": ["command": "/Applications/Old/usagebar", "args": ["mcp-serve"]],
        "user": ["command": "user-server"]], "user": true]
    try JSONSerialization.data(withJSONObject: mcp).write(to: state)
    _ = try IntegrationsStore.editClaudeState(state) {
        try IntegrationsStore.stateRegisteringMCPServer($0,
            entry: IntegrationsStore.mcpServerEntry(URL(fileURLWithPath: "/Applications/UsageBar.app/Contents/Helpers/usagebar")))
    }
    let registered = try JSONSerialization.jsonObject(with: Data(contentsOf: state)) as! [String: Any]
    let servers = registered["mcpServers"] as! [String: Any]
    check("mcp: our entry is updated in place and the user's server kept",
          (servers["usagebar"] as? [String: Any])?["command"] as? String == "/Applications/UsageBar.app/Contents/Helpers/usagebar"
          && servers["user"] != nil)
    let removed = IntegrationsStore.stateWithoutMCPServer(registered)!
    check("mcp: uninstall keeps the user server", (removed["mcpServers"] as? [String: Any])?.count == 1)

    let shell = tmp.appendingPathComponent("edit-zshenv")
    let outside = "claude() { \"$HOME/bin/claude\" \"$@\"; }\n"
    let shellBefore = outside + IntegrationsStore.blockBegin + "\nexport PATH=\"$HOME/old:$PATH\"\n"
        + IntegrationsStore.blockEnd + "\n"
    try shellBefore.write(to: shell, atomically: true, encoding: .utf8)
    try IntegrationsStore.upsertBlock(in: shell, body: "export PATH=\"$HOME/.usagebar/bin:$PATH\"")
    let adoptedShell = try String(contentsOf: shell, encoding: .utf8)
    check("shell: our block is replaced, the user's function unchanged",
          adoptedShell.hasPrefix(outside) && !adoptedShell.contains("$HOME/old")
          && adoptedShell.contains("$HOME/.usagebar/bin"))
    try IntegrationsStore.stripBlock(in: shell)
    check("shell: removal leaves the user's function", try String(contentsOf: shell, encoding: .utf8) == outside)

    let home = tmp.appendingPathComponent("edit-codex")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let codexFile = home.appendingPathComponent("hooks.json")
    let root = tmp.appendingPathComponent("edit-root")
    var events: [String: Any] = [:]
    for event in CodexSessionHooks.events {
        events[event] = [["matcher": "", "hooks": [
            ["type": "command", "command": "echo user"]
        ]]]
    }
    try JSONSerialization.data(withJSONObject: ["hooks": events]).write(to: codexFile)
    try CodexSessionHooks.install(homes: [home.path], root: root)
    var doc = try CodexSessionHooks.document(path: codexFile.path)
    check("codex: one UsageBar hook, and the user's kept in each event",
          CodexSessionHooks.events.allSatisfy { commands(doc, event: $0) == ["echo user", CodexSessionHooks.command] })
    try CodexSessionHooks.remove(root: root)
    doc = try CodexSessionHooks.document(path: codexFile.path)
    check("codex: removal preserves user hooks",
          CodexSessionHooks.events.allSatisfy { commands(doc, event: $0) == ["echo user"] })

    for target in [file, state, codexFile] {
        let invalid = Data("{broken".utf8)
        try invalid.write(to: target)
        var refused = false
        do {
            if target == file { _ = try IntegrationsStore.upsertStatusLine(in: target, command: ours) }
            else if target == state { _ = try IntegrationsStore.editClaudeState(target) { $0 } }
            else { try CodexSessionHooks.install(homes: [home.path], root: root) }
        } catch { refused = true }
        check("edit: malformed \(target.lastPathComponent) rejected without write",
              try refused && Data(contentsOf: target) == invalid)
    }

    // MARK: Names an earlier build left in UserDefaults

    let suiteName = "usagebar-legacy-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    defer { suite.removePersistentDomain(forName: suiteName) }
    let pairs = LegacyIdentifierMigration.defaultsKeys.sorted { $0.key < $1.key }
    for (old, _) in pairs { suite.set("old:" + old, forKey: old) }
    // One key already has a value under the new name: the user's newer choice wins.
    let (keptOld, keptNew) = pairs[0]
    suite.set("chosen", forKey: keptNew)
    let moved = LegacyIdentifierMigration.migrateDefaults(suite)
    check("defaults: every old key moves except the one already set", moved == pairs.count - 1)
    check("defaults: the new name holds the old value",
          pairs.dropFirst().allSatisfy { suite.string(forKey: $0.value) == "old:" + $0.key })
    check("defaults: a value already set under the new name is kept", suite.string(forKey: keptNew) == "chosen")
    check("defaults: no old key is left", pairs.allSatisfy { suite.object(forKey: $0.key) == nil } && suite.object(forKey: keptOld) == nil)
    suite.set("again", forKey: pairs[1].key)
    check("defaults: the migration runs once", LegacyIdentifierMigration.migrateDefaults(suite) == 0
          && suite.string(forKey: pairs[1].key) == "again")

    // MARK: Shims an earlier build wrote
    check("shim: the header of an earlier build still reads as ours",
          IntegrationsStore.shimIsOurs(LegacyIdentifierMigration.shimHeader + "7: route")
          && IntegrationsStore.shimIsOurs(IntegrationsStore.shimHeader + "8: route")
          && !IntegrationsStore.shimIsOurs("#!/bin/sh\necho mine"))
}
