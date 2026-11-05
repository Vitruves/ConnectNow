import Foundation

/// A published version of ConnectNow.
public struct AppRelease: Sendable, Equatable {
    public let version: String
    public let pageURL: URL
    public init(version: String, pageURL: URL) { self.version = version; self.pageURL = pageURL }
}

/// Asks GitHub for the latest release. Only the version number is sent (in the User-Agent);
/// the session is ephemeral, so nothing is cached or stored.
public enum UpdateCheck {
    static let latestURL = URL(string: "https://api.github.com/repos/Vitruves/ConnectNow/releases/latest")!

    public enum Failure: LocalizedError {
        case unexpectedResponse(Int)
        public var errorDescription: String? {
            switch self {
            case .unexpectedResponse(let code): "GitHub answered with HTTP \(code)."
            }
        }
    }

    /// The latest release if it is newer than `current`, nil if up to date. Throws on network errors.
    public static func newerRelease(than current: String) async throws -> AppRelease? {
        let release = try await latest(userAgent: "ConnectNow/\(current)")
        return isVersion(release.version, newerThan: current) ? release : nil
    }

    /// Development builds (0.0.0, 0.0.0-abc1234) have no release to compare with.
    public static func isReleaseVersion(_ version: String) -> Bool {
        guard let parts = components(version) else { return false }
        return parts.contains { $0 > 0 }
    }

    static func latest(userAgent: String) async throws -> AppRelease {
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.unexpectedResponse(code) }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> AppRelease {
        struct Payload: Decodable { let tag_name: String; let html_url: URL }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return AppRelease(version: version, pageURL: payload.html_url)
    }

    /// Numeric comparison of "1.10.0" against "1.9" (a pre-release suffix is ignored).
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        guard let a = components(candidate), let b = components(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int]? {
        let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}
