import SwiftUI

/// Read-only address capsule: security lock, host emphasized, the rest subdued.
struct PortalAddressField: View {
    let url: URL?
    let security: PortalSecurity
    let copy: () -> Void
    @State private var showsDetails = false

    var body: some View {
        HStack(spacing: 6) {
            Button { showsDetails.toggle() } label: {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .disabled(security == .none)
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) { details }

            if let label = shortLabel {
                Text(label).font(.callout.weight(.medium)).foregroundStyle(tint)
            }
            Text(address)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .frame(minWidth: 260, idealWidth: 520, maxWidth: 620)
        .modifier(CapsuleFill())
        .contextMenu {
            Button("Copy Address", systemImage: "doc.on.doc", action: copy).disabled(url == nil)
        }
        .help(url?.absoluteString ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Address: \(url?.absoluteString ?? "none")")
    }

    /// Scheme and path secondary, host primary and semibold.
    private var address: AttributedString {
        guard let url else {
            var empty = AttributedString("No Page")
            empty.foregroundColor = .secondary
            return empty
        }
        let full = url.absoluteString
        var text = AttributedString(full)
        text.foregroundColor = .secondary
        if let host = url.host(), let range = text.range(of: host) {
            text[range].foregroundColor = .primary
            text[range].font = .callout.weight(.semibold)
        }
        return text
    }

    private var symbol: String {
        switch security {
        case .none: "globe"
        case .secure: "lock.fill"
        case .insecure: "lock.slash.fill"
        case .acceptedCertificate: "lock.trianglebadge.exclamationmark.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch security {
        case .none, .secure: .secondary
        case .insecure, .acceptedCertificate, .failed: .orange
        }
    }

    private var shortLabel: String? {
        switch security {
        case .insecure: "Not Secure"
        case .acceptedCertificate: "Not Verified"
        default: nil
        }
    }

    private var details: some View {
        let (title, text): (String, String) = switch security {
        case .none: ("", "")
        case .secure: ("Secure Connection",
                       "Information you enter on this page is encrypted all the way to \(url?.host() ?? "this site").")
        case .insecure: ("Connection Not Secure",
                         "This page isn’t encrypted: other people on the network can read what you type here. Don’t enter an important password.")
        case .acceptedCertificate: ("Certificate Not Verified",
                                    "The connection is encrypted, but the identity of \(url?.host() ?? "the hotspot") couldn’t be verified. ConnectNow accepts it only because it’s a local network address, like that of a Wi-Fi hotspot.")
        case .failed: ("Page Unavailable", "The portal couldn’t be loaded at this address.")
        }
        return VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(.primary)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let url {
                Text(url.absoluteString).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    .textSelection(.enabled).lineLimit(3)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }
}

/// Before macOS 26 the toolbar draws no glass behind items: give the field its own fill.
private struct CapsuleFill: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) { content } else { content.background(.quaternary.opacity(0.6), in: Capsule()) }
    }
}
