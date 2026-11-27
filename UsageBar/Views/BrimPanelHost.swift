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
            let model = Self.model(store: store, now: context.date)
            BrimPanelView(model: model,
                          layout: BrimSettingsPrefs.shared.panelLayout,
                          used: BrimSettingsPrefs.shared.displayMode == .used,
                          actions: Self.actions(copying: model, screenWidth: hostScreen()?.visibleFrame.width),
                          maxHeight: (hostScreen()?.visibleFrame.height ?? 900) - 40,
                          screenWidth: hostScreen()?.visibleFrame.width,
                          onContentSize: onContentSize,
                          prompt: BrimResetUseStore.shared.prompt.map { ($0.accountID, $0.kind) },
                          refreshing: store.isRefreshing,
                          usageContent: { width, height in
                              AnyView(BrimUsageView(store: .shared, width: width, maxHeight: height))
                          },
                          incidents: ServiceStatusStore.shared.incidents(now: context.date))
        }
    }

    @MainActor
    static func model(store: UsageStore = .shared, now: Date = Date()) -> BrimPanelModel {
        var model = BrimPanelModel.make(snapshot: store.publishedSnapshot, readFailed: false,
                                        loaded: store.publishedOnce, now: now,
                                        claudeResets: BrimClaudeResetStore.shared.panelInput(for: store.publishedSnapshot),
                                        resetUses: BrimResetUseStore.shared.uses, format: format)
        // The login verdict lives in LoginStatusStore, not in the snapshot: the same answer the
        // card chips and the expiry notification read.
        for group in model.groups.indices {
            for index in model.groups[group].rows.indices {
                let id = model.groups[group].rows[index].id
                model.groups[group].rows[index].needsSignIn = LoginStatusStore.shared.isExpired(id)
                model.groups[group].rows[index].signingIn = RenewLoginStore.shared.isRenewing(id)
            }
        }
        return model
    }

    /// Times and durations in the app's language ("Çar 12:09", "3 sa 47 dk"), always 24-hour.
    static var format: BrimPanelModel.Format {
        BrimPanelModel.Format(locale: Locale(identifier: AppLocale.identifier))
    }

    @MainActor
    static var actions: BrimPanelActions { actions(copying: nil, screenWidth: nil) }

    /// `copying`: the model the copy button pictures; nil leaves the button out.
    @MainActor
    static func actions(copying model: BrimPanelModel?, screenWidth: CGFloat?) -> BrimPanelActions {
        var actions = baseActions
        if let model, model.body == .accounts {
            actions.copyImage = {
                PanelSnapshot.copy(model: model, layout: BrimSettingsPrefs.shared.panelLayout,
                                   used: BrimSettingsPrefs.shared.displayMode == .used, screenWidth: screenWidth)
            }
        }
        actions.openStatusPage = { NSWorkspace.shared.open($0) }
        return actions
    }

    @MainActor
    private static var baseActions: BrimPanelActions {
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
            setLayout: { BrimSettingsPrefs.shared.panelLayout = $0 },
            signIn: { RenewLoginStore.shared.renew(accountID: $0) })
    }

    @MainActor
    static func refreshNow() {
        Task { await UsageStore.shared.refreshClicked() }
    }
}
