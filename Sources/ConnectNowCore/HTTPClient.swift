import Foundation
import Network
import os

struct HTTPResponse: Sendable, Equatable {
    var status: Int
    var headers: [String: String]   // lowercased names, first occurrence wins
    var body: [UInt8]
    var text: String { String(decoding: body, as: UTF8.self) }
    subscript(header name: String) -> String? { headers[name.lowercased()] }
}

/// Minimal HTTP/1.1: one GET per connection, `Connection: close`.
enum HTTP {
    static let maxBody = 64 << 10
    static let userAgent = "CaptiveNetworkSupport-ConnectNow wispr"
    private static let crlf: [UInt8] = [13, 10]

    static func request(_ url: URL, accept: String) -> [UInt8] {
        let c = URLComponents(url: url, resolvingAgainstBaseURL: true)
        var target = c?.percentEncodedPath ?? "/"
        if target.isEmpty { target = "/" }
        if let q = c?.percentEncodedQuery { target += "?" + q }
        var host = url.host ?? ""
        if host.contains(":") { host = "[\(host)]" }
        if let port = url.port { host += ":\(port)" }
        return Array("""
            GET \(target) HTTP/1.1\r
            Host: \(host)\r
            User-Agent: \(userAgent)\r
            Accept: \(accept)\r
            Cache-Control: no-cache\r
            Connection: close\r
            \r

            """.utf8)
    }

    /// Parses a raw response; nil while more bytes are needed.
    /// At end of stream, returns whatever body was received.
    static func parse(_ raw: [UInt8], atEOF: Bool) throws(NetError) -> HTTPResponse? {
        guard let headEnd = raw.firstRange(of: crlf + crlf) else {
            if atEOF || raw.count > maxBody { throw .malformed }
            return nil
        }
        let lines = String(decoding: raw[..<headEnd.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let statusLine = lines[0].split(separator: " ", maxSplits: 2)
        guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/"), let status = Int(statusLine[1]) else { throw .malformed }
        let rest = Array(raw[headEnd.upperBound...])
        // Interim response (100 Continue…): the real one follows.
        if (100..<200).contains(status) && status != 101 { return try parse(rest, atEOF: atEOF) }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if headers[name] == nil { headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) }
        }
        func done(_ body: some Collection<UInt8>) -> HTTPResponse {
            HTTPResponse(status: status, headers: headers, body: Array(body.prefix(maxBody)))
        }

        if status < 200 || status == 204 || status == 304 { return done([]) }
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            let (body, complete) = dechunk(rest)
            return complete || atEOF || body.count >= maxBody ? done(body) : nil
        }
        if let length = headers["content-length"].flatMap(Int.init), length >= 0 {
            return rest.count >= min(length, maxBody) || atEOF ? done(rest.prefix(length)) : nil
        }
        return atEOF || rest.count >= maxBody ? done(rest) : nil
    }

    /// Decodes a chunked body; `complete` once the final chunk is seen.
    static func dechunk(_ b: [UInt8]) -> (body: [UInt8], complete: Bool) {
        var out: [UInt8] = [], i = 0
        while let lineEnd = b[i...].firstRange(of: crlf) {
            let sizeField = String(decoding: b[i..<lineEnd.lowerBound], as: UTF8.self)
                .split(separator: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let size = Int(sizeField, radix: 16), size >= 0 else { return (out, true) } // malformed: stop here
            if size == 0 { return (out, true) }
            let start = lineEnd.upperBound
            guard start + size <= b.count else { return (out + b[start...], false) }
            out += b[start..<start + size]
            i = min(start + size + 2, b.count)
        }
        return (out, false)
    }
}

/// HTTP client whose connections are bound to the analysed interface.
/// Plain HTTP over BSD sockets; HTTPS (RFC 8908 API only) over Network.framework.
struct HTTPClient: Sendable {
    enum Resolver: Sendable, Hashable {
        case system
        case server(IPAddress)   // the network's own DNS, queried directly
    }

    var binding = Binding()
    var resolver = Resolver.system
    var connectTimeout: Duration = .seconds(3)
    var timeout: Duration = .seconds(5)
    var dnsTimeout: Duration = .seconds(2)

