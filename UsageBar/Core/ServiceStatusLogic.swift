import Foundation

/// The providers' public status pages (Atlassian Statuspage's `/api/v2/status.json`, which both
/// status.claude.com and status.openai.com serve). Foundation only: the parse and the rule for
/// when an incident is news are tested standalone (tests/run-servicestatus-tests.sh).
enum ServiceStatusLogic {
    struct Page: Sendable {
        var providerID: String
        var name: String
        var api: URL
        var site: URL
    }

    static let pages: [Page] = [
        Page(providerID: "claude", name: "Claude",
             api: URL(string: "https://status.claude.com/api/v2/status.json")!,
             site: URL(string: "https://status.claude.com")!),
        Page(providerID: "codex", name: "OpenAI",
             api: URL(string: "https://status.openai.com/api/v2/status.json")!,
             site: URL(string: "https://status.openai.com")!),
    ]

    /// Statuspage's indicator, in its own words.
    enum Indicator: String, Codable, Sendable, Comparable {
        case none, maintenance, minor, major, critical

        var isIncident: Bool { self != .none }

        private var rank: Int {
            switch self {
            case .none: 0
            case .maintenance: 1
            case .minor: 2
            case .major: 3
            case .critical: 4
            }
        }

        static func < (lhs: Indicator, rhs: Indicator) -> Bool { lhs.rank < rhs.rank }
    }

    struct Reading: Equatable, Sendable {
        var indicator: Indicator
        /// The page's own sentence ("Partially Degraded Service"), English only.
        var description: String
        var readAt: Date
    }

    /// nil for anything that is not a status document: a failed read is not "operational".
    static func parse(_ data: Data, now: Date) -> Reading? {
        struct Document: Decodable {
            struct Status: Decodable { var indicator: String; var description: String? }
            var status: Status
        }
        guard let document = try? JSONDecoder().decode(Document.self, from: data) else { return nil }
        // An indicator this code does not know is still an incident of some kind.
        let indicator = Indicator(rawValue: document.status.indicator.lowercased()) ?? .minor
        return Reading(indicator: indicator, description: document.status.description ?? "", readAt: now)
    }

    /// A reading older than this is not shown: the page could have recovered since.
    static let maxAge: TimeInterval = 30 * 60

    static func shown(_ reading: Reading?, now: Date) -> Reading? {
        guard let reading, reading.indicator.isIncident, now.timeIntervalSince(reading.readAt) <= maxAge
        else { return nil }
        return reading
    }

    /// What has been announced for one page, persisted so a relaunch during an incident does not
    /// announce it again.
    struct Announced: Codable, Equatable {
        var indicator: Indicator
        var at: Date
    }

    /// The same incident is not announced again within this long.
    static let quiet: TimeInterval = 6 * 3_600

    /// Whether this reading is news: an incident (maintenance is not), first seen or worse than the
    /// one announced, or the announced one is old enough to say again. A recovery clears the memory
    /// so the next incident speaks.
    static func announce(_ reading: Reading, last: Announced?) -> (notify: Bool, next: Announced?) {
        guard reading.indicator.isIncident else { return (false, nil) }
        guard reading.indicator != .maintenance else { return (false, last) }
        if let last, reading.indicator <= last.indicator, reading.readAt.timeIntervalSince(last.at) < quiet {
            return (false, last)
        }
        return (true, Announced(indicator: reading.indicator, at: reading.readAt))
    }
}
