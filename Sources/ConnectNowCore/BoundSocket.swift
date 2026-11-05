import Darwin
import Foundation
import os

// BSD sockets bound to an interface (IP_BOUND_IF): traffic leaves through the
// analysed network even when a VPN, Ethernet or iPhone tethering has priority.

/// Network error with a short human-readable message.
enum NetError: Error, Sendable, Equatable, CustomStringConvertible {
    case dns(String)        // name resolution failed
    case timeout
    case system(Int32)      // errno
    case malformed          // unreadable HTTP / DNS response
    case other(String)      // any other failure (TLS, unsupported URL…)

    var isDNS: Bool { if case .dns = self { true } else { false } }

    var description: String {
        switch self {
        case .dns(let host): "DNS: cannot resolve \(host)"
        case .timeout: "timed out"
        case .malformed: "malformed response"
        case .other(let message): message
        case .system(let code):
            switch code {
            case ECONNREFUSED: "connection refused"
            case ENETUNREACH: "network unreachable"
            case EHOSTUNREACH: "host unreachable"
            case ETIMEDOUT: "timed out"
            case ECONNRESET: "connection reset"
            default: String(cString: strerror(code))
            }
        }
    }
}

enum IPAddress: Sendable, Hashable, CustomStringConvertible {
    case v4(in_addr)
    case v6(in6_addr)

    init?(_ string: String) {
        var a4 = in_addr(), a6 = in6_addr()
        if inet_pton(AF_INET, string, &a4) == 1 { self = .v4(a4) }
        else if inet_pton(AF_INET6, string, &a6) == 1 { self = .v6(a6) }
        else { return nil }
    }

    var family: Int32 { if case .v4 = self { AF_INET } else { AF_INET6 } }

    var description: String {
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        switch self {
        case .v4(var a): inet_ntop(AF_INET, &a, &buf, socklen_t(buf.count))
        case .v6(var a): inet_ntop(AF_INET6, &a, &buf, socklen_t(buf.count))
        }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Form usable in a URL (brackets for IPv6).
    var urlHost: String { if case .v6 = self { "[\(self)]" } else { description } }

    static func == (l: Self, r: Self) -> Bool { l.description == r.description }
    func hash(into h: inout Hasher) { h.combine(description) }

    /// Calls `body` with the matching sockaddr.
    func withSockaddr<T>(port: UInt16, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        switch self {
        case .v4(let a):
            var sa = sockaddr_in()
            sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sa.sin_family = sa_family_t(AF_INET); sa.sin_port = port.bigEndian; sa.sin_addr = a
            return withUnsafePointer(to: &sa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        case .v6(let a):
            var sa = sockaddr_in6()
            sa.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            sa.sin6_family = sa_family_t(AF_INET6); sa.sin6_port = port.bigEndian; sa.sin6_addr = a
            return withUnsafePointer(to: &sa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in6>.size)) } }
        }
    }
}

/// Interface connections are bound to (index 0 = follow the default route).
struct Binding: Sendable, Hashable {
    var interfaceIndex: UInt32 = 0
    var ipv4Only = false     // a portal filtering only IPv4 would go unnoticed over IPv6
    var isWiFi = false
}

// Dedicated (overcommit) queue: blocking calls stay off the cooperative pool.
private let ioQueue = DispatchQueue(label: "ConnectNow.io", attributes: .concurrent)

/// Runs a blocking call off the cooperative pool; gives up after `timeout`.
func blocking<T: Sendable>(timeout: Duration? = nil, onTimeout: NetError = .timeout,
                           _ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
        let done = OSAllocatedUnfairLock(initialState: false)
        let finish: @Sendable (Result<T, Error>) -> Void = { result in
            if done.withLock({ let first = !$0; $0 = true; return first }) { cont.resume(with: result) }
        }
        ioQueue.async { finish(Result(catching: body)) }
        if let timeout {
            ioQueue.asyncAfter(deadline: .now() + timeout.timeInterval) { finish(.failure(onTimeout)) }
        }
    }
}

