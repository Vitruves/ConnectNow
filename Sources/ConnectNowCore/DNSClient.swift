import Darwin

/// Minimal DNS client (A records, UDP 53) querying the analysed network's own DNS
/// directly: useful when a custom DNS (1.1.1.1…) is blocked until authenticated.
enum DNSClient {
    /// Recursive A query for `name`.
    static func query(id: UInt16, name: String) -> [UInt8]? {
        var q: [UInt8] = [UInt8(id >> 8), UInt8(id & 0xff), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            guard (1...63).contains(bytes.count) else { return nil }
            q.append(UInt8(bytes.count)); q += bytes
        }
        q += [0, 0, 1, 0, 1] // end of name, type A, class IN
        return q
    }

    /// IPv4 addresses of the response; nil if it doesn't match `id` or is malformed.
    static func parseResponse(_ p: [UInt8], id: UInt16) -> [in_addr]? {
        guard p.count >= 12, UInt16(p[0]) << 8 | UInt16(p[1]) == id, p[2] & 0x80 != 0 else { return nil }
        guard p[3] & 0x0f == 0 else { return [] } // RCODE ≠ 0: unknown name, refused…
        let u16 = { (i: Int) -> Int in Int(p[i]) << 8 | Int(p[i + 1]) }
        let qd = u16(4), an = u16(6)
        var i = 12
        // Skips a name (labels or compression pointer).
        func skipName() -> Bool {
            while i < p.count {
                let len = Int(p[i])
                if len == 0 { i += 1; return true }
                if len & 0xc0 == 0xc0 { i += 2; return i <= p.count }
                i += len + 1
            }
            return false
        }
        for _ in 0..<qd { guard skipName(), i + 4 <= p.count else { return nil }; i += 4 }
        var out: [in_addr] = []
        for _ in 0..<an {
            guard skipName(), i + 10 <= p.count else { return nil }
            let type = u16(i), cls = u16(i + 2), rdlen = u16(i + 8)
            i += 10
            guard i + rdlen <= p.count else { return nil }
            if type == 1, cls == 1, rdlen == 4 {
                out.append(in_addr(s_addr: (UInt32(p[i]) << 24 | UInt32(p[i + 1]) << 16 | UInt32(p[i + 2]) << 8 | UInt32(p[i + 3])).bigEndian))
            }
            i += rdlen
        }
        return out
    }

    /// Resolves `name` via `server` over a socket bound to the interface. Two attempts.
    static func resolve(_ name: String, server: IPAddress, port: UInt16 = 53, binding: Binding,
                        timeout: Duration = .milliseconds(1500)) async throws -> [IPAddress] {
        if let ip = IPAddress(name) { return [ip] }
        return try await blocking {
            let id = UInt16.random(in: .min ... .max)
            guard let q = query(id: id, name: name) else { throw NetError.dns(name) }
            let s = try BoundSocket.connect(server, port: port, type: SOCK_DGRAM, binding: binding, timeout: timeout)
            let end = ContinuousClock.now + timeout
            for attempt in 1...2 {
                try s.send(q, until: end)
                let attemptEnd = attempt == 1 ? ContinuousClock.now + timeout / 2 : end
                // Ignore datagrams that aren't our answer.
                while true {
                    guard let r = try? s.receive(max: 1500, until: attemptEnd) else { break }
                    if let addrs = parseResponse(r, id: id) {
                        guard !addrs.isEmpty else { throw NetError.dns(name) }
                        return addrs.map(IPAddress.v4)
                    }
                }
            }
            throw NetError.dns(name)
        }
    }
}
