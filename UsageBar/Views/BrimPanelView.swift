import SwiftUI

/// What the panel's buttons do. Closures, so the view knows nothing about the app's stores and
/// can be rendered from fixtures (tests/brimpanel/render.swift).
struct BrimPanelActions {
    var refresh: () -> Void = {}
    var openSettings: () -> Void = {}
    /// Opening a reset line (account, kind, grant): consent for Claude in either mode;
    /// Codex explains the live-mode requirement when mirroring.
    var openReset: ((String, BrimPanelModel.ResetKind, String?) -> Void)? = nil
    /// Another kind on the open card.
    var chooseReset: (BrimPanelModel.ResetKind) -> Void = { _ in }
    var cancelReset: () -> Void = {}
    /// The card's "Use reset". nil: the button shows disabled.
    var useReset: (() -> Void)? = nil
    /// The view menu's choices, saved by the host.
    var setLayout: (BrimPanelLayout) -> Void = { _ in }
    /// A card's "Sign in again" for an account whose login was refused. nil: no button.
    var signIn: ((String) -> Void)? = nil
    /// Copy a picture of the accounts to the clipboard. nil: no button.
    var copyImage: (() -> Void)? = nil
    /// Open a provider's status page from its incident line.
    var openStatusPage: (URL) -> Void = { _ in }
}

/// The UsageBar menu bar panel: a header (mark, name, update time, refresh, view menu, settings),
/// one short line when the numbers are old or unreadable, the accounts as cards or a list, and
/// Quit. Cards come in 1-4 columns (BrimPanelLayout sets the width); the list is one table. As tall
/// as its content, the accounts scroll once they would not fit `maxHeight`.
struct BrimPanelView: View {
    let model: BrimPanelModel
    var layout = BrimPanelLayout()
    var used = false
    var actions = BrimPanelActions()
    var maxHeight: CGFloat = 900
    /// The width of the screen the panel is on; caps the card columns. nil: no cap.
    var screenWidth: CGFloat? = nil
    var onContentSize: ((CGSize) -> Void)? = nil
    /// Screenshots only: draw the view menu open over the panel.
    var showsLayoutMenu = false
    /// The open confirm card: which account, which kind.
    var prompt: (accountID: String, kind: BrimPanelModel.ResetKind)? = nil
    /// A refresh round is running (`UsageStore.isRefreshing`): the refresh button spins.
    var refreshing = false
    /// The Usage tab's content for a width and the height it may take (BrimUsageView). nil: no
    /// tab switch, the accounts only (screenshots render the panel without the token scan).
    var usageContent: ((_ width: CGFloat, _ maxHeight: CGFloat) -> AnyView)? = nil
    /// Providers whose status page reports an incident (ServiceStatusStore), one line each.
    var incidents: [BrimServiceIncident] = []
    /// A picture for the clipboard: no header buttons.
    var snapshotMode = false

    enum Tab: String { case accounts, usage }
    @AppStorage("brimPanelTab") private var tabRaw = Tab.accounts.rawValue
    private var tab: Tab { usageContent == nil ? .accounts : Tab(rawValue: tabRaw) ?? .accounts }

    @Environment(\.colorScheme) private var scheme
    @State private var menuOpen = false
    /// Clicked and the round has not started yet: the button answers at once, not when the
    /// store's Task gets to run.
    @State private var refreshRequested = false
    /// The clicked round just ended: a check for a moment, so "it did refresh" is visible.
    @State private var refreshDone = false
    /// The store reported a round running since the click. State, not `refreshing`: a closure
    /// would read the copy of `refreshing` taken at click time.
    @State private var refreshSeenRunning = false
    @State private var listHeight: CGFloat = 0
    @State private var chromeTop: CGFloat = 0
    @State private var chromeBottom: CGFloat = 0

