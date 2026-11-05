import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration
import SystemConfiguration.SCDynamicStoreCopyDHCPInfo

// System layer: native reads via SystemConfiguration, getifaddrs and CoreWLAN.

struct DefaultRoute: Sendable, Hashable { var interface: String?; var gateway: String? }
struct WiFiService: Sendable, Hashable { var serviceName: String; var device: String }
struct InterfaceAddress: Sendable, Hashable { var index: UInt32; var hasUsableIPv4: Bool; var isSelfAssigned: Bool }

enum SystemNetwork {
    /// Interface and router of the default IPv4 route.
    static func defaultRoute() -> DefaultRoute {
        let ipv4 = DynamicStore.dictionary("State:/Network/Global/IPv4")
        let gateway = (ipv4?[kSCPropNetIPv4Router as String] as? String).flatMap { isIPAddress($0) ? $0 : nil }
        return DefaultRoute(interface: ipv4?[kSCDynamicStorePropNetPrimaryInterface as String] as? String, gateway: gateway)
    }

    /// Wi-Fi network service and its BSD device (en0…), if any.
    static func wifiService() -> WiFiService? {
        NetworkPreferences.services().first { $0.type == (kSCNetworkInterfaceTypeIEEE80211 as String) }
            .map { WiFiService(serviceName: $0.name, device: $0.device) }
    }

    /// macOS network service name for a BSD device.
    static func serviceName(forDevice device: String) -> String? {
        NetworkPreferences.services().first { $0.device == device }?.name
    }

    /// DNS servers actually used by the system, deduplicated.
    static func dnsServers() -> [String] {
        let key = kSCPropNetDNSServerAddresses as String
        let global = DynamicStore.dictionary("State:/Network/Global/DNS")?[key] as? [String] ?? []
        // Like configd: a manual DNS (Setup:) overrides the DHCP-learned one (State:).
        let manual = DynamicStore.dictionaries(matching: "Setup:/Network/Service/[^/]+/DNS")
            .compactMapValues { $0[key] as? [String] }
            .reduce(into: [String: [String]]()) { $0[$1.key.replacingOccurrences(of: "Setup:", with: "State:")] = $1.value }
        let perService = DynamicStore.dictionaries(matching: "State:/Network/Service/[^/]+/DNS")
            .sorted { $0.key < $1.key }
            .flatMap { manual[$0.key] ?? $0.value[key] as? [String] ?? [] }
        return dedupe(global + perService)
    }

    /// DNS servers entered manually on a service (empty if automatic).
    static func manualDNS(service: String) -> [String] {
        NetworkPreferences.services().first { $0.name == service }?.manualDNS ?? []
    }

    /// Raw DHCP option: router (3), DNS (6), captive portal API URL (114).
    static func dhcpRouter(interface: String) -> String? { DHCP.option(3, interface: interface).flatMap(firstIPv4) }
    static func dhcpDNS(interface: String) -> String? { DHCP.option(6, interface: interface).flatMap(firstIPv4) }
    static func dhcpCaptivePortalURL(interface: String) -> URL? {
        DHCP.option(114, interface: interface).flatMap(captivePortalURL)
    }

