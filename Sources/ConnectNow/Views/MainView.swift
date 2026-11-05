import AppKit
import SwiftUI
import ConnectNowCore

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("detailsExpanded") private var detailsExpanded = false
    /// Measured height of the scrollable content: the window hugs it, up to a cap, then scrolls.
    @State private var contentHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            HeroHeader(status: model.scan.status, isScanning: model.isScanning, subtitle: model.subtitle)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PortalSection(model: model)

                    if !model.hints.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(model.hints) { hint in
                                HintCard(hint: hint,
                                         canPerform: hint.action.map(model.canPerform) ?? false,
                                         perform: model.perform)
                                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                            }
                        }
                    }

                    DetailsSection(scan: model.scan, isExpanded: $detailsExpanded)
                }
                .padding(20)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, 620))
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.top)

            FooterBar(model: model)
        }
        .frame(width: 440)
        .background(WindowHook())
        .focusedSceneValue(\.mainWindowModel, model)
        .alert(model.alert?.title ?? "", isPresented: Binding(
            get: { model.alert != nil },
            set: { if !$0 { model.alert = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.alert?.message ?? "")
        }
        // Each new request opens (or brings forward) the portal window, which loads it.
        .onChange(of: model.portalRequest, initial: true) { _, request in
            guard request != nil else { return }
            openWindow(id: "portal")
            NSApp.activate()
        }
    }
}

/// Configures the hosting NSWindow: draggable from the background, and closing it quits the app.
private struct WindowHook: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HookView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HookView: NSView {
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, token == nil else { return }
            window.isMovableByWindowBackground = true
            window.tabbingMode = .disallowed
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }
    }
}

extension FocusedValues {
    /// Set only while the main window is key, so its shortcuts (⌘R…) leave the portal window alone.
    @Entry var mainWindowModel: AppModel?
}
