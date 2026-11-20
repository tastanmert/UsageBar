import Foundation

func runHarnessTools(args: [String], integrationInstall: Bool = BrimFeatures.integrationInstall) -> Int32 {
    do {
        let options: Set<String> = ["--source-home", "--target-home", "--skills-root", "--state-root"]
        let parsed = try HarnessArguments(args, options: options)
        // BRIM-GATE: installation and removal modify provider files.
        guard integrationInstall || parsed.verb == "status" else { return 1 }
        var configuration = try HarnessToolsConfiguration(
            claudeHomes: [parsed.path("--source-home", fallback: HarnessArguments.home("claude"))],
            codexHomes: [parsed.path("--target-home", fallback: HarnessArguments.home("codex"))],
            skillsRoot: parsed.path("--skills-root", fallback: FileManager.default.homeDirectoryForCurrentUser.path + "/.agents/skills"),
            stateRoot: parsed.path("--state-root", fallback: HarnessArguments.stateRoot))
        let recordedConfiguration = Set(parsed.values.keys).isSubset(of: ["--state-root"])
        if ["status", "remove"].contains(parsed.verb), recordedConfiguration,
           let receipt = try HarnessTools.receipt(in: configuration.stateRoot) {
            configuration = receipt.configuration
        }
        switch parsed.verb {
        case "install":
            try HarnessTools.install(configuration, executable: HarnessIO.canonical(CommandLine.arguments[0]))
        case "remove":
            try HarnessTools.remove(configuration.stateRoot, expected: recordedConfiguration ? nil : configuration)
        case "status": break
        default: throw HarnessError("Use \(BrandPaths.cliName) harness tools install, remove, or status.")
        }
        try harnessPrint(HarnessTools.status(configuration))
        return 0
    } catch { return harnessError(error) }
}
