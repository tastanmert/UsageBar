import AppKit
import SwiftUI

/// Everything a settings pane reads, gathered by the host (BrimSettingsView) or a fixture, so the
/// panes are plain views of data and render offscreen the same way they do in the window.
struct BrimSettingsData {
    var panel: BrimPanelModel
    var snapshot: UsageSnapshot?
    var now: Date
    var format = BrimPanelModel.Format()
    var accounts: BrimAccountsTable
    /// nil while the read-only scan is still running.
    var integrations: BrimIntegrationsReport?
    var version: String
}

/// The settings that work today, all UsageBar's own.
struct BrimSettingsBindings {
    var menuBarText: Binding<BrimMenuBarText>
    var appearance: Binding<BrimAppearance>
    var panelLayout: Binding<BrimPanelLayout>
    /// "" follows the system.
    var language: Binding<String>
    var displayMode: Binding<DisplayMode> = .constant(.remaining)
    var menuSelection: Binding<BrimMenuSelection> = .constant(.init())
    var refreshIntervalMinutes: Binding<Int> = .constant(1)
}

struct BrimSettingsActions {
    var revealFolder: (String) -> Void = { _ in }
    var rescan: () -> Void = {}
    var refresh: () -> Void = {}
    // Settings > Accounts: each is a flow started by the user only.
    var addAccount: (() -> Void)?
    var rename: ((String) -> Void)?
    var signIn: ((String) -> Void)?
    var setMonitored: ((String, Bool) -> Void)?
    var remove: ((String) -> Void)?
    /// Codex: forget an earlier login's open reset attempt after a confirmation.
    var clearCodexAttempt: ((String) -> Void)?
    /// Claude: sign in to claude.ai inside UsageBar so the plan's renewal date can be read.
    var connectClaudeWeb: ((String) -> Void)?
}

/// One pane by tab.
struct BrimSettingsPane: View {
    let tab: BrimSettingsTab
    let data: BrimSettingsData
    let bindings: BrimSettingsBindings
    var actions = BrimSettingsActions()

    var body: some View {
        switch tab {
        case .general: BrimGeneralPane(data: data, bindings: bindings, actions: actions)
        case .accounts: BrimAccountsPane(data: data, actions: actions)
        case .routing: BrimRoutingPane(format: data.format)
        case .integrations: BrimIntegrationsPane(report: data.integrations)
        case .about: BrimAboutPane(data: data, actions: actions)
        }
    }
}

// MARK: - General

struct BrimGeneralPane: View {
    let data: BrimSettingsData
    let bindings: BrimSettingsBindings
    var actions = BrimSettingsActions()
    @Environment(\.colorScheme) private var scheme

    static let languages = ["en", "tr", "ja", "ko", "zh-Hans", "zh-Hant"]

