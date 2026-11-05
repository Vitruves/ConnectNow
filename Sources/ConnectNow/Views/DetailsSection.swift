import AppKit
import SwiftUI
import ConnectNowCore

/// Technical details, collapsed by default; selectable and copyable for support.
struct DetailsSection: View {
    let scan: ScanResult
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text("Details").font(.headline)
                        if !isExpanded, let summary {
                            Text(summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Details")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                Spacer(minLength: 0)
                if isExpanded {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.report(scan), forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Copy these details as text")
                    .transition(.opacity)
                }
            }

            if isExpanded {
                content.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    private var summary: String? {
        guard let interface = scan.interface else { return nil }
        return [interface, scan.gateway].compactMap { $0 }.joined(separator: " → ")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(Self.rows(scan), id: \.0) { label, value in
                    GridRow {
                        Text(label).foregroundStyle(.secondary)
                        Text(value).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !scan.probes.isEmpty {
                Divider()
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                    ForEach(scan.probes) { probe in
                        GridRow {
                            Image(systemName: probe.state.symbol)
                                .foregroundStyle(probe.state.color)
                                .accessibilityLabel(probe.state.label)
                            Text(probe.name).fontWeight(.medium)
                            Text(probe.detail)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(probe.latency?.millisecondsText ?? "—")
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                        }
                        .help(probe.url.absoluteString)
                    }
                }
            }
        }
        .font(.callout)
        .monospacedDigit()
        .textSelection(.enabled)
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    static func rows(_ scan: ScanResult) -> [(String, String)] {
        var rows: [(String, String)] = []
        let interface = scan.interface.map { scan.isWiFi ? "\($0) (Wi-Fi)" : $0 }
        rows.append(("Interface", interface ?? "—"))
        if let primary = scan.defaultInterface, primary != scan.interface {
            rows.append(("Priority", primary))
        }
        if let service = scan.service { rows.append(("Service", service)) }
        rows.append(("Gateway", scan.gateway ?? "—"))
        rows.append(("DNS", scan.dnsServers.isEmpty ? "—" : scan.dnsServers.joined(separator: ", ")))
        if !scan.manualDNS.isEmpty { rows.append(("Manual DNS", scan.manualDNS.joined(separator: ", "))) }
        if scan.usedDNSFallback { rows.append(("Fallback", "Found using the hotspot's DNS")) }
        return rows
    }

    static func report(_ scan: ScanResult) -> String {
        var lines = ["ConnectNow — \(scan.status.title)"]
        lines += rows(scan).map { "\($0.0): \($0.1)" }
        lines += scan.probes.map { "\($0.name): \($0.detail)" + ($0.latency.map { " (\($0.millisecondsText))" } ?? "") }
        lines += scan.portals.map { "Portal: \($0.url.absoluteString) [\($0.source)]" }
        return lines.joined(separator: "\n")
    }
}
