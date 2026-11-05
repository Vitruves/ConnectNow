import SwiftUI
import ConnectNowCore

/// Candidate addresses, the most likely first, with the two open actions.
struct PortalSection: View {
    @Bindable var model: AppModel

    /// Once online, the candidates are only the router's own pages, not a sign-in portal.
    private var isOnline: Bool { model.scan.status == .online && !model.scan.portals.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(isOnline ? "Router pages" : "Portal addresses").font(.headline)
                Spacer()
                Button(action: model.forceHTTPPage) {
                    Label("Force an HTTP page", systemImage: "globe")
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .tint(.secondary)
                .help("Opens http://example.com/, an unencrypted page the hotspot can intercept and redirect")
            }

            Group {
                if model.scan.portals.isEmpty {
                    EmptyPortals(status: model.scan.status, isScanning: model.isScanning)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.scan.portals.enumerated()), id: \.element.id) { index, portal in
                            if index > 0 { Divider().padding(.leading, 42) }
                            PortalRow(portal: portal,
                                      isLikeliest: index == 0 && model.scan.status == .captive,
                                      isSelected: portal.url == model.selectedPortal?.url,
                                      select: { model.selectedPortalURL = portal.url },
                                      open: {
                                          model.selectedPortalURL = portal.url
                                          model.openSelectedPortal()
                                      })
                        }
                    }
                    .padding(4)
                }
            }
            .frame(maxWidth: .infinity)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }

            if model.selectedPortal != nil {
                HStack(spacing: 10) {
                    Button(action: model.openSelectedPortal) {
                        Label(isOnline ? "Open page" : "Open portal", systemImage: "door.left.hand.open")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .help("Sign in to the selected address in ConnectNow's portal window")

                    Button(action: model.openSelectedInBrowser) {
                        Label("Browser", systemImage: "safari")
                    }
                    .tint(nil)
                    .help("Open the selected address in your default browser")
                }
                .controlSize(.large)
                .transition(.opacity)
            }
        }
    }
}

private struct PortalRow: View {
    let portal: Portal
    let isLikeliest: Bool
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if portal.url.scheme == "https" {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Secure")
                        }
                        Text(portal.url.displayHost)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if isLikeliest {
                            Text("Most likely")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .foregroundStyle(.tint)
                                .background(.tint.opacity(0.14), in: Capsule())
                                .fixedSize()
                        }
                    }
                    Text(portal.url.absoluteString)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Label(portal.source.description, systemImage: portal.source.symbol)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded(open))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(portal.url.displayHost), \(portal.source.description)\(isLikeliest ? ", most likely" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Open portal", open)
    }
}

private struct EmptyPortals: View {
    let status: NetworkStatus
    let isScanning: Bool

    private var message: (symbol: String, text: String) {
        switch status {
        case .scanning: ("magnifyingglass", "Looking for a sign-in page…")
        case .online: ("checkmark.seal", "Nothing to sign in to: the Internet already works.")
        case .noNetwork: ("wifi.slash", "Join a Wi-Fi network to look for its portal.")
        default: ("questionmark.circle", "No portal address found yet. Try “Force an HTTP page” below.")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if status == .scanning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: message.symbol).foregroundStyle(.secondary)
            }
            Text(message.text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(minHeight: 60)
        .contentTransition(.opacity)
    }
}
