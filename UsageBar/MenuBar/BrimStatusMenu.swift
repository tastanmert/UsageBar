import AppKit

/// UsageBar's status item: the two-bar glyph with the displayed windows' remaining quota, and the
/// native menu on right-, control- or option-click (design: MenuBar.png, MenuNative.png).
/// Everything comes from `BrimPanelModel`, the same reading the panel shows.
extension StatusItemController {
    /// Draws the mark and its figure. Returns without touching the button when nothing changed.
    func applyBrimFace(to button: NSStatusBarButton) {
        let model = BrimPanelHost.model()
        let prefs = BrimSettingsPrefs.shared
        let rows = model.groups.flatMap(\.rows)
        if model.body == .accounts || model.body == .noAccounts {
            let pruned = prefs.menuSelection.pruned(rows: rows)
            if pruned != prefs.menuSelection { prefs.menuSelection = pruned }
        }
        let segments = prefs.menuBarText == .selected
            ? prefs.menuSelection.segments(rows: rows, used: prefs.displayMode == .used, format: BrimPanelHost.format) : []
        let tooltip = Self.brimTooltip(model) + (segments.isEmpty ? "" : "\n" + segments.map { segment in
            (rows.first { $0.id == segment.id }?.name ?? segment.id) + ": "
                + segment.parts.map { $0.window.tag + " " + $0.value }.joined(separator: " · ")
        }.joined(separator: "\n"))
        let glyph = BrimSettingsPrefs.menuBarGlyph(for: model)
        let style = BrimMenuStrip.Style(showWindowTags: prefs.menuSelection.showWindowTags,
                                        monochrome: BrimMenuStrip.currentMonochrome)
        let face = BrimFace(glyph: glyph, tooltip: tooltip, segments: segments, style: style)
        if !BrimMenuBarText.showsCup(prefs.menuBarText, segments: segments) {
            guard face != Self.lastBrimFace else { return }
            Self.lastBrimFace = face
            button.image = BrimMenuStrip.image(segments, style: style)
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
            button.toolTip = tooltip
            button.setAccessibilityLabel(tooltip)
            return
        }
        guard face != Self.lastBrimFace else { return }
        Self.lastBrimFace = face
        button.image = BrimCup.templateImage(glyph)
        if let text = glyph.text {
            button.attributedTitle = NSAttributedString(string: " " + text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            ])
            button.imagePosition = .imageLeading
        } else {
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
        }
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
    }

    private struct BrimFace: Equatable {
        var glyph: BrimPanelModel.Glyph
        var tooltip: String
        var segments: [BrimMenuSelection.Segment]
        var style: BrimMenuStrip.Style
    }

    private static var lastBrimFace: BrimFace?

    private static func brimTooltip(_ model: BrimPanelModel) -> String {
        var lines = ["UsageBar", L(BrimSettingsPrefs.shared.displayMode == .used ? "Used" : "Remaining")]
        switch model.banner {
        case .unavailable: lines.append(L("Usage data unavailable."))
        case .stale(let minutes): lines.append(BrimPanelText(localize: L).stale(minutes))
        case nil: break
        }
        if let tightest = model.tightest { lines.append(tightestText(tightest)) }
        return lines.joined(separator: "\n")
    }

    /// "Tightest: Work 9% · 18:46", "Limit" at a wall.
    private static func tightestText(_ t: BrimPanelModel.Tightest) -> String {
        L("Tightest:") + " " + t.accountName + " " +
            BrimPanelModel.cell(t.remaining).displayed(used: BrimSettingsPrefs.shared.displayMode == .used,
                                                      format: BrimPanelHost.format).percentText
    }

    // MARK: - Menu

    func showBrimMenu(from button: NSStatusBarButton) {
        BrimClaudeResetStore.shared.tick()
        let menu = makeBrimMenu(BrimPanelHost.model())
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    func makeBrimMenu(_ model: BrimPanelModel) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(Self.note(L(BrimSettingsPrefs.shared.displayMode == .used ? "Used" : "Remaining")))
        menu.autoenablesItems = false

        if model.banner == .unavailable {
            menu.addItem(Self.note(L("Usage data unavailable.")))
        } else if case .stale(let minutes) = model.banner {
            menu.addItem(Self.note(BrimPanelText(localize: L).stale(minutes)))
        }
        if let tightest = model.tightest {
            menu.addItem(Self.note(Self.tightestText(tightest)))
        }
        if !model.groups.isEmpty {
            menu.addItem(.separator())
            for group in model.groups { addGroup(group, to: menu) }
        }

        // One entry per reset an account holds; accounts with none, or whose count is not
        // known, are left out. With no reset anywhere the item says so and opens nothing.
        if !model.groups.isEmpty {
            menu.addItem(.separator())
            let entries = model.groups.flatMap(\.rows).flatMap { row in
                (row.resetCredits?.lines ?? []).filter { $0.count > 0 }.map { (row, $0) }
            }
            let use = NSMenuItem(title: entries.isEmpty ? L("No resets") : L("Use reset"), action: nil, keyEquivalent: "")
            if entries.isEmpty {
                use.isEnabled = false
            } else {
                let sub = NSMenu()
                sub.autoenablesItems = false
                let words = BrimPanelText(localize: L)
                for (row, line) in entries {
                    // Selecting a reset opens the panel for consent or a mode/session explanation.
                    let kind = words.shortKindName(line.kind) + (line.expiresIn.map { " · " + $0 } ?? "")
                    let item = NSMenuItem(title: row.name + " · " + kind, action: #selector(brimUseReset(_:)),
                                          keyEquivalent: "")
                    item.target = self
                    item.attributedTitle = Self.columns([row.name, kind], font: Self.rowFont, color: .labelColor)
                    item.representedObject = BrimResetMenuChoice(accountID: row.id, kind: line.kind, grantID: line.grantID)
                    item.isEnabled = line.action != .none
                    sub.addItem(item)
                }
                use.submenu = sub
            }
            if !entries.isEmpty { menu.addItem(use) }
        }

        menu.addItem(.separator())
        menu.addItem(item(L("Refresh now"), #selector(brimRefresh), key: "r"))
        menu.addItem(item(L("Settings…"), #selector(brimOpenSettings), key: ","))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        quit.keyEquivalentModifierMask = [.command]
        quit.allowsAutomaticKeyEquivalentLocalization = false
        menu.addItem(quit)
        return menu
    }

    /// Provider name followed by one account per line: its tightest window, named short, with the
    /// time until that window resets ("Main · Fable 28% · 2d 19h", name left, figure right).
    private func addGroup(_ group: BrimPanelModel.Group, to menu: NSMenu) {
        menu.addItem(Self.note(Self.providerName(group.id)))
        let words = BrimPanelText(localize: L)
        for row in group.rows {
            let figure = words.menuFigure(row, used: BrimSettingsPrefs.shared.displayMode == .used, format: BrimPanelHost.format) ?? "–"
            let entry = NSMenuItem(title: row.name, action: #selector(brimOpenPanel), keyEquivalent: "")
            entry.target = self
            entry.image = BrimProviderMark.image(row.provider)
            entry.attributedTitle = Self.columns([row.name, figure], font: Self.rowFont,
                                                 color: row.heldOver ? .secondaryLabelColor : .labelColor)
            menu.addItem(entry)
            if row.hasNoResetCredits { menu.addItem(Self.note(L("No reset credits"))) }
        }
    }

    private static var rowFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) }

    /// Name left, percentage and time together at a right-aligned tab stop.
    private static func columns(_ parts: [String], font: NSFont, color: NSColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 320)]
        var name = parts[0]
        if name.count > 24 { name = String(name.prefix(23)) + "…" }
        return NSAttributedString(string: ([name] + parts.dropFirst()).joined(separator: "\t"),
                                  attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    private static func providerName(_ id: String) -> String {
        switch id {
        case "claude": "Claude"
        case "codex": "Codex"
        default: id.capitalized
        }
    }

    private static func note(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = [.command]
        item.allowsAutomaticKeyEquivalentLocalization = false
        return item
    }

    @objc private func brimRefresh() { BrimPanelHost.refreshNow() }
    @objc private func brimOpenSettings() { StatusItemController.openSettingsWindow() }

    /// "Use reset ▸ account · kind": the panel opens with that card's confirmation showing.
    @objc private func brimUseReset(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? BrimResetMenuChoice,
              let button = statusItem?.button else { return }
        BrimResetUseStore.shared.open(accountID: choice.accountID, kind: choice.kind, grantID: choice.grantID)
        DispatchQueue.main.async { button.performClick(nil) }
    }

    /// A row in the menu opens the panel, where the account's detail is.
    @objc private func brimOpenPanel() {
        guard let button = statusItem?.button else { return }
        DispatchQueue.main.async { button.performClick(nil) }
    }
}

/// What a "Use reset" menu entry stands for.
final class BrimResetMenuChoice: NSObject {
    let accountID: String
    let kind: BrimPanelModel.ResetKind
    let grantID: String?
    init(accountID: String, kind: BrimPanelModel.ResetKind, grantID: String?) {
        self.grantID = grantID
        self.accountID = accountID
        self.kind = kind
    }
}
