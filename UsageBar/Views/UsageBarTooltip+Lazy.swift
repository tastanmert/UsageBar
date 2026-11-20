import SwiftUI

// The callout's lazy entries, kept out of UsageBarTooltip.swift for the 500-line rule.

extension View {
    /// `usageBarTooltip(blocks:)`, with blocks that are built only while somebody can be shown them: under
    /// the pointer, held open for a capture, outside a layer (the system tooltip needs its text up
    /// front), or with VoiceOver on (the hint is how it hears them). For a callout whose figures
    /// cost real work on every redraw of a target nobody is hovering (a field report).
    func usageBarTooltip(lazyBlocks: @escaping () -> [UsageBarTooltipBlock], forced: Bool = false, hugsRow: Bool = false) -> some View {
        modifier(UsageBarTooltipTarget(resolve: { .blocks(lazyBlocks()) }, lazy: true, forced: forced, hugsRow: hugsRow))
    }

    /// The text callout, built only while somebody can be shown it, exactly as
    /// `usageBarTooltip(lazyBlocks:)` builds its blocks. For a sentence that costs real work on every
    /// redraw of a target nobody is hovering (a field report, the advisor row).
    func usageBarTooltip(lazyText: @escaping () -> String, forced: Bool = false) -> some View {
        modifier(UsageBarTooltipTarget(resolve: { .lines(lazyText().components(separatedBy: "\n").filter { !$0.isEmpty }) },
                                    lazy: true, forced: forced))
    }
}
