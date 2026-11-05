import Testing
@testable import ConnectNowCore

@Test func canSwitchDNSRequiresManualDNSAndService() {
    var s = ScanResult()
    s.status = .captive
    #expect(!s.canSwitchDNS)
    s.manualDNS = ["1.1.1.1"]; s.service = "Wi-Fi"
    #expect(s.canSwitchDNS)
}
