import Foundation

enum PortalTrust {
    /// A hotspot cannot hold a valid certificate for a local IP, so an invalid certificate is
    /// accepted only in that case (or for the gateway), never for a domain name.
    static func acceptsInvalidCertificate(host rawHost: String, gateway: String?) -> Bool {
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let v4 = ipv4(host) {
            let (a, b) = (v4[0], v4[1])
            return a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
                || (a == 169 && b == 254) || host == gateway
        }
        if let v6 = ipv6(host) {
            let loopback = v6[..<15].allSatisfy { $0 == 0 } && v6[15] == 1
            return loopback || v6[0] & 0xFE == 0xFC || (v6[0] == 0xFE && v6[1] & 0xC0 == 0x80)
                || host == gateway
        }
        return false
    }

    private static func ipv4(_ s: String) -> [UInt8]? {
        var addr = in_addr()
        guard inet_pton(AF_INET, s, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }

    private static func ipv6(_ s: String) -> [UInt8]? {
        // Strip any zone identifier (fe80::1%en0).
        let bare = s.split(separator: "%", maxSplits: 1).first.map(String.init) ?? s
        var addr = in6_addr()
        guard inet_pton(AF_INET6, bare, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }
}
