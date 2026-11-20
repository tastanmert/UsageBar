import SwiftUI

/// Settings > Integrations > Anthropic Console: one row per Claude account. Each account has its
/// own Console sign-in (ConsoleCreditsFetch keeps a separate web store per account); this only
/// lists them by name, opens the sign-in for the account whose button was pressed and disconnects it.
struct SettingsConsoleRow: View {
    private let store = ConsoleCreditsStore.shared
    private let usage = UsageStore.shared

    private var accounts: [ProviderAccount] {
        usage.discoveredAccounts.filter { $0.providerID == ClaudeAccounts.providerID }
    }

    var body: some View {
        SettingsSection(L("Anthropic Console"), symbol: "creditcard") {
            ForEach(accounts) { account in
                SettingsRow(title: SettingsStore.shared.displayLabel(accountID: account.id, fallback: account.label),
                            subtitle: status(account.id), icon: "banknote",
                            info: account.id == accounts.first?.id
                                ? L("Signs in to platform.claude.com once per account inside UsageBar and reads that account's prepaid API balance, this month's spend and the tier limit on every refresh. The session stays in UsageBar's own web storage; Disconnect removes it.")
                                : nil) {
                    HStack(spacing: 10) {
                        switch store.state(for: account.id) {
                        case .notConnected:
                            Button(L("Connect")) { ConsoleSignInWindowController.shared.show(accountID: account.id) }
                        case .needsReconnect:
                            Button(L("Reconnect")) { ConsoleSignInWindowController.shared.show(accountID: account.id) }
                            Button(L("Disconnect")) { Task { await store.disconnect(accountID: account.id) } }
                        default:
                            Button(L("Disconnect")) { Task { await store.disconnect(accountID: account.id) } }
                        }
                    }
                }
            }
        }
    }

    private func status(_ id: String) -> String {
        let base: String
        switch store.state(for: id) {
        case .notConnected: return L("Not connected")
        case .needsReconnect: base = L("Console session expired")
        case .noPrepaid: base = L("Connected, no prepaid credits")
        case .unavailable: base = L("Connected, could not read credits")
        case .ready(_, _, let stale): base = stale ? L("Connected, could not refresh") : L("Connected")
        }
        return store.isDifferentAccount(id) ? base + " · " + L("Different Console account") : base
    }
}
