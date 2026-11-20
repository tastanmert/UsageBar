import SwiftUI

/// The confirm card in place of an account's reset line:
/// which account, which reset, each window it gives back from now to 100%, that it cannot be
/// undone. Cancel is the default and has the focus; "Use reset" is the secondary button.
struct BrimResetConfirmView: View {
    let row: BrimPanelModel.Row
    let kind: BrimPanelModel.ResetKind
    let theme: BrimTheme
    /// Every kind this account can spend now; more than one offers the choice.
    var kinds: [BrimPanelModel.ResetKind] = []
    var onChoose: (BrimPanelModel.ResetKind) -> Void = { _ in }
    var onCancel: () -> Void
    /// nil = nothing can spend the reset; the button shows disabled.
    var onUse: (() -> Void)?
    /// The percentage spelling of the panel ("%100" in Turkish).
    var format = BrimPanelModel.Format(locale: Locale(identifier: AppLocale.identifier))
    var used = false

    @FocusState private var cancelFocused: Bool
    private var words: BrimPanelText { BrimPanelText(localize: L) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: L("Use a reset on %@?"), row.name))
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if kinds.count > 1 {
                BrimSegmented(options: kinds.map { ($0, words.kindName($0)) },
                              selection: Binding(get: { kind }, set: { onChoose($0) }))
                    .padding(.top, 8)
            } else {
                Text(words.kindName(kind)).font(.system(size: 12)).foregroundStyle(theme.text2)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(BrimPanelModel.resetEffects(row, kind: kind).enumerated()), id: \.offset) { _, effect in
                    change(words.window(effect.window), effect.before)
                }
            }
            .font(.system(size: 12))
            .padding(.top, 8)
            Text(L("Can't be undone."))
                .font(.system(size: 12)).foregroundStyle(theme.text2)
                .padding(.top, 6)
            HStack(spacing: 6) {
                Spacer()
                Button(L("Reset now")) { onUse?() }
                    .buttonStyle(BrimOutlineButtonStyle(theme: theme, ink: theme.critical))
                    .disabled(onUse == nil)
                Button(L("Cancel"), action: onCancel)
                    .buttonStyle(BrimFilledButtonStyle(theme: theme))
                    .keyboardShortcut(.defaultAction)
                    .focused($cancelFocused)
            }
            .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.hairline))
        .onAppear { cancelFocused = true }
    }

    /// "5 hours %12 → %100".
    private func change(_ label: String, _ cell: BrimPanelModel.Cell) -> some View {
        (Text(label).foregroundColor(theme.text2) + Text(verbatim: " ")
            + Text(cell.displayed(used: used, format: format).percentText).foregroundColor(theme.ink(cell.level))
            + Text(verbatim: " → ") + Text(verbatim: format.percent(used ? 0 : 100)).foregroundColor(theme.accent).fontWeight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BrimLinkButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

struct BrimOutlineButtonStyle: ButtonStyle {
    let theme: BrimTheme
    let ink: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled ? ink : theme.text3)
            .padding(.horizontal, 9).padding(.vertical, 2)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(enabled ? ink : theme.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct BrimFilledButtonStyle: ButtonStyle {
    let theme: BrimTheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.surface)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// The design's segmented control: a muted track, the chosen segment on a raised surface. Drawn
/// here so the system accent colour never paints it.
struct BrimSegmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let theme = BrimTheme.of(scheme)
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let (value, title) = options[index]
                let selected = value == selection
                Button { selection = value } label: {
                    Text(title)
                        .font(.system(size: 12, weight: selected ? .medium : .regular))
                        .foregroundStyle(!enabled ? theme.text3 : selected ? theme.text : theme.text2)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).frame(height: 22)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 5).fill(scheme == .dark ? theme.mutedFill : theme.surface)
                                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.12), radius: 0.5, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.hairline))
    }
}

/// The card column choice: Automatic, 1, 2, 3, 4, each with a small drawing of its columns (the
/// panel's view menu and Settings > General).
struct BrimColumnPicker: View {
    @Binding var selection: BrimPanelLayout.Columns
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    static func title(_ columns: BrimPanelLayout.Columns) -> String {
        columns == .auto ? L("Automatic") : columns.rawValue
    }

    var body: some View {
        let theme = BrimTheme.of(scheme)
        HStack(spacing: 2) {
            ForEach(BrimPanelLayout.Columns.allCases, id: \.self) { option in
                let selected = option == selection
                let ink = !enabled ? theme.text3 : selected ? theme.accent : theme.text2
                Button { selection = option } label: {
                    VStack(spacing: 4) {
                        drawing(option, ink: ink)
                        Text(Self.title(option))
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(ink)
                    .frame(minWidth: 40)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(selected && enabled ? theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected && enabled ? theme.accent : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.title(option))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// Automatic: a wide and a narrow block; n: n equal blocks.
    private func drawing(_ option: BrimPanelLayout.Columns, ink: Color) -> some View {
        let widths: [CGFloat] = switch option {
        case .auto: [13, 9]
        case .one: [26]
        case .two: [12, 12]
        case .three: [7.3, 7.3, 7.3]
        case .four: [5, 5, 5, 5]
        }
        return HStack(spacing: 2) {
            ForEach(widths.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.85))
                    .frame(width: widths[index], height: option == .auto && index == 1 ? 9 : 13)
            }
        }
        .frame(width: 28, height: 14)
    }
}

/// The panel's view menu: list or cards, the card columns, compact or detailed, grouping.
struct BrimLayoutMenu: View {
    @Binding var layout: BrimPanelLayout
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = BrimTheme.of(scheme)
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Panel layout")).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.text2)
            BrimSegmented(options: [(BrimPanelLayout.Arrangement.list, L("List")), (.cards, L("Card"))],
                          selection: $layout.arrangement)
            BrimColumnPicker(selection: $layout.columns)
                .disabled(layout.arrangement != .cards)
            Text(L("Density")).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.text2)
                .padding(.top, 2)
            BrimSegmented(options: [(BrimPanelLayout.Density.compact, L("Compact")), (.detailed, L("Detailed"))],
                          selection: $layout.density)
            Rectangle().fill(theme.hairline).frame(height: 1).padding(.vertical, 2)
            Toggle(isOn: $layout.groupByProvider) {
                Text(L("Group by provider")).font(.system(size: 13)).foregroundStyle(theme.text)
            }
            .toggleStyle(.checkbox)
            .tint(theme.accent)
        }
        .padding(14)
        .fixedSize()
    }
}
