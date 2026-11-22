import AppKit

/// The "Selected accounts" menu bar strip drawn as one image: each account's mark, then its
/// figures, on one compact line.
///
/// Colour carries the state (green / orange / red, BrimMenuSelection.Part.Tone). It drops to the
/// menu bar's own text colour where colour stops helping: an old reading kept after a failed
/// refresh is drawn dimmed and uncoloured, and with Increase Contrast on the whole strip becomes a
/// template image so macOS draws it like any other menu bar item.
@MainActor
enum BrimMenuStrip {
    struct Style: Equatable {
        var showWindowTags: Bool
        var monochrome: Bool
    }

    static var currentMonochrome: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

    static func image(_ segments: [BrimMenuSelection.Segment], style: Style) -> NSImage {
        observeContrastOnce()
        let height = max(NSStatusBar.system.thickness, 22)
        let laidOut = segments.map { layout($0, style: style) }
        let markSize: CGFloat = 14
        let markGap: CGFloat = 4
        let segmentGap: CGFloat = 10
        let width = laidOut.reduce(CGFloat(0)) { $0 + markSize + markGap + $1.width } + segmentGap * CGFloat(max(0, segments.count - 1))
        let size = NSSize(width: ceil(max(width, 1)), height: height)
        // Rendered once here, not on every draw of the image.
        let marks = segments.map { BrimProviderMark.image($0.provider) }
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for ((segment, lines), mark) in zip(zip(segments, laidOut), marks) {
                if let mark {
                    let rect = NSRect(x: x, y: (height - markSize) / 2, width: markSize, height: markSize)
                    tinted(mark, color(.mark, style: style, stale: segment.stale)).draw(in: rect)
                }
                x += markSize + markGap
                let strings = lines.strings
                let lineHeights = strings.map { $0.size().height }
                let total = lineHeights.reduce(0, +) - (strings.count > 1 ? 1 : 0)
                var y = (height + total) / 2
                for (string, lineHeight) in zip(strings, lineHeights) {
                    y -= lineHeight
                    string.draw(at: NSPoint(x: x, y: y))
                    y += strings.count > 1 ? 1 : 0
                }
                x += lines.width + segmentGap
            }
            return true
        }
        image.isTemplate = style.monochrome
        return image
    }

    /// Increase Contrast flips the strip to monochrome without waiting for the next refresh.
    private static var observing = false
    private static func observeContrastOnce() {
        guard !observing else { return }
        observing = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { UsageStore.shared.onChange?() }
        }
    }

    // MARK: Layout

    private struct Lines {
        var strings: [NSAttributedString]
        var width: CGFloat
    }

    private static func layout(_ segment: BrimMenuSelection.Segment, style: Style) -> Lines {
        var strings = [line(segment, parts: segment.parts, style: style)]
        if let label = segment.label {
            let labelString = NSAttributedString(string: label + " ", attributes: [
                .font: font(.figure, style: style), .foregroundColor: color(.tag, style: style, stale: segment.stale),
            ])
            strings[0] = { let m = NSMutableAttributedString(attributedString: labelString); m.append(strings[0]); return m }()
        }
        return Lines(strings: strings, width: ceil(strings.map { $0.size().width }.max() ?? 0))
    }

    private static func line(_ segment: BrimMenuSelection.Segment, parts: [BrimMenuSelection.Part], style: Style) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: " \u{2009}", attributes: [.font: font(.figure, style: style)]))
            }
            if style.showWindowTags {
                result.append(NSAttributedString(string: part.window.tag + "\u{2009}", attributes: [
                    .font: font(.tag, style: style), .foregroundColor: color(.tag, style: style, stale: segment.stale),
                ]))
            }
            result.append(NSAttributedString(string: part.value.menuBarFigure, attributes: [
                .font: font(.figure, style: style),
                .foregroundColor: color(.figure(part.tone), style: style, stale: segment.stale),
            ]))
        }
        return result
    }

    private enum Role { case tag, figure }
    private enum Ink { case mark, tag, figure(BrimMenuSelection.Part.Tone?) }

    /// A size under the menu bar's own text, so the whole strip stays short; medium weight keeps
    /// it legible at that size.
    private static func font(_ role: Role, style: Style) -> NSFont {
        let size: CGFloat = 11
        switch role {
        case .tag: return NSFont.systemFont(ofSize: size, weight: .semibold)
        case .figure: return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        }
    }

    private static func color(_ ink: Ink, style: Style, stale: Bool) -> NSColor {
        // A template image keeps only alpha: black, dimmed where the reading is old.
        if style.monochrome { return NSColor.black.withAlphaComponent(stale ? 0.5 : 1) }
        let text = stale ? NSColor.secondaryLabelColor : NSColor.labelColor
        switch ink {
        case .mark, .tag: return text
        case .figure(let tone): return stale ? text : tone.menuColor
        }
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