/// Blocking call that cannot fail.
func offload<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { cont in ioQueue.async { cont.resume(returning: body()) } }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (s, atto) = components
        return TimeInterval(s) + TimeInterval(atto) / 1e18
    }
    var milliseconds: Int32 { Int32(clamping: max(0, Int((timeInterval * 1000).rounded(.up)))) }
}

/// Resolution through the system resolver (getaddrinfo), time-bounded.
func systemResolve(_ host: String, ipv4Only: Bool, timeout: Duration) async throws -> [IPAddress] {
    if let ip = IPAddress(host) { return [ip] }
    return try await blocking(timeout: timeout, onTimeout: .dns(host)) {
        var hints = addrinfo()
        hints.ai_family = ipv4Only ? AF_INET : AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { throw NetError.dns(host) }
        defer { freeaddrinfo(first) }
        var out: [IPAddress] = []
        for ai in sequence(first: first, next: { $0.pointee.ai_next }) {
            guard let sa = ai.pointee.ai_addr else { continue }
            switch ai.pointee.ai_family {
            case AF_INET: out.append(.v4(sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }))
            case AF_INET6: out.append(.v6(sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }))
            default: break
            }
        }
        guard !out.isEmpty else { throw NetError.dns(host) }
        var seen = Set<IPAddress>()
        return out.filter { seen.insert($0).inserted }
    }
}

/// Non-blocking socket bound to the interface; every operation has a deadline.
struct BoundSocket: ~Copyable {
    let fd: Int32

    init(_ address: IPAddress, type: Int32, binding: Binding) throws(NetError) {
        fd = socket(address.family, type, 0)
        guard fd >= 0 else { throw .system(errno) }
        var one: Int32 = 1, index = Int32(binding.interfaceIndex)
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        if index > 0 {
            let ok = address.family == AF_INET
                ? setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<Int32>.size))
                : setsockopt(fd, IPPROTO_IPV6, IPV6_BOUND_IF, &index, socklen_t(MemoryLayout<Int32>.size))
            if ok != 0 { let e = errno; Darwin.close(fd); throw .system(e) }
        }
    }

    deinit { Darwin.close(fd) }

    /// TCP connect (or UDP association) with a timeout.
    static func connect(_ address: IPAddress, port: UInt16, type: Int32 = SOCK_STREAM,
                        binding: Binding, timeout: Duration) throws(NetError) -> BoundSocket {
        let s = try BoundSocket(address, type: type, binding: binding)
        let rc = address.withSockaddr(port: port) { Darwin.connect(s.fd, $0, $1) }
        if rc != 0 {
            guard errno == EINPROGRESS else { throw .system(errno) }
            try s.wait(POLLOUT, until: .now + timeout)
            var err: Int32 = 0, len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(s.fd, SOL_SOCKET, SO_ERROR, &err, &len)
            if err != 0 { throw .system(err) }
        }
        return s
    }

    func wait(_ events: Int32, until deadline: ContinuousClock.Instant) throws(NetError) {
        while true {
            let left = ContinuousClock.now.duration(to: deadline)
            guard left > .zero else { throw .timeout }
            var p = pollfd(fd: fd, events: Int16(events), revents: 0)
            let n = poll(&p, 1, left.milliseconds)
            if n > 0 { return }
            if n < 0 && errno != EINTR { throw .system(errno) }
        }
    }

    func send(_ bytes: [UInt8], until deadline: ContinuousClock.Instant) throws(NetError) {
        var sent = 0
        while sent < bytes.count {
            try wait(POLLOUT, until: deadline)
            let n = bytes[sent...].withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            if n < 0 { if errno == EAGAIN || errno == EINTR { continue }; throw .system(errno) }
            sent += n
        }
    }

    /// Reads what is available; empty array = end of stream.
    func receive(max: Int = 16 << 10, until deadline: ContinuousClock.Instant) throws(NetError) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: max)
        while true {
            try wait(POLLIN, until: deadline)
            let n = buf.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, $0.count, 0) }
            if n >= 0 { return Array(buf[..<n]) }
            if errno != EAGAIN && errno != EINTR { throw .system(errno) }
        }
    }
}
