import AppKit
import SwiftUI
import ConnectNowCore

@main
struct ConnectNowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("ConnectNow", id: "main") {
            MainView(model: delegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 600)
        .commands { MainCommands() }

        Window("Wi-Fi Portal", id: "portal") {
            PortalWindowContent(model: delegate.model)
        }
        .defaultSize(width: 900, height: 720)
    }
}

/// Separate view so that observation tracks the request and the gateway.
private struct PortalWindowContent: View {
    let model: AppModel
    var body: some View {
        PortalBrowserView(request: model.portalRequest, trustedGateway: model.scan.gateway)
    }
}

private struct MainCommands: Commands {
    @FocusedValue(\.mainWindowModel) private var model

    var body: some Commands {
        // No "New Window": a single main window. Disabled items let the portal window use the same keys.
        CommandGroup(replacing: .newItem) {
            Button("Rescan network") { model?.rescan() }
                .keyboardShortcut("r")
                .disabled(model == nil)
            Divider()
            Button("Open portal") { model?.openSelectedPortal() }
                .keyboardShortcut("o")
                .disabled(model?.selectedPortal == nil)
            Button("Open in browser") { model?.openSelectedInBrowser() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model?.selectedPortal == nil)
            Button("Force an HTTP page") { model?.forceHTTPPage() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model == nil)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(launchURL: LaunchOptions.portalURL())

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleURL.pathExtension != "app" {
            NSApp.applicationIconImage = Brand.icon  // Dock icon when run from .build
        }
        NSApp.activate()
        #if DEBUG
        // Demo screenshots: come forward even when launched from a background shell.
        if DemoData.requested != nil { NSApp.perform(NSSelectorFromString("activateIgnoringOtherApps:"), with: true) }
        if let name = ProcessInfo.processInfo.environment["CONNECTNOW_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
        }
        #endif
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()  // restores a temporarily switched DNS
    }
}

enum LaunchOptions {
    /// `--open <URL>` (or `--open=<URL>`): show that address in the portal window at launch.
    static func portalURL(arguments: [String] = CommandLine.arguments) -> URL? {
        var value: String?
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            if argument == "--open" || argument == "-open" {
                value = iterator.next() ?? ""
            } else if argument.hasPrefix("--open=") {
                value = String(argument.dropFirst("--open=".count))
            }
        }
        guard let value else { return nil }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else {
            FileHandle.standardError.write(Data("ConnectNow: invalid URL: \(value)\n".utf8))
            exit(2)
        }
        return url
    }
}
