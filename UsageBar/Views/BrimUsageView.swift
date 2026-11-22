import Charts
import SwiftUI

/// The panel's Usage tab: what the local Claude and Codex transcripts burned and cost over a
/// range, against the window of equal length before it when the history reaches that far, a
/// curve over the days, and one row per project, model or provider (UsageBreakdown over
/// TokenStatsStore's priced cells). Arriving on the tab brings the scan up to date; unchanged
/// transcripts are not reread.
struct BrimUsageView: View {
    @Bindable var store: TokenStatsStore
    var width: CGFloat
    var maxHeight: CGFloat

    @AppStorage("brimUsageGroup") private var groupRaw = UsageBreakdown.Group.project.rawValue
    @AppStorage("brimUsageRange") private var rangeRaw = TokenStatsRange.sevenDays.rawValue
    @AppStorage("brimUsageMetric") private var metricRaw = Metric.cost.rawValue
    @State private var hoveredDay: Int?
    @State private var contentHeight: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    enum Metric: String { case tokens, cost }

    private var theme: BrimTheme { .of(scheme) }
    private var group: UsageBreakdown.Group { UsageBreakdown.Group(rawValue: groupRaw) ?? .project }
    private var range: TokenStatsRange { TokenStatsRange(rawValue: rangeRaw) ?? .sevenDays }
    private var metric: Metric { Metric(rawValue: metricRaw) ?? .cost }
    private var locale: Locale { Locale(identifier: AppLocale.identifier) }

