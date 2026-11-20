import SwiftUI

/// The frame of the nearest enclosing `usageBarTooltipAnchorRow()`, in the tooltip layer's space.
private struct UsageBarTooltipRowFrameKey: EnvironmentKey {
    static let defaultValue: CGRect? = nil
}

/// Every seam (top and bottom edge of a row, heading or title line) the nearest enclosing
/// `usageBarTooltipSeams()` collected, in the tooltip layer's space.
private struct UsageBarTooltipSeamsKey: EnvironmentKey {
    static let defaultValue: [CGFloat] = []
}

/// The edges published by `usageBarTooltipSeam()` and `usageBarTooltipAnchorRow()`, on their way up to
/// the `usageBarTooltipSeams()` that hands them back down.
private struct UsageBarTooltipSeamPreference: PreferenceKey {
    static let defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) { value += nextValue() }
}

/// Where a card's labels and controls sit, in the card's own space (`usageBarTooltipObstacles()`), for
/// a callout that goes beside its target (`TooltipPlacement.besideSlot`).
private struct UsageBarTooltipObstacleKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

/// The title line of a settings row label, in the card's space (`usageBarTooltipTitle()`): what a
/// beside-the-target callout hangs on, so it lands next to the pointer.
struct UsageBarTooltipTitleKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = value ?? nextValue() }
}

private struct UsageBarTooltipObstaclesKey: EnvironmentKey {
    static let defaultValue: [CGRect] = []
}

extension UsageBarTooltip {
    /// The space a card's obstacles are measured in. Not the surface's: those frames shift with
    /// every scroll step and would re-render the whole card, these only move when the card does.
    static let cardSpace = "usageBarTooltipCard"
}

extension EnvironmentValues {
    var usageBarTooltipObstacles: [CGRect] {
        get { self[UsageBarTooltipObstaclesKey.self] }
        set { self[UsageBarTooltipObstaclesKey.self] = newValue }
    }

    var usageBarTooltipRowFrame: CGRect? {
        get { self[UsageBarTooltipRowFrameKey.self] }
        set { self[UsageBarTooltipRowFrameKey.self] = newValue }
    }

    var usageBarTooltipSeams: [CGFloat] {
        get { self[UsageBarTooltipSeamsKey.self] }
        set { self[UsageBarTooltipSeamsKey.self] = newValue }
    }
}

extension View {
    /// Publishes this row's frame to the callouts inside it that pass `hugsRow: true`, so they
    /// clear the rows above and below rather than the hovered figure's own, shorter, edges.
    func usageBarTooltipAnchorRow() -> some View {
        modifier(UsageBarTooltipAnchorRow())
    }

    /// Publishes this line's top and bottom edges as seams a hugging callout's far edge may stop on
    /// (`TooltipPlacement.farEdgeStretch`), for the lines in a table that are not rows (its headings,
    /// the title above it). Rows publish theirs through `usageBarTooltipAnchorRow()`.
    func usageBarTooltipSeam() -> some View {
        background(GeometryReader { proxy in
            let rect = proxy.frame(in: .named(UsageBarTooltip.space))
            Color.clear.preference(key: UsageBarTooltipSeamPreference.self, value: [rect.minY, rect.maxY])
        })
    }

    /// Marks this view's frame as something a beside-the-target callout must not cover.
    func usageBarTooltipObstacle() -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: UsageBarTooltipObstacleKey.self,
                                   value: [proxy.frame(in: .named(UsageBarTooltip.cardSpace))])
        })
    }

    /// Marks this view as the title line its enclosing label's callout is placed against.
    func usageBarTooltipTitle() -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: UsageBarTooltipTitleKey.self, value: proxy.frame(in: .named(UsageBarTooltip.cardSpace)))
        })
    }

    /// A card: measures its obstacles in its own space and hands them to the callouts inside it.
    func usageBarTooltipObstacles() -> some View {
        modifier(UsageBarTooltipObstacles())
    }

    /// Collects the seams published inside this view and hands them to the callouts inside it.
    func usageBarTooltipSeams() -> some View {
        modifier(UsageBarTooltipSeams())
    }
}

private struct UsageBarTooltipSeams: ViewModifier {
    @State private var seams: [CGFloat] = []

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(UsageBarTooltipSeamPreference.self) { seams = $0 }
            .environment(\.usageBarTooltipSeams, seams)
    }
}

private struct UsageBarTooltipObstacles: ViewModifier {
    @State private var obstacles: [CGRect] = []

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: UsageBarTooltip.cardSpace)
            .onPreferenceChange(UsageBarTooltipObstacleKey.self) { obstacles = $0 }
            .environment(\.usageBarTooltipObstacles, obstacles)
    }
}

private struct UsageBarTooltipAnchorRow: ViewModifier {
    @State private var frame: CGRect?

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                let rect = proxy.frame(in: .named(UsageBarTooltip.space))
                Color.clear
                    .preference(key: UsageBarTooltipSeamPreference.self, value: [rect.minY, rect.maxY])
                    .onAppear { frame = rect }
                    .onChange(of: rect) { _, new in frame = new }
            })
            .environment(\.usageBarTooltipRowFrame, frame)
    }
}