    private var theme: BrimTheme { .of(scheme) }
    private var words: BrimPanelText { BrimPanelText(localize: L) }
    private var columns: Int { layout.columnCount(accounts: model.accountCount, screenWidth: screenWidth) }
    private var width: CGFloat {
        let accounts = model.body == .accounts ? layout.panelWidth(accounts: model.accountCount, screenWidth: screenWidth)
            : BrimPanelLayout.singleCardWidth
        return tab == .usage ? max(accounts, Self.usageWidth) : accounts
    }
    static let usageWidth: CGFloat = 600

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                banner
            }
            .background(measure { chromeTop = $0 })
            if tab == .usage, let usageContent {
                usageContent(width, max(200, maxHeight - chromeTop - 140))
            } else {
                accountsArea
            }
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.surface)
        .foregroundStyle(theme.text)
        .font(.system(size: 13))
        .monospacedDigit()
        .overlay(alignment: .topTrailing) {
            if showsLayoutMenu {
                BrimLayoutMenu(layout: layoutBinding)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.hairline, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .padding(.top, 44).padding(.trailing, 12)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { onContentSize?(proxy.size) }
                .onChange(of: proxy.size) { _, size in onContentSize?(size) }
        })
    }

    private var layoutBinding: Binding<BrimPanelLayout> {
        Binding(get: { layout }, set: { actions.setLayout($0) })
    }

    private func measure(_ write: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { write(proxy.size.height) }
                .onChange(of: proxy.size.height) { _, height in write(height) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            BrimCupMark(fill: model.glyph.fiveHourFill, weeklyFill: model.glyph.weeklyFill,
                        ink: theme.text, liquid: theme.accentFill, dimmed: model.glyph.dashed)
                .frame(width: 18, height: 18)
            Text(verbatim: "UsageBar").font(.system(size: 15, weight: .semibold)).padding(.leading, 2)
            if usageContent != nil {
                tabSwitch.padding(.leading, 6)
            } else {
                Text(L(used ? "Used" : "Remaining")).font(.system(size: 11)).foregroundStyle(theme.text2)
            }
            Spacer(minLength: 8)
            if tab == .accounts, let updated = model.updated {
                Text(String(format: L("Updated %@"), updated))
                    .font(.system(size: 11)).foregroundStyle(theme.text2)
                    .lineLimit(1).fixedSize()
            }
            if !snapshotMode {
                headerButtons
            }
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: snapshotMode ? 16 : 8))
    }

    @ViewBuilder private var headerButtons: some View {
            if tab == .accounts, let copyImage = actions.copyImage {
                CopyImageButton(theme: theme, action: copyImage)
            }
            refreshButton
            iconButton("square.grid.2x2", label: L("View"), action: { menuOpen.toggle() })
                .popover(isPresented: $menuOpen, arrowEdge: .bottom) {
                    BrimLayoutMenu(layout: layoutBinding)
                        .background(theme.surface)
                        .environment(\.colorScheme, scheme)
                }
            iconButton("gearshape", label: L("Settings"), action: actions.openSettings)
    }

    /// Accounts (remaining or used, as Settings has it) and Usage, as two quiet words; the chosen
    /// one in the text colour on a soft fill.
    private var tabSwitch: some View {
        HStack(spacing: 2) {
            ForEach([(Tab.accounts, L(used ? "Used" : "Remaining")), (Tab.usage, L("Usage"))], id: \.0) { item in
                Button { tabRaw = item.0.rawValue } label: {
                    Text(item.1).font(.system(size: 11, weight: tab == item.0 ? .medium : .regular))
                        .foregroundStyle(tab == item.0 ? theme.text : theme.text2)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(tab == item.0 ? theme.mutedFill.opacity(0.6) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Spins while a round runs (a click, or the timer's own) and shows a check for a moment after
    /// a clicked round ends. A click during the timer's round still counts (the store queues a full
    /// read behind it); a second click on the same request does nothing.
    private var refreshButton: some View {
        let busy = refreshing || refreshRequested
        return Button {
            guard !refreshRequested else { return }
            refreshDone = false
            refreshRequested = true
            refreshSeenRunning = refreshing
            actions.refresh()
            // A round that never reports itself running (demo fixtures, a store that returned at
            // once) must not leave the spinner up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if refreshRequested && !refreshSeenRunning { finishRefresh() }
            }
        } label: {
            Group {
                if busy {
                    ProgressView().controlSize(.small).scaleEffect(0.75)
                } else if refreshDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(theme.text2)
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(busy ? L("Refreshing…") : L("Refresh now"))
        .accessibilityLabel(busy ? L("Refreshing…") : L("Refresh now"))
        .onChange(of: refreshing) { was, now in
            if now && refreshRequested { refreshSeenRunning = true }
            if was && !now && refreshRequested { finishRefresh() }
        }
    }

    private func finishRefresh() {
        refreshRequested = false
        refreshDone = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { refreshDone = false }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(theme.text2)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: Banner

    @ViewBuilder private var banner: some View {
        switch model.banner {
        case .unavailable:
            notice(symbol: "exclamationmark.triangle", tint: theme.critical,
                   text: L("Usage data unavailable."))
        case .stale(let minutes):
            notice(symbol: "clock", tint: theme.warn, text: words.stale(minutes))
        case nil:
            EmptyView()
        }
        ForEach(incidents) { incident in
            BrimIncidentLine(incident: incident, theme: theme, open: { actions.openStatusPage(incident.site) })
        }
    }

    /// One short line, the icon carrying the colour.
    private func notice(symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint)
            Text(text).font(.system(size: 12)).foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
    }

    // MARK: Accounts

    @ViewBuilder private var accountsArea: some View {
        switch model.body {
        case .accounts:
            let content = VStack(alignment: .leading, spacing: layout.arrangement == .cards ? 14 : 8) {
                ForEach(model.sections(groupByProvider: layout.groupByProvider)) { section in
                    switch layout.arrangement {
                    case .cards: cardSection(section)
                    case .list: listSection(section)
                    }
                }
            }
            .padding(EdgeInsets(top: 2, leading: layout.arrangement == .cards ? BrimPanelLayout.edge : 8,
                                bottom: 6, trailing: layout.arrangement == .cards ? BrimPanelLayout.edge : 8))
            let room = max(160, maxHeight - chromeTop - chromeBottom)
            if listHeight > room {
                ScrollView(.vertical) { content.background(measure { listHeight = $0 }) }
                    .frame(height: room)
            } else {
                content.background(measure { listHeight = $0 })
            }
        case .loading:
            emptyState(L("Reading usage…"))
        case .noData:
            emptyState(L("No usage data yet."))
        case .noAccounts:
            emptyState(L("No accounts yet."))
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(theme.text2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
    }

    private func providerName(_ id: String) -> String {
        switch id {
        case "claude": "Claude"
        case "codex": "Codex"
        default: id.capitalized
        }
    }

    /// "Claude  3" over a provider's cards; nothing over the single ungrouped section.
    @ViewBuilder private func sectionTitle(_ section: BrimPanelModel.Group) -> some View {
        if section.id != "all" {
            HStack(spacing: 6) {
                BrimProviderMark(provider: section.id)
                (Text(verbatim: providerName(section.id)).font(.system(size: 12, weight: .semibold))
                + Text(verbatim: "  \(section.rows.count)").font(.system(size: 12)).foregroundColor(theme.text3))
                .foregroundStyle(theme.text2)
                .padding(.leading, 2)
            }
        }
    }

    /// A card asking for a sign-in stays at full strength: its button is the thing to read.
    private func dimmed(_ row: BrimPanelModel.Row) -> Double {
        (model.dimmed || row.heldOver) && !row.needsSignIn ? 0.55 : 1
    }

    /// The windows a card shows: 5 hours only when the account reports one (Codex does not), weekly
    /// always, the model window when there is one.
    private func windows(_ row: BrimPanelModel.Row) -> [(BrimPanelModel.Window, BrimPanelModel.Cell, BrimPanelModel.ResetTime?)] {
        BrimPanelModel.windows(row)
    }

    private func percent(_ cell: BrimPanelModel.Cell) -> String {
        cell.displayed(used: used, format: BrimPanelModel.Format(locale: Locale(identifier: AppLocale.identifier))).percentText
    }

    // MARK: Cards

    private func cardSection(_ section: BrimPanelModel.Group) -> some View {
        let count = columns
        let cardWidth = count == 1 ? BrimPanelLayout.singleCardWidth - 2 * BrimPanelLayout.edge
            : BrimPanelLayout.cardWidth
        let chunks = stride(from: 0, to: section.rows.count, by: count).map {
            Array(section.rows[$0..<min($0 + count, section.rows.count)])
        }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(section)
            VStack(alignment: .leading, spacing: BrimPanelLayout.cardGap) {
                ForEach(chunks.indices, id: \.self) { index in
                    // Cards in one row share its height.
                    HStack(alignment: .top, spacing: BrimPanelLayout.cardGap) {
                        ForEach(chunks[index]) { row in card(row).frame(width: cardWidth) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func card(_ row: BrimPanelModel.Row) -> some View {
        let compact = layout.density == .compact
        return VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                BrimProviderMark(provider: row.provider)
                nameText(row)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusMark(row)
            }
            VStack(alignment: .leading, spacing: compact ? 6 : 9) {
                ForEach(Array(windows(row).enumerated()), id: \.offset) { _, item in
                    if compact {
                        compactWindow(item.0, item.1, item.2, spend: spend(row, item.0))
                    } else {
                        detailedWindow(item.0, item.1, item.2, spend: spend(row, item.0))
                    }
                }
            }
            creditRow(row)
            refreshFailure(row)
            resetArea(row)
                .padding(.top, compact ? 0 : 2)
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.hairline, lineWidth: 0.5))
        .opacity(dimmed(row))
        .help(row.name)
    }

    /// Label bold, then the plan and (for duplicate labels) the home folder, wrapping as one text.
    private func nameText(_ row: BrimPanelModel.Row) -> Text {
        let facts = [row.plan, row.home].compactMap { $0 }.joined(separator: " · ")
        let name = Text(verbatim: row.label).font(.system(size: 13, weight: .semibold))
        guard !facts.isEmpty else { return name }
        return name + Text(verbatim: "  " + facts).font(.system(size: 12)).foregroundColor(theme.text2)
    }

    /// A small dot: orange-red at or near a limit, amber when low, teal on the account with the
    /// most left. Nothing otherwise.
    @ViewBuilder private func statusMark(_ row: BrimPanelModel.Row) -> some View {
        let levels = windows(row).compactMap(\.1.level)
        if row.refreshFailed {
            dot(theme.warnFill, label: row.serverHoldUntil != nil ? row.refreshFailureTitle
                : row.refreshProblem?.isEmpty == false ? row.refreshProblem! : L("Could not refresh"))
        } else if levels.contains(where: { $0 == .limit || $0 == .critical }) {
            dot(theme.criticalFill, label: L("Near the limit"))
        } else if levels.contains(.low) {
            dot(theme.warnFill, label: L("Running low"))
        }
    }

    private func dot(_ color: Color, label: String) -> some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .help(label)
            .accessibilityLabel(label)
    }

    private func windowLabel(_ window: BrimPanelModel.Window) -> some View {
        Text(words.window(window))
            .font(.system(size: 12)).foregroundStyle(theme.text2)
            .lineLimit(1).fixedSize()
            .frame(minWidth: 56, alignment: .leading)
    }

    private func meter(_ cell: BrimPanelModel.Cell, height: CGFloat) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.mutedFill)
                Capsule().fill(theme.barFill(cell.level))
                    .frame(width: max(cell.displayed(used: used).fill > 0 ? height : 0, proxy.size.width * cell.displayed(used: used).fill))
            }
        }
        .frame(height: height)
        .opacity(cell.remaining == nil ? 0.5 : 1)
    }

    private func percentText(_ cell: BrimPanelModel.Cell, size: CGFloat) -> some View {
        Text(percent(cell))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(cell.remaining == nil ? theme.text3 : theme.ink(cell.level))
            .lineLimit(1).fixedSize()
            .frame(minWidth: 38, alignment: .trailing)
    }

    private func windowHelp(_ window: BrimPanelModel.Window, _ reset: BrimPanelModel.ResetTime?) -> String {
        guard let reset else { return words.window(window) }
        return words.window(window) + " · " + String(format: L("resets %@"), reset.clock)
    }

    private func spend(_ row: BrimPanelModel.Row, _ window: BrimPanelModel.Window) -> BrimPanelModel.WindowSpend? {
        let key: String
        switch window {
        case .fiveHour: key = "five_hour"
        case .weekly: key = "seven_day"
        case .model: key = "seven_day_fable"
        }
        return row.windowSpend[key]
    }

    private var creditFormat: BrimPanelModel.Format {
        BrimPanelModel.Format(locale: Locale(identifier: AppLocale.identifier))
    }

    /// Fixed widths keep every account's meter aligned, independent of its credit text.
    private enum UsageColumn {
        static let label: CGFloat = 64
        static let percent: CGFloat = 44
        static let countdown: CGFloat = 62
        static let gap: CGFloat = 6
        static let credit = percent + gap + countdown
    }

    private func usageLabel(_ label: String) -> some View {
        Text(label).font(.system(size: 12)).foregroundStyle(theme.text2)
            .lineLimit(1)
            .frame(width: UsageColumn.label, alignment: .leading)
    }

    private func detailedWindow(_ window: BrimPanelModel.Window, _ cell: BrimPanelModel.Cell,
                                _ reset: BrimPanelModel.ResetTime?, spend: BrimPanelModel.WindowSpend? = nil) -> some View {
        compactWindow(window, cell, reset, spend: spend)
    }

    private func compactWindow(_ window: BrimPanelModel.Window, _ cell: BrimPanelModel.Cell,
                               _ reset: BrimPanelModel.ResetTime?, spend: BrimPanelModel.WindowSpend? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: UsageColumn.gap) {
                usageLabel(words.window(window))
                meter(cell, height: 4).frame(maxWidth: .infinity)
                Text(percent(cell))
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(cell.remaining == nil ? theme.text3 : theme.ink(cell.level))
                    .lineLimit(1)
                    .frame(width: UsageColumn.percent, alignment: .trailing)
                Text(reset.map(words.resetShort) ?? "")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.text2)
                    .lineLimit(1)
                    .frame(width: UsageColumn.countdown, alignment: .trailing)
            }
            if let spend {
                Text(spend.text(used: used, format: creditFormat))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.text2)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .help(windowHelp(window, reset))
        .accessibilityElement(children: .combine)
    }

    private func creditGrid<Bar: View>(label: String, value: String, warning: Bool = false,
                                       @ViewBuilder bar: () -> Bar) -> some View {
        HStack(spacing: UsageColumn.gap) {
            usageLabel(label)
            bar().frame(maxWidth: .infinity)
            Text(value).font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(warning ? theme.warn : theme.text2)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: UsageColumn.credit, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func creditRow(_ row: BrimPanelModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if row.provider == "claude" { consoleRows(row) }
            creditGrid(label: row.credit?.codex != nil ? L("Credit") : L("Extra usage"),
                       value: row.credit?.tableText(used: used, format: creditFormat, localize: L) ?? "–",
                       warning: row.credit?.spendLimitReached == true) {
                // A disabled or unmetered credit still gets its track, empty, so every row lines up.
                meter(BrimPanelModel.cell(row.credit?.remainingPercent(), format: creditFormat), height: 4)
            }
            .opacity(row.creditHeldOver && !row.heldOver ? 0.48
                     : row.credit?.enabled == false && row.credit?.spendLimitReached != true ? 0.65 : 1)
            ForEach(Array(row.promotions.enumerated()), id: \.offset) { _, promo in
                let amount = promo.text(format: creditFormat, localize: L)
                creditGrid(label: L("Promotion"),
                           value: [amount, promo.expiresIn].compactMap { $0 }.joined(separator: " · ")) {
                    Color.clear.frame(height: 4)
                }
                .help([amount, promo.expiresIn.map { String(format: L("expires in %@"), $0) }]
                    .compactMap { $0 }.joined(separator: " · "))
            }
        }
    }

    /// This account's Console organization credits, above its Extra usage row: the prepaid balance
    /// (with the soonest expiry) and a bar of this month's tier limit left, or a "Connect" /
    /// "Reconnect" link that opens that account's own Console sign-in. A failed refresh leaves the
    /// last reading dimmed. Reads ConsoleCreditsStore, which keeps one state per account.
    @ViewBuilder private func consoleRows(_ row: BrimPanelModel.Row) -> some View {
        let store = ConsoleCreditsStore.shared
        let display = ConsoleAccounts.display(
            state: store.state(for: row.id), mismatch: store.isDifferentAccount(row.id),
            locale: Locale(identifier: AppLocale.identifier),
            money: { creditFormat.money($0, currency: $1) })
        VStack(alignment: .leading, spacing: 6) {
            if display.action != .none {
                HStack(spacing: UsageColumn.gap) {
                    usageLabel(L("Org credits"))
                    // An empty track, so a card waiting on sign-in lines up with one that has read.
                    meter(BrimPanelModel.cell(nil), height: 4).frame(maxWidth: .infinity)
                    Button(display.action == .connect ? L("Connect") : L("Reconnect")) {
                        ConsoleSignInWindowController.shared.show(accountID: row.id)
                    }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(theme.text2).underline()
                    .lineLimit(1)
                    .frame(width: UsageColumn.credit, alignment: .trailing)
                }
            }
            if let balance = display.balance {
                // The bar is what is left of this month's tier limit; the spend itself is in the tooltip.
                creditGrid(label: L("Org credits"), value: balance) {
                    meter(BrimPanelModel.cell(display.remainingPercent, format: creditFormat), height: 4)
                }
                .opacity(display.stale ? 0.48 : 1)
                .help(display.help ?? "")
            }
            if display.mismatch {
                Text(L("Different Console account"))
                    .font(.system(size: 11)).foregroundStyle(theme.warn)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func refreshFailure(_ row: BrimPanelModel.Row) -> some View {
        if row.needsSignIn {
            // The provider refused the login: the numbers cannot come back on their own, so the
            // card says so and offers the same sign-in Settings does (RenewLoginStore).
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(theme.warn)
                Text(L("Sign-in needed")).font(.system(size: 11)).foregroundStyle(theme.warn)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let signIn = actions.signIn {
                    Button(row.signingIn ? L("Signing in…") : L("Sign in again")) { signIn(row.id) }
                        .controlSize(.small)
                        .disabled(row.signingIn)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(row.refreshProblem?.isEmpty == false ? row.refreshProblem! : L("Sign-in needed"))
        } else if row.refreshFailed {
            // A server-stated 429 hold leads with the wait, so a stale card is not mistaken for a
            // broken account and neither a refresh nor a fresh sign-in is tried inside the window.
            let held = row.serverHoldUntil != nil
            let base = held ? row.refreshFailureTitle
                : row.refreshReading.map { String(format: L("Could not refresh · %@ data"), $0) } ?? L("Could not refresh")
            let retry = held ? row.refreshReading.map { String(format: L("%@ data"), $0) } : nil
            // The reason's first paragraph is on the card: hidden in a tooltip, "Could not refresh"
            // alone left the user guessing what to do. The full text stays in the tooltip.
            let reason = row.refreshProblem?.components(separatedBy: "\n\n").first?.nilIfEmpty
            VStack(alignment: .leading, spacing: 2) {
                Text([base, retry].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(theme.text2)
                    .lineLimit(1)
                if let reason {
                    Text(reason).font(.system(size: 11)).foregroundStyle(theme.text2)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(row.refreshProblem?.isEmpty == false ? row.refreshProblem! : L("Could not refresh"))
        }
    }

    /// Under an account: the confirm card when it is open, else what a spend just did, else the
    /// reset line ("↺ 1 reset left · expires in 28d"). In live mode a usable line opens the card;
    /// in mirror mode it is plain words.
    @ViewBuilder private func resetArea(_ row: BrimPanelModel.Row) -> some View {
        if let prompt, prompt.accountID == row.id {
            BrimResetConfirmView(row: row, kind: prompt.kind, theme: theme,
                                 kinds: BrimPanelModel.usableKinds(row),
                                 onChoose: actions.chooseReset,
                                 onCancel: actions.cancelReset, onUse: actions.useReset, used: used)
        } else if let use = row.resetUse {
            resetStatus(use, row: row)
        } else if row.resetUnknown == .loginExpiring || row.resetCredits?.note == .loginExpiring {
            resetLine(L("Session needs renewing"), heldOver: false, active: false)
        } else if row.hasNoResetCredits {
            Text(L("No reset credits")).font(.system(size: 11)).foregroundStyle(theme.text3)
        } else if let credits = row.resetCredits {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(credits.lines.enumerated()), id: \.offset) { _, line in
                    if let open = actions.openReset, line.action != .none {
                        Button { open(row.id, line.kind, line.grantID) } label: {
                            resetLine(words.resetLine(line), heldOver: false, active: true)
                        }.buttonStyle(.plain)
                    } else {
                        resetLine(words.resetLine(line), heldOver: credits.heldOver, active: false)
                    }
                }
            }
        }
    }

    private func resetLine(_ text: String, heldOver: Bool, active: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .medium))
            Text(text).font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            if active {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(active ? theme.accent : theme.text2)
        .opacity(heldOver ? 0.6 : 1)
        .contentShape(Rectangle())
    }

    /// "↺ Used · 5 hours %100", "Checking…" while it is measured again.
    private func resetStatus(_ use: BrimPanelModel.ResetUse, row: BrimPanelModel.Row) -> some View {
        let tint: Color = switch use {
        case .used: theme.accent
        case .failed, .refused: theme.warn
        default: theme.text2
        }
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            switch use {
            case .working, .checking: ProgressView().controlSize(.mini)
            default: Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .medium))
            }
            Text(words.resetUse(use, row: row, used: used, format: BrimPanelModel.Format(locale: Locale(identifier: AppLocale.identifier)))).font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
    }

    // MARK: List

    private func listSection(_ section: BrimPanelModel.Group) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if section.id != "all" { BrimProviderMark(provider: section.id) }
                Text(section.id == "all" ? L("Accounts") : providerName(section.id))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text2)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            ForEach(section.rows) { row in listRow(row) }
        }
    }

    private func listRow(_ row: BrimPanelModel.Row) -> some View {
        let compact = layout.density == .compact
        return VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: compact ? row.name : row.label)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if !compact, let facts = [row.plan, row.home].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                    Text(verbatim: facts).font(.system(size: 11)).foregroundStyle(theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(Array(windows(row).enumerated()), id: \.offset) { _, item in
                compactWindow(item.0, item.1, item.2, spend: spend(row, item.0))
            }
            creditRow(row)
            refreshFailure(row)
            resetArea(row)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 4 : 7)
        .opacity(dimmed(row))
        .help(row.name)
    }

}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension BrimPanelModel.Row {
    /// When a server-stated read hold (an HTTP 429 with its wait, ProbeCadence.UsageReadHold) ends.
    var serverHoldUntil: Date? { ProbeCadence.UsageReadHold.shared.firmUntil(id, now: Date()) }

    /// The failed-refresh headline: the server's wait when there is one ("Rate limited · retrying
    /// at 17:08"), since a fresh sign-in or a manual refresh does not lift it; else "Could not refresh".
    var refreshFailureTitle: String {
        guard let until = serverHoldUntil else { return L("Could not refresh") }
        return String(format: L("Rate limited · retrying at %@"), until.formatted(date: .omitted, time: .shortened))
    }
}
