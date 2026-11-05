#if DEBUG
import Foundation
import ConnectNowCore

/// Sample states for screenshots: CONNECTNOW_DEMO=captive|online|offline|nonet|scanning.
/// CONNECTNOW_APPEARANCE=dark|light forces the appearance; add `-detailsExpanded YES` to the command line to open the Details section.
enum DemoData {
    static var requested: String? { ProcessInfo.processInfo.environment["CONNECTNOW_DEMO"].flatMap { $0.isEmpty ? nil : $0 } }

    static func scan(_ name: String) async -> ScanResult {
        if name == "scanning" {
            try? await Task.sleep(for: .seconds(3600))
            return ScanResult()
        }
        try? await Task.sleep(for: .milliseconds(900))
        var r = ScanResult()
        r.interface = "en0"
        r.isWiFi = true
        r.defaultInterface = "en0"
        r.service = "Wi-Fi"
        r.gateway = "10.12.0.1"
        r.dnsServers = ["10.12.0.1"]
        func probe(_ name: String, _ url: String, _ state: ProbeState, _ detail: String, _ ms: Int?, portal: String? = nil) -> ProbeResult {
            ProbeResult(name: name, url: URL(string: url)!, state: state, detail: detail,
                        latency: ms.map { .milliseconds($0) }, portalURL: portal.flatMap(URL.init(string:)))
        }
        switch name {
        case "online":
            r.status = .online
            r.gateway = "192.168.1.254"
            r.dnsServers = ["192.168.1.254", "2a01:cb00::1"]
            r.probes = [
                probe("Apple", "http://captive.apple.com/hotspot-detect.html", .ok, "HTTP 200, Success", 38),
                probe("Google", "http://connectivitycheck.gstatic.com/generate_204", .ok, "HTTP 204", 24),
                probe("Microsoft", "http://www.msftconnecttest.com/connecttest.txt", .ok, "HTTP 200", 41),
            ]
        case "offline":
            r.status = .offline
            r.manualDNS = ["1.1.1.1", "8.8.8.8"]
            r.dnsServers = r.manualDNS
            r.probes = [
                probe("Apple", "http://captive.apple.com/hotspot-detect.html", .error, "DNS lookup failed", nil),
                probe("Google", "http://connectivitycheck.gstatic.com/generate_204", .error, "Timed out", nil),
            ]
            r.hints = [
                Hint(id: "manual-dns", title: "Manual DNS servers are blocked here",
                     message: "Public hotspots usually only answer their own DNS. Switch to automatic DNS while you sign in.",
                     action: .switchDNSToAutomatic),
            ]
        case "nonet":
            r = ScanResult()
            r.status = .noNetwork
            r.hints = [Hint(id: "wifi-off", title: "Wi-Fi is turned off",
                            message: "Turn Wi-Fi on from Control Center, then join the hotspot.")]
        default:
            r.status = .captive
            r.portals = [
                Portal(url: URL(string: "https://wifi.hotspot.example/login?redirect=example.com")!, source: .probe("Apple")),
                Portal(url: URL(string: "http://10.12.0.1:8002/index.php?zone=guest")!, source: .announced),
                Portal(url: URL(string: "http://10.12.0.1/")!, source: .gateway(port: 80)),
            ]
            r.probes = [
                probe("Apple", "http://captive.apple.com/hotspot-detect.html", .portal, "HTTP 302 → wifi.hotspot.example", 112,
                      portal: "https://wifi.hotspot.example/login"),
                probe("Google", "http://connectivitycheck.gstatic.com/generate_204", .portal, "HTTP 200 instead of 204", 96),
                probe("Microsoft", "http://www.msftconnecttest.com/connecttest.txt", .error, "Connection reset", nil),
            ]
            r.hints = [
                Hint(id: "vpn-active", title: "A VPN is active",
                     message: "Pause it until you've signed in: the hotspot can't redirect encrypted traffic.",
                     severity: .info),
                .proxy(["automatic proxy discovery (WPAD)"]),
                .privateAddress,
            ]
        }
        return r
    }
}
#endif