    /// Each language in its own words ("Türkçe", "English"), from the system.
    static func languageName(_ code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code).map { $0.capitalized(with: locale) } ?? code
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                BrimSettingsGroup(L("Menu bar")) {
                    BrimSettingsRow(title: L("Content")) {
                        BrimSegmented(options: [(BrimMenuBarText.glyph, L("Icon only")),
                                                (.percent, L("Tightest limit")),
                                                (.selected, L("Selected accounts"))],
                                      selection: bindings.menuBarText)
                    }
                    if bindings.menuBarText.wrappedValue == .selected {
                        selectedAccounts
                    }
                }
                BrimSettingsGroup(L("Panel")) {
                    BrimSettingsRow(title: L("Percentages")) {
                        BrimSegmented(options: [(DisplayMode.remaining, L("Remaining")), (.used, L("Used"))],
                                      selection: bindings.displayMode)
                    }
                    BrimSettingsDivider()
                    BrimSettingsRow(title: L("Panel layout")) {
                        BrimSegmented(options: [(BrimPanelLayout.Arrangement.list, L("List")), (.cards, L("Card"))],
                                      selection: bindings.panelLayout.arrangement)
                    }
                    BrimSettingsDivider()
                    BrimSettingsRow(title: L("Columns")) {
                        BrimColumnPicker(selection: bindings.panelLayout.columns)
                            .disabled(bindings.panelLayout.wrappedValue.arrangement != .cards)
                    }
                    BrimSettingsDivider()
                    BrimSettingsRow(title: L("Density")) {
                        BrimSegmented(options: [(BrimPanelLayout.Density.compact, L("Compact")), (.detailed, L("Detailed"))],
                                      selection: bindings.panelLayout.density)
                    }
                    BrimSettingsDivider()
                    BrimSettingsRow(title: L("Group by provider")) {
                        Toggle("", isOn: bindings.panelLayout.groupByProvider).toggleStyle(.switch).labelsHidden()
                            .tint(BrimTheme.of(scheme).accent)
                    }
                }
                BrimSettingsGroup(L("Data")) {
                    BrimSettingsRow(title: L("Refresh frequency")) {
                        BrimSegmented(options: [(1, L("1 min")), (2, L("2 min")),
                                                (5, L("5 min")), (15, L("15 min"))],
                                      selection: bindings.refreshIntervalMinutes)
                    }
                    Text(L("Usage reads are checked at this interval."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.bottom, 8)
                    BrimSettingsDivider()
                    BrimSettingsRow(title: L("Last refresh")) {
                        Text(data.panel.updated ?? L("Not yet"))
                            .font(.system(size: 12)).monospacedDigit()
                            .frame(width: 76, alignment: .center)
                        Button(L("Refresh now"), action: actions.refresh)
                            .buttonStyle(BrimSettingsButtonStyle())
                    }
                }
                BrimSettingsGroup(L("App")) {
                    BrimSettingsRow(title: L("Language")) {
                        Picker("", selection: bindings.language) {
                            Text(L("System")).tag("")
                            ForEach(Self.languages, id: \.self) { Text(verbatim: Self.languageName($0)).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    BrimSettingsDivider()
                    BrimSettingsRow(title: L("Appearance")) {
                        BrimSegmented(options: [(BrimAppearance.system, L("System")), (.light, L("Light")),
                                                (.dark, L("Dark"))],
                                      selection: bindings.appearance)
                    }
                    BrimSettingsDivider()
                    BrimLaunchAtLoginRow()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            preview.frame(width: 268)
        }
        .brimSettingsPage()
    }

    private var selectedAccounts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text(L("Account")).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(BrimMenuSelection.Window.allCases, id: \.rawValue) { window in
                        Text(windowTitle(window)).frame(width: 54)
                    }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(data.panel.groups.flatMap(\.rows)) { row in
                    GridRow {
                        HStack(spacing: 5) {
                            BrimProviderMark(provider: row.provider)
                            Text(verbatim: row.name).lineLimit(1).truncationMode(.middle)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(BrimMenuSelection.Window.allCases, id: \.rawValue) { window in
                            if window != .fable || row.model != nil || bindings.menuSelection.wrappedValue.contains(row.id, window) {
                                Toggle(windowTitle(window), isOn: Binding(
                                    get: { bindings.menuSelection.wrappedValue.contains(row.id, window) },
                                    set: { bindings.menuSelection.wrappedValue.set(row.id, window, enabled: $0) }))
                                    .labelsHidden().toggleStyle(.checkbox).frame(width: 54)
                                    .accessibilityLabel(row.name + " " + windowTitle(window))
                            } else { Color.clear.frame(width: 54, height: 16) }
                        }
                    }
                }
            }
            HStack(spacing: 16) {
                Toggle(L("Short account labels"), isOn: bindings.menuSelection.showLabels)
                Toggle(L("Window labels"), isOn: bindings.menuSelection.showWindowTags)
            }
            .toggleStyle(.checkbox)
        }.font(.system(size: 12)).tint(BrimTheme.of(scheme).accent).padding(12)
    }

    private func windowTitle(_ window: BrimMenuSelection.Window) -> String {
        switch window {
        case .fiveHour: L("5 hours")
        case .weekly: L("Weekly")
        case .fable: "Fable"
        }
    }

    // MARK: Preview

    private var preview: some View {
        let theme = BrimTheme.of(scheme)
        let glyph = BrimMenuBarText.face(bindings.menuBarText.wrappedValue, model: data.panel,
                                         selection: bindings.menuSelection.wrappedValue,
                                         used: bindings.displayMode.wrappedValue == .used, format: data.format)
        let text = glyph.text
        let segments = bindings.menuSelection.wrappedValue.segments(
            rows: data.panel.groups.flatMap(\.rows), used: bindings.displayMode.wrappedValue == .used, format: data.format)
        let bestRow = data.panel.groups.flatMap(\.rows).first { $0.id == data.panel.tightest?.accountID }
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Preview")).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 4)
            BrimSettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    // A slice of the menu bar.
                    HStack(spacing: 4) {
                        if !BrimMenuBarText.showsCup(bindings.menuBarText.wrappedValue, segments: segments) {
                            ViewThatFits(in: .horizontal) {
                                menuPreview(segments, vertical: false)
                                menuPreview(segments, vertical: true)
                            }
                        } else {
                            Image(nsImage: BrimCup.templateImage(glyph)).renderingMode(.template)
                            if bindings.menuBarText.wrappedValue != .selected, let text { Text(verbatim: text).font(.system(size: 12)).monospacedDigit() }
                        }
                    }
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 6).frame(minHeight: 22)
                    .background(theme.text.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).frame(minHeight: 30)
                    .background(theme.surface2, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.hairline))
                    Text(L(bindings.displayMode.wrappedValue == .used ? "Used" : "Remaining"))
                        .font(.system(size: 12)).foregroundStyle(theme.text2)
                    if bindings.menuBarText.wrappedValue == .percent, let bestRow {
                        Text(verbatim: bestRow.name).font(.system(size: 13, weight: .medium))
                    }
                }
                .padding(14)
            }
            perAccount(theme)
        }
    }

    private func menuPreview(_ segments: [BrimMenuSelection.Segment], vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                              : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            ForEach(segments, id: \.id) { segment in
                HStack(spacing: 4) {
                    BrimProviderMark(provider: segment.provider, monochrome: true)
                    if let label = segment.label {
                        Text(verbatim: label).font(.system(size: 12)).fixedSize()
                    }
                    let selection = bindings.menuSelection.wrappedValue
                    HStack(spacing: 5) {
                        ForEach(Array(segment.parts.enumerated()), id: \.offset) { _, part in
                            HStack(spacing: 2) {
                                if selection.showWindowTags {
                                    Text(verbatim: part.window.tag).font(.system(size: 11, weight: .semibold))
                                }
                                Text(verbatim: part.value.menuBarFigure)
                                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(segment.stale ? Color.secondary : Color(nsColor: part.tone.menuColor))
                            }
                        }
                    }
                    .fixedSize()
                    .padding(.leading, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func perAccount(_ theme: BrimTheme) -> some View {
        let rows = data.panel.groups.flatMap(\.rows)
        if !rows.isEmpty {
            Text(L("Per account")).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 4).padding(.top, 12)
            BrimSettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            Text(verbatim: row.name).font(.system(size: 12)).foregroundStyle(theme.text)
                                .lineLimit(1).frame(width: 96, alignment: .leading)
                            VStack(spacing: 3) {
                                ForEach(Array(BrimPanelModel.windows(row).enumerated()), id: \.offset) { _, window in
                                    bar(window.cell, theme)
                                }
                            }
                        }
                    }
                    BrimSettingsDivider()
                    Text(L("Windows: Fable, 5 hours, weekly.")).font(.system(size: 12)).foregroundStyle(theme.text2)
                }
                .padding(14)
            }
        }
    }

    private func bar(_ cell: BrimPanelModel.Cell, _ theme: BrimTheme) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.mutedFill)
                Capsule().fill(theme.barFill(cell.level)).frame(width: proxy.size.width * cell.displayed(used: bindings.displayMode.wrappedValue == .used).fill)
            }
        }
        .frame(height: 3)
    }
}

