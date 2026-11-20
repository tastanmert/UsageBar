import Foundation
import Observation

/// Spending a reset from the panel or the status menu; Codex requires live mode. One confirm card open at a
/// time (`prompt`), one spend at a time per account, and the outcome on the card's reset line
/// (`uses`) until it is old news.
///
/// Claude goes through BrimClaudeClaimRunner (the consent bound when the card opened), Codex
/// through the identity-bound consume (BrimCodexApproval, `RedeemAction.redeem(usage:approval:)`,
/// then the follow-through refresh); the old unbound `consumeSoonestResetCredit` path is
/// not used here. Nothing here runs without the card's "Use reset"; Cancel is the default there.
@MainActor
@Observable
final class BrimResetUseStore {
    static let shared = BrimResetUseStore()

    /// The open confirm card.
    struct Prompt: Equatable {
        var accountID: String
        var kind: BrimPanelModel.ResetKind
        /// Claude's consent, taken when the card opened; nil for Codex.
        var approval: BrimClaudeClaimRunner.Approval?
        /// Codex's consent (identity and credit), taken when the card opened; nil for Claude.
        var codex: BrimCodexApproval? = nil
    }

    private(set) var prompt: Prompt?
    private(set) var uses: [String: BrimPanelModel.ResetUse] = [:]

    @ObservationIgnored private let claude = BrimClaudeClaimRunner()
    /// Claude claims whose answer was unclear, waiting for the reading after them.
    @ObservationIgnored private var uncertain: [String: BrimClaudeClaimRunner.Approval] = [:]
    /// How long an outcome stays on the card.
    static let outcomeShown: TimeInterval = 90

    private init() {}

    /// Opens the confirm card for `kind` on this account. Claude binds the consent here, to the
    /// reading on screen; a reading that cannot back one opens nothing and asks again.
    func open(accountID: String, kind: BrimPanelModel.ResetKind, grantID: String? = nil) {
        guard !isBusy(accountID) else { return }
        if BrimClaudeResetStore.shared.schedule.entries[accountID]?.problem == .loginExpiring {
            show(.refused(.loginExpiring), on: accountID)
            return
        }
        guard let account = UsageStore.shared.discoveredAccounts.first(where: { $0.id == accountID }) else { return }
        var approval: BrimClaudeClaimRunner.Approval?
        if account.providerID == "claude" {
            guard let home = account.launchableHome, let claudeKind = Self.claudeKind(kind),
                  let bound = BrimClaudeClaimRunner.approval(
                    accountID: accountID, home: home, kind: claudeKind,
                    entry: BrimClaudeResetStore.shared.schedule.entries[accountID], now: Date(), grantID: grantID)
            else {
                show(.refused(.changed), on: accountID)
                BrimClaudeResetStore.shared.tick(force: true)
                return
            }
            approval = bound
        }
        var codex: BrimCodexApproval?
        if kind == .codex {
            // Bound to who the home is signed in as at the reading on screen, and to one credit.
            guard let home = account.launchableHome,
                  let usage = UsageStore.shared.accounts.first(where: { $0.id == accountID }) else {
                show(.refused(.changed), on: accountID)
                return
            }
            guard let identity = CodexIdentityBook.shared.identity(home: home) else {
                show(.refused(.accountUnverified), on: accountID)
                return
            }
            guard let bound = BrimCodexApproval.make(accountID: accountID, home: home, identity: identity,
                                                     credits: usage.resetCredits) else {
                show(.refused(.noCredit), on: accountID)
                return
            }
            codex = bound
        }
        prompt = Prompt(accountID: accountID, kind: kind, approval: approval, codex: codex)
    }

    func cancel() { prompt = nil }

    /// Picks another kind on the open card (Claude's full and Fable resets are separate).
    func choose(_ kind: BrimPanelModel.ResetKind) {
        guard let current = prompt, current.kind != kind else { return }
        prompt = nil
        open(accountID: current.accountID, kind: kind)
    }

    /// The card's "Use reset". Spends the prompt's reset and reports on the card.
    func confirm() {
        guard let prompt, !isBusy(prompt.accountID),
              prompt.approval != nil ? BrimFeatures.claudeResetClaim : BrimFeatures.panelResetUse else { return }
        self.prompt = nil
        let id = prompt.accountID
        uses[id] = .working
        Task {
            if let approval = prompt.approval {
                await spendClaude(approval)
            } else if let codex = prompt.codex {
                await spendCodex(codex)
            } else {
                show(.refused(.changed), on: id)
            }
        }
    }

    func isBusy(_ accountID: String) -> Bool {
        if uses.values.contains(where: { if case .working = $0 { return true }; if case .checking = $0 { return true }; return false }) { return true }
        return switch uses[accountID] {
        case .working, .checking: true
        default: claude.isBusy || uncertain[accountID] != nil
        }
    }

