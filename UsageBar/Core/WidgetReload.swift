import Foundation
import WidgetKit

/// Tells WidgetKit the snapshot changed, at most once every five minutes: the widget's own timeline
/// reloads on that beat anyway, and every request counts against the system's budget for it.
@MainActor
enum WidgetReload {
    private static var last: Date?
    static let minimumGap: TimeInterval = 5 * 60

    static func snapshotWritten(now: Date = Date()) {
        if let last, now.timeIntervalSince(last) < minimumGap { return }
        last = now
        WidgetCenter.shared.reloadAllTimelines()
    }
}
