import Foundation
import Network
import os

/// The analysed network. Connections are forcibly bound to it, to test Wi-Fi
/// even when a VPN, iPhone tethering or Ethernet has priority.
struct Target: Sendable, Hashable {
    var interface: String
    var binding = Binding()
    var gateway: IPAddress?
    var dhcpDNS: IPAddress?
    var service: String?
    /// DNS of the network itself, for the fallback resolver.
    var networkDNS: IPAddress? { dhcpDNS ?? gateway }
}

public struct NetworkScanner: Sendable {
    public init() {}

    /// Full network scan (≈ 1–7 s). Never throws: errors are in the result.
    public func scan() async -> ScanResult {
        var s = ScanResult()
        async let dnsServers = offload { SystemNetwork.dnsServers() }
        async let route = offload { SystemNetwork.defaultRoute() }
        async let wifi = offload { SystemNetwork.wifiService() }
        let (r, w) = await (route, wifi)
        let defIface = r.interface
        s.defaultInterface = defIface
        let (picked, wifiNote) = await offload { pickTarget(route: r, wifi: w) }
        s.dnsServers = await dnsServers

        guard let t = picked else {
            s.status = .noNetwork
            s.hints = [wifiNote ?? .noNetwork]
            return s
        }
        s.interface = t.interface
        s.isWiFi = t.binding.isWiFi
        s.gateway = t.gateway?.description
        s.service = t.service

        let client = HTTPClient(binding: t.binding)
        let fallback = t.networkDNS.map { HTTPClient(binding: t.binding, resolver: .server($0)) }
        async let manualDNS = offload { t.service.map(SystemNetwork.manualDNS(service:)) ?? [] }
        async let gatewayCandidates = t.gateway.asyncMap { await gatewayPortals($0, binding: t.binding) } ?? []
        async let announced = announced(t, client: client, fallback: fallback)

        var results = await runProbes(client: client)
        if let fallback, results.allSatisfy(\.isDNSError) {
            let alt = await runProbes(client: fallback)
            if alt.contains(where: { $0.state != .error }) { results = alt; s.usedDNSFallback = true }
        }
        s.probes = results
        s.manualDNS = await manualDNS
        let (announcedURL, announcedCaptive) = await announced

        var seen = Set<URL>()
        func add(_ url: URL?, _ source: PortalSource) {
            if let url, seen.insert(url).inserted { s.portals.append(Portal(url: url, source: source)) }
        }
        if announcedCaptive { add(announcedURL, .announced) }
        for r in results where r.state == .portal { add(r.portalURL, .probe(r.name)) }
        // A single hijacked probe is enough: some portals let captive.apple.com
        // through, which is precisely what keeps macOS from showing the page.
        s.status = !s.portals.isEmpty ? .captive : results.contains { $0.state == .ok } ? .online : .offline
        if !announcedCaptive { add(announcedURL, .announced) }
        for p in await gatewayCandidates { add(p.url, p.source) }

        if s.status == .online { return s }
        let privateAddress = t.binding.isWiFi && SystemNetwork.usesPrivateAddress(device: t.interface)
        s.hints = hints(for: s, target: t, defaultInterface: defIface, wifiNote: wifiNote,
                        proxies: SystemNetwork.proxies(), privateAddress: privateAddress)
        return s
    }

    private func announced(_ t: Target, client: HTTPClient, fallback: HTTPClient?) async -> (URL?, Bool) {
        let api = await offload { SystemNetwork.dhcpCaptivePortalURL(interface: t.interface) }
        guard let api = api.flatMap({ PortalExtractor.resolve($0.absoluteString) }) else { return (nil, false) }
        return await announcedPortal(api: api, client: client, fallback: fallback)
    }
}

/// Picks the network to analyse: Wi-Fi as soon as it has an address, otherwise
/// the default connection. `wifiNote` explains an unusable Wi-Fi. Blocking.
func pickTarget(route: DefaultRoute, wifi: WiFiService?) -> (Target?, wifiNote: Hint?) {
    let defIface = route.interface, defGateway = route.gateway.flatMap(IPAddress.init)
    var wifiNote: Hint?
    if let wifi {
        let addr = SystemNetwork.address(of: wifi.device)
        if let addr, addr.hasUsableIPv4 {
            var t = Target(interface: wifi.device, binding: Binding(interfaceIndex: addr.index, ipv4Only: true, isWiFi: true),
                           service: wifi.serviceName)
            t.gateway = SystemNetwork.dhcpRouter(interface: wifi.device).flatMap(IPAddress.init)
                ?? (defIface == wifi.device ? defGateway : nil)
            t.dhcpDNS = SystemNetwork.dhcpDNS(interface: wifi.device).flatMap(IPAddress.init)
            return (t, nil)
        } else if addr?.isSelfAssigned == true {
            wifiNote = .wifiSelfAssigned
        } else if SystemNetwork.isWiFiPoweredOff(device: wifi.device) {
            wifiNote = .wifiOff
        } else if defIface != wifi.device {
            wifiNote = .wifiNotJoined
        }
    }
    guard let defIface, !defIface.isEmpty else { return (nil, wifiNote) }
    var t = Target(interface: defIface, gateway: defGateway, service: SystemNetwork.serviceName(forDevice: defIface))
    if !SystemNetwork.isVPN(defIface), let addr = SystemNetwork.address(of: defIface) {
        t.binding = Binding(interfaceIndex: addr.index, ipv4Only: addr.hasUsableIPv4)
    }
    return (t, wifiNote)
}

