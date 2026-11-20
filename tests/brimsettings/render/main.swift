import AppKit
import SwiftUI

// Renders the UsageBar settings window's tabs from fixtures to PNGs, light and dark, English and
// Turkish. Usage: render <output directory>. Never reads user data; never launches the app.

/// The app localizes through AppLocale; the renderer looks keys up in the catalog itself.
nonisolated(unsafe) var renderLanguage = "en"
nonisolated(unsafe) var catalog: [String: [String: String]] = [:]
nonisolated(unsafe) var missing = Set<String>()
/// The confirm card reads the app's language for its percentages; the renderer's is `renderLanguage`.
enum AppLocale { static var identifier: String { renderLanguage } }

func L(_ key: String) -> String {
    guard renderLanguage != "en" else { return key }
    guard let value = catalog[key]?[renderLanguage] else {
        missing.insert(key)
        return key
    }
    return value
}

func loadCatalog() {
    let url = URL(fileURLWithPath: "UsageBar/Resources/Localizable.xcstrings")
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = root["strings"] as? [String: [String: Any]] else { fatalError("catalog unreadable") }
    for (key, entry) in strings {
        let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
        for (language, unit) in localizations {
            if let value = (unit["stringUnit"] as? [String: Any])?["value"] as? String {
                catalog[key, default: [:]][language] = value
            }
        }
    }
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".brimbar-work/settings-shots",
                 isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Draws switches and segments as they look in a window in front.
final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc func _hasActiveControls() -> Bool { true }
    @objc func _hasKeyAppearance() -> Bool { true }
    @objc func hasKeyAppearance() -> Bool { true }
}

@MainActor
func render<V: View>(_ view: V, dark: Bool, name: String) {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
    host.appearance = appearance
    let size = host.fittingSize
    host.frame = NSRect(origin: .zero, size: size)
    let window = KeyWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    for _ in 0..<3 { RunLoop.current.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded() }
    let final = host.fittingSize
    if final != host.frame.size {
        host.frame = NSRect(origin: .zero, size: final)
        window.setContentSize(final)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("no bitmap") }
    host.cacheDisplay(in: host.bounds, to: rep)
    let url = outDir.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path) \(Int(final.width))x\(Int(final.height))")
}

/// The window as it comes up: a stand-in title bar (traffic lights, the tab's name), the tabs, the pane.
struct SettingsShot: View {
    let tab: BrimSettingsTab
    let data: BrimSettingsData
    @State var text: BrimMenuBarText = .percent
    @State var displayMode: DisplayMode = .remaining
    @State var menuSelection = BrimMenuSelection()
    @State var appearance: BrimAppearance = .system
    @State var language = ""
    @State var layout = BrimPanelLayout()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = BrimTheme.of(scheme)
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(theme.text.opacity(0.18)).frame(width: 12, height: 12) }
                    Spacer()
                }
                .padding(.leading, 14)
                Text(tab.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text)
            }
            .frame(height: 28)
            .background(theme.surface2)
            BrimSettingsTabBar(selection: .constant(tab))
            BrimSettingsPane(tab: tab, data: data,
                             bindings: BrimSettingsBindings(menuBarText: $text, appearance: $appearance, panelLayout: $layout,
                                                            language: $language, displayMode: $displayMode, menuSelection: $menuSelection))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: BrimSettingsMetrics.windowWidth)
        .background(theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.hairline))
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    loadCatalog()
    typealias F = BrimSettingsFixtures
    let now = BrimFixtures.now
    let taskL = CommandLine.arguments.contains("--task-l-only")
    let snapshot = taskL ? BrimFixtures.refreshFailure() : BrimFixtures.normal()
    let probe = F.probe(F.usageBarInstalled)
    // Times in the shot's language, as the app formats them (BrimPanelHost.format).
    func data(_ language: String) -> BrimSettingsData {
        let format = BrimPanelModel.Format(timeZone: TimeZone(identifier: "UTC")!,
                                           locale: Locale(identifier: language == "en" ? "en_US_POSIX" : language))
        return BrimSettingsData(
            panel: BrimPanelModel.make(snapshot: snapshot, readFailed: false, loaded: true, now: now,
                                       claudeResets: BrimFixtures.claudeResets, format: format),
            snapshot: snapshot, now: now, format: format,
            accounts: BrimAccountsTable.make(snapshot: snapshot, folders: F.folders, home: F.home, probe: probe),
            integrations: BrimIntegrationsReport.detect(home: F.home, claudeHomes: F.claudeHomes,
                                                        codexHomes: F.codexHomes, probe: probe),
            version: "0.1.0 (1)")
    }
    for language in (taskL ? ["tr"] : ["en", "tr"]) {
        renderLanguage = language
        for tab in (taskL ? [.accounts] : BrimSettingsTab.allCases) {
            for dark in [false, true] {
                render(SettingsShot(tab: tab, data: data(language)), dark: dark,
                       name: "settings-\(tab.rawValue)-\(dark ? "dark" : "light")-\(language).png")
            }
        }
    }
    if taskL { exit(missing.isEmpty ? 0 : 1) }
    renderLanguage = "tr"
    var selection = BrimMenuSelection()
    for row in data("tr").panel.groups.flatMap(\.rows) {
        selection.set(row.id, .fiveHour, enabled: true)
        selection.set(row.id, .weekly, enabled: true)
        if row.model != nil { selection.set(row.id, .fable, enabled: true) }
    }
    selection.showLabels = true
    for dark in [false, true] {
        render(SettingsShot(tab: .general, data: data("tr"), text: .selected,
                            displayMode: .used, menuSelection: selection), dark: dark,
               name: "settings-selected-used-\(dark ? "dark" : "light")-tr.png")
    }
    render(SettingsShot(tab: .general, data: data("tr"), text: .selected), dark: false,
           name: "settings-selected-empty-light-tr.png")
    if !missing.isEmpty {
        print("MISSING Turkish: " + missing.sorted().joined(separator: " | "))
        exit(1)
    }
}
