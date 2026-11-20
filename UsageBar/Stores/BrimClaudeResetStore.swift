import Foundation
import Observation

/// Each Claude account's limit-reset inventory, read by UsageBar itself because UsageBar's snapshot
/// does not carry it (`resetState: notSupported`). The rules are BrimClaudeResetSchedule's and
/// ClaudeResetInventoryFetch's: a GET with the login's own unexpired token, at most every ten
/// minutes per account, backed off on 401/403/429, never a refresh or a write. A claim happens only
/// behind the card's confirmation, in live mode (BrimResetUseStore). Readings stay in memory.
@MainActor
@Observable
final class BrimClaudeResetStore {
    static let shared = BrimClaudeResetStore()

    private(set) var schedule = BrimClaudeResetSchedule()
    @ObservationIgnored private var timer: Timer?

    /// Claude Code's installed version for the User-Agent, resolved once, off the main thread.
    nonisolated static let claudeVersion =
        ClaudeResetInventoryFetch.version(executable: CLIRunner.resolve("claude"))

    /// The usage endpoint's 429 window as Claude Code reported it (1184 seconds, 2026-11-17).
    nonisolated static let rateLimitWindow: TimeInterval = 20 * 60

    private init() {}

    /// Starts the once-a-minute check; each account is still asked only when it is due.
    func start() {
        // BRIM-GATE: the Claude reset inventory read; off, nothing is read or sent.
        guard BrimFeatures.claudeResetInventoryRead, timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in BrimClaudeResetStore.shared.tick() }
        }
    }

    /// Asks every due Claude account in the snapshot on screen (UsageBar's, or UsageBar's own in live
    /// mode). The panel opening calls this too. `force` asks the accounts whose reading was just
    /// dropped (a claim, entering live mode); the cadence still holds for the rest.
    func tick(now: Date = Date(), force: Bool = false) {
        guard BrimFeatures.claudeResetInventoryRead,
              let snapshot = UsageStore.shared.publishedSnapshot else { return }
        let claude = snapshot.accounts.filter { $0.provider == "claude" }
        schedule.prune(keeping: Set(claude.map(\.id)))
        if force {
            // Readings without the login they belong to cannot back a claim: ask those again now.
            for account in claude where schedule.entries[account.id].map({
                $0.reading != nil && $0.identity == nil && !$0.inFlight && $0.notBefore == nil
            }) == true {
                schedule.invalidate(account.id)
            }
        }
        for account in claude {
            // One bearer, one endpoint: this read and the usage probe both ask `/api/oauth/usage`,
            // so an account the probe is holding off (a 429) is not asked here either.
            guard !ProbeCadence.UsageReadHold.shared.holds(account.id, now: now),
                  // Resets change rarely: nothing is lost by sitting out the cool-down too.
                  !ProbeCadence.UsageReadHold.shared.cooling(account.id, now: now),
                  let home = account.launchHome, schedule.begin(account.id, now: now) else { continue }
            let id = account.id
            let generation = schedule.generation(id)
            Task {
                // Whose login this asks under, read beside the token so the answer is filed to it.
                let (identity, outcome) = await Task.detached(priority: .utility) {
                    let identity = ClaudeResetClaim.identity(configHome: home)
                    return (identity, await ClaudeResetInventoryFetch.fetch(home: home, version: Self.claudeVersion))
                }.value
                // Another login in the home now: the old reading goes, this answer (taken under the
                // new login) stands. Otherwise an answer that left before a claim spent is dropped.
                let held = self.schedule.entries[id]?.identity
                let changedHands = held != nil && identity != nil && held != identity?.accountID
                if changedHands { self.schedule.note(id, identity: identity?.accountID) }
                // And a 429 here holds the usage probe off the same bearer for the server's window
                // (about 20 minutes, measured 2026-11-17): asking again inside it only extends it.
                if outcome == .failed(status: 429) {
                    ProbeCadence.UsageReadHold.shared.refused(id, now: Date(),
                                                              serverWait: Self.rateLimitWindow)
                }
                self.schedule.land(id, outcome, now: Date(), identity: identity?.accountID,
                                   organizationID: identity?.organizationID,
                                   generation: changedHands ? nil : generation)
                BrimResetUseStore.shared.readingLanded(id)
            }
        }
    }

    /// The home changed hands, or a claim spent from it: the reading goes and is asked again.
    func invalidate(_ id: String) {
        schedule.invalidate(id)
    }

    /// The panel's input: every Claude account in the snapshot, empty while the read is off.
    func panelInput(for snapshot: UsageSnapshot?) -> [String: BrimPanelModel.ClaudeResets] {
        guard BrimFeatures.claudeResetInventoryRead, let snapshot else { return [:] }
        var input: [String: BrimPanelModel.ClaudeResets] = [:]
        for account in snapshot.accounts where account.provider == "claude" {
            input[account.id] = schedule.panelInput(account.id)
        }
        return input
    }
}
