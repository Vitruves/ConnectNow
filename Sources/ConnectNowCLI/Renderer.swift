import Foundation
import ConnectNowCore

/// Turns a scan into terminal text or JSON.
struct Renderer {
    var color: Bool
    var verbose: Bool

    // MARK: Text

    func report(_ scan: ScanResult) -> String {
        var lines = ["\(paint("●", scan.status.ansi)) \(paint(scan.status.title, .bold)) \(paint("— \(scan.status.subtitle)", .dim))"]

        // Once online, the candidates are only the router's own pages, not a sign-in portal.
        let heading = scan.status == .online ? "Router" : "Portal"
        for (index, portal) in scan.portals.enumerated() {
            let label = index == 0 ? heading : ""
            lines.append("  \(pad(label)) \(paint(portal.url.absoluteString, index == 0 ? .bold : .plain)) \(paint("(\(portal.source))", .dim))")
        }

        for hint in scan.hints {
            let mark = hint.severity == .warning ? paint("!", .yellow) : paint("i", .blue)
            lines.append("")
            lines.append("  \(mark) \(paint(hint.title, .bold))")
            lines.append(contentsOf: wrap(hint.message, indent: 4))
        }

        if verbose {
            lines.append("")
            for (label, value) in scan.detailRows { lines.append("  \(paint(pad(label), .dim)) \(value)") }
            if !scan.probes.isEmpty { lines.append("") }
            let width = scan.probes.map(\.name.count).max() ?? 0
            for probe in scan.probes {
                let name = probe.name.padding(toLength: width, withPad: " ", startingAt: 0)
                let latency = probe.latency?.millisecondsText ?? "—"
                lines.append("  \(paint(probe.state.mark, probe.state.ansi)) \(name)  \(probe.detail) \(paint("(\(latency))", .dim))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// One line for `watch`: time, status, top portal.
    func line(_ scan: ScanResult, at date: Date) -> String {
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        var line = "\(paint(time, .dim)) \(paint("●", scan.status.ansi)) \(scan.status.title)"
        if scan.status != .online, let portal = scan.portals.first { line += "  \(paint(portal.url.absoluteString, .bold))" }
        if let hint = scan.hints.first { line += paint("  · \(hint.title)", .dim) }
        return line
    }

    // MARK: JSON

    func json(_ scan: ScanResult, pretty: Bool) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(JSONReport(scan))) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Helpers

    enum Style: String {
        case plain = "", bold = "1", dim = "2", red = "31", green = "32", yellow = "33", blue = "34"
    }

    func paint(_ text: String, _ style: Style) -> String {
        guard color, style != .plain else { return text }
        return "\u{1B}[\(style.rawValue)m\(text)\u{1B}[0m"
    }

    private func pad(_ label: String) -> String { label.padding(toLength: 10, withPad: " ", startingAt: 0) }

    /// Word-wraps at 80 columns so long hint messages stay readable.
    private func wrap(_ text: String, indent: Int, width: Int = 80) -> [String] {
        let prefix = String(repeating: " ", count: indent)
        var lines: [String] = [], current = ""
        for word in text.split(separator: " ") {
            if !current.isEmpty, indent + current.count + 1 + word.count > width {
                lines.append(prefix + current)
                current = ""
            }
            current += current.isEmpty ? String(word) : " \(word)"
        }
        if !current.isEmpty { lines.append(prefix + current) }
        return lines
    }
}

private extension NetworkStatus {
    var ansi: Renderer.Style {
        switch self {
        case .online: .green
        case .captive: .yellow
        case .offline: .red
        case .noNetwork, .scanning: .dim
        }
    }
}

private extension ProbeState {
    var mark: String {
        switch self {
        case .ok: "✓"
        case .portal: "↪"
        case .error: "✗"
        }
    }

    var ansi: Renderer.Style {
        switch self {
        case .ok: .green
        case .portal: .yellow
        case .error: .red
        }
    }
}

/// Stable JSON shape, independent of the Core types.
private struct JSONReport: Encodable {
    struct PortalJSON: Encodable { let url: String; let source: String }
    struct HintJSON: Encodable { let id, title, message, severity: String }
    struct ProbeJSON: Encodable {
        let name, url, state, detail: String
        let latencyMs: Int?
        let portalURL: String?
    }

    let status: String
    let title: String
    let date: Date
    let interface: String?
    let isWiFi: Bool
    let defaultInterface: String?
    let gateway: String?
    let service: String?
    let dnsServers: [String]
    let manualDNS: [String]
    let usedDNSFallback: Bool
    let portals: [PortalJSON]
    let hints: [HintJSON]
    let probes: [ProbeJSON]

    init(_ s: ScanResult) {
        status = s.status.rawValue
        title = s.status.title
        date = s.date
        interface = s.interface
        isWiFi = s.isWiFi
        defaultInterface = s.defaultInterface
        gateway = s.gateway
        service = s.service
        dnsServers = s.dnsServers
        manualDNS = s.manualDNS
        usedDNSFallback = s.usedDNSFallback
        portals = s.portals.map { PortalJSON(url: $0.url.absoluteString, source: $0.source.description) }
        hints = s.hints.map { HintJSON(id: $0.id, title: $0.title, message: $0.message,
                                       severity: $0.severity == .warning ? "warning" : "info") }
        probes = s.probes.map {
            ProbeJSON(name: $0.name, url: $0.url.absoluteString, state: $0.state.rawValue, detail: $0.detail,
                      latencyMs: $0.latency.map { Int(($0 / .milliseconds(1)).rounded()) },
                      portalURL: $0.portalURL?.absoluteString)
        }
    }
}
