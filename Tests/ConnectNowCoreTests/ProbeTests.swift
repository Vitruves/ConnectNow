import Foundation
import Network
import Testing
@testable import ConnectNowCore

/// Tiny HTTP server on loopback: answers every connection with a canned response, then closes.
final class TestHTTPServer: Sendable {
    let listener: NWListener
    let port: UInt16

    init(response: String) async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 << 10) { _, _, _, _ in
                conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let e): cont.resume(throwing: e)
                default: break
                }
            }
            listener.start(queue: .global())
        }
        listener.stateUpdateHandler = nil
        self.listener = listener
        self.port = listener.port!.rawValue
    }

    deinit { listener.cancel() }
    var checkURL: URL { URL(string: "http://127.0.0.1:\(port)/check")! }
}

func response(_ status: String = "200 OK", headers: [String] = [], body: String = "") -> String {
    (["HTTP/1.1 \(status)", "Content-Length: \(body.utf8.count)"] + headers).joined(separator: "\r\n") + "\r\n\r\n" + body
}

struct ProbeCase: Sendable, CustomTestStringConvertible {
    let name: String
    let raw: String
    let state: ProbeState
    let portal: String?  // "" = the probe URL itself
    var testDescription: String { name }
}

let probeCases = [
    ProbeCase(name: "connected", raw: response(body: "Success"), state: .ok, portal: nil),
    ProbeCase(name: "302 redirect", raw: response("302 Found", headers: ["Location: http://portal.example/login?mac=aa"]),
              state: .portal, portal: "http://portal.example/login?mac=aa"),
    ProbeCase(name: "relative Location", raw: response("302 Found", headers: ["Location: /login"]),
              state: .portal, portal: "/login"),
    ProbeCase(name: "meta refresh", raw: response(body: #"<html><meta http-equiv="refresh" content="0; url=https://wifi.example/start"></html>"#),
              state: .portal, portal: "https://wifi.example/start"),
    // Chunked body, to cover the decoder end to end.
    ProbeCase(name: "javascript", raw: "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n11\r\n<script>window.lo\r\n30\r\ncation.href = \"http://10.0.0.1/portal\";</script>\r\n0\r\n\r\n",
              state: .portal, portal: "http://10.0.0.1/portal"),
    // No Content-Length: body delimited by connection close.
    ProbeCase(name: "WISPr", raw: "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n<!--<WISPAccessGatewayParam><LoginURL>https://hotspot.example/l?a=1&amp;b=2</LoginURL></WISPAccessGatewayParam>-->",
              state: .portal, portal: "https://hotspot.example/l?a=1&b=2"),
    ProbeCase(name: "content replaced", raw: response(body: #"<form action="/login"></form>"#), state: .portal, portal: ""),
]

@Test(arguments: probeCases)
func probeAgainstLocalServer(_ c: ProbeCase) async throws {
    let server = try await TestHTTPServer(response: c.raw)
    let probe = Probe(name: "test", url: server.checkURL) { s, b in s == 200 && b == "Success" }
    let r = await runProbe(probe, client: HTTPClient())
    #expect(r.state == c.state, "\(r.detail)")
    let want: URL? = switch c.portal {
    case nil: nil
    case "": server.checkURL
    case let p?: URL(string: p, relativeTo: server.checkURL)!.absoluteURL
    }
    #expect(r.portalURL?.absoluteString == want?.absoluteString)
    #expect(r.latency != nil)
}

@Test func probeConnectionRefusedIsError() async throws {
    var port: UInt16
    do { let server = try await TestHTTPServer(response: ""); port = server.port }  // port freed on deinit
    let probe = Probe(name: "test", url: URL(string: "http://127.0.0.1:\(port)/")!) { _, _ in true }
    let r = await runProbe(probe, client: HTTPClient())
    #expect(r.state == .error)
    #expect(!r.isDNSError)
}

@Test func unresolvableHostIsDNSError() async {
    let probe = Probe(name: "test", url: URL(string: "http://nonexistent.invalid/")!) { _, _ in true }
    let r = await runProbe(probe, client: HTTPClient())
    #expect(r.state == .error)
    #expect(r.isDNSError)
}

@Test func requestHasProbeHeaders() {
    let req = String(decoding: HTTP.request(URL(string: "http://example.com:8080/a/b?x=1")!, accept: "*/*"), as: UTF8.self)
    #expect(req.hasPrefix("GET /a/b?x=1 HTTP/1.1\r\nHost: example.com:8080\r\n"))
    #expect(req.contains("User-Agent: CaptiveNetworkSupport-ConnectNow wispr\r\n"))
    #expect(req.contains("Cache-Control: no-cache\r\n"))
    #expect(req.hasSuffix("\r\n\r\n"))
}

@Test func parserWaitsForContentLength() throws {
    let head = Array("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nab".utf8)
    #expect(try HTTP.parse(head, atEOF: false) == nil)
    #expect(try HTTP.parse(head + Array("cde".utf8), atEOF: false)?.text == "abcde")
    #expect(try HTTP.parse(head, atEOF: true)?.text == "ab")
}

@Test func parserCapsBodyAndSkipsInterim() throws {
    let big = Array("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\n\r\n".utf8) + [UInt8](repeating: 65, count: HTTP.maxBody + 10)
    let r = try #require(try HTTP.parse(big, atEOF: false))
    #expect(r.status == 200)
    #expect(r.body.count == HTTP.maxBody)
    #expect(throws: NetError.malformed) { try HTTP.parse(Array("garbage\r\n\r\n".utf8), atEOF: true) }
}

@Test func dechunk() {
    let full = Array("4\r\nWiki\r\n5;ext=1\r\npedia\r\n0\r\n\r\n".utf8)
    #expect(HTTP.dechunk(full) == (Array("Wikipedia".utf8), true))
    #expect(HTTP.dechunk(Array(full.prefix(12))).complete == false)
}

@Test func redirectExtraction() {
    let base = URL(string: "http://captive.apple.com/hotspot-detect.html")!
    let cases: [(String, String?)] = [
        ("<LoginURL> https://h.example/l?a=1&amp;b=2 </LoginURL>", "https://h.example/l?a=1&b=2"),
        ("<META HTTP-EQUIV=Refresh CONTENT='0;URL=/portal'>", "http://captive.apple.com/portal"),
        ("location.replace('https://p.example/x')", "https://p.example/x"),
        ("window.location.assign(\"//p.example/y\")", "http://p.example/y"),
        ("document.location = 'https://p.example/z'", "https://p.example/z"),
        ("location.href=\"javascript:void(0)\"", nil),  // only http/https
        ("<html>nothing here</html>", nil),
    ]
    for (body, want) in cases {
        #expect(PortalExtractor.bodyRedirect(body, base: base)?.absoluteString == want, "\(body)")
    }
}

@Test func resolveRejectsNonWebURLs() {
    #expect(PortalExtractor.resolve("ftp://x.example/") == nil)
    #expect(PortalExtractor.resolve("/relative") == nil)
    #expect(PortalExtractor.resolve("https://x.example/a")?.absoluteString == "https://x.example/a")
}

@Test func htmlUnescape() {
    #expect(PortalExtractor.htmlUnescape("a&amp;b&lt;&#65;&#x42;&unknown;&") == "a&b<AB&unknown;&")
}