    /// A Claude reading landed for this account: an unclear claim before it is now settled.
    func readingLanded(_ accountID: String) {
        guard let approval = uncertain[accountID],
              let settled = BrimClaudeClaimRunner.afterUncertain(
                approval, entry: BrimClaudeResetStore.shared.schedule.entries[accountID]) else { return }
        uncertain[accountID] = nil
        show(settled, on: accountID)

    }

    // MARK: Spending

    private func spendClaude(_ approval: BrimClaudeClaimRunner.Approval) async {
        let id = approval.accountID, home = approval.home
        let env = BrimClaudeClaimRunner.Environment(
            currentEntry: { BrimClaudeResetStore.shared.schedule.entries[id] },
            stillListed: { UsageStore.shared.discoveredAccounts.contains { $0.id == id && $0.launchableHome == home } },
            readContext: {
                await Task.detached(priority: .utility) {
                    ClaudeResetClaim.readContext(
                        home: home,
                        defaultHome: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path,
                        now: Date(), identityRead: ClaudeResetClaim.identity,
                        keychainRead: { ClaudeLoginExpiryKeychain.readForResetInventory(service: $0) },
                        fileRead: { try? Data(contentsOf: $0) })
                }.value
            },
            version: BrimClaudeResetStore.claudeVersion,
            transport: ClaudeResetClaim.liveTransport,
            identityNow: {
                await Task.detached(priority: .utility) { ClaudeResetClaim.identity(configHome: home) }.value
            })
        let outcome = await claude.claim(approval, confirmed: true, env: env)
        let status = BrimClaudeClaimRunner.status(outcome)
        uses[id] = status
        switch status {
        case .checking(spent: true):
            // Spent: the reading goes, both are measured again, then the card says what it gave.
            uncertain[id] = approval
            BrimClaudeResetStore.shared.invalidate(id)
            BrimClaudeResetStore.shared.tick(force: true)

        case .checking(spent: nil):
            // Unclear: read again before anything is said or tried again (same request id then).
            uncertain[id] = approval
            BrimClaudeResetStore.shared.invalidate(id)
            BrimClaudeResetStore.shared.tick(force: true)
        default:
            BrimClaudeResetStore.shared.tick(force: true)
            show(status, on: id)
        }
    }

    private func spendCodex(_ approval: BrimCodexApproval) async {
        let id = approval.accountID
        // Still the same account, signed in as the same identity, as when the card opened; the
        // consume reads the identity again itself right before the write.
        guard BrimFeatures.panelResetUse,
              let usage = UsageStore.shared.accounts.first(where: { $0.id == id }),
              UsageStore.shared.discoveredAccounts.contains(where: {
                  $0.id == id && $0.launchableHome == approval.identity.home }) else {
            show(.refused(.changed), on: id)
            return
        }
        guard approval.stillBound(to: CodexIdentityBook.shared.identity(home: approval.identity.home)) else {
            show(.refused(.accountChanged), on: id)
            return
        }
        // An earlier attempt whose answer was lost is settled first (same credit, same key).
        let open = CodexConsumeCoordinator.shared.pending(home: approval.identity.home)
        let settlesEarlier = open.map {
            !$0.settled && $0.identity == approval.identity && $0.creditID != approval.credit.id
        } ?? false
        guard let outcome = await RedeemAction.redeem(usage: usage, approval: approval) else {
            // Another redeem for this account is on the wire, or one just spent a credit here.
            show(.refused(.changed), on: id)
            return
        }
        let status = BrimCodexApproval.status(outcome, settlesEarlier: settlesEarlier)
        switch status {
        case .checking(spent: true):
            uses[id] = status
            await RedeemAction.followThrough(outcome: .redeemed, usage: usage)
            await UsageStore.shared.refresh(userInitiated: true)
            show(.used, on: id)
        case .checking(spent: nil):
            // Unclear: read again; the attempt stays open and the next confirm settles it first.
            uses[id] = status
            await UsageStore.shared.refresh(userInitiated: true)
            show(status, on: id)
        default:
            show(status, on: id)
            await UsageStore.shared.refresh(userInitiated: true)
        }
    }

    /// An outcome on the card, cleared after `outcomeShown` unless something newer replaced it.
    private func show(_ use: BrimPanelModel.ResetUse, on id: String) {
        uses[id] = use
        Task {
            try? await Task.sleep(for: .seconds(Self.outcomeShown))
            if uses[id] == use { uses[id] = nil }
        }
    }

    static func claudeKind(_ kind: BrimPanelModel.ResetKind) -> ClaudeResetInventory.Kind? {
        switch kind {
        case .full: .full
        case .fable: .fable
        case .session: .session
        case .weekly: .weekly
        case .codex, .other: nil
        }
    }
}
