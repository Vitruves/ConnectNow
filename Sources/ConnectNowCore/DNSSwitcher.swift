import Foundation

/// Temporarily switches a manual DNS to automatic, writing an on-disk backup
/// BEFORE the change so it can be restored even after a crash.
public enum DNSSwitcher {
    public static func switchToAutomatic(service: String, servers: [String]) throws {
        try DNSSwitcherCore.live.switchToAutomatic(service: service, servers: servers)
    }
    public static var isSwitched: Bool { DNSSwitcherCore.live.isSwitched }
    /// Restores the original DNS if it was removed. No-op otherwise.
    public static func restore() throws { try DNSSwitcherCore.live.restore() }
}

public enum DNSSwitcherError: LocalizedError, Equatable {
    case nothingToSwitch
    case backupFailed(String)
    case networksetupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .nothingToSwitch: "There is no manual DNS to remove."
        case .backupFailed(let detail): "Could not save the DNS backup: \(detail)"
        case .networksetupFailed(let output): "Changing the DNS failed (networksetup): \(output)"
        }
    }
}

/// Testable logic: backup path and networksetup runner are injectable.
struct DNSSwitcherCore: Sendable {
    struct Backup: Codable, Equatable { var service: String; var servers: [String] }

    var backupURL: URL
    var setDNS: @Sendable (_ service: String, _ servers: [String]) throws -> Void

    static let live = DNSSwitcherCore(
        backupURL: URL.applicationSupportDirectory.appending(path: "ConnectNow/dns-backup.json"),
        setDNS: { service, servers in
            do { _ = try Subprocess.run("/usr/sbin/networksetup", ["-setdnsservers", service] + servers) }
            catch let failure as Subprocess.Failure {
                throw DNSSwitcherError.networksetupFailed(failure.output.isEmpty ? "code \(failure.status)" : failure.output)
            } catch { throw DNSSwitcherError.networksetupFailed(error.localizedDescription) }
        })

    func switchToAutomatic(service: String, servers: [String]) throws {
        guard !service.isEmpty, !servers.isEmpty else { throw DNSSwitcherError.nothingToSwitch }
        let fm = FileManager.default
        do {
            let data = try JSONEncoder().encode(Backup(service: service, servers: servers))
            try fm.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            guard fm.createFile(atPath: backupURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        } catch {
            throw DNSSwitcherError.backupFailed(error.localizedDescription)
        }
        do { try setDNS(service, ["empty"]) } catch {
            try? fm.removeItem(at: backupURL)
            throw error
        }
    }

    var isSwitched: Bool { FileManager.default.fileExists(atPath: backupURL.path) }

    func restore() throws {
        guard let data = try? Data(contentsOf: backupURL) else { return }
        // Unreadable backup: delete it rather than leave the user stuck.
        guard let backup = try? JSONDecoder().decode(Backup.self, from: data),
              !backup.service.isEmpty, !backup.servers.isEmpty else {
            try FileManager.default.removeItem(at: backupURL)
            return
        }
        try setDNS(backup.service, backup.servers)
        try FileManager.default.removeItem(at: backupURL)
    }
}
