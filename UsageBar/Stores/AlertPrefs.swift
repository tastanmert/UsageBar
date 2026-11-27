import Foundation
import Observation

/// The settings of the Notifications tab and the two App rows that sit beside them (the global
/// shortcut and keeping the Mac awake). UsageBar's own defaults domain only.
@MainActor
@Observable
final class AlertPrefs {
    static let shared = AlertPrefs()

    /// Used percent at which a window's alert fires; 0 is off (LimitAlertLogic.thresholdChoices).
    var limitThreshold: Int {
        didSet { UserDefaults.standard.set(limitThreshold, forKey: Keys.threshold) }
    }

    /// The weekly window resets within a day with half or more of it unused.
    var unusedWeekly: Bool {
        didSet { UserDefaults.standard.set(unusedWeekly, forKey: Keys.unusedWeekly) }
    }

    /// Read status.claude.com and status.openai.com and show an incident in the panel.
    var serviceStatus: Bool {
        didSet {
            UserDefaults.standard.set(serviceStatus, forKey: Keys.serviceStatus)
            ServiceStatusStore.shared.settingChanged()
        }
    }

    /// And post a notification when one starts.
    var serviceStatusNotify: Bool {
        didSet { UserDefaults.standard.set(serviceStatusNotify, forKey: Keys.serviceStatusNotify) }
    }

    var hotKey: GlobalHotKey.Choice {
        didSet {
            UserDefaults.standard.set(hotKey.rawValue, forKey: Keys.hotKey)
            GlobalHotKey.shared.apply(hotKey)
        }
    }

    /// Hold off idle sleep while a supervised session is working.
    var keepAwake: Bool {
        didSet {
            UserDefaults.standard.set(keepAwake, forKey: Keys.keepAwake)
            KeepAwake.shared.reevaluate()
        }
    }

    var limitSettings: LimitAlertSettings {
        LimitAlertSettings(threshold: limitThreshold, unusedWeekly: unusedWeekly)
    }

    private enum Keys {
        static let threshold = "alertLimitThreshold"
        static let unusedWeekly = "alertUnusedWeekly"
        static let serviceStatus = "serviceStatusEnabled"
        static let serviceStatusNotify = "serviceStatusNotify"
        static let hotKey = "globalHotKey"
        static let keepAwake = "keepAwakeWhileWorking"
    }

    private init() {
        let defaults = UserDefaults.standard
        let threshold = defaults.object(forKey: Keys.threshold) as? Int ?? 90
        limitThreshold = LimitAlertLogic.thresholdChoices.contains(threshold) ? threshold : 90
        unusedWeekly = defaults.object(forKey: Keys.unusedWeekly) as? Bool ?? true
        serviceStatus = defaults.object(forKey: Keys.serviceStatus) as? Bool ?? true
        serviceStatusNotify = defaults.object(forKey: Keys.serviceStatusNotify) as? Bool ?? true
        hotKey = GlobalHotKey.Choice(rawValue: defaults.string(forKey: Keys.hotKey) ?? "") ?? .off
        keepAwake = defaults.bool(forKey: Keys.keepAwake)
    }
}
