import AppKit
import SwiftUI

/// Two quota windows on an 18-point canvas. Geometry: task-i-icon/glyph-spec.md.
/// The existing internal names are retained for callers.
enum BrimCup {
    static let bars = [CGRect(x: 1, y: 3.5, width: 16, height: 6),
                       CGRect(x: 1, y: 11.5, width: 16, height: 3)]

    static func capsule(_ rect: CGRect) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: rect.height / 2,
               cornerHeight: rect.height / 2, transform: nil)
    }

    /// Unknown windows have only a track. Stale readings retain their lengths at half opacity.
    static func templateImage(_ glyph: BrimPanelModel.Glyph, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: rect.width / 18, y: rect.height / 18)
            for (bar, value) in zip(bars, [glyph.fiveHourFill, glyph.weeklyFill]) {
                let path = capsule(bar)
                context.addPath(path)
                context.setFillColor(gray: 0, alpha: glyph.dashed ? 0.15 : 0.30)
                context.fillPath()
                guard let value, value.isFinite, value > 0 else { continue }
                context.saveGState()
                context.addPath(path)
                context.clip()
                context.clip(to: CGRect(x: bar.minX, y: bar.minY,
                    width: max(bar.width * CGFloat(min(value, 1)), bar.height), height: bar.height))
                context.setFillColor(gray: 0, alpha: glyph.dashed ? 0.5 : 1)
                context.fill(bar)
                context.restoreGState()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "UsageBar"
        return image
    }
}

/// The same two windows in panel headers and the fixed mark in Settings.
struct BrimCupMark: View {
    var fill: Double?
    var weeklyFill: Double? = 0.40
    var ink: Color
    var liquid: Color
    var dimmed = false

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 18, y: size.height / 18)
            for (bar, value) in zip(BrimCup.bars, [fill, weeklyFill]) {
                let path = Path(BrimCup.capsule(bar))
                context.fill(path, with: .color(ink.opacity(dimmed ? 0.15 : 0.30)))
                guard let value, value.isFinite, value > 0 else { continue }
                var clipped = context
                clipped.clip(to: path)
                clipped.clip(to: Path(CGRect(x: bar.minX, y: bar.minY,
                    width: max(bar.width * CGFloat(min(value, 1)), bar.height), height: bar.height)))
                clipped.fill(path, with: .color(liquid.opacity(dimmed ? 0.5 : 1)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The spec's "calm instrument" palette, light and dark. Picked by the view's colour scheme so
/// the panel follows the system appearance (and so an offscreen render can pin either).
struct BrimTheme {
    let ground, surface, surface2, text, text2, text3, hairline: Color
    let accent, accentFill, accentSoft, warn, warnFill, warnSoft, critical, criticalFill, criticalSoft: Color
    let mutedFill: Color

    static func of(_ scheme: ColorScheme) -> BrimTheme { scheme == .dark ? dark : light }

    static let light = BrimTheme(
        ground: Color(hex: 0xF4F4F3), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xFAFAF9),
        text: Color(hex: 0x1C1C1E), text2: Color(hex: 0x57575E), text3: Color(hex: 0x6E6E76),
        hairline: Color(hex: 0xE3E3E6),
        accent: Color(hex: 0x426B73), accentFill: Color(hex: 0x69878C), accentSoft: Color(hex: 0xEBF0F0),
        warn: Color(hex: 0xB45309), warnFill: Color(hex: 0xF2A33A), warnSoft: Color(hex: 0xFDF1E2),
        critical: Color(hex: 0xC2410C), criticalFill: Color(hex: 0xE8602C), criticalSoft: Color(hex: 0xFCE9E1),
        mutedFill: Color(hex: 0xD5D5D9))

    static let dark = BrimTheme(
        ground: Color(hex: 0x161618), surface: Color(hex: 0x1F1F22), surface2: Color(hex: 0x26262A),
        text: Color(hex: 0xF2F2F3), text2: Color(hex: 0xB4B4BB), text3: Color(hex: 0x9A9AA2),
        hairline: Color(hex: 0x333338),
        accent: Color(hex: 0x92B3BA), accentFill: Color(hex: 0x92B3BA), accentSoft: Color(hex: 0x92B3BA).opacity(0.16),
        warn: Color(hex: 0xF2A33A), warnFill: Color(hex: 0xF2A33A), warnSoft: Color(hex: 0xF2A33A).opacity(0.14),
        critical: Color(hex: 0xF07A4A), criticalFill: Color(hex: 0xF07A4A), criticalSoft: Color(hex: 0xF07A4A).opacity(0.16),
        mutedFill: Color(hex: 0x3A3A40))

    /// Number colour for a window: plain text while there is plenty, the level's colour below.
    func ink(_ level: BrimPanelModel.Level?) -> Color {
        switch level {
        case .low: warn
        case .critical, .limit: critical
        default: text
        }
    }

    func barFill(_ level: BrimPanelModel.Level?) -> Color {
        switch level {
        case .low: warnFill
        case .critical, .limit: criticalFill
        default: text2.opacity(0.55)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}


struct BrimProviderMark: View {
    let provider: String
    var monochrome = false
    var body: some View {
        if let path = ProviderMarks.path(for: provider) {
            ProviderIconShape(pathData: path)
                .fill(monochrome ? Color.primary : ProviderBrand.markHex(for: provider).map { Color(hex: $0) } ?? .primary)
                .frame(width: 14, height: 14)
                .accessibilityLabel(provider == "claude" ? "Claude" : "OpenAI")
        }
    }

    @MainActor static func image(_ provider: String) -> NSImage? {
        let renderer = ImageRenderer(content: BrimProviderMark(provider: provider, monochrome: true))
        renderer.scale = 2
        let image = renderer.nsImage
        image?.isTemplate = true
        return image
    }
}
