import AppKit
import SwiftUI

/// The UsageBar settings window's root: toolbar tabs over one pane, the window title naming the tab.
/// The Settings window's content in SettingsWindowController (the old panes stay in the
/// tree, unreached). Sizing follows the old window's contract: every pane is measured while
/// collapsed, so a tab switch hands the window its new height in the same turn as the click.
struct BrimSettingsView: View {
    let store: UsageStore
    @Bindable var settings: SettingsStore
    @Bindable var prefs: BrimSettingsPrefs
    var onContentHeight: (CGFloat) -> Void = { _ in }
    var onPaneSwitch: (_ height: CGFloat, _ title: String) -> Void = { _, _ in }

    @State private var tab: BrimSettingsTab = SettingsCaptureLaunch.openingTab ?? .general
    @State private var paneHeights: [BrimSettingsTab: CGFloat] = [:]
    @State private var folders: [URL] = []
    @State private var integrations: BrimIntegrationsReport?
    /// Settings > Accounts' "Add account…" sheet .
    @State private var addingAccount = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Countdowns in the preview move between snapshot reads.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let data = makeData(now: context.date)
            VStack(spacing: 0) {
                BrimSettingsTabBar(selection: $tab) { select($0) }
                ZStack(alignment: .top) {
                    ForEach(BrimSettingsTab.allCases) { item in
                        BrimSettingsPane(tab: item, data: data, bindings: bindings, actions: actions)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(heightProbe { paneHeights[item] = $0 })
                            .opacity(tab == item ? 1 : 0)
                            .allowsHitTesting(tab == item)
                            .accessibilityHidden(tab != item)
                            .frame(height: tab == item ? nil : 0, alignment: .top)
                            .clipped()
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: BrimSettingsMetrics.windowWidth)
        // The tab bar's colour runs up behind the transparent titlebar, the page's below it.
        .background {
            VStack(spacing: 0) {
                BrimTheme.of(scheme).surface2.frame(height: BrimSettingsMetrics.tabBarHeight)
                BrimTheme.of(scheme).ground
            }
            .ignoresSafeArea()
        }
        // A language switch rebuilds the tree so every label re-localizes (see SettingsView).
        .id(settings.languageOverride ?? "system")
        .task { await rescan() }
        .sheet(isPresented: $addingAccount) {
            SettingsAddAccountView(
                flow: AddAccountStore.shared,
                fallbackCommand: { id in
                    SettingsAccountsView.addAccountCommand(
                        id, homes: store.discoveredAccounts.filter { $0.providerID == id }.compactMap(\.launchHome))
                },
                fallbackNote: { CLIPathAdvice.fallbackNote($0, usageBarInstalled: false) },
                dismiss: { addingAccount = false })
        }
    }

    private var bindings: BrimSettingsBindings {
        BrimSettingsBindings(
            menuBarText: $prefs.menuBarText,
            appearance: $prefs.appearance,
            panelLayout: $prefs.panelLayout,
            language: Binding(get: { settings.languageOverride ?? "" },
                              set: { settings.languageOverride = $0.isEmpty ? nil : $0 }),
            displayMode: $prefs.displayMode, menuSelection: $prefs.menuSelection,
            refreshIntervalMinutes: $settings.refreshIntervalMinutes)
    }

    private var actions: BrimSettingsActions {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return BrimSettingsActions(
            revealFolder: { folder in
                let path = folder.hasPrefix("~/") ? home.appendingPathComponent(String(folder.dropFirst(2))).path : folder
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            },
            rescan: { Task { await rescan() } },
            refresh: BrimPanelHost.refreshNow,
            addAccount: {
                store.ensureDiscovered()
                AddAccountStore.shared.beginEntry(providerID: AddAccountStore.shared.providerID)
                addingAccount = true
            },
            rename: { Self.rename($0, store: store) },
            signIn: { RenewLoginStore.shared.renew(accountID: $0) },
            setMonitored: { id, on in
                settings.setAccountEnabled(id, on)
                Task { await store.refresh(userInitiated: true) }
            },
            remove: { Self.remove($0, store: store) },
            clearCodexAttempt: { Self.clearCodexAttempt($0, store: store) },
            connectClaudeWeb: { id in
                guard let account = store.discoveredAccounts.first(where: { $0.id == id }) else { return }
                ConsoleSignInWindowController.claudeWeb.show(accountID: id) {
                    Task { await SubscriptionStore.shared.didConnectClaude(account: account) }
                }
            })
    }

    /// Forgets UsageBar's record of an open Codex reset attempt left by an earlier login, after a
    /// confirmation. Sends nothing to the provider.
    @MainActor
    static func clearCodexAttempt(_ id: String, store: UsageStore) {
        guard let account = store.discoveredAccounts.first(where: { $0.id == id }),
              let home = account.launchableHome else { return }
        let coordinator = CodexConsumeCoordinator.shared
        guard coordinator.strandedAttempt(home: home, current: CodexIdentityBook.shared.identity(home: home)) != nil
        else { return }
        let label = SettingsStore.shared.displayLabel(accountID: id, fallback: account.label)
        guard CentredAlert.confirmWithCancelDefault(
            title: "\(label) · \(L("Clear pending Codex reset attempt"))",
            body: L("An earlier login left a reset attempt whose answer never came. UsageBar forgets its own record of it; nothing is sent to Codex. If that reset went through, it stays spent."),
            confirmTitle: L("Clear")) else { return }
        // Re-checked after the dialog: the attempt may have settled or the login changed back.
        guard coordinator.clearStranded(home: home, current: CodexIdentityBook.shared.identity(home: home)) else { return }
        CodexAutoRedeemStore.shared.forgetUncertain(accountID: id)
    }

    /// The account's name in UsageBar only (its defaults), never in a provider file.
    @MainActor
    static func rename(_ id: String, store: UsageStore) {
        let settings = SettingsStore.shared
        let fallback = store.discoveredAccounts.first { $0.id == id }?.label ?? id
        let alert = NSAlert()
        alert.messageText = L("Rename")
        alert.informativeText = L("Shown in UsageBar only. Leave empty for the provider's name.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = settings.accountLabels[id] ?? ""
        field.placeholderString = fallback
        alert.accessoryView = field
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard CentredAlert.run(alert) == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { settings.accountLabels[id] = nil } else { settings.accountLabels[id] = name }
        store.republishSnapshot()
        Task { await store.refresh(userInitiated: true) }
    }

    /// The confirmed removal: the profile folder goes to the Trash.
    @MainActor
    static func remove(_ id: String, store: UsageStore) {
        guard let account = store.discoveredAccounts.first(where: { $0.id == id }),
              let home = account.launchHome else { return }
        let label = SettingsStore.shared.displayLabel(accountID: id, fallback: account.label)
        guard accountHomeIsRemovable(providerID: account.providerID, home: home, fresh: true) else {
            CentredAlert.notice(title: "\(label) · \(L("Remove account"))",
                                body: L("The main profile folder can't be removed."))
            return
        }
        RemoveAccountAction.present(accountID: id, providerID: account.providerID, label: label, home: home)
    }

    @MainActor
    private func makeData(now: Date) -> BrimSettingsData {
        let panel = BrimPanelHost.model(store: store, now: now)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let snapshot = store.publishedSnapshot
        let format = BrimPanelHost.format
        // Every discovered account is listed, the switched-off ones too (Monitor).
        let discovered = store.discoveredAccounts.map {
            BrimAccountsTable.Discovered(id: $0.id, provider: $0.providerID,
                                         label: settings.displayLabel(accountID: $0.id, fallback: $0.label),
                                         home: $0.launchHome)
        }
        let strandedCodexAttempts = Set(store.discoveredAccounts.compactMap { account -> String? in
            guard account.providerID == "codex", let home = account.launchableHome,
                  CodexConsumeCoordinator.shared.strandedAttempt(
                      home: home, current: CodexIdentityBook.shared.identity(home: home)) != nil else { return nil }
            return account.id
        })
        var accounts = BrimAccountsTable.make(snapshot: snapshot, folders: folders, home: home, probe: .live,
                                              discovered: discovered, strandedCodexAttempts: strandedCodexAttempts)
        // The same chain the panel's hover asks (probe, this round's poll, then memory), so a
        // switched-off account keeps its address here too.
        let polled = Dictionary(store.accounts.map { ($0.id, $0.accountEmail) }, uniquingKeysWith: { a, _ in a })
        accounts.fillEmails { id in
            LoginStatusStore.shared.identityEmail(accountID: id, polled: polled[id] ?? nil)
        }
        let subscriptions = SubscriptionStore.shared
        let claudeIDs = Set(store.discoveredAccounts.filter { $0.providerID == ClaudeAccounts.providerID }.map(\.id))
        accounts.fillRenewals { id in
            if let renewal = subscriptions.renewals[id] { return .known(renewal) }
            guard claudeIDs.contains(id) else { return nil }
            if !subscriptions.isConnectedToClaudeWeb(id) { return .connect }
            switch subscriptions.statuses[id] {
            case .differentAccount: return .differentAccount
            case .notConnected: return .connect
            default: return nil
            }
        }
        return BrimSettingsData(
            panel: panel, snapshot: snapshot, now: now, format: format,
            accounts: accounts,
            integrations: integrations,
            version: Self.version)
    }

    /// Lists the profile folders and checks the integrations off the main thread. Names and reads
    /// only; nothing is written.
    @MainActor
    private func rescan() async {
        let result = await Task.detached(priority: .utility) { () -> ([URL], BrimIntegrationsReport) in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let folders = accountWatchRoots(home: home)
            let claude = folders.filter { !$0.lastPathComponent.hasPrefix(".codex") }
            let codex = folders.filter { $0.lastPathComponent.hasPrefix(".codex") }
            return (folders, BrimIntegrationsReport.detect(home: home, claudeHomes: claude, codexHomes: codex,
                                                           probe: .live))
        }.value
        folders = result.0
        integrations = result.1
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    private func heightProbe(_ take: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                take(height)
                if let reported = reportedHeight(for: tab) { onContentHeight(reported) }
            }
        }
    }

    private func reportedHeight(for item: BrimSettingsTab) -> CGFloat? {
        paneHeights[item].map { $0 + BrimSettingsMetrics.tabBarHeight }
    }

    private func select(_ item: BrimSettingsTab) {
        onPaneSwitch(reportedHeight(for: item) ?? 0, item.title)
    }
}
