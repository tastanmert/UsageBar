import Foundation

// BRIM-GATE: `usagebar` runs every verb except the three that repair the Keychain,
// update the Codex binary or run the Chrome step (`brimCLIClosed`). The integration verbs (`codex-session-status
// install`, `harness install`) and the hooks the integrations register (`hook-*`, `codex-session-hook`,
// `mcp-serve`) run: the user installs them from Settings or the CLI (BrimFeatures.integrationInstall).

/// Closed: the Keychain repair, binary updates and the Chrome step.
func brimCLIClosed(_ arguments: [String]) -> Bool {
    switch arguments.first {
    case "keychain-repair", "codex-update", "chrome":
        return true
    default:
        return false
    }
}

/// The refusal `usagebar` prints and exits 2 with, or nil when the command may run.
func brimCLIRefusal(_ arguments: [String]) -> String? {
    guard brimCLIClosed(arguments) else { return nil }
    let command = arguments.prefix(2).joined(separator: " ")
    return """
    \(BrandPaths.cliName) \(command): disabled in \(BrandPaths.displayName). Repairing the Keychain, \
    updating binaries and the Chrome step are off.
    """
}
