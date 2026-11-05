import Testing
@testable import ConnectNowCore

@Test func describesEnabledProxiesOnly() {
    let d: [String: Any] = [
        "ProxyAutoDiscoveryEnable": 1,
        "ProxyAutoConfigEnable": 1, "ProxyAutoConfigURLString": "http://wpad/wpad.dat",
        "HTTPEnable": 1, "HTTPProxy": "10.0.0.1", "HTTPPort": 3128,
        "HTTPSEnable": 0, "HTTPSProxy": "ignored",
    ]
    #expect(SystemNetwork.proxyDescriptions(d) == [
        "automatic proxy discovery (WPAD)",
        "a proxy configuration file http://wpad/wpad.dat",
        "a HTTP proxy (10.0.0.1:3128)",
    ])
    #expect(SystemNetwork.proxyDescriptions([:]).isEmpty)
}

@Test func detectsRandomisedWiFiAddress() {
    #expect(SystemNetwork.isLocallyAdministered([0x0a, 0x19, 0x1a, 0x06, 0x9a, 0x45]))
    #expect(!SystemNetwork.isLocallyAdministered([0x50, 0xa6, 0xd8, 0xd9, 0x5b, 0xfc]))
    #expect(!SystemNetwork.isLocallyAdministered([]))
}

@Test func parsesActiveNetworkExtensions() {
    let output = """
    3 extension(s)
    --- com.apple.system_extension.network_extension (Go to 'System Settings > General > Login Items & Extensions > Network Extensions' to modify these system extension(s))
    enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
    *\t*\tJ6S6Q257EK\tch.protonvpn.mac.WireGuard-Extension (6.5.2/1)\tProton VPN WireGuard\t[activated enabled]
    \t\tABCDE12345\tcom.example.filter (1.0/1)\tOld Filter\t[terminated waiting to uninstall on reboot]
    --- com.apple.system_extension.driver_extension
    enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
    *\t*\tXYZ\tcom.example.driver (1.0/1)\tSome Driver\t[activated enabled]
    """
    #expect(SystemChecks.parseNetworkExtensions(output) == ["Proton VPN WireGuard"])
}

@Test func proxyAndPrivateAddressHintsComeLast() {
    var s = ScanResult()
    s.status = .captive
    let h = hints(for: s, target: Target(interface: "en0"), defaultInterface: "en0", wifiNote: nil,
                  proxies: ["a HTTP proxy (10.0.0.1:3128)"], privateAddress: true)
    #expect(h.map(\.id) == ["proxy", "private-address"])
    s.status = .offline
    let offline = hints(for: s, target: Target(interface: "en0"), defaultInterface: "en0", wifiNote: nil, privateAddress: true)
    #expect(offline.map(\.id) == ["no-response"])  // the address only matters once a portal is found
}
