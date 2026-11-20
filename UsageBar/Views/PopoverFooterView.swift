import SwiftUI
import AppKit

/// The footer strip, split out of PopoverRootView for file size: the used/left toggle, the reload,
/// view options, pin, window and settings buttons, then the help button set apart at the trailing
/// end. What the
/// surface SHOWS is switched in the header, not here: this row is the view controls, and mixing
/// "which screen" into it made the one action here hard to find.

/// The measured widths of the footer's two rigid clusters.
struct FooterWidths: Equatable {
    var picker: CGFloat = 0
    var icons: CGFloat = 0
}

extension PopoverRootView {
    /// The break before the help button, on top of the stack's own spacing. Small enough that help
    /// still reads as part of the footer, wide enough that it is plainly not the sixth view control.
    private static let helpLead: CGFloat = 10

    var footer: some View {
        HStack(spacing: 0) {
            // A segmented control, not a switch: both states are valid views (nothing is "off"), and
            // showing both labels at once means the current mode and the alternative are always legible.
            // Used before Left, mirroring the meters' geometry: the used portion fills from the
            // track's left edge and the remainder hugs the right, so the toggle order matches
            // where each quantity lives in the bar.
            if UsageLayout.active == nil {
                NeutralSegmentedPicker(selection: $settings.displayMode,
                                       options: [.used, .remaining],
                                       size: .small) { $0 == .used ? L("Used") : L("Left") }
                    .usageBarTooltip(L("Meters show"))
                    .background { widthProbe { footerWidths.picker = $0 } }
            }
            Spacer(minLength: 12)
            footerIcons
        }
        .padding(.horizontal, bar ? 8 : 12)
        .padding(.vertical, 4)
        // The Detailed panel sets the footer on a rounded bar of its own, and the Compact one keeps
        // the plain strip under a divider. The modifiers stay on the same row either way, only their
        // values change: a branch here would rebuild the row when the density flips, and the View
        // options button's popover closes when its presenter is rebuilt (see `footer` above).
        .background {
            if bar {
                RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous).fill(PanelStyle.footerFill)
                RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                    .strokeBorder(PanelStyle.footerEdge, lineWidth: 1)
            }
        }
        .padding(.horizontal, bar ? PanelMetrics.bodyPadH : 0)
        .padding(.top, bar ? PanelMetrics.cardGap : 0)
        .padding(.bottom, bar ? 8 : 0)
    }

    /// Whether the footer is the Detailed panel's rounded bar.
    private var bar: Bool { settings.panelDensity == .list }

    /// The trailing cluster, one view so it can be measured as one. Its buttons sit 6pt apart, as the
    /// draft has them (the round buttons are 28pt, so the stack default's 8pt crowded the icons
    /// too wide at the Detailed panel's width).
    private var footerIcons: some View {
        HStack(spacing: 6) {
            // Footer icons are one muted set (secondary); only the pin lights up (accent) when active,
            // so an unpinned pin doesn't read as already-on.
            // First in the group because it is the only ACTION here: everything after it changes
            // what this window shows, and an action reads wrong buried among view toggles. The
            // glyph is deliberately not a plain circular arrow - that is the header's quota
            // refresh, and two circular arrows on one surface would read as the same control.
            // Two arrows closing a loop: at the footer's 13pt a single circular arrow is the
            // header's quota refresh and a gear-in-loop turns to mush, while this reads as
            // "cycle it" at size (rendered and compared at 13pt before choosing).
            // Never disabled on a live count: nothing tells SwiftUI that a session started or ended,
            // so a rendered zero would leave the icon dead for the life of the window. The press
            // reads the count fresh and says so (see ReloadAction.presentConfirm).
            Button {
                ReloadAction.presentConfirm()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .frame(width: 28, height: 28)
                    .panelChip()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(PanelStyle.chipInk)
            .usageBarTooltip(ReloadAction.tooltip(ReloadReadinessStore.shared.readiness))
            // View options: every layout dimension behind one footer icon. A popover card rather
            // than a native menu, because the column count is now a row of layout tiles - a picture
            // of each layout beats five numbers, and a menu can only list text. The keyboard and
            // VoiceOver affordances a menu would have brought for free are carried by the tiles'
            // own help / accessibility labels instead.
            Button {
                showViewOptions.toggle()
            } label: {
                Image(systemName: "rectangle.split.3x1")
                    .font(.callout)
                    .frame(width: 28, height: 28)
                    .panelChip()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(showViewOptions ? Color.accentColor : PanelStyle.chipInk)
            .usageBarTooltip(L("View options"))
            // WHERE THE CARD STANDS, on the surfaces that place it themselves: this button's own
            // rectangle on screen, read when the card opens and read again at every press while it
            // is up (`ViewOptionsAnchor`). Harmless on the popover, which uses neither.
            .viewOptionsAnchor(viewOptionsAnchor)
            // The card carries its own callout layer, whichever way it is presented: it is a
            // separate presentation, so the layout tiles inside read "hosted" and skip the
            // system-tooltip fallback, while their preference never travels back OUT to the panel's
            // layer - the hover was answered with nothing at all. One layer per presentation is what
            // closes that (see `UsageBarTooltip`).
            //
            // ATTACHED ONLY WHERE IT HAS TO BE. On the popover the card is AppKit's popover, hung
            // off this button; on the two surfaces that own a frame it is a window placed in screen
            // space, because those resize under it and an attached card travels with the footer
            // (`SurfaceHost.detachesViewOptionsCard` says which is which, and why).
            .popover(isPresented: Binding(get: { showViewOptions && !host.detachesViewOptionsCard },
                                          set: { showViewOptions = $0 }),
                     arrowEdge: .bottom) {
                viewOptions.usageBarTooltipLayer()
            }
            .onChange(of: showViewOptions) { _, open in
                guard host.detachesViewOptionsCard else { return }
                guard open else {
                    ViewOptionsCard.shared.dismiss(host: host)
                    return
                }
                ViewOptionsCard.shared.present(
                    host: host, anchor: viewOptionsAnchor,
                    // Rebuilt on every pass of the card's own body, so the controls in it that
                    // change what the card shows (density changes the column tiles, the gauge switch
                    // greys the rows under it) are read again rather than frozen at opening.
                    content: { AnyView(viewOptions.usageBarTooltipLayer()) },
                    // The card can go without this button being pressed - a press anywhere else,
                    // Escape - and the button has to stop reading as lit when it does.
                    onDismiss: { showViewOptions = false })
            }
            Button {
                StatusItemController.togglePin()
            } label: {
                Image(systemName: settings.isUsagePanelPinned ? "pin.fill" : "pin")
                    .font(.callout)
                    .frame(width: 28, height: 28)
                    .panelChip()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(settings.isUsagePanelPinned ? Color.accentColor : PanelStyle.chipInk)
            .usageBarTooltip(settings.isUsagePanelPinned ? L("Unpin window") : L("Pin on top"))
            Button {
                MainWindowController.shared.show()
            } label: {
                Image(systemName: "macwindow")
                    .font(.callout)
                    .frame(width: 28, height: 28)
                    .panelChip()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(PanelStyle.chipInk)
            .usageBarTooltip(L("Open UsageBar"))
            Button {
                StatusItemController.openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .frame(width: 28, height: 28)
                    .panelChip()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(PanelStyle.chipInk)
            .usageBarTooltip(L("Settings…"))
            // Help sits past the trailing end of the group, with a gap wide enough to read as a
            // break rather than as loose tracking. It is the one control here that acts on nothing
            // in this window, and macOS parks the help button in the bottom trailing corner away
            // from the other controls for exactly that reason. Between the view toggles it read as
            // one of them.
            Button {
                showLaunchHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.callout)
                    .frame(width: 28, height: 28)
                    .panelChip()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(PanelStyle.chipInk)
            .usageBarTooltip(L("Help"))
            // Its own layer too, for the same reason as the view-options card above: the copy chips
            // inside it are hover targets, and a presentation cannot publish into the layer outside it.
            .popover(isPresented: $showLaunchHelp, arrowEdge: .bottom) {
                launchHelp.usageBarTooltipLayer()
            }
            .padding(.leading, Self.helpLead)
        }
        .background { widthProbe { footerWidths.icons = $0 } }
    }

    /// The view-options card, in the cards' own spacing vocabulary: the layout tiles first (the
    /// dimension people come here to change), then the two switches that decide what is on the
    /// panel at all, then what the gauges render. Same order and same words as the Settings pane's
    /// display rows, so neither surface teaches a vocabulary the other contradicts.
    var viewOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: UsageBarMetrics.headerToCard) {
                Text(L("Layout")).font(.caption).foregroundStyle(.secondary)
                // THE PAGE IN FRONT OF THE USER IS THE PAGE THIS EDITS. The session board has its
                // own count, spent on the width its CARDS are laid out at rather than on the
                // surface, which is one width whichever page is up (`sessionsBoardWidth`,
                // `PopoverRootView.popoverWidth`); and density is not a word
                // it speaks at all - a card or a row is what an ACCOUNT is drawn as - so offering
                // that switch here would be a control that changes nothing on screen.
                if tab == .sessions {
                    LayoutColumnPicker(selection: $settings.sessionsColumns,
                                       maxColumns: SettingsStore.maxSessionsColumns,
                                       atMost: true)
                    // WHY A NUMBER HERE IS A MAXIMUM, said on the card rather than left to be
                    // discovered: this board lives in a width the Usage pages decide, so a panel one
                    // comfortable row wide lays out one column whatever is picked. The tiles all
                    // stay selectable - a preference is kept even where today's width cannot show it
                    // off, and it takes effect the moment the panel is wider - and this line is what
                    // keeps that from reading as a control that did nothing (Albert, 2026-08-18).
                    Text(L("Panel width follows the Usage pages. Auto takes the columns that fit when the board is opened, and a number is the most it will use."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Density first, then the count: what each element IS comes before how many of
                    // them fit. The footer's own used/left switch is this control, so the card
                    // offers one vocabulary for "pick one of two views" rather than a second
                    // hand-rolled one.
                    NeutralSegmentedPicker(selection: $settings.panelDensity,
                                           options: PanelDensity.allCases,
                                           size: .small) { $0 == .cards ? L("Compact") : L("Detailed") }
                    // One picker, two remembered numbers: it edits the count of whichever density is
                    // on screen (`densityColumns`), so switching density restores that density's own
                    // layout instead of carrying a number chosen for the other one.
                    LayoutColumnPicker(selection: $settings.densityColumns,
                                       maxColumns: settings.densityMaxColumns)
                }
            }
            Divider()
            // The two strips' own switches, the same ones the Settings pane carries: they decide
            // whether the gauge and the advisor are on the panel at all, which is the question that
            // comes before how the gauges are drawn. Reaching Settings to turn a strip off was the
            // one layout decision this card could not make.
            Toggle(L("Fleet gauge"), isOn: $settings.showFleetGauge)
            Toggle(L("Usage advisor"), isOn: $settings.showAdvisor)
            Toggle(L("Group by provider"), isOn: $settings.groupByProvider)
            // "Gauges only" is the one-click version of collapsing every pooled provider; clicking
            // a single gauge row stays the granular tool.
            Toggle(L("Gauges only"), isOn: Binding(
                get: { isGaugesOnly },
                set: { on in
                    let pooled = pooledProviderIDs
                    if on { settings.collapsedProviders.formUnion(pooled) }
                    else { settings.collapsedProviders.subtract(pooled) }
                }
            ))
            // Folding cards behind a gauge that is switched off would hide them behind nothing at
            // all, which is the one state the panel must never reach (see `visibleAccounts`).
            .disabled(pooledProviderIDs.isEmpty || !settings.showFleetGauge)
            Divider()
            // What the gauges render: every pooled window, one row each (5-hour, weekly,
            // each model window; the default), or collapsed to a single pool for people who only
            // ration one budget. The menu-bar number follows the leading pool.
            VStack(alignment: .leading, spacing: UsageBarMetrics.headerToCard) {
                Text(L("Gauges show")).font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $settings.gaugeFocus) {
                    Text(L("All pools")).tag(GaugeFocus.all)
                    Text(L("Primary model only")).tag(GaugeFocus.primary)
                    Text(L("Weekly total only")).tag(GaugeFocus.weekly)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            // Nothing to configure while there is no gauge to configure. Greyed rather than hidden,
            // so the card does not change height under the pointer when the switch above is flipped.
            .disabled(!settings.showFleetGauge)
            .opacity(settings.showFleetGauge ? 1 : 0.5)
        }
        .padding(UsageBarMetrics.cardPaddingH)
        .frame(width: 268)
    }
}