/// A whole-percent slider that shows every step while dragged and writes once, on release, so a
/// drag publishes one state.json rather than one per step.
struct BrimPercentSlider: View {
    let title: String
    var subtitle: String?
    let format: BrimPanelModel.Format
    let range: ClosedRange<Int>
    let value: Int
    let commit: (Int) -> Void
    @State private var draft: Int?

    var body: some View {
        let shown = draft ?? value
        BrimSettingsRow(title: title, subtitle: subtitle) {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { Double(shown) }, set: { draft = Int($0.rounded()) }),
                       // Rounded here rather than with `step:`, which draws a tick for every percent.
                       in: Double(range.lowerBound)...Double(range.upperBound)) { editing in
                    if !editing, let draft {
                        commit(draft)
                        self.draft = nil
                    }
                }
                .frame(width: 110)
                Text(verbatim: shown == 0 ? L("Off") : format.percent(Double(shown)))
                    .font(.system(size: 13)).monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

// MARK: - Launch at login

/// The login item switch, drawn from `SMAppService.mainApp.status` and re-read whenever the app
/// comes forward, since System Settings can revoke it without telling us. Only the user's press
/// registers anything; the uninvited first-launch default stays behind its own gate
/// (`BrimFeatures.launchAtLoginDefault`). A build-tree copy reads but never writes, because
/// `SMAppService.mainApp` registers the RUNNING bundle and would aim the login item at a build tree.
struct BrimLaunchAtLoginRow: View {
    @State private var state: LaunchAtLoginState = .notRegistered
    @State private var failure: LaunchAtLoginFailure?
    @Environment(\.colorScheme) private var scheme

    private var manageable: Bool { BuildVariant.ownsSharedChoices }

