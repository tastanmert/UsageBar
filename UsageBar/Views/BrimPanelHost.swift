import AppKit
import SwiftUI

/// The UsageBar panel as the status item hosts it: the published snapshot from `UsageStore`, run
/// through `BrimPanelModel` against the clock, with the app's own actions behind the buttons.
struct BrimPanelHost: View {
    let store: UsageStore
    var onContentSize: ((CGSize) -> Void)? = nil
    /// The screen the popover is on, for the scroll cap; nil leaves the default.
    var hostScreen: () -> NSScreen? = { nil }

    var body: some View {
        // Countdowns move on their own between snapshot reads.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            BrimPanelView(model: Self.model(store: store, now: context.date),
                          layout: BrimSettingsPrefs.shared.panelLayout,
                          used: BrimSettingsPrefs.shared.displayMode == .used,
                          actions: Self.actions,
                          maxHeight: (hostScreen()?.visibleFrame.height ?? 900) - 40,
                          screenWidth: hostScreen()?.visibleFrame.width,
                          onContentSize: onContentSize,
                          prompt: BrimResetUseStore.shared.prompt.map { ($0.accountID, $0.kind) })
        }
    }

    @MainActor
    static func model(store: UsageStore = .shared, now: Date = Date()) -> BrimPanelModel {
        BrimPanelModel.make(snapshot: store.publishedSnapshot, readFailed: false,
                            loaded: store.publishedOnce, now: now,
                            claudeResets: BrimClaudeResetStore.shared.panelInput(for: store.publishedSnapshot),
                            resetUses: BrimResetUseStore.shared.uses, format: format)
    }

    /// Times and durations in the app's language ("Çar 12:09", "3 sa 47 dk"), always 24-hour.
    static var format: BrimPanelModel.Format {
        BrimPanelModel.Format(locale: Locale(identifier: AppLocale.identifier))
    }

    @MainActor
    static var actions: BrimPanelActions {
        BrimPanelActions(
            refresh: refreshNow,
            openSettings: {
                StatusItemController.shared?.closePopover()
                StatusItemController.openSettingsWindow()
            },
            // The store binds every claim to the card's consent.
            openReset: { BrimResetUseStore.shared.open(accountID: $0, kind: $1, grantID: $2) },
            chooseReset: { BrimResetUseStore.shared.choose($0) },
            cancelReset: { BrimResetUseStore.shared.cancel() },
            useReset: { BrimResetUseStore.shared.confirm() },
            setLayout: { BrimSettingsPrefs.shared.panelLayout = $0 })
    }

    @MainActor
    static func refreshNow() {
        Task { await UsageStore.shared.refreshClicked() }
    }
}
