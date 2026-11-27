import Foundation
import IOKit.pwr_mgt

/// Holds off idle system sleep while a supervised session is working, when Settings asks for it.
/// The display may still sleep; a closed lid or the user's own Sleep still sleeps. The assertion is
/// named, so `pmset -g assertions` says who holds it.
@MainActor
final class KeepAwake {
    static let shared = KeepAwake()

    private var assertion: IOPMAssertionID = 0
    private var held = false
    /// While held, the board is re-read every minute: a session that died without telling the
    /// board must not keep the Mac awake until somebody opens the panel.
    private var recheck: Timer?

    private init() {}

    /// Called when the setting or the session board changes.
    func reevaluate() {
        let working = SessionRosterStore.shared.rows.contains { $0.state == .working }
        set(AlertPrefs.shared.keepAwake && working)
    }

    var isHolding: Bool { held }

    private func set(_ hold: Bool) {
        guard hold != held else { return }
        if hold {
            var id: IOPMAssertionID = 0
            let reason = "UsageBar: a Claude Code or Codex session is working" as CFString
            guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id)
                    == kIOReturnSuccess else { return }
            assertion = id
            held = true
            let timer = Timer(timeInterval: 60, repeats: true) { _ in
                Task { @MainActor in
                    SessionRosterStore.shared.refresh()
                    KeepAwake.shared.reevaluate()
                }
            }
            timer.tolerance = 10
            RunLoop.main.add(timer, forMode: .common)
            recheck = timer
        } else {
            IOPMAssertionRelease(assertion)
            assertion = 0
            held = false
            recheck?.invalidate()
            recheck = nil
        }
    }
}
