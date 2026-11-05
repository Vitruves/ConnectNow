import Foundation

/// A probe is a plain HTTP URL (never HTTPS, otherwise the portal cannot
/// intercept it) whose normal response is known in advance.
struct Probe: Sendable {
    let name: String
    let url: URL
    let isExpected: @Sendable (_ status: Int, _ body: String) -> Bool

    static let all: [Probe] = [
        Probe(name: "Apple", url: URL(string: "http://captive.apple.com/hotspot-detect.html")!) { s, b in
            s == 200 && b.contains("Success")
        },
        Probe(name: "Google", url: URL(string: "http://connectivitycheck.gstatic.com/generate_204")!) { s, _ in
            s == 204
        },
        Probe(name: "Firefox", url: URL(string: "http://detectportal.firefox.com/success.txt")!) { s, b in
            s == 200 && b.trimmingCharacters(in: .whitespacesAndNewlines) == "success"
        },
        Probe(name: "Microsoft", url: URL(string: "http://www.msftconnecttest.com/connecttest.txt")!) { s, b in
            s == 200 && b.trimmingCharacters(in: .whitespacesAndNewlines) == "Microsoft Connect Test"
        },
    ]
}

enum PortalExtractor {
    /// Resolves a (possibly relative, HTML-escaped) reference; only http/https with a host.
    static func resolve(_ ref: String, against base: URL? = nil) -> URL? {
        let cleaned = htmlUnescape(ref.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let url = URL(string: cleaned, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Redirect hidden in the page body when the portal answers 200.
    static func bodyRedirect(_ body: String, base: URL) -> URL? {
        let patterns = [
            #/(?i)<LoginURL>\s*([^<\s]+)\s*</LoginURL>/#,
            #/(?i)http-equiv=["']?refresh["']?[^>]*url=\s*['"]?([^'">\s]+)/#,
            #/(?i)location\.(?:replace|assign)\(\s*["']([^"']+)["']/#,
            #/(?i)location(?:\.href)?\s*=\s*["']([^"']+)["']/#,
        ]
        for pattern in patterns {
            if let m = body.firstMatch(of: pattern), let url = resolve(String(m.1), against: base) { return url }
        }
        return nil
    }

    static func htmlUnescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{a0}"]
        var out = "", rest = s[...]
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let entity = after[..<semi]
                var replacement = named[String(entity)]
                if replacement == nil, entity.hasPrefix("#") {
                    let num = entity.dropFirst()
                    let code = num.first == "x" || num.first == "X" ? UInt32(num.dropFirst(), radix: 16) : UInt32(num)
                    replacement = code.flatMap(Unicode.Scalar.init).map { String($0) }
                }
                if let replacement { out += replacement; rest = after[after.index(after: semi)...]; continue }
            }
            out += "&"; rest = after
        }
        return out + rest
    }
}

func runProbe(_ probe: Probe, client: HTTPClient) async -> ProbeResult {
    let start = ContinuousClock.now
    let response: HTTPResponse
    do { response = try await client.get(probe.url) } catch {
        let e = error as? NetError ?? .other(error.localizedDescription)
        return ProbeResult(name: probe.name, url: probe.url, state: .error, detail: e.description, isDNSError: e.isDNS)
    }
    let latency = start.duration(to: .now)
    let status = response.status, body = response.text
    if probe.isExpected(status, body) {
        return ProbeResult(name: probe.name, url: probe.url, state: .ok, detail: "HTTP \(status)", latency: latency)
    }
    // The redirect IS the information we're after: it is not followed.
    var portal: URL?, detail = ""
    if let location = response[header: "location"], !location.isEmpty {
        portal = PortalExtractor.resolve(location, against: probe.url)
        detail = "HTTP \(status) → \(location)"
    }
    if portal == nil, let url = PortalExtractor.bodyRedirect(body, base: probe.url) {
        portal = url
        detail = "HTTP \(status), redirect in page"
    }
    if portal == nil {
        // The portal is served instead of the expected page.
        portal = probe.url
        detail = "HTTP \(status), content replaced"
    }
    return ProbeResult(name: probe.name, url: probe.url, state: .portal, detail: detail, latency: latency, portalURL: portal)
}

/// Runs the probes concurrently, keeping their order.
func runProbes(_ probes: [Probe] = Probe.all, client: HTTPClient) async -> [ProbeResult] {
    await withTaskGroup(of: (Int, ProbeResult).self) { group in
        for (i, p) in probes.enumerated() { group.addTask { (i, await runProbe(p, client: client)) } }
        var results = [ProbeResult?](repeating: nil, count: probes.count)
        for await (i, r) in group { results[i] = r }
        return results.compactMap { $0 }
    }
}

/// Tests the gateway's web ports: many hotspots host their login page there.
func gatewayPortals(_ gateway: IPAddress, binding: Binding) async -> [Portal] {
    let h = gateway.urlHost
    let candidates = [(80, "http://\(h)/"), (8080, "http://\(h):8080/"), (443, "https://\(h)/")]
    let open = await withTaskGroup(of: (Int, Bool).self) { group in
        for (i, c) in candidates.enumerated() {
            group.addTask {
                let ok = (try? await blocking {
                    _ = try BoundSocket.connect(gateway, port: UInt16(c.0), binding: binding, timeout: .milliseconds(1200))
                    return true
                }) ?? false
                return (i, ok)
            }
        }
        var open = Set<Int>()
        for await (i, ok) in group where ok { open.insert(i) }
        return open
    }
    return candidates.indices.filter(open.contains).compactMap { i in
        URL(string: candidates[i].1).map { Portal(url: $0, source: .gateway(port: candidates[i].0)) }
    }
}

/// Portal the network announces itself (DHCP option 114, RFC 8910), read from
/// its API (RFC 8908). Retries through the network's DNS if the first try fails.
func announcedPortal(api: URL, client: HTTPClient, fallback: HTTPClient?) async -> (url: URL?, captive: Bool) {
    struct Info: Decodable {
        var captive: Bool?
        var userPortalURL: String?
        enum CodingKeys: String, CodingKey { case captive, userPortalURL = "user-portal-url" }
    }
    let end = ContinuousClock.now + .seconds(7)
    let accept = "application/captive+json"
    var response = try? await client.get(api, accept: accept, deadline: end)
    if response == nil, let fallback { response = try? await fallback.get(api, accept: accept, deadline: end) }
    guard let response, let info = try? JSONDecoder().decode(Info.self, from: Data(response.body)) else { return (nil, false) }
    return (info.userPortalURL.flatMap { PortalExtractor.resolve($0, against: api) }, info.captive ?? false)
}
