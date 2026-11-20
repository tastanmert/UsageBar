import CoreGraphics

/// How the panel lays the accounts out: a list or cards, the card columns, the density and
/// whether providers get their own section. Chosen in the panel's view menu and in Settings >
/// General; stored in UsageBar's own defaults (`BrimSettingsPrefs`). Pure, so tests/brimpanel pins
/// the column rule and the widths.
struct BrimPanelLayout: Equatable {
    enum Arrangement: String, CaseIterable { case list, cards }
    enum Columns: String, CaseIterable { case auto, one = "1", two = "2", three = "3", four = "4" }
    enum Density: String, CaseIterable { case compact, detailed }

    var arrangement: Arrangement = .cards
    var columns: Columns = .auto
    var density: Density = .detailed
    var groupByProvider = true

    enum Key {
        static let arrangement = "brimPanelArrangement"
        static let columns = "brimPanelColumns"
        static let density = "brimPanelDensity"
        static let groupByProvider = "brimPanelGroupByProvider"
    }

    /// Reads the stored choices through `value` (a defaults lookup); anything missing or unknown
    /// keeps its default.
    static func load(_ value: (String) -> Any?) -> BrimPanelLayout {
        var layout = BrimPanelLayout()
        if let raw = value(Key.arrangement) as? String, let v = Arrangement(rawValue: raw) { layout.arrangement = v }
        if let raw = value(Key.columns) as? String, let v = Columns(rawValue: raw) { layout.columns = v }
        if let raw = value(Key.density) as? String, let v = Density(rawValue: raw) { layout.density = v }
        if let v = value(Key.groupByProvider) as? Bool { layout.groupByProvider = v }
        return layout
    }

    /// What `load` reads back.
    var stored: [String: Any] {
        [Key.arrangement: arrangement.rawValue, Key.columns: columns.rawValue, Key.density: density.rawValue,
         Key.groupByProvider: groupByProvider]
    }

    // MARK: Columns and width

    static let listWidth: CGFloat = 500
    static let singleCardWidth: CGFloat = 400
    static let cardWidth: CGFloat = 300
    static let cardGap: CGFloat = 12
    static let edge: CGFloat = 16

    /// Automatic: one column for one or two accounts, two up to six, three beyond.
    static func autoColumns(accounts: Int) -> Int {
        accounts <= 2 ? 1 : accounts <= 6 ? 2 : 3
    }

    /// The panel's width with `columns` card columns.
    static func width(columns: Int) -> CGFloat {
        columns <= 1 ? singleCardWidth : 2 * edge + CGFloat(columns) * cardWidth + CGFloat(columns - 1) * cardGap
    }

    /// The card columns actually drawn: the choice (or the automatic rule), cut down until the
    /// panel fits `screenWidth` (nil leaves it). Always 1 in the list.
    func columnCount(accounts: Int, screenWidth: CGFloat?) -> Int {
        guard arrangement == .cards else { return 1 }
        var count: Int = switch columns {
        case .auto: Self.autoColumns(accounts: accounts)
        case .one: 1
        case .two: 2
        case .three: 3
        case .four: 4
        }
        if let screenWidth {
            while count > 1, Self.width(columns: count) > screenWidth - 24 { count -= 1 }
        }
        return count
    }

    func panelWidth(accounts: Int, screenWidth: CGFloat?) -> CGFloat {
        arrangement == .list ? Self.listWidth : Self.width(columns: columnCount(accounts: accounts, screenWidth: screenWidth))
    }
}