    var body: some View {
        let usage = store.usage(group: group, range: range)
        VStack(alignment: .leading, spacing: 14) {
            controls
            if !store.hasScanned {
                placeholder(L("Reading transcripts…"))
            } else if usage.isEmpty {
                placeholder(L("No usage in this range."))
            } else {
                let content = VStack(alignment: .leading, spacing: 16) {
                    summary(usage)
                    if usage.bars.count > 2 { chart(usage) }
                    rows(usage)
                    footnote(usage)
                }
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                })
                if contentHeight > maxHeight {
                    ScrollView(.vertical) { content }.frame(height: maxHeight).scrollIndicators(.never)
                } else {
                    content
                }
            }
        }
        .padding(EdgeInsets(top: 2, leading: 16, bottom: 14, trailing: 16))
        .frame(width: width, alignment: .leading)
        .onAppear { store.refresh() }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 8) {
            BrimQuietSegments(selection: $groupRaw, theme: theme, options: [
                (UsageBreakdown.Group.project.rawValue, L("Project")),
                (UsageBreakdown.Group.model.rawValue, L("Model")),
                (UsageBreakdown.Group.provider.rawValue, L("Provider")),
            ])
            Spacer(minLength: 8)
            if store.isScanning { ProgressView().controlSize(.mini) }
            BrimQuietSegments(selection: $rangeRaw, theme: theme,
                              options: TokenStatsRange.allCases.map { ($0.rawValue, $0.label) })
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(theme.text2)
            .frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    // MARK: Summary

    private func summary(_ usage: UsageBreakdown) -> some View {
        let days = max(1, usage.monthly ? usage.bars.count * 30 : usage.bars.count)
        return HStack(alignment: .top, spacing: 0) {
            figure(L("Cost"), CostFormat.dollars(usage.totals.cost),
                   note: days > 1 ? String(format: L("%@ a day"), CostFormat.dollars(usage.totals.cost / Double(days))) : nil,
                   change: UsageBreakdown.change(usage.totals.cost, usage.previous?.cost))
            figure(L("Tokens"), TokenCount.short(usage.totals.tokens, locale: locale),
                   note: days > 1 ? String(format: L("%@ a day"), TokenCount.short(usage.totals.tokens / Int64(days), locale: locale)) : nil,
                   change: UsageBreakdown.change(Double(usage.totals.tokens), usage.previous.map { Double($0.tokens) }))
            figure(L("Output"), TokenCount.short(usage.totals.output, locale: locale),
                   note: usage.totals.tokens > 0 ? String(format: L("%@ of tokens"), Self.share(Double(usage.totals.output) / Double(usage.totals.tokens), locale: locale)) : nil,
                   change: UsageBreakdown.change(Double(usage.totals.output), usage.previous.map { Double($0.output) }))
        }
    }

    private func figure(_ title: String, _ value: String, note: String?, change: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(theme.text2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                if let change {
                    Text(Self.percent(change)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(theme.text2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(theme.mutedFill.opacity(0.5), in: Capsule())
                        .help(L("Against the previous period of the same length"))
                }
            }
            if let note {
                Text(note).font(.system(size: 11)).foregroundStyle(theme.text3).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func percent(_ change: Int) -> String { change > 0 ? "+\(change)%" : "\(change)%" }

    static func share(_ value: Double, locale: Locale) -> String {
        let digits = value > 0 && value < 0.1 ? 1 : 0
        return (value * 100).formatted(.number.precision(.fractionLength(digits)).locale(locale)) + "%"
    }

    // MARK: Chart

    private func value(_ totals: UsageBreakdown.Totals) -> Double {
        metric == .cost ? totals.cost : Double(totals.tokens)
    }

    private func label(_ totals: UsageBreakdown.Totals) -> String {
        metric == .cost ? CostFormat.dollars(totals.cost) : TokenCount.short(totals.tokens, locale: locale)
    }

    /// A soft curve over the days: the shape of the range matters here more than any one bar, and
    /// the exact value is one hover away.
    private func chart(_ usage: UsageBreakdown) -> some View {
        let hovered = usage.bars.first { $0.day == hoveredDay }
        let peak = usage.bars.max { value($0.totals) < value($1.totals) }
        let unit: Calendar.Component = usage.monthly ? .month : .day
        let fill = LinearGradient(colors: [theme.accentFill.opacity(0.5), theme.accentFill.opacity(0.02)],
                                  startPoint: .top, endPoint: .bottom)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Group {
                    if let hovered {
                        Text(dayLabel(hovered.day, monthly: usage.monthly, long: true)).foregroundStyle(theme.text2)
                            + Text(verbatim: "  ") + Text(label(hovered.totals)).foregroundStyle(theme.text)
                    } else if let peak {
                        Text(L("Busiest")).foregroundStyle(theme.text2)
                            + Text(verbatim: "  \(dayLabel(peak.day, monthly: usage.monthly, long: true))  ").foregroundStyle(theme.text2)
                            + Text(label(peak.totals)).foregroundStyle(theme.text)
                    }
                }
                .font(.system(size: 11)).monospacedDigit().lineLimit(1)
                Spacer(minLength: 8)
                BrimQuietSegments(selection: $metricRaw, theme: theme, small: true, options: [
                    (Metric.cost.rawValue, L("Cost")), (Metric.tokens.rawValue, L("Tokens")),
                ])
            }
            Chart {
                ForEach(usage.bars) { bar in
                    AreaMark(x: .value("Day", Self.date(bar.day), unit: unit, calendar: Self.utc),
                             y: .value("Value", value(bar.totals)))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(fill)
                    LineMark(x: .value("Day", Self.date(bar.day), unit: unit, calendar: Self.utc),
                             y: .value("Value", value(bar.totals)))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(theme.accentFill)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                if let hovered {
                    RuleMark(x: .value("Day", Self.date(hovered.day), unit: unit, calendar: Self.utc))
                        .foregroundStyle(theme.text3.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    PointMark(x: .value("Day", Self.date(hovered.day), unit: unit, calendar: Self.utc),
                              y: .value("Value", value(hovered.totals)))
                        .foregroundStyle(theme.accent)
                        .symbolSize(36)
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(max(peak.map { value($0.totals) } ?? 1, 0.0001) * 1.08))
            .chartXAxis {
                AxisMarks(values: axisDays(usage).map(Self.date)) { mark in
                    AxisValueLabel(centered: true) {
                        if let date = mark.as(Date.self) {
                            Text(dayLabel(Self.day(date), monthly: usage.monthly, long: false))
                                .font(.system(size: 10)).foregroundStyle(theme.text3)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            let date: Date? = proxy.value(atX: point.x)
                            hoveredDay = date.map(Self.day).flatMap { d in
                                usage.monthly ? usage.bars.last { $0.day <= d }?.day
                                    : usage.bars.min { abs($0.day - d) < abs($1.day - d) }?.day
                            }
                        case .ended:
                            hoveredDay = nil
                        }
                    }
            }
            .frame(height: 92)
        }
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// A local day number as the UTC midnight that names it (the day numbers are already local).
    static func date(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86_400) }
    static func day(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 86_400).rounded(.down)) }

    /// At most about six labels, the last on today.
    private func axisDays(_ usage: UsageBreakdown) -> [Int] {
        let days = usage.bars.map(\.day)
        let step = max(1, Int((Double(days.count) / 6).rounded(.up)))
        return stride(from: days.count - 1, through: 0, by: -step).map { days[$0] }.reversed()
    }

    private func dayLabel(_ day: Int, monthly: Bool, long: Bool) -> String {
        var style = Date.FormatStyle(locale: locale, timeZone: TimeZone(identifier: "UTC")!)
        if monthly {
            style = long ? style.month(.wide).year() : style.month(.abbreviated)
        } else {
            style = long ? style.day().month(.wide).weekday(.abbreviated) : style.day().month(.abbreviated)
        }
        return Self.date(day).formatted(style)
    }

    // MARK: Rows

    private enum Column {
        static let share: CGFloat = 110, tokens: CGFloat = 64, cost: CGFloat = 72, change: CGFloat = 54
    }

    /// One line per row: the name, a bar against the largest row with its share of the whole, then
    /// tokens, cost and (when there is a full previous window) the change.
    private func rows(_ usage: UsageBreakdown) -> some View {
        var names = Self.names(usage.rows.map(\.key), group: group)
        if let pooled = usage.rows.first(where: { $0.key == UsageBreakdown.otherKey }) {
            names[pooled.key] = String(format: L(group == .project ? "%d more projects" : "%d more"), pooled.members)
        }
        let compared = usage.previous != nil
        let largest = usage.rows.map(\.share).max() ?? 1
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(groupTitle).frame(maxWidth: .infinity, alignment: .leading)
                Text(L("Share")).frame(width: Column.share, alignment: .leading)
                Text(L("Tokens")).frame(width: Column.tokens)
                Text(L("Cost")).frame(width: Column.cost)
                if compared { Text(L("Change")).frame(width: Column.change) }
            }
            .font(.system(size: 11)).foregroundStyle(theme.text3)
            .padding(.bottom, 6)
            ForEach(usage.rows) { row in
                let pooled = row.key.hasPrefix("\u{0}") || row.key.isEmpty && group == .project
                HStack(spacing: 10) {
                    Text(names[row.key] ?? row.key).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(pooled ? theme.text2 : theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(row.key)
                    shareCell(row.share, relative: largest > 0 ? row.share / largest : 0, muted: pooled)
                        .frame(width: Column.share)
                    Text(TokenCount.short(row.totals.tokens, locale: locale)).foregroundStyle(theme.text2)
                        .frame(width: Column.tokens)
                    Text(row.totals.unpricedTokens == row.totals.tokens ? "–" : CostFormat.dollars(row.totals.cost))
                        .frame(width: Column.cost)
                    if compared {
                        Text(change(row).map(Self.percent) ?? "–").foregroundStyle(theme.text3)
                            .frame(width: Column.change)
                    }
                }
                .font(.system(size: 12)).monospacedDigit()
                .padding(.vertical, 6)
                .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
            }
        }
    }

    private func shareCell(_ share: Double, relative: Double, muted: Bool) -> some View {
        HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.mutedFill.opacity(0.45))
                    Capsule().fill(muted ? theme.text3.opacity(0.6) : theme.accentFill)
                        .frame(width: max(3, proxy.size.width * relative))
                }
            }
            .frame(height: 5)
            Text(Self.share(share, locale: locale)).font(.system(size: 11)).foregroundStyle(theme.text3)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var groupTitle: String {
        switch group {
        case .project: L("Project")
        case .model: L("Model")
        case .provider: L("Provider")
        }
    }

    /// Each row's name. Projects whose folder names match (ignoring case) get leading path
    /// components until they differ: `rpa360` twice reads `RPA/rpa360` and `Desktop/RPA/rpa360`.
    static func names(_ keys: [String], group: UsageBreakdown.Group) -> [String: String] {
        func name(_ key: String, _ components: Int) -> String {
            if key == UsageBreakdown.otherKey { return L("Others") }
            if key.isEmpty && group == .project { return L("No project") }
            if key == UsageBreakdown.claudeAppKey { return L("Claude app sessions") }
            if key == UsageBreakdown.temporaryKey { return L("Temporary folders") }
            switch group {
            case .project: return TokenProject.displayName(forKey: key, components: components)
            case .model: return UsageBreakdown.modelName(key)
            case .provider: return ProviderCatalog.displayName(for: key)
            }
        }
        var depth = Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: { a, _ in a })
        for _ in 0..<5 {
            let current = depth.map { ($0.key, name($0.key, $0.value).lowercased()) }
            let clashes = Dictionary(grouping: current, by: \.1).filter { $0.value.count > 1 }
            guard group == .project, !clashes.isEmpty else { break }
            for (_, members) in clashes { for (key, _) in members { depth[key, default: 1] += 1 } }
        }
        return depth.reduce(into: [:]) { $0[$1.key] = name($1.key, $1.value) }
    }

    /// By cost where the window is priced, else by tokens, the same weight the rows sort by.
    private func change(_ row: UsageBreakdown.Row) -> Int? {
        guard let previous = row.previous else { return nil }
        return row.totals.cost > 0
            ? UsageBreakdown.change(row.totals.cost, previous.cost)
            : UsageBreakdown.change(Double(row.totals.tokens), Double(previous.tokens))
    }

    @ViewBuilder private func footnote(_ usage: UsageBreakdown) -> some View {
        if usage.totals.unpricedTokens > 0 {
            Text(String(format: L("%@ tokens on models with no price list (Codex) are not in the cost."),
                        TokenCount.short(usage.totals.unpricedTokens, locale: locale)))
                .font(.system(size: 11)).foregroundStyle(theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The panel's own segmented control: plain words, the chosen one in the text colour on a soft
/// fill, no system accent, so it sits with the rest of the panel instead of shouting over it.
struct BrimQuietSegments: View {
    @Binding var selection: String
    var theme: BrimTheme
    var small = false
    var options: [(String, String)]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.0) { option in
                let chosen = option.0 == selection
                Button { selection = option.0 } label: {
                    Text(option.1)
                        .font(.system(size: small ? 10.5 : 11.5, weight: chosen ? .medium : .regular))
                        .foregroundStyle(chosen ? theme.text : theme.text2)
                        .padding(.horizontal, small ? 7 : 9).padding(.vertical, small ? 2.5 : 4)
                        .background(chosen ? theme.surface2 : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(chosen ? theme.hairline : .clear, lineWidth: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(theme.mutedFill.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
    }
}
