import AppKit
import SwiftUI

// Renders the UsageBar panel and the menu bar glyph from fixtures to PNGs for a visual check.
// Usage: render <output directory> [--live] [--strings <dir with tr.lproj>]. Never launches the
// app and never goes to the network: `--live` reads UsageBar's snapshot file only, and the Claude
// reset rows come from fixtures (the app's own reset read is not compiled in).

/// The app localizes through AppLocale; the renderer shows the English source keys, or the
/// catalog's Turkish while `turkish` is on (the compiled `tr.lproj/Localizable.strings`).
nonisolated(unsafe) var turkish = false
let turkishStrings: [String: String] = {
    let args = CommandLine.arguments
    guard let flag = args.firstIndex(of: "--strings"), flag + 1 < args.count else { return [:] }
    let path = args[flag + 1] + "/tr.lproj/Localizable.strings"
    return (NSDictionary(contentsOfFile: path) as? [String: String]) ?? [:]
}()
func L(_ key: String) -> String { turkish ? (turkishStrings[key] ?? key) : key }
/// The confirm card reads the app's language for its percentages; the renderer's is `turkish`.
enum AppLocale { static var identifier: String { turkish ? "tr" : "en" } }

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("--")
                     ? CommandLine.arguments[1] : ".brimbar-work/phase2-shots",
                 isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let format = BrimPanelModel.Format(timeZone: TimeZone(identifier: "UTC")!)
func model(_ snapshot: UsageSnapshot?, failed: Bool = false,
           claudeResets: [String: BrimPanelModel.ClaudeResets] = [:]) -> BrimPanelModel {
    BrimPanelModel.make(snapshot: snapshot, readFailed: failed, loaded: true, now: BrimFixtures.now,
                        claudeResets: claudeResets, format: format)
}

@MainActor
func render<V: View>(_ view: V, dark: Bool, name: String, background: NSColor? = nil) {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
    host.appearance = appearance
    let size = host.fittingSize
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = host
    if let background { window.backgroundColor = background }
    host.layoutSubtreeIfNeeded()
    // Two run-loop turns so measured sizes (the scroll cap) settle before the capture.
    for _ in 0..<2 { RunLoop.current.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded() }
    let final = host.fittingSize
    if final != host.frame.size {
        host.frame = NSRect(origin: .zero, size: final)
        window.setContentSize(final)
        host.layoutSubtreeIfNeeded()
    }
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("no bitmap") }
    host.cacheDisplay(in: host.bounds, to: rep)
    let url = outDir.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path) \(Int(final.width))x\(Int(final.height))")
}

/// All glyph states at 4x and 1x, monochrome as the menu bar tints a template image.
struct GlyphSheet: View {
    @Environment(\.colorScheme) private var scheme
    let states: [(String, BrimPanelModel.Glyph)]

    var body: some View {
        let ink: Color = scheme == .dark ? .white : .black
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "UsageBar menü çubuğu, \(scheme == .dark ? "koyu" : "açık")")
                .font(.system(size: 13, weight: .semibold))
            HStack(alignment: .top, spacing: 16) {
                ForEach(states.indices, id: \.self) { index in
                    let (label, glyph) = states[index]
                    VStack(spacing: 8) {
                        Image(nsImage: BrimCup.templateImage(glyph, size: 72))
                            .renderingMode(.template).foregroundStyle(ink)
                        HStack(spacing: 4) {
                            Image(nsImage: BrimCup.templateImage(glyph))
                                .renderingMode(.template).foregroundStyle(ink)
                            if let text = glyph.text {
                                Text(verbatim: text).font(.system(size: 13)).monospacedDigit()
                            }
                        }
                        .padding(.horizontal, 6).frame(height: 22)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        Text(verbatim: label).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(width: 110)
                }
            }
        }
        .foregroundStyle(ink)
        .padding(20)
        .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
    }
}

func panel(_ model: BrimPanelModel, _ layout: BrimPanelLayout = BrimPanelLayout(), menu: Bool = false) -> BrimPanelView {
    BrimPanelView(model: model, layout: layout, maxHeight: 1400, screenWidth: 1512, showsLayoutMenu: menu)
}

