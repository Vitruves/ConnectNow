import SwiftUI
import WebKit

/// Embeds the navigator's WKWebView in the SwiftUI hierarchy.
struct PortalWebView: NSViewRepresentable {
    let navigator: PortalNavigator
    func makeNSView(context: Context) -> WKWebView { navigator.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