/// Advice for a network that isn't online, in display order.
func hints(for s: ScanResult, target t: Target, defaultInterface defIface: String?, wifiNote: Hint?,
           proxies: [String] = [], privateAddress: Bool = false) -> [Hint] {
    var hints: [Hint] = wifiNote.map { [$0] } ?? []
    if let defIface, SystemNetwork.isVPN(defIface) {
        hints.append(t.interface != defIface ? .vpnBypassed(defIface) : .vpnActive(defIface))
    } else if let defIface, !defIface.isEmpty, t.interface != defIface {
        hints.append(.otherInterface(defIface))
    }
    let manual = s.manualDNS.joined(separator: ", ")
    switch (s.usedDNSFallback, s.manualDNS.isEmpty) {
    case (true, false): hints.append(.manualDNSBlocked(manual))
    case (true, true): hints.append(.systemDNSUnreachable)
    case (false, false): hints.append(.manualDNS(manual))
    case (false, true): break
    }
    if s.status == .offline && s.portals.isEmpty && hints.isEmpty { hints.append(.noResponse) }
    if !proxies.isEmpty { hints.append(.proxy(proxies)) }
    if s.status == .captive, privateAddress { hints.append(.privateAddress) }
    return hints
}

extension Hint {
    static let noNetwork = Hint(id: "no-network", title: "No network",
        message: "No network connection. First join the Wi-Fi network from the macOS Wi-Fi menu.")
    static let wifiSelfAssigned = Hint(id: "wifi-self-assigned", title: "No address from the access point",
        message: "Wi-Fi received no address from the access point (self-assigned address). Turn Wi-Fi off and on again, or move closer to the access point.")
    static let wifiOff = Hint(id: "wifi-off", title: "Wi-Fi is off",
        message: "Wi-Fi is turned off. Turn it on and join the public network.")
    static let wifiNotJoined = Hint(id: "wifi-not-joined", title: "Wi-Fi not joined",
        message: "Wi-Fi isn't connected to any network. First join the public network from the Wi-Fi menu.")
    static func vpnBypassed(_ iface: String) -> Hint {
        Hint(id: "vpn-bypassed", title: "A VPN is active",
             message: "A VPN is active (\(iface)). The scan bypasses it, but turn it off so the portal page can show up.")
    }
    static func vpnActive(_ iface: String) -> Hint {
        Hint(id: "vpn-active", title: "Traffic goes through a VPN",
             message: "Traffic goes through a VPN (\(iface)). Turn it off while you validate the portal.")
    }
    static func otherInterface(_ iface: String) -> Hint {
        Hint(id: "other-interface", title: "Another connection has priority",
             message: "The Mac uses another connection first (\(iface)). The portal page may go through it: unplug it while you sign in.")
    }
    static func manualDNSBlocked(_ servers: String) -> Hint {
        Hint(id: "manual-dns-blocked", title: "Your manual DNS is blocked",
             message: "Your manual DNS (\(servers)) is blocked by this network: that's what keeps the portal from showing. Click “Switch DNS to automatic”; it will be restored once you're connected.",
             action: .switchDNSToAutomatic)
    }
    static let systemDNSUnreachable = Hint(id: "system-dns-unreachable", title: "System DNS not responding",
        message: "The system DNS doesn't respond on this network; the portal was found by querying the access point. If the page doesn't show, check that no encrypted DNS or network filter is active.")
    static func manualDNS(_ servers: String) -> Hint {
        Hint(id: "manual-dns", title: "A manual DNS is set",
             message: "A manual DNS is set (\(servers)). Many public networks block it: try “Switch DNS to automatic”.",
             action: .switchDNSToAutomatic)
    }
    static let noResponse = Hint(id: "no-response", title: "No response from the network",
        message: "No response from the network. Check that Wi-Fi is properly associated, or try “Force an HTTP page”.",
        action: .forceHTTPPage)
}

private extension Optional {
    func asyncMap<U>(_ f: (Wrapped) async -> U) async -> U? {
        if let self { await f(self) } else { nil }
    }
}

/// Reports network changes (Wi-Fi joined, cable unplugged, VPN…).
public final class NetworkMonitor: Sendable {
    public init() {}

    /// One event per network path change (debounced 0.5 s). Ends when the task is cancelled.
    public func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            struct State { var initial = true; var pending: Task<Void, Never>? }
            let state = OSAllocatedUnfairLock(initialState: State())
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { _ in
                state.withLock { st in
                    // The first update is the current path, not a change.
                    if st.initial { st.initial = false; return }
                    st.pending?.cancel()
                    st.pending = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        if !Task.isCancelled { continuation.yield() }
                    }
                }
            }
            continuation.onTermination = { _ in
                monitor.cancel()
                state.withLock { $0.pending?.cancel() }
            }
            monitor.start(queue: DispatchQueue(label: "ConnectNow.monitor"))
        }
    }
}
