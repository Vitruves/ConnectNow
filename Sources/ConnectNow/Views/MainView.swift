import AppKit
import SwiftUI
import ConnectNowCore

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("detailsExpanded") private var detailsExpanded = false
    @AppStorage(Accent.storageKey) private var accent = Accent.dawn
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage("keepsWindowInFront") private var keepsWindowInFront = false
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
        .contentShape(Rectangle())
        .tint(accent.color)
        .contextMenu { SettingsMenu(model: model) }
        .background(WindowHook(floats: keepsWindowInFront))
        .onChange(of: appearance) { _, choice in choice.apply() }
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
        // The link may have been removed from a terminal meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshCLIState()
        }
        .onChange(of: model.portalRequest, initial: true) { _, request in
            guard request != nil else { return }
            openWindow(id: "portal")
            NSApp.activate()
        }
    }
}

/// Right-click menu of the main window: display, behaviour, command-line tool and updates.
struct SettingsMenu: View {
    @Bindable var model: AppModel
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage(Accent.storageKey) private var accent = Accent.dawn
    @AppStorage("keepsWindowInFront") private var keepsWindowInFront = false
    @AppStorage("detailsExpanded") private var detailsExpanded = false

    var body: some View {
        Picker("Appearance", selection: $appearance) {
            ForEach(Appearance.allCases) { Text($0.title).tag($0) }
        }
        Picker("Accent Color", selection: $accent) {
            ForEach(Accent.allCases) { Text($0.title).tag($0) }
        }
        Toggle("Show Details", isOn: $detailsExpanded)
        Divider()
        Toggle("Open Portal Automatically", isOn: $model.opensPortalAutomatically)
        Toggle("Keep Window in Front", isOn: $keepsWindowInFront)
        Divider()
        Button("Rescan Network") { model.rescan() }
        Button("Copy Details") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(DetailsSection.report(model.scan), forType: .string)
        }
        Divider()
        if model.canInstallCLI {
            Button(model.isCLIInstalled ? "Remove Command-Line Tool" : "Install Command-Line Tool…") { model.toggleCLI() }
                .help("Adds the “connectnow” command to \(CommandLineTool.linkURL.deletingLastPathComponent().path)")
            Divider()
        }
        Toggle("Check for Updates at Launch", isOn: $model.checksForUpdates)
        Button("Check for Updates Now") { model.checkForUpdatesNow() }
    }
}

/// Configures the hosting NSWindow: draggable from the background, optionally floating, and closing it quits the app.
private struct WindowHook: NSViewRepresentable {
    /// "Keep Window in Front": stays above other apps' windows.
    var floats: Bool

    func makeNSView(context: Context) -> NSView { HookView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? HookView)?.floats = floats
    }

    private final class HookView: NSView {
        private var token: NSObjectProtocol?
        var floats = false { didSet { window?.level = floats ? .floating : .normal } }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.level = floats ? .floating : .normal
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