    var body: some View {
        let lines = manageable
            ? [state.noticeKey.map { L($0) }, failure?.message].compactMap { $0 }
            : [L("This build does not save these settings; the installed app does.")]
        VStack(alignment: .leading, spacing: 0) {
            BrimSettingsRow(title: L("Launch at login"),
                            subtitle: lines.isEmpty ? nil : lines.joined(separator: " ")) {
                HStack(spacing: 10) {
                    if manageable, LaunchAtLoginState.offersSystemSettings(for: state, failure: failure) {
                        Button(L("Open Login Items")) { LaunchAtLoginService.openLoginItems() }
                            .buttonStyle(BrimSettingsButtonStyle())
                    }
                    BrimSwitch(isOn: Binding(get: { state.isRegistered }, set: { setRegistered($0) }))
                        .disabled(!manageable)
                }
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        state = LaunchAtLoginService.current
        failure = LaunchAtLoginState.surviving(failure, beside: state)
    }

    private func setRegistered(_ registered: Bool) {
        var thrown: Error?
        do { try LaunchAtLoginService.setRegistered(registered) } catch { thrown = error }
        failure = thrown.map { LaunchAtLoginFailure(wanted: registered, message: $0.localizedDescription) }
        refresh()
    }
}

// MARK: - Routing

struct BrimRoutingPane: View {
    var format = BrimPanelModel.Format()
    @Environment(\.colorScheme) private var scheme
    private var store: LaunchPolicyStore { LaunchPolicyStore.shared }

    var body: some View {
        let theme = BrimTheme.of(scheme)
        VStack(alignment: .leading, spacing: 20) {
            // A build-tree copy never publishes state.json (LaunchPolicyStore.persist).
            if !BuildVariant.ownsSharedChoices {
                BrimLiveModeNote(text: L("This build does not save these settings; the installed app does."))
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        BrimSettingsGroup(L("Account selection")) {
                            modeRow("Claude", providerID: "claude")
                            BrimSettingsDivider()
                            modeRow("Codex", providerID: "codex")
                        }
                        Text(L("Smart opens each new session on the account with the most quota left. Manual always uses the account you pick. Off leaves the choice to you."))
                            .font(.system(size: 12)).foregroundStyle(theme.text2)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    }
                    BrimSettingsGroup(L("Thresholds")) {
                        BrimPercentSlider(title: L("Move a session when left drops below"),
                                          subtitle: L("When the account runs this low, the Claude session continues on another account."),
                                          format: format,
                                          range: LaunchPolicyStore.Routing.defaultSwitchBelow...50,
                                          value: store.switchBelow) { store.setSwitchBelow($0) }
                        BrimSettingsDivider()
                        BrimPercentSlider(title: L("Skip accounts with weekly left under"),
                                          subtitle: L("New sessions do not start on an account whose weekly quota is nearly used up. Off skips none."),
                                          format: format, range: 0...50,
                                          value: store.skipWeeklyBelow) { store.setSkipWeeklyBelow($0) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 20) {
                    BrimSettingsGroup(L("Handoff safety")) {
                        BrimSettingsRow(title: String(format: L("At most %d handoffs per %d min"),
                                                      store.maxHandoffs, 10),
                                        subtitle: L("Keeps a Claude session from jumping between accounts again and again.")) {
                            Stepper("", value: Binding(get: { store.maxHandoffs },
                                                       set: { store.setMaxHandoffs($0) }),
                                    in: 1...9).labelsHidden()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .brimSettingsPage()
    }

    private func modeRow(_ title: String, providerID: String) -> some View {
        BrimSettingsRow(title: title) {
            BrimSegmented(options: [(LaunchPolicyStore.Mode.auto, L("Smart")),
                                    (.manual, L("Manual")), (.off, L("Off"))],
                          selection: Binding(get: { store.mode(providerID) },
                                             set: { store.setMode(providerID, $0) }))
        }
    }
}

extension BrimMenuSelection.Window {
    /// The small dimmed name before a figure in the menu bar: 5H / W / F (Turkish 5S / H / F).
    var tag: String {
        switch self {
        case .fiveHour: L("5H")
        case .weekly: L("W")
        case .fable: L("F")
        }
    }
}

extension BrimMenuSelection.Part.Tone? {
    /// Green, orange, red: the system tones, which macOS already tunes for light and dark bars.
    var menuColor: NSColor {
        switch self {
        case .fine: .systemGreen
        case .watch: .systemOrange
        case .low: .systemRed
        case nil: .labelColor
        }
    }
}

extension String {
    /// A figure as the menu bar shows it: the window tag already says it is a share, so the
    /// percent sign is dropped ("%84" / "84%" -> "84").
    var menuBarFigure: String { replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces) }
}
