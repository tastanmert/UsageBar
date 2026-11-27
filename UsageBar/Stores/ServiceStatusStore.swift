import AppKit
import Observation

/// Reads the providers' status pages every five minutes while the setting is on, for the
/// providers this Mac has accounts of. One anonymous GET per page: no cookie, no identifier.
@MainActor
@Observable
final class ServiceStatusStore {
    static let shared = ServiceStatusStore()

    /// The latest good reading per provider id. A failed read leaves the previous one in place,
    /// and `ServiceStatusLogic.shown` stops showing it once it is old.
    private(set) var readings: [String: ServiceStatusLogic.Reading] = [:]

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private let announcedKey = "\(BrandPaths.reverseDNS).serviceStatus.announced"
    static let interval: TimeInterval = 5 * 60

    private init() {}

    func install() { settingChanged() }

    func settingChanged() {
        timer?.invalidate()
        timer = nil
        guard AlertPrefs.shared.serviceStatus, BrimFeatures.liveProbes, !DemoUsage.isActive else {
            readings = [:]
            return
        }
        Task { await poll() }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The incidents the panel shows, worst first.
    func incidents(now: Date = Date()) -> [BrimServiceIncident] {
        if DemoUsage.isActive, UserDefaults.standard.bool(forKey: "UsageBarDemoIncident") {
            return [BrimServiceIncident(id: "claude", name: "Claude", indicator: .minor,
                                        site: ServiceStatusLogic.pages[0].site)]
        }
        return ServiceStatusLogic.pages.compactMap { page in
            guard let reading = ServiceStatusLogic.shown(readings[page.providerID], now: now) else { return nil }
            return BrimServiceIncident(id: page.providerID, name: page.name,
                                       indicator: reading.indicator, site: page.site)
        }
        .sorted { $0.indicator > $1.indicator }
    }

    private func poll() async {
        let providers = Set(UsageStore.shared.discoveredAccounts.map(\.providerID))
        // At launch the accounts may not be discovered yet; look again shortly rather than in five minutes.
        guard !providers.isEmpty else {
            try? await Task.sleep(for: .seconds(30))
            if !Set(UsageStore.shared.discoveredAccounts.map(\.providerID)).isEmpty { await poll() }
            return
        }
        for page in ServiceStatusLogic.pages where providers.contains(page.providerID) {
            var request = URLRequest(url: page.api)
            request.setValue("UsageBar", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let reading = ServiceStatusLogic.parse(data, now: Date()) else { continue }
            readings[page.providerID] = reading
            announceIfNews(reading, page: page)
        }
    }

    private func announceIfNews(_ reading: ServiceStatusLogic.Reading, page: ServiceStatusLogic.Page) {
        var announced = loadAnnounced()
        let (notify, next) = ServiceStatusLogic.announce(reading, last: announced[page.providerID])
        if announced[page.providerID] != next {
            announced[page.providerID] = next
            saveAnnounced(announced)
        }
        guard notify, AlertPrefs.shared.serviceStatusNotify, BrimFeatures.userNotifications,
              BuildVariant.publishesOwnState else { return }
        let title = "\(page.name): \(BrimServiceIncident.words(reading.indicator))"
        let body = reading.description.isEmpty ? page.site.host ?? "" : "\(reading.description) · \(page.site.host ?? "")"
        Task { _ = await SystemAlert.post(title: title, body: body) }
    }

    private func loadAnnounced() -> [String: ServiceStatusLogic.Announced] {
        guard let data = UserDefaults.standard.data(forKey: announcedKey),
              let value = try? JSONDecoder().decode([String: ServiceStatusLogic.Announced].self, from: data)
        else { return [:] }
        return value
    }

    private func saveAnnounced(_ value: [String: ServiceStatusLogic.Announced]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: announcedKey)
    }
}
