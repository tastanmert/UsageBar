import SwiftUI
import WidgetKit

/// The desktop widget: the accounts' 5-hour and weekly windows from the snapshot the app writes.
/// It reads one file and draws it; the app asks WidgetKit to reload when the file changes.
@main
struct UsageBarWidgets: WidgetBundle {
    var body: some Widget { UsageBarAccountsWidget() }
}

struct UsageBarAccountsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UsageBarAccounts", provider: SnapshotTimeline()) { entry in
            AccountsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("UsageBar")
        .description(String(localized: "The 5-hour and weekly windows of your accounts."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SnapshotEntry: TimelineEntry {
    var date: Date
    /// nil: no snapshot to read (UsageBar never ran, or the file could not be read).
    var snapshot: WidgetSnapshot?
}

struct SnapshotTimeline: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let read = WidgetSnapshot.read()
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? (read ?? .sample) : read))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let entry = SnapshotEntry(date: now, snapshot: WidgetSnapshot.read())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(5 * 60))))
    }
}

/// The part of ~/.usagebar/snapshot.json the widget draws (UsageSnapshot in the app is the writer).
struct WidgetSnapshot: Decodable {
    struct Account: Decodable, Identifiable {
        var id: String
        var label: String
        var provider: String
        var sessionRemaining: Double?
        var sessionResetsAt: Date?
        var weeklyRemaining: Double?
        var weeklyResetsAt: Date?
    }
    var generatedAt: Date?
    var displayMode: String?
    var accounts: [Account]
    var accountOrder: [String]?

    var used: Bool { displayMode == "used" }

    /// The panel's order.
    var ordered: [Account] {
        guard let order = accountOrder else { return accounts }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return accounts.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
    }

    static func read() -> WidgetSnapshot? {
        // The sandbox's own home is a container; the snapshot is under the user's real one.
        guard let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir else { return nil }
        let url = URL(fileURLWithPath: String(cString: home)).appendingPathComponent(".usagebar/snapshot.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static let sample = WidgetSnapshot(
        generatedAt: Date(), displayMode: "remaining",
        accounts: [
            Account(id: "a", label: "Claude", provider: "claude", sessionRemaining: 72,
                    sessionResetsAt: Date().addingTimeInterval(5_400), weeklyRemaining: 64, weeklyResetsAt: nil),
            Account(id: "b", label: "Claude 2", provider: "claude", sessionRemaining: 18,
                    sessionResetsAt: Date().addingTimeInterval(2_400), weeklyRemaining: 41, weeklyResetsAt: nil),
            Account(id: "c", label: "Codex", provider: "codex", sessionRemaining: 95,
                    sessionResetsAt: nil, weeklyRemaining: 88, weeklyResetsAt: nil),
        ],
        accountOrder: nil)
}
