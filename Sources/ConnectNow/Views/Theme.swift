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
    var title: String {
        switch self {
        case .online: "You're connected"
        case .captive: "Portal detected"
        case .offline: "No Internet access"
        case .noNetwork: "No network"
        case .scanning: "Scanning network…"
        }
    }

    var subtitle: String {
        switch self {
        case .online: "The Internet is responding normally."
        case .captive: "This network wants you to sign in."
        case .offline: "The network isn't answering any probe."
        case .noNetwork: "This Mac isn't connected to any network."
        case .scanning: "Looking for the sign-in page"
        }
    }

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
        }
    }
}

extension Duration {
    var millisecondsText: String { "\(Int((self / .milliseconds(1)).rounded())) ms" }
}

extension URL {
    /// Host with its port, the part of the address users recognise.
    var displayHost: String {
        guard let host = host() else { return absoluteString }
        return port.map { "\(host):\($0)" } ?? host
    }
}