try MainActor.assumeIsolated {
    _ = NSApplication.shared
    turkish = true
    if CommandLine.arguments.contains("--task-l-only") {
        for dark in [false, true] {
            render(panel(model(BrimFixtures.refreshFailure(), claudeResets: BrimFixtures.claudeResets)), dark: dark,
                   name: "refresh-failed-\(dark ? "dark" : "light").png")
        }
        exit(0)
    }
    if CommandLine.arguments.contains("--task-k-only") {
        let states: [(String, BrimPanelModel.Glyph)] = [0, 35, 70, 100].map { percent in
            ("%\(percent)", .init(kind: .normal, fill: Double(percent) / 100, dashed: false, text: nil,
                                 fiveHourFill: Double(percent) / 100, weeklyFill: Double(percent) / 100))
        } + [
            ("Haftalık bilinmiyor", .init(kind: .normal, fill: 0.68, dashed: false, text: nil,
                                         fiveHourFill: 0.68, weeklyFill: nil)),
            ("Bayat", .init(kind: .normal, fill: 0.68, dashed: true, text: nil,
                            fiveHourFill: 0.68, weeklyFill: 0.40))
        ]
        for dark in [false, true] {
            render(GlyphSheet(states: states), dark: dark,
                   name: "menubar-\(dark ? "dark" : "light").png")
            render(panel(model(BrimFixtures.normal())), dark: dark,
                   name: "panel-header-\(dark ? "dark" : "light").png")
        }
        exit(0)
    }
    var creditCards = BrimPanelModel.make(snapshot: BrimFixtures.normal(), readFailed: false, loaded: true, now: BrimFixtures.now,
                                          format: .init(locale: Locale(identifier: "tr")))
    for group in creditCards.groups.indices {
        for index in creditCards.groups[group].rows.indices {
            var row = creditCards.groups[group].rows[index]
            switch row.label {
            case "Main":
                row.credit = .init(usedCents: 541, limitCents: 2000, enabled: true, utilization: 27.05)
                row.windowSpend["five_hour"] = .init(limit: 20, used: 5.41)
                row.label = "Limitli"
            case "Work": row.credit = .init(usedCents: 541, enabled: true); row.label = "Limitsiz"
            case "Spare": row.credit = .zero; row.label = "Kapalı"
                row.promotions = [.init(amount: 7.5, currency: "EUR", expiresAt: nil, expiresIn: "12 g")]
            case "Info": row.credit = .init(usedCents: 0, enabled: true, codex: .init(balance: 12.75)); row.label = "Codex bakiye"
            default: row.credit = .init(usedCents: 2000, limitCents: 2000, enabled: false, spendLimitReached: true); row.label = "Limit doldu"
            }
            creditCards.groups[group].rows[index] = row
        }
    }
    for dark in [false, true] {
        for used in [false, true] {
            for arrangement in BrimPanelLayout.Arrangement.allCases {
                for density in BrimPanelLayout.Density.allCases {
                    let layout = BrimPanelLayout(arrangement: arrangement, density: density)
                    render(BrimPanelView(model: creditCards, layout: layout, used: used, maxHeight: 1400),
                           dark: dark,
                           name: "task-h-credit-\(arrangement.rawValue)-\(density.rawValue)-\(used ? "used" : "remaining")-\(dark ? "dark" : "light").png")
                }
            }
        }
    }
    if CommandLine.arguments.contains("--task-h-only") { exit(0) }
    turkish = false
    let normal = model(BrimFixtures.normal())
    let list = BrimPanelLayout(arrangement: .list)
    render(panel(normal), dark: false, name: "popover-light.png")
    render(panel(normal), dark: true, name: "popover-dark.png")
    render(panel(normal, list), dark: false, name: "popover-list-light.png")
    // Read failed after a good read: one line on top, last values dimmed.
    render(panel(model(BrimFixtures.normal(), failed: true)), dark: false, name: "popover-error.png")
    render(panel(model(BrimFixtures.normal(generatedMinutesAgo: 14))), dark: false, name: "popover-stale.png")
    render(panel(model(nil, failed: true)), dark: false, name: "popover-nodata.png")
    render(panel(model(BrimFixtures.noFiveHourCodex)), dark: false, name: "popover-usagebar-shape.png")

    // Claude resets read (fixture): Main holds a full and a Fable reset, Work none, Spare unknown.
    let resets = model(BrimFixtures.normal(), claudeResets: BrimFixtures.claudeResets)
    render(panel(resets), dark: false, name: "popover-claude-resets.png")
    if !turkishStrings.isEmpty {
        turkish = true
        let trFormat = BrimPanelModel.Format(timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "tr"))
        let trResets = BrimPanelModel.make(snapshot: BrimFixtures.normal(), readFailed: false, loaded: true,
                                           now: BrimFixtures.now, claudeResets: BrimFixtures.claudeResets, format: trFormat)
        render(panel(trResets), dark: true, name: "popover-claude-resets-tr-dark.png")
        render(panel(trResets), dark: false, name: "popover-claude-resets-tr-light.png")
        for dark in [false, true] {
            render(BrimPanelView(model: trResets, used: true, maxHeight: 1400), dark: dark,
                   name: "popover-used-tr-\(dark ? "dark" : "light").png")
        }
        render(panel(trResets, list), dark: true, name: "popover-claude-resets-list-tr-dark.png")

        // Confirm card with usable reset grants.
        // The live read marks Main's grants usable now (the fixture's are read-only).
        var usableResets = BrimFixtures.claudeResets
        if case .read(let grants)? = usableResets["claude:.claude"]?.state {
            usableResets["claude:.claude"] = .init(state: .read(grants.map { var g = $0; g.usable = true; return g }),
                                                   problem: nil)
        }
        func trModel() -> BrimPanelModel {
            BrimPanelModel.make(snapshot: BrimFixtures.normal(), readFailed: false, loaded: true, now: BrimFixtures.now,
                                claudeResets: usableResets, format: trFormat)
        }
        let live = trModel()
        if let row = live.groups.flatMap(\.rows).first(where: { !BrimPanelModel.usableKinds($0).isEmpty }),
           let kind = BrimPanelModel.usableKinds(row).first {
            var actions = BrimPanelActions()
            actions.openReset = { _, _, _ in }
            actions.useReset = {}
            render(BrimPanelView(model: live, layout: BrimPanelLayout(), actions: actions, maxHeight: 1400,
                                 screenWidth: 1512, prompt: (row.id, kind)),
                   dark: true, name: "live-reset-confirm-tr-dark.png")
            render(BrimPanelView(model: live, layout: BrimPanelLayout(), actions: actions, maxHeight: 1400,
                                 screenWidth: 1512),
                   dark: true, name: "live-reset-lines-tr-dark.png")
        } else {
            print("no usable reset row in the fixture")
        }
        // The status-page incident line and the copy button.
        var extras = BrimPanelActions()
        extras.copyImage = {}
        let incidents = [BrimServiceIncident(id: "claude", name: "Claude", indicator: .minor,
                                             site: URL(string: "https://status.claude.com")!)]
        for dark in [false, true] {
            render(BrimPanelView(model: live, layout: BrimPanelLayout(), actions: extras, maxHeight: 1400,
                                 screenWidth: 1512, incidents: incidents),
                   dark: dark, name: "incident-tr-\(dark ? "dark" : "light").png")
        }
        render(BrimPanelView(model: live, layout: BrimPanelLayout(), maxHeight: 1400, screenWidth: 1512,
                             snapshotMode: true),
               dark: true, name: "copy-image-tr-dark.png")
        turkish = false
    }

    let states: [(String, BrimPanelModel.Glyph)] = [
        ("Normal", model(BrimFixtures.normal()).glyph),
        ("Low (<30%)", .init(kind: .low, fill: 0.22, dashed: false, text: "22%",
                              fiveHourFill: 0.22, weeklyFill: 0.40)),
        ("Critical (<10%)", .init(kind: .critical, fill: 0.06, dashed: false, text: "6%",
                                   fiveHourFill: 0.06, weeklyFill: 0.20)),
        ("All limited", model(BrimFixtures.allLimited).glyph),
        ("Stale", model(BrimFixtures.normal(generatedMinutesAgo: 14)).glyph),
        ("Unreadable", model(nil, failed: true).glyph),
        ("No accounts", model(BrimFixtures.empty).glyph),
    ]
    let sheet = VStack(spacing: 0) {
        GlyphSheet(states: states).environment(\.colorScheme, .light)
        GlyphSheet(states: states).environment(\.colorScheme, .dark)
    }
    render(sheet, dark: false, name: "glyph-states.png")

    // `--live`: also render UsageBar's real snapshot, read-only, at the real clock, in Turkish: dark
    // and light, list and 1- and 2-column cards, compact and detailed, and the view menu open.
    if CommandLine.arguments.contains("--live") {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: Data(contentsOf: UsageSnapshot.fileURL))
        let live = BrimPanelModel.make(snapshot: snapshot, readFailed: snapshot == nil, loaded: true, now: Date())
        render(panel(live), dark: false, name: "popover-live.png")
        if !turkishStrings.isEmpty {
            turkish = true
            let trLive = BrimPanelModel.make(snapshot: snapshot, readFailed: snapshot == nil, loaded: true, now: Date(),
                                             format: BrimPanelModel.Format(locale: Locale(identifier: "tr")))
            let shapes: [(String, BrimPanelLayout.Arrangement, BrimPanelLayout.Columns)] = [
                ("list", .list, .auto), ("card1", .cards, .one), ("card2", .cards, .two),
            ]
            for dark in [true, false] {
                for (name, arrangement, columns) in shapes {
                    for density in BrimPanelLayout.Density.allCases {
                        let layout = BrimPanelLayout(arrangement: arrangement, columns: columns, density: density)
                        render(panel(trLive, layout), dark: dark,
                               name: "live-tr-\(dark ? "dark" : "light")-\(name)-\(density.rawValue).png")
                    }
                }
                render(panel(trLive, BrimPanelLayout(columns: .two), menu: true), dark: dark,
                       name: "live-tr-\(dark ? "dark" : "light")-view-menu.png")
            }
            render(panel(trLive), dark: true, name: "popover-live-tr-dark.png")
            turkish = false
        }
    }
}

