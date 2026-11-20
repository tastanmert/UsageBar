import Foundation

// `/usagebar` - the one slash command UsageBar installs. Installed, updated and removed by the machinery
// in IntegrationsPromptCommand.swift; what is here is the command's own text, and the list that
// machinery walks.
//
// The panel behind it holds both axes, account and model, side by side. An entry written by an
// earlier build runs a former subcommand (`PromptCommand.formerHookMarkers`) and is recognised as
// ours by it, so one sync rewrites it to the current one.
//
// The command file is the FALLBACK for a machine where the hook is not registered or shell execution
// is turned off by policy, and it is also the ONLY half a user can read - so it says what the hook
// does rather than assuming the hook is there.
extension IntegrationsStore {
    /// Every slash command UsageBar manages. One now, and still a list: the sync, the uninstall and the
    /// "is this install current" check all walk it, which is what stopped a command being added to
    /// one of them and forgotten by the others.
    nonisolated static var promptCommands: [PromptCommand] { [usageBarPromptCommand] }

    /// `/usagebar`: pick an account or a model for this conversation, or name one and skip the panel.
    nonisolated static var usageBarPromptCommand: PromptCommand {
        PromptCommand(name: BrandPaths.cliName, hookMarker: BrandPaths.promptHookVerb, mcpTool: .pick,
                      markdown: """
        ---
        description: Move this Claude Code session to another account, or run it on another model
        argument-hint: [account name] | [model] [effort]
        allowed-tools: Bash(usagebar:*)
        ---

        <!-- \(promptCommandMarker), managed by UsageBar.app (Settings -> Integrations); safe to delete -->

        # Move this session, or change what answers it

        If you are reading this, UsageBar's hook did not answer, and that is the whole of what happened here.
        `/usagebar` is normally answered before any model is woken: a prompt hook queues the move or
        the model when one is named, and offers the accounts and the models on one panel when
        neither is. Neither spends a turn, which is the point, because the usual reason to reach for
        this command is that the account or the model this session is on has nothing left to answer
        with.

        So this turn is the cost the command exists to avoid: answer briefly and end it.

        ## If `$ARGUMENTS` names anything

        A model, with or without a depth (`opus`, `opus high`):

        ```
        \(BrandPaths.cliName) model $ARGUMENTS
        ```

        Anything else is an account name, and it may contain spaces, so it is quoted as one word:

        ```
        \(BrandPaths.cliName) account "$ARGUMENTS"
        ```

        Run one of them once and stop, then relay what it printed. The change
        happens when this turn ENDS, the conversation survives it, and naming only a model leaves
        the depth exactly as it is. A non-zero exit means nothing was queued and the message says
        why.

        `auto` on its own is the one line to hand back rather than run: it releases a pin, and this
        command sets two. Say which axis was meant, in one line:

        > `auto` releases a pin and `/usagebar` sets two of them. Run `\(BrandPaths.cliName) model auto` to hand the
        > model back, or `\(BrandPaths.cliName) account --auto` to hand the account back.

        ## If nothing is named

        Do not run anything and do not open a picker: with no hook to draw one, reading the fleet
        and the models here would spend a second turn on what should have cost none. Say this, in
        one line:

        > UsageBar's picker did not answer this prompt (it is not connected, or the panel was left open
        > past its deadline). Try `/usagebar` again, run `\(BrandPaths.cliName) account "<account>"` or
        > `\(BrandPaths.cliName) model <model> [effort]` from a terminal, or
        > restart the session if it keeps happening.

        For "this project should ALWAYS run there", the instruction is different and is written down
        instead: `usagebar project set --account "<account>"`, or
        `usagebar project set --model <model> [--effort <effort>]`.
        """, commandManifest: "claudeUsageBarCommand", hookManifest: "claudeUsageBarHook",
                      formerHookMarkers: [LegacyIdentifierMigration.promptHookVerb])
    }
}
