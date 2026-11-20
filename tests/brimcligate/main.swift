import Foundation

// The CLI allows account operations and refuses disabled integrations before dispatch.
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}

let reads: [[String]] = [
    [], ["status"], ["status", "--json"], ["status", "--history"], ["cost"], ["best-dir", "claude"],
    ["launch-dir", "codex"], ["statusline"], ["completion", "zsh"], ["help"], ["--help"], ["-h"],
    ["events", "--since", "0"], ["events", "--latest-seq"], ["events", "--follow"],
    ["events", "sink", "show"], ["project"], ["project", "show"], ["project", "list"],
    ["worktree"], ["worktree", "tree"], ["worktree", "root"], ["worktree", "list"],
    ["prespawn"], ["prespawn", "show"], ["inbox", "list"], ["inbox", "status"],
    ["harness", "inventory"], ["codex-session-status", "status"],
]
let writes: [[String]] = [
    ["add", "claude"], ["share", "claude", "--all"], ["claude"], ["codex"], ["start"], ["resume"],
    ["project", "set", "--model", "x"], ["project", "clear"], ["worktree", "remove", "w"],
    ["prespawn", "set", "true"], ["prespawn", "clear"], ["reload"], ["reload", "--self"],
    ["account", "x"], ["switch", "x"], ["account"], ["model", "opus"], ["model"],
    ["session", "send", "hi"], ["session", "clear"], ["session", "skip-update"],
    ["type", "hi"], ["send", "hi"], ["message", "x"], ["chrome", "x"],
    ["events", "--deliver-once"], ["events", "sink", "set", "u"], ["events", "sink", "clear"],
    ["inbox", "post"], ["inbox", "claim"], ["inbox", "ack"], ["inbox", "recover"], ["inbox", "hook"],
    ["codex-session-status", "install"], ["codex-session-status", "remove"],
    ["codex-session-hook"], ["codex-hook"], ["codex-update"], ["update"], ["reap"], ["redeem"],
    ["keychain-repair"], ["__resupervise"], ["mcp-serve"],
    ["hook-quota"], ["hook-notify"], ["hook-knock"], ["hook-switch"], ["hook-model"],
    ["hook-agents"], ["hook-artifact"], ["launch-reserve"], ["some-future-verb"],
]

let liveClosed: [[String]] = [
    ["codex-update"], ["update"], ["keychain-repair"], ["chrome", "x"],
]
let liveOpen = (reads + writes).filter { !liveClosed.contains($0) }
check("opened, every other verb runs",
      liveOpen.allSatisfy { brimCLIRefusal($0) == nil })
for args in liveClosed {
    check("opened, `usagebar \(args.joined(separator: " "))` stays refused",
          brimCLIRefusal(args)?.contains("disabled in UsageBar") == true)
}
check("CLI acting verbs are enabled", BrimFeatures.cliWrites)

// Before anything: the refusal precedes the hook dispatch and the verb switch, so `add` clears no
// marker and `share` merges nothing first.
let main = (try? String(contentsOfFile: "UsageBarCLI/main.swift", encoding: .utf8)) ?? ""
let gate = main.range(of: "if let refusal = brimCLIRefusal(arguments)")
let hooks = main.range(of: "runHookSubcommand(word")
let verbs = main.range(of: "switch arguments.first {")
check("main.swift refuses before the hooks and the verbs",
      gate != nil && hooks != nil && verbs != nil
          && gate!.upperBound < hooks!.lowerBound && gate!.upperBound < verbs!.lowerBound)
check("…with exit 2", main.contains("warn(refusal)\n    exit(2)"))

// The app's own Phase 1 launch gates, pinned by source (AppKit is not compiled here).
let delegate = (try? String(contentsOfFile: "UsageBar/App/AppDelegate.swift", encoding: .utf8)) ?? ""
check("UsageBar ships with closing older Dev copies off", !BrimFeatures.closesOlderDevInstances)
check("…and the closer returns before it looks for any copy",
      delegate.range(of: "guard BrimFeatures.closesOlderDevInstances else { return }").map { gate in
          (delegate.range(of: "runningApplications(withBundleIdentifier:")?.lowerBound
              ?? gate.lowerBound) > gate.upperBound
      } == true)
check("live probes warm the login shell PATH at launch",
      delegate.contains("if BrimFeatures.liveProbes { CLISearchPath.shared.warm() }"))

if failures > 0 { print("\(failures) FAILED"); exit(1) }
print("ALL PASS")
