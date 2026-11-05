import Foundation

// SHARED CONTRACT between the network core and the UI. Change only in coordination.

public enum NetworkStatus: String, Sendable, Hashable {
    case online     // Internet responds normally
    case captive    // at least one probe hijacked, or a portal is announced
    case offline    // network present, no probe answers
    case noNetwork  // no usable interface
    case scanning   // initial state, before the first scan
}

public enum PortalSource: Sendable, Hashable, CustomStringConvertible {
    case announced            // DHCP option 114 / RFC 8908
    case probe(String)        // probe name (Apple, Google…)
    case gateway(port: Int)   // web port open on the gateway

    public var description: String {
        switch self {
        case .announced: "Announced by the network"
        case .probe(let name): "Probe \(name)"
        case .gateway(let port): "Gateway, port \(port) open"
        }
    }
}

public struct Portal: Sendable, Hashable, Identifiable {
    public let url: URL
    public let source: PortalSource
    public var id: URL { url }
    public init(url: URL, source: PortalSource) { self.url = url; self.source = source }
}

public enum ProbeState: String, Sendable, Hashable { case ok, portal, error }

public struct ProbeResult: Sendable, Hashable, Identifiable {
    public let name: String
    public let url: URL
    public let state: ProbeState
    public let detail: String          // "HTTP 204", "HTTP 302 → …", error message
    public let latency: Duration?      // response time, nil on error
    public let portalURL: URL?         // inferred portal when state == .portal
    public let isDNSError: Bool        // DNS resolution failure (triggers the DNS fallback)
    public var id: String { name }
    public init(name: String, url: URL, state: ProbeState, detail: String,
                latency: Duration? = nil, portalURL: URL? = nil, isDNSError: Bool = false) {
        self.name = name; self.url = url; self.state = state; self.detail = detail
        self.latency = latency; self.portalURL = portalURL; self.isDNSError = isDNSError
    }
}

/// Advice shown to the user. Text is ready to display.
public struct Hint: Sendable, Hashable, Identifiable {
    public enum Severity: Sendable, Hashable { case info, warning }
    public enum Action: Sendable, Hashable { case switchDNSToAutomatic, forceHTTPPage }
    public let id: String          // stable identifier ("vpn-active", "manual-dns"…)
    public let title: String       // short sentence
    public let message: String     // explanation
    public let severity: Severity
    public let action: Action?
    public init(id: String, title: String, message: String, severity: Severity = .warning, action: Action? = nil) {
        self.id = id; self.title = title; self.message = message; self.severity = severity; self.action = action
    }
}

public struct ScanResult: Sendable, Hashable {
    public var status: NetworkStatus = .scanning
    public var interface: String?          // analysed interface (en0…)
    public var isWiFi = false
    public var defaultInterface: String?   // interface of the default route
    public var gateway: String?
    public var dnsServers: [String] = []
    public var usedDNSFallback = false     // portal found through the access point's DNS
    public var service: String?            // macOS network service name ("Wi-Fi")
    public var manualDNS: [String] = []    // DNS servers set manually on this service
    public var portals: [Portal] = []      // the first one is the most likely
    public var probes: [ProbeResult] = []
    public var hints: [Hint] = []
    public var date = Date()
    public init() {}

    /// The "Switch DNS to Automatic" action makes sense.
    public var canSwitchDNS: Bool { status != .online && !manualDNS.isEmpty && service != nil }
}
