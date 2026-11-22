import AppKit
import OSLog
import WebKit

/// The one-time Console sign-in for one Claude account: a small window with a web view on that
/// account's own Console data store (ConsoleCreditsFetch.dataStore(forAccount:)) opened at
/// https://platform.claude.com/login. The user
/// signs in as in any browser (email code, Google, SSO). Google opens its account chooser in a
/// popup that talks back to the opener, so popups are real child web views built from the
/// configuration WebKit passes in (same data store, window.opener intact). After each page that
/// lands on the Console proper, and after a popup closes, a probe asks `/api/organizations`; a
/// list means signed in, so the window marks the connection, closes and the credits refresh.
/// Navigations stay in the window: nothing is handed to the system browser, because Google's
/// consent step fails outside the web view that holds the opener. Cookies are never read here: the web view only uses the store, and ConsoleCreditsFetch is the
/// one place that reads them.
@MainActor
final class ConsoleSignInWindowController: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = ConsoleSignInWindowController(target: .console)
    /// The same window for claude.ai: the session that reads the plan's renewal date
    /// (SubscriptionFetch). Its own per-account store, never the Console's.
    static let claudeWeb = ConsoleSignInWindowController(target: .claudeWeb)

    /// What one kind of sign-in opens, where its session lives, and how it knows it worked.
    struct Target {
        var title: String
        var loginURL: URL
        var host: String
        var dataStore: @MainActor (String) -> WKWebsiteDataStore
        var isSignedIn: @Sendable (String) async -> Bool
        var defaultConnected: @MainActor (String) -> Void

        static var console: Target {
            Target(title: "Connect to Console", loginURL: ConsoleCreditsFetch.loginURL, host: ConsoleCreditsFetch.host,
                   dataStore: { ConsoleCreditsFetch.dataStore(forAccount: $0) },
                   isSignedIn: { await ConsoleCreditsFetch.isSignedIn(jar: ConsoleCreditsFetch.WebKitJar(account: $0)) },
                   defaultConnected: { id in Task { await ConsoleCreditsStore.shared.didConnect(accountID: id) } })
        }

        static var claudeWeb: Target {
            Target(title: "Connect to claude.ai", loginURL: SubscriptionFetch.claudeLoginURL, host: SubscriptionFetch.claudeHost,
                   dataStore: { SubscriptionFetch.claudeDataStore(forAccount: $0) },
                   isSignedIn: { await SubscriptionFetch.claudeOrganizations(store: SubscriptionFetch.claudeStoreID(for: $0)) != nil },
                   defaultConnected: { _ in })
        }
    }

    private let target: Target
    private init(target: Target) { self.target = target }

    private static let log = Logger(subsystem: "app.usagebar", category: "ConsoleSignIn")

    private(set) var window: NSWindow?
    private var webView: WKWebView?
    private var popups: [WKWebView: NSWindow] = [:]
    private var probing = false
    private var finished = false
    private(set) var accountID: String?

    var isWindowVisible: Bool { window?.isVisible == true }

    /// Opens the sign-in for one account (or brings it forward). `onConnected` runs once after a
    /// working session. A window open for another account is closed first: one sign-in at a time.
    func show(accountID: String, onConnected: (@MainActor () -> Void)? = nil) {
        if let window, self.accountID == accountID {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        window?.close()
        self.accountID = accountID
        let fallback = target.defaultConnected
        self.onConnected = onConnected ?? { fallback(accountID) }
        finished = false
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = target.dataStore(accountID)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 720), configuration: configuration)
        prepare(webView)
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView

        let window = NSWindow(contentRect: webView.frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L(target.title)
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        webView.load(URLRequest(url: target.loginURL))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var onConnected: @MainActor () -> Void = {}

    private func prepare(_ view: WKWebView) {
        view.customUserAgent = ConsoleCreditsFetch.signInUserAgent()
        view.navigationDelegate = self
        view.uiDelegate = self
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(ConsoleCreditsFetch.isSignInURLAllowed(navigationAction.request.url) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView !== self.webView { return }
        probeIfOnConsole()
    }

    private func probeIfOnConsole() {
        guard !finished, !probing, let url = webView?.url, url.host == target.host,
              !url.path.hasPrefix("/login"), !url.path.hasPrefix("/logout") else { return }
        probe()
    }

    /// Asks the Console whether the session works; on success closes the window and reports.
    private func probe() {
        guard !finished, !probing else { return }
        probing = true
        Task { [weak self] in
            guard let self, let accountID = self.accountID else { return }
            let signedIn = await self.target.isSignedIn(accountID)
            self.probing = false
            guard signedIn, !self.finished else { return }
            self.finished = true
            self.window?.close()
            self.onConnected()
        }
    }

    // MARK: Popups (Google sign-in)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard ConsoleCreditsFetch.isSignInURLAllowed(navigationAction.request.url) else { return nil }
        // The configuration WebKit passes in carries the opener link and the shared data store.
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        prepare(popup)
        let width = windowFeatures.width?.doubleValue ?? 480
        let height = windowFeatures.height?.doubleValue ?? 640
        let popupWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(width, 360), height: max(height, 420)),
                                   styleMask: [.titled, .closable, .resizable],
                                   backing: .buffered, defer: false)
        popupWindow.contentView = popup
        popupWindow.isReleasedWhenClosed = false
        popupWindow.delegate = self
        popupWindow.title = L(target.title)
        if let parent = window {
            popupWindow.setFrameOrigin(NSPoint(x: parent.frame.midX - popupWindow.frame.width / 2,
                                               y: parent.frame.midY - popupWindow.frame.height / 2))
        } else {
            popupWindow.center()
        }
        popups[popup] = popupWindow
        popupWindow.makeKeyAndOrderFront(nil)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let popupWindow = popups[webView] else { return }
        closePopup(webView, window: popupWindow)
        probe()
    }

    private func closePopup(_ popup: WKWebView, window popupWindow: NSWindow) {
        popups[popup] = nil
        popup.navigationDelegate = nil
        popup.uiDelegate = nil
        popup.stopLoading()
        popupWindow.delegate = nil
        popupWindow.close()
    }

    // MARK: JavaScript dialogs

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: L("Cancel"))
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if let (popup, _) = popups.first(where: { $0.value === closing }) {
            popups[popup] = nil
            popup.navigationDelegate = nil
            popup.uiDelegate = nil
            popup.stopLoading()
            probe()
            return
        }
        guard closing === window else { return }
        for (popup, popupWindow) in popups { closePopup(popup, window: popupWindow) }
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.stopLoading()
        webView = nil
        window = nil
        accountID = nil
    }
}
