import Foundation

// `usagebar update` - the CLI face of the app's Sparkle updater. Split out of main.swift purely for
// file size; the behavior is unchanged.

/// `usagebar update`: ask the menu bar app to run a user-initiated Sparkle check (its window
/// follows the pointer's screen), launching the app first when it isn't running. Uses pgrep +
/// a distributed notification so the statusline hot path never has to link AppKit.
func runUpdate() {
    if !usageBarAppRunning() {
        _ = runQuiet("/usr/bin/open", ["-b", BrandPaths.appBundleID])
        Thread.sleep(forTimeInterval: 2)   // let the updater finish starting before we knock
    }
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("\(BrandPaths.reverseDNS).checkForUpdates"),
        object: nil, userInfo: nil, deliverImmediately: true)
    print("[usagebar] update check requested; UsageBar's update window will appear in a moment.")
}

/// Run a tool with its output discarded and return its exit status.
private func runQuiet(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus
}

/// Whether the installed menu bar app is running (`usagebar update`, `usagebar redeem`). An exact process
/// name match, so a "UsageBar Dev" build does not count.
func usageBarAppRunning() -> Bool {
    runQuiet("/usr/bin/pgrep", ["-xq", BrandPaths.displayName]) == 0
}
