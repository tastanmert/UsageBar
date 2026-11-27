import SwiftUI

/// Settings > Notifications: the per-account limit alerts and the providers' status pages.
struct BrimNotificationsPane: View {
    @Bindable var prefs = AlertPrefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BrimSettingsGroup(L("Limits")) {
                BrimSettingsRow(title: L("Alert at"),
                                subtitle: L("Once per window and reset, for every account. A second alert when the window is used up.")) {
                    BrimSegmented(options: LimitAlertLogic.thresholdChoices.map { ($0, $0 == 0 ? L("Off") : BrimPercent.text($0, locale: Locale(identifier: AppLocale.identifier))) },
                                  selection: $prefs.limitThreshold)
                }
                BrimSettingsDivider()
                BrimSettingsRow(title: L("Unused week"),
                                subtitle: L("A day before a weekly window resets with half or more of it left.")) {
                    BrimSwitch(isOn: $prefs.unusedWeekly)
                }
            }
            BrimSettingsGroup(L("Service status")) {
                BrimSettingsRow(title: L("Show incidents in the panel"),
                                subtitle: L("Reads status.claude.com and status.openai.com every 5 minutes, for the providers you have accounts with.")) {
                    BrimSwitch(isOn: $prefs.serviceStatus)
                }
                BrimSettingsDivider()
                BrimSettingsRow(title: L("Notify when an incident starts")) {
                    BrimSwitch(isOn: $prefs.serviceStatusNotify)
                }
                .disabled(!prefs.serviceStatus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .brimSettingsPage()
    }
}

/// General > App: the shortcut that opens the panel from anywhere.
struct BrimHotKeyRow: View {
    @Bindable var prefs = AlertPrefs.shared

    var body: some View {
        BrimSettingsRow(title: L("Open panel shortcut"),
                        subtitle: prefs.hotKey != .off && !GlobalHotKey.shared.registered
                            ? L("Another app already uses this shortcut.") : nil) {
            Picker("", selection: $prefs.hotKey) {
                ForEach(GlobalHotKey.Choice.allCases) { Text(verbatim: $0.label).tag($0) }
            }
            .labelsHidden().fixedSize()
        }
    }
}

/// General > App: hold off idle sleep while a session works.
struct BrimKeepAwakeRow: View {
    @Bindable var prefs = AlertPrefs.shared

    var body: some View {
        BrimSettingsRow(title: L("Keep the Mac awake while a session works"),
                        subtitle: L("Sessions started through UsageBar. The display can still sleep.")) {
            BrimSwitch(isOn: $prefs.keepAwake)
        }
    }
}
