import Foundation

/// `usagebar start [args...]`: launch whichever provider this directory declares
/// (`usagebar project set ... --default`), Claude when none is declared or the declared one is missing.
func runStart(args: [String]) -> Never {
    let declared = projectDefaultProvider()
    let id = startProviderID(declared: declared, installed: providerInstalled)
    if let declared, declared != id {
        warn("\(declared) is this project's default but is not installed; starting \(id)")
    }
    runLaunch(providers.first { $0.id == id }!, args: args)
}
