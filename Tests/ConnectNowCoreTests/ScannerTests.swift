import Foundation
import Testing
@testable import ConnectNowCore

private func ids(_ h: [Hint]) -> [String] { h.map(\.id) }

@Test func hintsVPNBypassedAndManualDNSBlocked() {
    var s = ScanResult()
    s.status = .captive; s.usedDNSFallback = true; s.manualDNS = ["1.1.1.1", "8.8.8.8"]
    s.portals = [Portal(url: URL(string: "http://p.example/")!, source: .probe("Apple"))]
    let h = hints(for: s, target: Target(interface: "en0"), defaultInterface: "utun4", wifiNote: nil)
    #expect(ids(h) == ["vpn-bypassed", "manual-dns-blocked"])
    #expect(h[0].message.contains("utun4"))
    #expect(h[1].message.contains("1.1.1.1, 8.8.8.8"))
    #expect(h[1].action == .switchDNSToAutomatic)
}

@Test func hintsVPNActiveOtherInterfaceAndDNS() {
    var s = ScanResult()
    s.status = .captive
    #expect(ids(hints(for: s, target: Target(interface: "utun2"), defaultInterface: "utun2", wifiNote: nil)) == ["vpn-active"])
    s.manualDNS = ["9.9.9.9"]
    let h = hints(for: s, target: Target(interface: "en0"), defaultInterface: "en7", wifiNote: .wifiSelfAssigned)
    #expect(ids(h) == ["wifi-self-assigned", "other-interface", "manual-dns"])
    s.manualDNS = []; s.usedDNSFallback = true
    #expect(ids(hints(for: s, target: Target(interface: "en0"), defaultInterface: "en0", wifiNote: nil)) == ["system-dns-unreachable"])
}

@Test func hintNoResponseOnlyWhenNothingElse() {
    var s = ScanResult()
    s.status = .offline
    let h = hints(for: s, target: Target(interface: "en0"), defaultInterface: "en0", wifiNote: nil)
    #expect(ids(h) == ["no-response"])
    #expect(h[0].action == .forceHTTPPage)
    s.portals = [Portal(url: URL(string: "http://10.0.0.1/")!, source: .gateway(port: 80))]
    #expect(hints(for: s, target: Target(interface: "en0"), defaultInterface: "en0", wifiNote: nil).isEmpty)
}

@Test func gatewayPortalURLs() async throws {
    // Port 80/8080/443 are normally closed on loopback in CI; only the URL shape matters if one is open.
    let portals = await gatewayPortals(IPAddress("127.0.0.1")!, binding: Binding())
    for p in portals {
        guard case .gateway(let port) = p.source else { Issue.record("wrong source"); continue }
        let want = ["http://127.0.0.1/", "http://127.0.0.1:8080/", "https://127.0.0.1/"][[80, 8080, 443].firstIndex(of: port)!]
        #expect(p.url.absoluteString == want)
    }
}

@Test(.timeLimit(.minutes(1))) func fullScanCompletesQuickly() async {
    let start = ContinuousClock.now
    let r = await NetworkScanner().scan()
    #expect(start.duration(to: .now) < .seconds(9))
    #expect(r.status != .scanning)
    #expect(r.probes.isEmpty || r.probes.count == Probe.all.count)
}
