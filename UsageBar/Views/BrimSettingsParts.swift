import SwiftUI

/// The settings window's building blocks (design: .brimbar-work/design/Settings-*.png): a titled
/// group card with hairline-separated rows, the toolbar tabs, the live-mode note and the status
/// dot. Colours come from the panel's `BrimTheme`.

enum BrimSettingsTab: String, CaseIterable, Identifiable {
    case general, accounts, routing, notifications, integrations, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("General")
        case .accounts: L("Accounts")
        case .routing: L("Routing")
        case .notifications: L("Notifications")
        case .integrations: L("Integrations")
        case .about: L("About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .accounts: "person"
        case .routing: "arrow.triangle.branch"
        case .notifications: "bell"
        case .integrations: "powerplug"
        case .about: "info.circle"
        }
    }
}

enum BrimSettingsMetrics {
    static let windowWidth: CGFloat = 880
    static let inset: CGFloat = 32
    static let tabBarHeight: CGFloat = 60
}

/// The toolbar row of tabs under the window title.
struct BrimSettingsTabBar: View {
    @Binding var selection: BrimSettingsTab
    var onSelect: (BrimSettingsTab) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = BrimTheme.of(scheme)
        HStack(spacing: 4) {
            ForEach(BrimSettingsTab.allCases) { tab in
                let selected = tab == selection
                Button {
                    selection = tab
                    onSelect(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 15, weight: .regular))
                            .frame(height: 18)
                            .foregroundStyle(selected ? theme.accent : theme.text2)
                        Text(tab.title)
                            .font(.system(size: 11, weight: selected ? .medium : .regular))
                            .foregroundStyle(selected ? theme.text : theme.text2)
                            .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .frame(minWidth: 76, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selected ? theme.text.opacity(0.08) : .clear))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: BrimSettingsMetrics.tabBarHeight, alignment: .top)
        .background(theme.surface2)
        .overlay(alignment: .bottom) { theme.hairline.frame(height: 1) }
    }
}

/// A titled group: the title above, the rows in one card.
struct BrimSettingsGroup<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = BrimTheme.of(scheme)
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty || !(accessory is EmptyView) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text)
                    Spacer(minLength: 8)
                    accessory
                }
                .padding(.horizontal, 4)
            }
            BrimSettingsCard { content }
        }
    }
}

extension BrimSettingsGroup where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

struct BrimSettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = BrimTheme.of(scheme)
        VStack(alignment: .leading, spacing: 0) { content }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.hairline, lineWidth: 0.5))
    }
}

struct BrimSettingsDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { BrimTheme.of(scheme).hairline.frame(height: 1) }
}

/// Title (and an optional second line) on the left, the control on the right.
struct BrimSettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let theme = BrimTheme.of(scheme)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(enabled ? theme.text : theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }
}

/// The one line that says why the controls under it are off.
struct BrimLiveModeNote: View {
    let text: String
    var boxed = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = BrimTheme.of(scheme)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(theme.text2)
            Text(text).font(.system(size: 12)).foregroundStyle(theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, boxed ? 12 : 4)
        .padding(.vertical, boxed ? 9 : 0)
        .background {
            if boxed {
                RoundedRectangle(cornerRadius: 8).strokeBorder(theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }
}

/// A coloured dot and its word; colour never carries the meaning alone.
struct BrimStatusLabel: View {
    enum Tone { case good, warn, critical, neutral, outline }
    let text: String
    let tone: Tone
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = BrimTheme.of(scheme)
        HStack(spacing: 6) {
            Group {
                if tone == .outline {
                    Circle().stroke(theme.text3, lineWidth: 1)
                } else {
                    Circle().fill(dot(theme))
                }
            }
            .frame(width: 7, height: 7)
            Text(text).font(.system(size: 12)).foregroundStyle(ink(theme)).lineLimit(1).fixedSize()
        }
    }

    private func dot(_ theme: BrimTheme) -> Color {
        switch tone {
        case .good: theme.accentFill
        case .warn: theme.warnFill
        case .critical: theme.criticalFill
        case .neutral, .outline: theme.text3
        }
    }

    private func ink(_ theme: BrimTheme) -> Color {
        switch tone {
        case .warn: theme.warn
        case .critical: theme.critical
        case .good: theme.text
        case .neutral, .outline: theme.text2
        }
    }
}

/// Small bordered button in the settings' quiet style.
struct BrimSettingsButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let theme = BrimTheme.of(scheme)
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(prominent && enabled ? theme.surface : enabled ? theme.text : theme.text3)
            .padding(.horizontal, 10).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(prominent && enabled ? theme.accent : theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(prominent && enabled ? .clear : theme.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Column header text for the fixed-column tables.
struct BrimColumnHeader: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(BrimTheme.of(scheme).text2).lineLimit(1)
    }
}

extension View {
    /// The pane's page: ground colour, window insets.
    func brimSettingsPage() -> some View {
        modifier(BrimSettingsPageModifier())
    }
}

private struct BrimSettingsPageModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, BrimSettingsMetrics.inset)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(width: BrimSettingsMetrics.windowWidth, alignment: .topLeading)
    }
}

/// A switch in the usagebar teal; segmented pickers keep the system's own selected look.
struct BrimSwitch: View {
    let isOn: Binding<Bool>
    @Environment(\.colorScheme) private var scheme

    init(isOn: Bool) { self.isOn = .constant(isOn) }
    init(isOn: Binding<Bool>) { self.isOn = isOn }

    var body: some View {
        Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
            .tint(BrimTheme.of(scheme).accent)
    }
}
