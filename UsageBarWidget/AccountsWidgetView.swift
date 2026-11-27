import SwiftUI
import WidgetKit

/// One row per account: the name on the left, the 5-hour and weekly figures in fixed columns, each
/// with a thin bar. Small shows two accounts, medium four, large eight.
struct AccountsWidgetView: View {
    let entry: SnapshotEntry
    /// Offscreen renders only: WidgetKit sets the family itself.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var limit: Int {
        switch family {
        case .systemSmall: 2
        case .systemMedium: 4
        default: 8
        }
    }

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.accounts.isEmpty {
            content(snapshot)
        } else {
            Text(String(localized: "Open UsageBar to see your accounts."))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        let small = family == .systemSmall
        return VStack(alignment: .leading, spacing: small ? 8 : 6) {
            HStack {
                Text(verbatim: "UsageBar").font(.caption.weight(.semibold))
                Spacer()
                if !small {
                    Text(String(localized: "5h")).frame(width: 64)
                    Text(String(localized: "Weekly")).frame(width: 64)
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
            ForEach(snapshot.ordered.prefix(limit)) { account in
                if small {
                    smallRow(account, used: snapshot.used)
                } else {
                    row(account, used: snapshot.used)
                }
            }
            Spacer(minLength: 0)
            if let generated = snapshot.generatedAt {
                Text(generated, style: .time).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ account: WidgetSnapshot.Account, used: Bool) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: account.label).font(.caption).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            meter(account.sessionRemaining, used: used).frame(width: 64)
            meter(account.weeklyRemaining, used: used).frame(width: 64)
        }
    }

    private func smallRow(_ account: WidgetSnapshot.Account, used: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: account.label).font(.caption).lineLimit(1)
            HStack(spacing: 6) {
                meter(account.sessionRemaining, used: used)
                meter(account.weeklyRemaining, used: used)
            }
        }
    }

    private func meter(_ remaining: Double?, used: Bool) -> some View {
        VStack(spacing: 2) {
            if let remaining {
                let shown = used ? 100 - remaining : remaining
                Text((shown / 100).formatted(.percent.precision(.fractionLength(0)))).font(.caption2.monospacedDigit())
                bar(remaining)
            } else {
                Text(verbatim: "–").font(.caption2).foregroundStyle(.secondary)
                bar(nil)
            }
        }
    }

    private func bar(_ remaining: Double?) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let remaining {
                    Capsule().fill(tint(remaining))
                        .frame(width: proxy.size.width * max(0, min(1, remaining / 100)))
                }
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 6)
    }

    private func tint(_ remaining: Double) -> Color {
        remaining <= 10 ? .red : remaining <= 25 ? .orange : .accentColor
    }
}
