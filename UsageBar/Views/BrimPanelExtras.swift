import AppKit
import SwiftUI

/// One line of the panel: a provider whose status page reports an incident.
struct BrimServiceIncident: Identifiable, Equatable {
    var id: String
    var name: String
    var indicator: ServiceStatusLogic.Indicator
    var site: URL

    static func words(_ indicator: ServiceStatusLogic.Indicator) -> String {
        switch indicator {
        case .none: L("Operational")
        case .maintenance: L("Under maintenance")
        case .minor: L("Degraded service")
        case .major: L("Partial outage")
        case .critical: L("Major outage")
        }
    }
}

/// One provider with an incident on its status page: the name, the state in UsageBar's words, and
/// the page one click away. Sits under the header with the panel's other one-line notices.
struct BrimIncidentLine: View {
    let incident: BrimServiceIncident
    let theme: BrimTheme
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(tint)
                Text(verbatim: "\(incident.name): \(BrimServiceIncident.words(incident.indicator))")
                    .font(.system(size: 12)).foregroundStyle(theme.text2)
                Spacer(minLength: 8)
                Text(L("Status page")).font(.system(size: 11)).foregroundStyle(theme.text3)
                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(theme.text3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
        .help(incident.site.absoluteString)
    }

    private var tint: Color {
        switch incident.indicator {
        case .major, .critical: theme.critical
        case .minor: theme.warn
        case .none, .maintenance: theme.text2
        }
    }
}

/// The header's copy button: a check for a moment after the picture is on the clipboard.
struct CopyImageButton: View {
    let theme: BrimTheme
    let action: () -> Void
    @State private var done = false

    var body: some View {
        Button {
            action()
            done = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { done = false }
        } label: {
            Image(systemName: done ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: done ? .semibold : .regular))
                .foregroundStyle(done ? theme.accent : theme.text2)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Copy as image"))
        .accessibilityLabel(L("Copy as image"))
    }
}

/// The accounts as a picture on the clipboard: the panel's own view, rendered offscreen without
/// its buttons, in the appearance on screen.
enum PanelSnapshot {
    @MainActor
    static func copy(model: BrimPanelModel, layout: BrimPanelLayout, used: Bool, screenWidth: CGFloat?) {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let view = BrimPanelView(model: model, layout: layout, used: used, screenWidth: screenWidth,
                                 snapshotMode: true)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([image])
    }
}