// The real NSMenu builder, backed only by fixtures; no application stores are linked.
@MainActor final class StatusItemController: NSObject {
    var statusItem: NSStatusItem? = nil
    static func openSettingsWindow() {}
}
@MainActor enum BrimPanelHost {
    static func model() -> BrimPanelModel { .make(snapshot: BrimFixtures.normal(), readFailed: false,
        loaded: true, now: BrimFixtures.now, claudeResets: BrimFixtures.claudeResets, format: format) }
    static var format: BrimPanelModel.Format { .init(locale: Locale(identifier: "tr")) }
    static func refreshNow() {}
}
@MainActor final class BrimSettingsPrefs {
    static let shared = BrimSettingsPrefs()
    var displayMode: DisplayMode = .remaining
    var menuSelection = BrimMenuSelection()
    var menuBarText: BrimMenuBarText = .percent
    static func menuBarGlyph(for model: BrimPanelModel) -> BrimPanelModel.Glyph { model.glyph }
    static func menuBarText(for model: BrimPanelModel) -> String? { model.glyph.text }
}
@MainActor final class BrimClaudeResetStore {
    static let shared = BrimClaudeResetStore()
    func tick() {}
}
@MainActor final class BrimResetUseStore {
    static let shared = BrimResetUseStore()
    func open(accountID: String, kind: BrimPanelModel.ResetKind, grantID: String?) {}
}
try MainActor.assumeIsolated {
    turkish = true
    let menu = StatusItemController().makeBrimMenu(BrimPanelHost.model())
    func dump(_ menu: NSMenu, indent: String = "") -> [String] {
        menu.items.flatMap { item -> [String] in
            if item.isSeparatorItem { return [indent + "---"] }
            let title = item.attributedTitle?.string ?? item.title
            let shortcut = item.keyEquivalent.isEmpty ? "" : "  ⌘" + item.keyEquivalent.uppercased()
            return [indent + title + shortcut] + (item.submenu.map { dump($0, indent: indent + "  ") } ?? [])
        }
    }
    try! (dump(menu).joined(separator: "\n") + "\n").write(to: outDir.appendingPathComponent("rightclick-menu-tr.txt"), atomically: true, encoding: .utf8)
    // Unknown counts must not be described as zero.
    var bare = BrimPanelHost.model()
    bare.groups = bare.groups.map { group in
        var group = group
        group.rows = group.rows.map { var row = $0; row.resetCredits = nil; return row }
        return group
    }
    let bareMenu = StatusItemController().makeBrimMenu(bare)
    try! (dump(bareMenu).joined(separator: "\n") + "\n").write(
        to: outDir.appendingPathComponent("rightclick-menu-noresets-tr.txt"), atomically: true, encoding: .utf8)
    precondition(!bareMenu.items.contains { $0.title == L("No resets") || $0.title == L("No reset credits") })
    precondition(menu.items.contains { $0.title == L("No reset credits") && !$0.isEnabled })
    precondition(menu.items.first(where: { $0.keyEquivalent == "," })?.allowsAutomaticKeyEquivalentLocalization == false)
    precondition(menu.items.first(where: { $0.keyEquivalent == "," })?.keyEquivalentModifierMask == [.command])
}
