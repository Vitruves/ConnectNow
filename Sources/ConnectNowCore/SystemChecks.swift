import Darwin
import Foundation
import SystemConfiguration

// Things on the Mac itself that can keep a portal page from showing up.

extension SystemNetwork {
    /// Proxies the system uses, and so does the portal window. Empty when there are none.
    static func proxies() -> [String] {
        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return [] }
        return proxyDescriptions(settings)
    }

    static func proxyDescriptions(_ d: [String: Any]) -> [String] {
        func on(_ key: String) -> Bool { (d[key] as? NSNumber)?.boolValue == true }
        var out: [String] = []
        if on("ProxyAutoDiscoveryEnable") { out.append("automatic proxy discovery (WPAD)") }
        if on("ProxyAutoConfigEnable") {
            let url = (d["ProxyAutoConfigURLString"] as? String).map { " \($0)" } ?? ""
            out.append("a proxy configuration file\(url)")
        }
        for (name, prefix) in [("HTTP", "HTTP"), ("HTTPS", "HTTPS"), ("SOCKS", "SOCKS")] where on("\(prefix)Enable") {
            let host = d["\(prefix)Proxy"] as? String ?? "?"
            let port = (d["\(prefix)Port"] as? NSNumber).map { ":\($0)" } ?? ""
            out.append("a \(name) proxy (\(host)\(port))")
        }
        return out
    }

    /// The interface currently uses a private (randomised) Wi-Fi address.
    static func usesPrivateAddress(device: String) -> Bool {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return false }
        defer { freeifaddrs(head) }
        for ifa in sequence(first: head, next: { $0?.pointee.ifa_next }).compactMap({ $0?.pointee }) {
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: ifa.ifa_name) == device else { continue }
            let mac = sa.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl -> [UInt8] in
                let p = dl.pointee
                guard p.sdl_alen == 6 else { return [] }
                return withUnsafeBytes(of: dl.pointee.sdl_data) { Array($0[Int(p.sdl_nlen)..<Int(p.sdl_nlen) + 6]) }
            }
            return isLocallyAdministered(mac)
        }
        return false
    }

    /// Randomised addresses set the "locally administered" bit; factory addresses never do.
    static func isLocallyAdministered(_ mac: [UInt8]) -> Bool {
        mac.count == 6 && mac[0] & 0x02 != 0
    }
}

public enum SystemChecks {
    /// Enabled third-party network extensions (firewalls, content filters, VPNs, proxies, DNS).
    /// Runs systemextensionsctl: call once, off the main thread.
    public static func networkExtensions() -> [String] {
        guard let output = try? Subprocess.run("/usr/bin/systemextensionsctl", ["list"]) else { return [] }
        return parseNetworkExtensions(output)
    }

    /// Keeps the names of network extensions that are activated and enabled.
    static func parseNetworkExtensions(_ output: String) -> [String] {
        var inNetworkSection = false
        var names: [String] = []
        for line in output.split(separator: "\n") {
            if line.hasPrefix("---") {
                inNetworkSection = line.contains("com.apple.system_extension.network_extension")
                continue
            }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard inNetworkSection, fields.count >= 6, fields.last?.contains("activated enabled") == true else { continue }
            let name = fields[fields.count - 2]
            if !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        return names
    }
}

extension Hint {
    public static func proxy(_ proxies: [String]) -> Hint {
        Hint(id: "proxy", title: "A web proxy is configured",
             message: "This Mac uses \(proxies.joined(separator: ", ")). The portal window goes through it, so the sign-in page may never load. Turn it off while you sign in: System Settings → Wi-Fi → Details → Proxies.")
    }

    public static let privateAddress = Hint(id: "private-address", title: "Private Wi-Fi address is on",
        message: "Portals recognise devices by their Wi-Fi address. If this one keeps asking you to sign in again, set “Private Wi-Fi address” to Fixed for this network: System Settings → Wi-Fi → Details.",
        severity: .info)

    public static func networkExtensions(_ names: [String]) -> Hint {
        Hint(id: "network-extensions", title: "Network extensions are active",
             message: "\(names.joined(separator: ", ")). Firewalls, content filters, VPNs and proxies built on them can hide the sign-in page: pause them while you sign in. iCloud Private Relay can too: turn off “Limit IP address tracking” in System Settings → Wi-Fi → Details.")
    }
}