    func get(_ url: URL, accept: String = "*/*", deadline: ContinuousClock.Instant? = nil) async throws -> HTTPResponse {
        let end = min(deadline ?? .now + timeout, .now + timeout)
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { throw NetError.other("unsupported URL") }
        let tls = scheme == "https"
        let port = UInt16(clamping: url.port ?? (tls ? 443 : 80))

        let dnsWait = min(dnsTimeout, ContinuousClock.now.duration(to: end))
        let addresses = switch resolver {
        case .system: try await systemResolve(host, ipv4Only: binding.ipv4Only, timeout: dnsWait)
        case .server(let dns): try await DNSClient.resolve(host, server: dns, binding: binding, timeout: dnsWait)
        }
        let request = HTTP.request(url, accept: accept)
        if tls { return try await TLSExchange.run(host: host, address: addresses[0], port: port, request: request,
                                                   binding: binding, until: end) }
        let (binding, connectTimeout) = (binding, connectTimeout)
        return try await blocking {
            for (n, address) in addresses.enumerated() {
                let socket: BoundSocket
                do {
                    let wait = min(connectTimeout, ContinuousClock.now.duration(to: end))
                    socket = try BoundSocket.connect(address, port: port, binding: binding, timeout: wait)
                } catch {
                    if n == addresses.count - 1 || .now >= end { throw error }
                    continue
                }
                try socket.send(request, until: end)
                var raw: [UInt8] = []
                while true {
                    let chunk = try socket.receive(until: end)
                    raw += chunk
                    if let response = try HTTP.parse(raw, atEOF: chunk.isEmpty) { return response }
                }
            }
            throw NetError.dns(host)
        }
    }
}

/// HTTPS exchange via NWConnection: there is no TLS API over a raw socket.
/// Binding is by interface type (Wi-Fi), which also bypasses the VPN.
private enum TLSExchange {
    static func run(host: String, address: IPAddress, port: UInt16, request: [UInt8],
                    binding: Binding, until end: ContinuousClock.Instant) async throws -> HTTPResponse {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        let params = NWParameters(tls: tls)
        params.preferNoProxies = true
        if binding.isWiFi { params.requiredInterfaceType = .wifi }
        let conn = NWConnection(host: NWEndpoint.Host(address.description), port: NWEndpoint.Port(rawValue: port)!, using: params)

        return try await withThrowingTaskGroup(of: HTTPResponse?.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await exchange(conn, request: request, host: host)
                } onCancel: { conn.cancel() }
            }
            group.addTask { try? await Task.sleep(until: end); return nil }
            defer { group.cancelAll(); conn.cancel() }
            guard let first = try await group.next(), let response = first else { throw NetError.timeout }
            return response
        }
    }

    private static func exchange(_ conn: NWConnection, request: [UInt8], host: String) async throws -> HTTPResponse {
        let fail: @Sendable (NWError) -> NetError = { e in
            switch e {
            case .posix(let code): .system(code.rawValue)
            case .dns: .dns(host)
            default: .other(e.localizedDescription)
            }
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            conn.stateUpdateHandler = { state in
                let result: Result<Void, Error>? = switch state {
                case .ready: .success(())
                case .failed(let e), .waiting(let e): .failure(fail(e))
                case .cancelled: .failure(NetError.timeout)
                default: nil
                }
                if let result, resumed.withLock({ let first = !$0; $0 = true; return first }) { cont.resume(with: result) }
            }
            conn.start(queue: .global())
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: Data(request), completion: .contentProcessed { e in
                if let e { cont.resume(throwing: fail(e)) } else { cont.resume() }
            })
        }
        var raw: [UInt8] = []
        while true {
            let (chunk, eof) = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<([UInt8], Bool), Error>) in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 16 << 10) { data, _, complete, e in
                    if let e { cont.resume(throwing: fail(e)) } else { cont.resume(returning: (Array(data ?? Data()), complete)) }
                }
            }
            raw += chunk
            if let response = try HTTP.parse(raw, atEOF: eof) { return response }
        }
    }
}
