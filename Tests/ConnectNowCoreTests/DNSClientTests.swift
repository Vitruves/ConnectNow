import Darwin
import Testing
@testable import ConnectNowCore

@Test func encodeQuery() throws {
    let q = try #require(DNSClient.query(id: 0xBEEF, name: "a.bc"))
    #expect(q == [0xBE, 0xEF, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0, 1, 97, 2, 98, 99, 0, 0, 1, 0, 1])
    #expect(DNSClient.query(id: 1, name: String(repeating: "x", count: 64)) == nil)
}

/// Response to the query above: one CNAME then one A record, names compressed.
func sampleResponse(id: UInt16 = 0xBEEF, rcode: UInt8 = 0) -> [UInt8] {
    var r = DNSClient.query(id: id, name: "a.bc")!
    r[2] = 0x81; r[3] = 0x80 | rcode; r[7] = 2  // QR + RD/RA, 2 answers
    r += [0xC0, 12, 0, 5, 0, 1, 0, 0, 0, 60, 0, 4, 1, 120, 0xC0, 14]   // CNAME → x.bc
    r += [0xC0, 34, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 192, 168, 1, 10]     // A 192.168.1.10
    return r
}

@Test func decodeResponse() throws {
    let addrs = try #require(DNSClient.parseResponse(sampleResponse(), id: 0xBEEF))
    #expect(addrs.map { IPAddress.v4($0).description } == ["192.168.1.10"])
}

@Test func decodeRejectsWrongIDOrTruncated() {
    #expect(DNSClient.parseResponse(sampleResponse(), id: 0x1234) == nil)
    #expect(DNSClient.parseResponse(Array(sampleResponse().dropLast(2)), id: 0xBEEF) == nil)
    #expect(DNSClient.parseResponse(sampleResponse(rcode: 3), id: 0xBEEF)?.isEmpty == true)  // NXDOMAIN
}

@Test func ipAddressRoundTrip() {
    #expect(IPAddress("10.0.0.1")?.description == "10.0.0.1")
    #expect(IPAddress("fe80::1")?.urlHost == "[fe80::1]")
    #expect(IPAddress("captive.apple.com") == nil)
}

/// Real UDP exchange against a fake DNS server on loopback.
@Test func resolveOverUDP() async throws {
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    defer { close(fd) }
    var addr = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET),
                           sin_port: 0, sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
    _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
    let port = UInt16(bigEndian: addr.sin_port)
    // Answer the first query with 192.168.1.10, echoing its id.
    let server = Task.detached {
        var buf = [UInt8](repeating: 0, count: 512)
        var peer = sockaddr_storage(), plen = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let n = withUnsafeMutablePointer(to: &peer) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &plen) } }
        guard n >= 12 else { return }
        let reply = sampleResponse(id: UInt16(buf[0]) << 8 | UInt16(buf[1]))
        _ = withUnsafePointer(to: &peer) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, reply, reply.count, 0, $0, plen) } }
    }
    let ips = try await DNSClient.resolve("a.bc", server: IPAddress("127.0.0.1")!, port: port, binding: Binding())
    await server.value
    #expect(ips.map(\.description) == ["192.168.1.10"])
}
