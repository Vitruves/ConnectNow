import Foundation
import Testing
@testable import ConnectNowCore

@Suite struct SystemNetworkParsingTests {
    @Test func firstIPv4FromDHCPBytes() {
        #expect(SystemNetwork.firstIPv4([192, 168, 1, 1]) == "192.168.1.1")
        #expect(SystemNetwork.firstIPv4([10, 0, 0, 1, 8, 8, 8, 8]) == "10.0.0.1")
        #expect(SystemNetwork.firstIPv4([10, 0, 0]) == nil)
        #expect(SystemNetwork.firstIPv4([]) == nil)
    }

    @Test func captivePortalURLFromDHCPBytes() {
        let bytes = Array("https://portal.example/api\0".utf8)
        #expect(SystemNetwork.captivePortalURL(bytes) == URL(string: "https://portal.example/api"))
        #expect(SystemNetwork.captivePortalURL(Array(" http://10.0.0.1/c \n".utf8)) == URL(string: "http://10.0.0.1/c"))
        #expect(SystemNetwork.captivePortalURL(Array("urn:ietf:params:capport:unrestricted".utf8)) == nil)
        #expect(SystemNetwork.captivePortalURL(Array("ftp://x/".utf8)) == nil)
        #expect(SystemNetwork.captivePortalURL([]) == nil)
    }

    @Test func selfAssignedRange() {
        #expect(SystemNetwork.isSelfAssigned(0xA9FE_0102))   // 169.254.1.2
        #expect(!SystemNetwork.isSelfAssigned(0xC0A8_0101))  // 192.168.1.1
        #expect(!SystemNetwork.isSelfAssigned(0xA9FF_0001))  // 169.255.0.1
    }

    @Test func ipValidation() {
        #expect(SystemNetwork.isIPAddress("192.168.1.1"))
        #expect(SystemNetwork.isIPAddress("fe80::1"))
        #expect(!SystemNetwork.isIPAddress("link#12"))
        #expect(!SystemNetwork.isIPAddress(""))
    }

    @Test func dedupeKeepsOrder() {
        #expect(SystemNetwork.dedupe(["1.1.1.1", "8.8.8.8", "1.1.1.1", "9.9.9.9", "8.8.8.8"]) == ["1.1.1.1", "8.8.8.8", "9.9.9.9"])
    }

    @Test func vpnDetection() {
        for name in ["utun0", "utun4", "ipsec0", "ppp0", "tun1", "tap0"] { #expect(SystemNetwork.isVPN(name)) }
        for name in ["en0", "en1", "bridge0", "lo0", "awdl0"] { #expect(!SystemNetwork.isVPN(name)) }
    }

    @Test func unknownInterfaceHasNoAddress() {
        #expect(SystemNetwork.address(of: "nosuchif99") == nil)
        #expect(SystemNetwork.address(of: "lo0")?.hasUsableIPv4 == true)
    }
}

/// Prints this machine's real values. Enable with CONNECTNOW_SYSTEM_DUMP=1.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CONNECTNOW_SYSTEM_DUMP"] != nil))
func dumpRealSystemValues() {
    let route = SystemNetwork.defaultRoute()
    let wifi = SystemNetwork.wifiService()
    let device = wifi?.device ?? route.interface ?? "en0"
    print("defaultRoute:", route)
    print("wifiService:", wifi as Any)
    print("serviceName(forDevice: \(device)):", SystemNetwork.serviceName(forDevice: device) as Any)
    if let i = route.interface { print("serviceName(forDevice: \(i)):", SystemNetwork.serviceName(forDevice: i) as Any) }
    print("dnsServers:", SystemNetwork.dnsServers())
    if let s = wifi?.serviceName { print("manualDNS(\(s)):", SystemNetwork.manualDNS(service: s)) }
    print("dhcpRouter:", SystemNetwork.dhcpRouter(interface: device) as Any)
    print("dhcpDNS:", SystemNetwork.dhcpDNS(interface: device) as Any)
    print("dhcpCaptivePortalURL:", SystemNetwork.dhcpCaptivePortalURL(interface: device) as Any)
    print("address(of: \(device)):", SystemNetwork.address(of: device) as Any)
    print("isWiFiPoweredOff:", SystemNetwork.isWiFiPoweredOff(device: device))
    print("DNSSwitcher.isSwitched:", DNSSwitcher.isSwitched)
}