    /// IPv4 addresses of an interface.
    static func address(of interface: String) -> InterfaceAddress? {
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        var result = InterfaceAddress(index: index, hasUsableIPv4: false, isSelfAssigned: false)
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return result }
        defer { freeifaddrs(head) }
        for ifa in sequence(first: head, next: { $0?.pointee.ifa_next }).compactMap({ $0?.pointee }) {
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ifa.ifa_name) == interface else { continue }
            let addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if isSelfAssigned(addr) { result.isSelfAssigned = true } else { result.hasUsableIPv4 = true }
        }
        return result
    }

    /// Wi-Fi is powered off.
    static func isWiFiPoweredOff(device: String) -> Bool {
        if let wifi = CWWiFiClient.shared().interface(withName: device) { return !wifi.powerOn() }
        // Fallback when CoreWLAN does not know the interface.
        return (try? Subprocess.run("/usr/sbin/networksetup", ["-getairportpower", device]))?.contains(": Off") ?? false
    }

    /// VPN / tunnel interface.
    static func isVPN(_ interface: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap"].contains { interface.hasPrefix($0) }
    }

    // MARK: Pure helpers (unit-tested)

    /// First IPv4 of an address-list DHCP option (3, 6).
    static func firstIPv4(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 4 else { return nil }
        return bytes[0..<4].map(String.init).joined(separator: ".")
    }

    /// Option 114 URL (RFC 8910): text, sometimes NUL-terminated.
    static func captivePortalURL(_ bytes: [UInt8]) -> URL? {
        let text = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// 169.254.0.0/16: self-assigned address, no DHCP reply.
    static func isSelfAssigned(_ hostOrderIPv4: UInt32) -> Bool { hostOrderIPv4 >> 16 == 0xA9FE }

    static func isIPAddress(_ s: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, s, &v4) == 1 || inet_pton(AF_INET6, s, &v6) == 1
    }

    static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

// MARK: - SCDynamicStore

private enum DynamicStore {
    static func make() -> SCDynamicStore? { SCDynamicStoreCreate(nil, "ConnectNow" as CFString, nil, nil) }

    static func dictionary(_ key: String) -> [String: Any]? {
        guard let store = make() else { return nil }
        return SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    }

    static func dictionaries(matching pattern: String) -> [String: [String: Any]] {
        guard let store = make(), let keys = SCDynamicStoreCopyKeyList(store, pattern as CFString) as? [String],
              let values = SCDynamicStoreCopyMultiple(store, keys as CFArray, nil) as? [String: Any] else { return [:] }
        return values.compactMapValues { $0 as? [String: Any] }
    }
}

private enum DHCP {
    static func option(_ code: UInt8, interface: String) -> [UInt8]? {
        guard let store = DynamicStore.make(), let id = serviceID(for: interface),
              let info = SCDynamicStoreCopyDHCPInfo(store, id as CFString),
              let data = DHCPInfoGetOptionData(info, code) else { return nil }
        return [UInt8](data as Data)
    }

    /// Active service of the interface, from its IPv4 state.
    private static func serviceID(for interface: String) -> String? {
        DynamicStore.dictionaries(matching: "State:/Network/Service/[^/]+/IPv4")
            .first { $0.value[kSCPropInterfaceName as String] as? String == interface }
            .map { $0.key.split(separator: "/")[3].description }
    }
}

// MARK: - Network preferences (Setup:)

private enum NetworkPreferences {
    struct Service { var name: String; var device: String; var type: String; var manualDNS: [String] }

    /// Services of the current location, in macOS priority order.
    static func services() -> [Service] {
        guard let prefs = SCPreferencesCreate(nil, "ConnectNow" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs),
              let all = SCNetworkSetCopyServices(set) as? [SCNetworkService] else { return [] }
        let order = SCNetworkSetGetServiceOrder(set) as? [String] ?? []
        let rank = { (s: SCNetworkService) in
            (SCNetworkServiceGetServiceID(s) as String?).flatMap(order.firstIndex) ?? .max
        }
        return all.sorted { rank($0) < rank($1) }.compactMap { service in
            guard let name = SCNetworkServiceGetName(service) as String?,
                  let iface = SCNetworkServiceGetInterface(service),
                  let device = SCNetworkInterfaceGetBSDName(iface) as String? else { return nil }
            let type = SCNetworkInterfaceGetInterfaceType(iface) as String? ?? ""
            let dns = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS)
                .flatMap(SCNetworkProtocolGetConfiguration) as? [String: Any]
            let servers = dns?[kSCPropNetDNSServerAddresses as String] as? [String] ?? []
            return Service(name: name, device: device, type: type, manualDNS: servers)
        }
    }
}

// MARK: - Subprocess

enum Subprocess {
    struct Failure: Error { var output: String; var status: Int32 }

    /// Runs an executable and returns its combined output; throws on a non-zero exit status.
    static func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw Failure(output: output, status: process.terminationStatus) }
        return output
    }
}
