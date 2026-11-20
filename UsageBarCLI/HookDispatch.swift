import Foundation

/// The internal hook subcommands, lifted out of main.swift's entry switch: they are one family,
/// they are never typed by a person, and the entry file is at its size cap.
/// Returns nil for a word that is not one of ours, which the caller reads as "not handled here".
func runHookSubcommand(_ word: String, _ rest: [String]) -> Int32? {
    switch word {
    case BrandPaths.promptHookVerb, LegacyIdentifierMigration.promptHookVerb:
        // internal: the `/usagebar` prompt hook (UsageBarHook.swift). The second word is the one an
        // earlier build registered in settings.json, answered until the app rewrites the entry.
        return runHookUsageBar(args: rest)
    // internal: the PATH shim's reserve check on a hand-exported home (LaunchDir.swift)
    case "launch-reserve":
        return runLaunchReserve(rest.first ?? "claude", arguments: Array(rest.dropFirst()))
    case "hook-notify":   // internal: Claude Code's Notification hook (UserNotice.swift)
        return runHookNotify(args: rest)
    // internal: Claude Code's three subagent-facing hooks, which take the event as their argument
    // because one subcommand answers all three (HookAgents.swift).
    case "hook-agents":
        return runHookAgents(args: rest)
    // internal: Claude Code's two context-carrying hooks, which take the event as their argument for
    // the reason the three above do - one subcommand answers both, and the answer has to name the event
    // it is answering (HookKnock.swift).
    case "hook-knock":
        return runHookKnock(args: rest)
    // RETIRED: the Artifact publishing guard. Older apps registered this on `PreToolUse` and the
    // app now takes it back out at launch (UsageBar/Stores/IntegrationsArtifactHook.swift,
    // `retireArtifactHook`). Until that pass has run on a machine, Claude Code still calls it on
    // every Artifact publish, and a word this binary does not answer prints usage and fails, which
    // Claude Code shows as a hook error. So it reads the payload it is handed and says nothing.
    // Deleted with that file (its header says when).
    case "hook-artifact":
        _ = FileHandle.standardInput.readDataToEndOfFile()
        return 0
    default:
        return nil
    }
}
