import Foundation

// CONTRACT between the main window and the portal window.
/// A request to display a page in the portal window. A new `id` forces a reload,
/// even when the URL is unchanged.
struct PortalRequest: Hashable, Sendable {
    let url: URL
    let id = UUID()
}
