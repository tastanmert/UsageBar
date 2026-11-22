import AppKit
import Observation

/// UsageBar's own preferences from the settings window. Stored in UsageBar's defaults domain
/// (`app.usagebar.*`), never in UsageBar's, an account folder or a provider file.
@MainActor
@Observable
final class BrimSettingsPrefs {
    static let shared = BrimSettingsPrefs()

    var menuSelection: BrimMenuSelection {
        didSet {
            guard menuSelection != oldValue else { return }
            UserDefaults.standard.set(menuSelection.windows, forKey: "brimMenuWindows")
            UserDefaults.standard.set(menuSelection.showLabels, forKey: "brimMenuLabels")
            UserDefaults.standard.set(menuSelection.showWindowTags, forKey: "brimMenuWindowTags")
            UsageStore.shared.onChange?()
        }
    }

    var displayMode: DisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: "brimDisplayMode")
            UsageStore.shared.onChange?()
        }
    }

    var menuBarText: BrimMenuBarText {
        didSet {
            UserDefaults.standard.set(menuBarText.rawValue, forKey: BrimMenuBarText.defaultsKey)
            // The status item is AppKit and repaints on the store's change hook.
            UsageStore.shared.onChange?()
        }
    }

    var appearance: BrimAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: BrimAppearance.defaultsKey)
            applyAppearance()
        }
    }

    /// The panel's layout: list or cards, columns, density, grouping (view menu and General).
    var panelLayout: BrimPanelLayout {
        didSet {
            guard panelLayout != oldValue else { return }
            for (key, value) in panelLayout.stored { UserDefaults.standard.set(value, forKey: key) }
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        menuSelection = BrimMenuSelection(
            windows: defaults.dictionary(forKey: "brimMenuWindows") as? [String: [String]] ?? [:],
            showLabels: defaults.bool(forKey: "brimMenuLabels"),
            showWindowTags: defaults.object(forKey: "brimMenuWindowTags") as? Bool ?? true)
        displayMode = DisplayMode(rawValue: defaults.string(forKey: "brimDisplayMode") ?? "") ?? .remaining
        panelLayout = BrimPanelLayout.load { defaults.object(forKey: $0) }
        let savedMenuText = BrimMenuBarText(rawValue: defaults.string(forKey: BrimMenuBarText.defaultsKey) ?? "")
            ?? BrimMenuBarText.fallback
        menuBarText = savedMenuText == .countdown ? .percent : savedMenuText
        appearance = BrimAppearance(rawValue: defaults.string(forKey: BrimAppearance.defaultsKey) ?? "")
            ?? .system
    }

    /// Sets this process's appearance; nil follows the system.
    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func menuBarGlyph(for model: BrimPanelModel) -> BrimPanelModel.Glyph {
        BrimMenuBarText.face(shared.menuBarText, model: model, selection: shared.menuSelection,
                             used: shared.displayMode == .used, format: BrimPanelHost.format)
    }
}
