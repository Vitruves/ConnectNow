import AppKit
import SwiftUI
import ConnectNowCore

// Dawn palette, taken from the app icon.
extension Color {
    static let night = Color(red: 0x1E / 255, green: 0x21 / 255, blue: 0x60 / 255)
    static let violet = Color(red: 0x4A / 255, green: 0x2A / 255, blue: 0x78 / 255)
    static let rose = Color(red: 0xC2 / 255, green: 0x48 / 255, blue: 0x6A / 255)
    static let coral = Color(red: 0xF0 / 255, green: 0x7A / 255, blue: 0x55 / 255)
    static let gold = Color(red: 0xFF / 255, green: 0xC5 / 255, blue: 0x6E / 255)
}

/// Window appearance chosen from the right-click menu.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "appearance"
    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Applies to every window of the app.
    @MainActor func apply() {
        var choice = self
        #if DEBUG
        // Demo screenshots: CONNECTNOW_APPEARANCE=dark|light wins over the saved choice.
        if let forced = ProcessInfo.processInfo.environment["CONNECTNOW_APPEARANCE"] { choice = forced == "dark" ? .dark : .light }
        #endif
        NSApp.appearance = switch choice {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Colour of buttons, selection and the portal loading bar, chosen from the right-click menu.
enum Accent: String, CaseIterable, Identifiable {
    case dawn, system, blue, green, purple, orange
    static let storageKey = "accent"
    var id: Self { self }

    var title: String {
        switch self {
        case .dawn: "Dawn (Default)"
        case .system: "System Accent"
        case .blue: "Blue"
        case .green: "Green"
        case .purple: "Purple"
        case .orange: "Orange"
        }
    }

    /// nil: the accent colour set in System Settings.
    var color: Color? {
        switch self {
        case .dawn: .rose
        case .system: nil
        case .blue: .blue
        case .green: .green
        case .purple: .purple
        case .orange: .orange
        }
    }
}

enum Brand {
    /// Icon shown in the header (and in the Dock when running outside a bundle).
    @MainActor static let icon: NSImage = {
        #if DEBUG
        if Bundle.main.bundleURL.pathExtension == "app" { return NSApp.applicationIconImage }
        // Development build: look for Resources/icon.png above the executable (.build/…) or the working directory.
        let starts = [Bundle.main.executableURL?.deletingLastPathComponent(),
                      URL(filePath: FileManager.default.currentDirectoryPath)]
        for start in starts {
            var dir = start
            while let current = dir, current.pathComponents.count > 1 {
                if let image = NSImage(contentsOf: current.appending(path: "Resources/icon.png")) { return image }
                dir = current.deletingLastPathComponent()
            }
        }
        #endif
        return NSApp.applicationIconImage
    }()
}

extension NetworkStatus {
    var symbol: String {
        switch self {
        case .online: "checkmark"
        case .captive: "door.left.hand.open"
        case .offline: "exclamationmark"
        case .noNetwork: "wifi.slash"
        case .scanning: "antenna.radiowaves.left.and.right"
        }
    }

    /// Badge fill, drawn over the dark header.
    var badgeFill: Color {
        switch self {
        case .online: Color(red: 0.24, green: 0.78, blue: 0.47)
        case .captive: .gold
        case .offline: .coral
        case .noNetwork: Color(white: 0.55)
        case .scanning: .white.opacity(0.22)
        }
    }

    var badgeGlyph: Color { self == .captive ? .night : .white }
}

extension PortalSource {
    var symbol: String {
        switch self {
        case .announced: "dot.radiowaves.left.and.right"
        case .probe: "scope"
        case .gateway: "server.rack"
        }
    }
}

extension ProbeState {
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .portal: "arrow.uturn.right.circle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .portal: .orange
        case .error: .red
        }
    }

    var label: String {
        switch self {
        case .ok: "Normal response"
        case .portal: "Redirected to a portal"
        case .error: "Failed"
        }
    }
}

extension Hint.Action {
    var title: String {
        switch self {
        case .switchDNSToAutomatic: "Switch DNS to automatic"
        case .forceHTTPPage: "Force an HTTP page"
        case .downloadUpdate: "Download"
        }
    }
}

extension URL {
    /// Host with its port, the part of the address users recognise.
    var displayHost: String {
        guard let host = host() else { return absoluteString }
        return port.map { "\(host):\($0)" } ?? host
    }
}
