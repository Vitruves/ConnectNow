import AppKit
import Observation
import WebKit

/// Security state of the displayed page, as shown in the address field.
enum PortalSecurity: Equatable {
    case none, secure, insecure, acceptedCertificate, failed
}

/// Owns the portal WKWebView and publishes its state to SwiftUI.
@MainActor @Observable
final class PortalNavigator: NSObject {
    private(set) var url: URL?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var hasOnlySecureContent = false
    /// Failed address, shown instead of about:blank while the error page is displayed.
    private(set) var failedURL: URL?
    /// Requested address, shown until the first page commits.
    private var pendingURL: URL?
    var trustedGateway: String?

    /// Hosts whose invalid certificate was accepted during this session.
    private var acceptedHosts: Set<String> = []
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private(set) lazy var webView: WKWebView = makeWebView()

    /// Real address to show: users always know who receives their credentials.
    var displayURL: URL? { failedURL ?? url.flatMap { $0.scheme == "about" ? nil : $0 } ?? pendingURL }

    var security: PortalSecurity {
        if failedURL != nil { return .failed }
        guard let url = displayURL else { return .none }
        if url.scheme == "https" {
            if let host = url.host(), acceptedHosts.contains(host) { return .acceptedCertificate }
            return hasOnlySecureContent ? .secure : .insecure
        }
        return .insecure
    }

    func load(_ request: PortalRequest) {
        failedURL = nil
        pendingURL = request.url
        webView.load(URLRequest(url: request.url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reloadOrStop() {
        if isLoading { webView.stopLoading() }
        else if let failedURL { webView.load(URLRequest(url: failedURL)) }
        else { webView.reload() }
    }

    func openExternally() {
        if let url = displayURL { NSWorkspace.shared.open(url) }
    }

    func copyURL() {
        guard let url = displayURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        // Nothing is stored on disk: no cached redirects from one Wi-Fi to the next.
        config.websiteDataStore = .nonPersistent()
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        observations = [
            view.observe(\.url) { [weak self] v, _ in MainActor.assumeIsolated { self?.sync(v) } },
            view.observe(\.canGoBack) { [weak self] v, _ in MainActor.assumeIsolated { self?.sync(v) } },
            view.observe(\.canGoForward) { [weak self] v, _ in MainActor.assumeIsolated { self?.sync(v) } },
            view.observe(\.isLoading) { [weak self] v, _ in MainActor.assumeIsolated { self?.sync(v) } },
            view.observe(\.estimatedProgress) { [weak self] v, _ in MainActor.assumeIsolated { self?.sync(v) } },
            view.observe(\.hasOnlySecureContent) { [weak self] v, _ in MainActor.assumeIsolated { self?.sync(v) } },
        ]
        return view
    }

    private func sync(_ view: WKWebView) {
        if url != view.url {
            url = view.url
            if let scheme = view.url?.scheme, scheme != "about" { failedURL = nil }
        }
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
        isLoading = view.isLoading
        progress = view.estimatedProgress
        hasOnlySecureContent = view.hasOnlySecureContent
        // macOS 14 lacks toolbar(removing: .title): hide the title by hand.
        if #unavailable(macOS 15) { view.window?.titleVisibility = .hidden }
    }

    private func presentAlert(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let window = webView.window { return await alert.beginSheetModal(for: window) }
        return alert.runModal()
    }

    private func alert(_ message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        let host = frame.securityOrigin.host
        alert.informativeText = host.isEmpty ? "" : "Message from \(host)"
        return alert
    }
}

extension PortalNavigator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust,
              PortalTrust.acceptsInvalidCertificate(host: space.host, gateway: trustedGateway)
        else { return (.performDefaultHandling, nil) }
        // No authority signs for a local IP: the certificate is necessarily unverified.
        acceptedHosts.insert(space.host)
        return (.useCredential, URLCredential(trust: trust))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard action.request.url?.scheme == PortalErrorPage.actionScheme else { return .allow }
        openExternally()
        return .cancel
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        let error = error as NSError
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else { return }
        // WebKit "Frame load interrupted" (download, etc.): nothing to show.
        guard error.domain != "WebKitErrorDomain" || error.code != 102 else { return }
        let target = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView.url ?? failedURL
        guard let target else { return }
        webView.loadHTMLString(PortalErrorPage.html(url: target, reason: error.localizedDescription), baseURL: nil)
        failedURL = target
        pendingURL = nil
    }
}

extension PortalNavigator: WKUIDelegate {
    // target=_blank links and window.open: stay in the same view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(action.request)
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = alert(message, frame: frame)
        alert.addButton(withTitle: "OK")
        _ = await presentAlert(alert)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = alert(message, frame: frame)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return await presentAlert(alert) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = alert(prompt, frame: frame)
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return await presentAlert(alert) == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
