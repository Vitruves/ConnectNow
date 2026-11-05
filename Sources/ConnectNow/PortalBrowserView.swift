import SwiftUI

/// Captive portal window: a minimal browser that always shows the real address.
struct PortalBrowserView: View {
    /// Latest display request; nil means nothing to load.
    let request: PortalRequest?
    /// Gateway address: the only host (besides private IPs) whose invalid certificate is accepted.
    let trustedGateway: String?

    @State private var navigator = PortalNavigator()
    @State private var copied = false

    var body: some View {
        PortalWebView(navigator: navigator)
            .overlay {
                if request == nil && navigator.url == nil {
                    ContentUnavailableView("No Portal to Show", systemImage: "wifi",
                                           description: Text("The Wi-Fi sign-in page opens here as soon as ConnectNow finds it."))
                        .background(.background)
                }
            }
            .overlay(alignment: .top) { progressBar }
            .frame(minWidth: 560, idealWidth: 960, minHeight: 420, idealHeight: 720)
            .navigationTitle(navigator.displayURL?.absoluteString ?? "Wi-Fi Portal")
            .modifier(HiddenWindowTitle())
            .toolbar { toolbar }
            .onChange(of: trustedGateway, initial: true) { navigator.trustedGateway = trustedGateway }
            // A new id reloads, even when the address is unchanged.
            .task(id: request?.id) {
                navigator.trustedGateway = trustedGateway
                if let request { navigator.load(request) }
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Back", systemImage: "chevron.backward", action: navigator.goBack)
                .disabled(!navigator.canGoBack)
                .keyboardShortcut("[", modifiers: .command)
                .help("Go back (⌘[)")
            Button("Forward", systemImage: "chevron.forward", action: navigator.goForward)
                .disabled(!navigator.canGoForward)
                .keyboardShortcut("]", modifiers: .command)
                .help("Go forward (⌘])")
        }
        ToolbarItem(placement: .principal) {
            PortalAddressField(url: navigator.displayURL, security: navigator.security, copy: copyURL)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(navigator.isLoading ? "Stop" : "Reload",
                   systemImage: navigator.isLoading ? "xmark" : "arrow.clockwise",
                   action: navigator.reloadOrStop)
                .contentTransition(.symbolEffect(.replace))
                .disabled(navigator.displayURL == nil && !navigator.isLoading)
                .keyboardShortcut("r", modifiers: .command)
                .help(navigator.isLoading ? "Stop loading" : "Reload this page (⌘R)")
            Button("Copy Address", systemImage: copied ? "checkmark" : "link", action: copyURL)
                .contentTransition(.symbolEffect(.replace))
                .disabled(navigator.displayURL == nil)
                .keyboardShortcut("l", modifiers: .command)
                .help("Copy the address (⌘L)")
            Button("Open in browser", systemImage: "safari", action: navigator.openExternally)
                .disabled(navigator.displayURL == nil)
                .help("Open in your default browser")
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.tint)
                .frame(width: geo.size.width * max(navigator.progress, 0.05))
                .animation(.easeOut(duration: 0.25), value: navigator.progress)
        }
        .frame(height: 2)
        .opacity(navigator.isLoading ? 1 : 0)
        .animation(.easeInOut(duration: navigator.isLoading ? 0.1 : 0.4), value: navigator.isLoading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func copyURL() {
        navigator.copyURL()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// The title (the address) stays the window's title (Window menu, Mission Control)
/// without duplicating the capsule in the toolbar.
private struct HiddenWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.toolbar(removing: .title) } else { content }
    }
}
