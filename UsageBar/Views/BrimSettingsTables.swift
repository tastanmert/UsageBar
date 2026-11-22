import SwiftUI

// MARK: - Accounts

/// The account list as the snapshot names it, plus profile folders found on disk. Add, rename,
/// sign in again, monitor and remove run their own flows, each started by the user.
struct BrimAccountsPane: View {
    @AppStorage("brimDisplayMode") private var creditDisplayMode = "remaining"
    let data: BrimSettingsData
    var actions = BrimSettingsActions()
    @Environment(\.colorScheme) private var scheme

    /// Name | Plan | Account (address over profile folder) | Login | Resets | Monitor | actions.
    private enum Column {
        static let name: CGFloat = 120
        static let plan: CGFloat = 80
        static let credit: CGFloat = 120
        static let login: CGFloat = 106
        static let resets: CGFloat = 116
        static let monitor: CGFloat = 64
        static let actions: CGFloat = 32
    }

    var body: some View {
        let theme = BrimTheme.of(scheme)
        let table = data.accounts
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: L("%d accounts"), table.count))
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
                    Text(L("Read by UsageBar. Order follows the panel."))
                        .font(.system(size: 12)).foregroundStyle(theme.text2)
                }
                Spacer(minLength: 12)
                Button(L("Scan for profiles"), action: actions.rescan)
                    .buttonStyle(BrimSettingsButtonStyle())
                // BRIM-GATE: adding an account writes into a profile folder (BrimFeatures.providerHomeMutation);
                // only from this button.
                Button(L("Add account…")) { actions.addAccount?() }
                    .buttonStyle(BrimSettingsButtonStyle(prominent: true))
                    .disabled(actions.addAccount == nil)
            }
            ForEach(table.untracked, id: \.self) { folder in
                HStack(spacing: 4) {
                    Text(verbatim: folder).font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.text)
                    Text(L("was found but is not monitored.")).font(.system(size: 12)).foregroundStyle(theme.text2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.hairline))
            }
            BrimSettingsCard {
                header(theme)
                if table.groups.isEmpty {
                    BrimSettingsDivider()
                    Text(emptyText).font(.system(size: 12)).foregroundStyle(theme.text2)
                        .padding(.horizontal, 12).padding(.vertical, 14)
                }
                ForEach(table.groups) { group in
                    BrimSettingsDivider()
                    Text(verbatim: BrimProviderName.of(group.id))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.text2)
                        .padding(.horizontal, 12).frame(height: 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface2)
                    ForEach(group.rows) { row in
                        BrimSettingsDivider()
                        accountRow(row, theme)
                    }
                }
            }
            Text(L("UsageBar signs in, renames or removes an account only when you ask. Removing moves the profile folder to the Trash."))
                .font(.system(size: 12)).foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
        }
        .brimSettingsPage()
    }

    private var emptyText: String {
        data.panel.banner == .unavailable ? L("Usage data unavailable.") : L("No accounts yet.")
    }

    private func header(_ theme: BrimTheme) -> some View {
        HStack(spacing: 12) {
            BrimColumnHeader(text: L("Name")).frame(width: Column.name, alignment: .leading)
            BrimColumnHeader(text: L("Plan")).frame(width: Column.plan, alignment: .leading)
            BrimColumnHeader(text: L("Account")).frame(maxWidth: .infinity, alignment: .leading)
            BrimColumnHeader(text: L("Login")).frame(width: Column.login, alignment: .leading)
            BrimColumnHeader(text: L("Reset credits")).frame(width: Column.resets, alignment: .leading)
            BrimColumnHeader(text: L("Credit")).frame(width: Column.credit, alignment: .center)
            BrimColumnHeader(text: L("Monitor")).frame(width: Column.monitor, alignment: .center)
            Color.clear.frame(width: Column.actions)
        }
        .padding(.horizontal, 12).frame(height: 32)
    }

    private func accountRow(_ row: BrimAccountsTable.Row, _ theme: BrimTheme) -> some View {
        let panelRow = data.panel.groups.flatMap(\.rows).first { $0.id == row.id }
        let credit = panelRow?.credit
        return HStack(spacing: 12) {
            HStack(spacing: 6) {
                BrimProviderMark(provider: row.provider)
                Text(verbatim: row.name).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                    .lineLimit(1).truncationMode(.middle)
            }.frame(width: Column.name, alignment: .leading)
            Text(verbatim: row.plan ?? "—").font(.system(size: 13)).foregroundStyle(theme.text2)
                .lineLimit(1).frame(width: Column.plan, alignment: .leading)
            // The address first (which login this is), the profile folder under it; the folder
            // alone when the account has not named itself yet.
            VStack(alignment: .leading, spacing: 1) {
                if let email = row.email {
                    Text(verbatim: email).font(.system(size: 12)).foregroundStyle(theme.text)
                        .lineLimit(1).truncationMode(.middle)
                }
                Text(verbatim: row.folder)
                    .font(.system(size: row.email == nil ? 12 : 10.5, design: .monospaced))
                    .foregroundStyle(theme.text2)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help([row.email, row.folder].compactMap { $0 }.joined(separator: "\n"))
            VStack(alignment: .leading, spacing: 2) {
                if let panelRow, panelRow.needsSignIn {
                    // The verdict LoginStatusStore holds, not a guess from the error's wording
                    // (which is translated, so the keyword match in `login(_:)` misses it).
                    login(.needsSignIn)
                    Button(panelRow.signingIn ? L("Signing in…") : L("Sign in again")) { actions.signIn?(row.id) }
                        .controlSize(.mini)
                        .disabled(actions.signIn == nil || panelRow.signingIn)
                } else if let panelRow, panelRow.refreshFailed {
                    Text(L("Could not refresh")).font(.system(size: 11)).foregroundStyle(theme.text2)
                    if let reading = panelRow.refreshReading {
                        Text(reading).font(.system(size: 10)).foregroundStyle(theme.text2)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                } else { login(row.login) }
            }.frame(width: Column.login, alignment: .leading)
                .help(panelRow?.refreshFailed == true
                      ? [panelRow?.refreshReading.map { String(format: L("Could not refresh · %@ data"), $0) }, panelRow?.refreshProblem].compactMap { $0 }.joined(separator: "\n\n")
                      : "")
            resets(row.id, theme).frame(width: Column.resets, alignment: .leading)
            Text(credit?.tableText(
                used: creditDisplayMode == "used",
                format: BrimPanelModel.Format(locale: Locale(identifier: AppLocale.identifier)), localize: L) ?? "–")
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(credit?.spendLimitReached == true ? theme.warn : theme.text2)
                .lineLimit(1).minimumScaleFactor(0.85).frame(width: Column.credit, alignment: .center)
                .opacity(panelRow?.heldOver == true || panelRow?.creditHeldOver == true ? 0.48 : 1)
            // The switch is UsageBar's own setting (its defaults only).
            Toggle("", isOn: Binding(get: { row.monitored },
                                     set: { on in actions.setMonitored?(row.id, on) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .tint(theme.accent)
                .disabled(actions.setMonitored == nil)
                .frame(width: Column.monitor)
            Menu {
                Button(L("Reveal profile in Finder")) { actions.revealFolder(row.folder) }
                Divider()
                // Renaming, signing in and removing write to the account or UsageBar's list: each
                // its own flow behind a confirmation.
                Button(L("Rename")) { actions.rename?(row.id) }.disabled(actions.rename == nil)
                Button(L("Sign in again")) { actions.signIn?(row.id) }.disabled(actions.signIn == nil)
                Button(row.monitored ? L("Stop monitoring") : L("Start monitoring")) {
                    actions.setMonitored?(row.id, !row.monitored)
                }
                .disabled(actions.setMonitored == nil)
                Button(L("Remove account…")) { actions.remove?(row.id) }.disabled(actions.remove == nil)
                if row.strandedCodexAttempt {
                    Divider()
                    // BRIM-GATE: deletes UsageBar's own record only; nothing goes to the provider.
                    Button(L("Clear pending Codex reset attempt…")) { actions.clearCodexAttempt?(row.id) }
                        .disabled(actions.clearCodexAttempt == nil)
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text2)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: Column.actions)
            .accessibilityLabel(String(format: L("Actions for %@"), row.name))
        }
        .padding(.horizontal, 12).frame(height: 42)
    }

    /// The panel shows a reset line only when there is a reset left; here every account says
    /// where it stands, and an unknown count says why (the full reason on hover).
    private func resets(_ id: String, _ theme: BrimTheme) -> some View {
        let words = BrimPanelText(localize: L)
        let row = data.panel.groups.flatMap(\.rows).first { $0.id == id }
        let help = row.flatMap { r in r.resetCredits.flatMap { words.resetSummary($0) } ?? r.resetUnknown.map(words.unknown) }
        return Text(row.map(words.accountStatus) ?? "—")
            .font(.system(size: 12))
            .foregroundStyle(row?.hasNoResetCredits == true || row?.resetUnknown != nil ? theme.text2 : theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .help(help ?? "")
    }

    private func login(_ login: BrimAccountsTable.Login) -> BrimStatusLabel {
        switch login {
        case .signedIn: BrimStatusLabel(text: L("Signed in"), tone: .good)
        case .needsSignIn: BrimStatusLabel(text: L("Sign-in needed"), tone: .critical)
        case .heldOver: BrimStatusLabel(text: L("Held over"), tone: .warn)
        case .error: BrimStatusLabel(text: L("Read error"), tone: .warn)
        case .notMonitored: BrimStatusLabel(text: L("Not monitored"), tone: .outline)
        }
    }
}

enum BrimProviderName {
    static func of(_ id: String) -> String {
        switch id {
        case "claude": "Claude"
        case "codex": "Codex"
        default: id.capitalized
        }
    }
}

// MARK: - Integrations

struct BrimIntegrationsPane: View {
    let report: BrimIntegrationsReport?
    @State private var refreshedReport: BrimIntegrationsReport?
    private var store: IntegrationsStore { .shared }
    @Environment(\.colorScheme) private var scheme

    private enum Column {
        static let status: CGFloat = 150
        static let location: CGFloat = 180
        static let action: CGFloat = 145
    }

    var body: some View {
        let theme = BrimTheme.of(scheme)
        VStack(alignment: .leading, spacing: 16) {
            if !BuildVariant.ownsIntegrations {
                BrimLiveModeNote(text: IntegrationsStore.buildFolderMessage)
            }
            if let error = store.lastError {
                Text(error).font(.system(size: 12)).foregroundStyle(UsageBarColor.warning)
            }
            BrimSettingsCard {
                HStack(spacing: 12) {
                    BrimColumnHeader(text: L("Integration")).frame(maxWidth: .infinity, alignment: .leading)
                    BrimColumnHeader(text: L("Status")).frame(width: Column.status, alignment: .leading)
                    BrimColumnHeader(text: L("Location")).frame(width: Column.location, alignment: .leading)
                    Color.clear.frame(width: Column.action)
                }
                .padding(.horizontal, 12).frame(height: 32)
                if let report = refreshedReport ?? report {
                    ForEach(report.rows) { row in
                        BrimSettingsDivider()
                        integrationRow(row, theme)
                    }
                } else {
                    BrimSettingsDivider()
                    Text(L("Checking…")).font(.system(size: 12)).foregroundStyle(theme.text2)
                        .padding(.horizontal, 12).padding(.vertical, 14)
                }
            }
            Text(L("Existing settings of yours are preserved when you install."))
                .font(.system(size: 12)).foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
        }
        .brimSettingsPage()
    }

    private func integrationRow(_ row: BrimIntegrationsReport.Row, _ theme: BrimTheme) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(row.kind)).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                Text(Self.detail(row.kind)).font(.system(size: 11)).foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Self.status(row.status).frame(width: Column.status, alignment: .center)
            Text(verbatim: row.location).font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.text2)
                .lineLimit(1).truncationMode(.middle).frame(width: Column.location, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                Button(L(row.status == .installed ? "Reinstall" : "Install")) {
                    perform(row.kind, removing: false)
                }
                if row.status == .installed || hasReceipt(row.kind) {
                    Button(L("Remove")) { perform(row.kind, removing: true) }
                }
            }
            .buttonStyle(BrimSettingsButtonStyle())
            .disabled(!BrimFeatures.integrationInstall || !BuildVariant.ownsIntegrations
                      || store.cliElevationTask != nil)
            .frame(width: Column.action, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 46)
    }

    private func hasReceipt(_ kind: BrimIntegrationsReport.Kind) -> Bool {
        switch kind {
        case .cli: return store.cliToolStatus.offersRemoval
        case .mcp: return store.skillStatus.offersRemoval
        case .statusLine: return store.statusLineStatus.offersRemoval
        case .hooks: return [store.agentHookStatus, store.knockHookStatus, store.notificationHookStatus].contains { $0.offersRemoval }
        case .codex: return store.codexSessionHookStatus.offersRemoval
        case .shims: return IntegrationsStore.Shim.allCases.contains { store.shimStatus($0).offersRemoval }
        }
    }

    private func perform(_ kind: BrimIntegrationsReport.Kind, removing: Bool) {
        let actions: [() -> Void]
        switch kind {
        case .cli: actions = [removing ? store.removeCLITool : { store.installCLITool() }]
        case .mcp: actions = [removing ? store.removeSkill : store.installSkill]
        case .statusLine: actions = [removing ? store.removeStatusLine : store.installStatusLine]
        case .hooks:
            actions = removing
                ? [store.removeAgentHooks, store.removeKnockHooks, store.removeNotificationHook]
                : [store.installAgentHooks, store.installKnockHooks, store.installNotificationHook]
        case .codex: actions = [removing ? store.removeCodexSessionHooks : store.installCodexSessionHooks]
        case .shims:
            actions = IntegrationsStore.Shim.allCases.map { shim in
                { removing ? store.removeShim(shim) : store.installShim(shim) }
            }
        }
        for action in actions {
            action()
            if store.lastError != nil { break }
        }
        Task {
            if let task = store.cliElevationTask { await task.value }
            refreshReport()
        }
    }

    private func refreshReport() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = accountWatchRoots(home: home)
        refreshedReport = BrimIntegrationsReport.detect(home: home,
            claudeHomes: folders.filter { !$0.lastPathComponent.hasPrefix(".codex") },
            codexHomes: folders.filter { $0.lastPathComponent.hasPrefix(".codex") }, probe: .live)
    }

    static func title(_ kind: BrimIntegrationsReport.Kind) -> String {
        switch kind {
        case .cli: L("usagebar command line tool")
        case .mcp: L("MCP, skill and command")
        case .statusLine: L("Claude Code statusline")
        case .hooks: L("Claude Code hooks")
        case .codex: L("Codex")
        case .shims: L("CLI shims")
        }
    }

    static func detail(_ kind: BrimIntegrationsReport.Kind) -> String {
        switch kind {
        case .cli: L("status, pick and handoff from any shell")
        case .mcp: L("usagebar-quota skill and /usagebar command")
        case .statusLine: L("Usage under the Claude Code prompt")
        case .hooks: L("Session start and limit events for handoff")
        case .codex: L("Session events and handoff for Codex CLI")
        case .shims: L("claude and codex start on the best account")
        }
    }

    static func status(_ status: BrimIntegrationsReport.Status) -> BrimStatusLabel {
        switch status {
        case .installed: BrimStatusLabel(text: L("Installed"), tone: .good)
        case .notInstalled: BrimStatusLabel(text: L("Not installed"), tone: .outline)
        case .unreadable: BrimStatusLabel(text: L("Couldn't read"), tone: .warn)
        }
    }
}

// MARK: - About

struct BrimAboutPane: View {
    let data: BrimSettingsData
    var actions = BrimSettingsActions()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = BrimTheme.of(scheme)
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                BrimCupMark(fill: 0.68, ink: theme.text, liquid: theme.accentFill).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: BrandPaths.displayName).font(.system(size: 20, weight: .semibold))
                    Text(String(format: L("Version %@"), data.version)).font(.system(size: 13))
                        .foregroundStyle(theme.text2).textSelection(.enabled)
                }
            }
            BrimSettingsGroup(L("Data")) {
                Text(L("UsageBar reads your accounts itself and publishes ~/.usagebar/snapshot.json. It writes to an account folder only when you add, sign in again or remove an account."))
                    .font(.system(size: 12)).foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .frame(width: 560, alignment: .leading)
        .brimSettingsPage()
    }
}
