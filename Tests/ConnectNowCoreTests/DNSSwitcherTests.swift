import Foundation
import Testing
@testable import ConnectNowCore

/// Records networksetup calls instead of running them.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.withLock { _calls } }
    func record(_ call: [String]) { lock.withLock { _calls.append(call) } }
}

private func makeCore(fail: Bool = false) -> (DNSSwitcherCore, Recorder, URL) {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cn-dns-\(UUID().uuidString)")
    let url = dir.appending(path: "ConnectNow/dns-backup.json")
    let recorder = Recorder()
    let core = DNSSwitcherCore(backupURL: url) { service, servers in
        // The backup must already exist when networksetup is called.
        recorder.record([service] + servers + [FileManager.default.fileExists(atPath: url.path) ? "backup" : "no-backup"])
        if fail { throw DNSSwitcherError.networksetupFailed("denied") }
    }
    return (core, recorder, url)
}

@Suite struct DNSSwitcherTests {
    @Test func switchWritesBackupFirstThenRestores() throws {
        let (core, rec, url) = makeCore()
        try core.switchToAutomatic(service: "Wi-Fi", servers: ["1.1.1.1", "8.8.8.8"])
        #expect(rec.calls == [["Wi-Fi", "empty", "backup"]])
        #expect(core.isSwitched)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        #expect((dirAttrs[.posixPermissions] as? Int) == 0o700)
        let backup = try JSONDecoder().decode(DNSSwitcherCore.Backup.self, from: Data(contentsOf: url))
        #expect(backup == .init(service: "Wi-Fi", servers: ["1.1.1.1", "8.8.8.8"]))

        try core.restore()
        #expect(rec.calls.last == ["Wi-Fi", "1.1.1.1", "8.8.8.8", "backup"])
        #expect(!core.isSwitched)
    }

    @Test func failedSwitchRemovesBackup() {
        let (core, rec, _) = makeCore(fail: true)
        #expect(throws: DNSSwitcherError.networksetupFailed("denied")) {
            try core.switchToAutomatic(service: "Wi-Fi", servers: ["1.1.1.1"])
        }
        #expect(rec.calls.count == 1)
        #expect(!core.isSwitched)
    }

    @Test func nothingToSwitch() {
        let (core, rec, _) = makeCore()
        #expect(throws: DNSSwitcherError.nothingToSwitch) { try core.switchToAutomatic(service: "Wi-Fi", servers: []) }
        #expect(throws: DNSSwitcherError.nothingToSwitch) { try core.switchToAutomatic(service: "", servers: ["1.1.1.1"]) }
        #expect(rec.calls.isEmpty)
    }

    @Test func restoreWithoutBackupDoesNothing() throws {
        let (core, rec, _) = makeCore()
        try core.restore()
        #expect(rec.calls.isEmpty)
    }

    @Test func corruptBackupIsDeleted() throws {
        let (core, rec, url) = makeCore()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(core.isSwitched)
        try core.restore()
        #expect(rec.calls.isEmpty)
        #expect(!core.isSwitched)
    }

    @Test func failedRestoreKeepsBackup() throws {
        let (ok, _, url) = makeCore()
        try ok.switchToAutomatic(service: "Wi-Fi", servers: ["9.9.9.9"])
        let failing = DNSSwitcherCore(backupURL: url) { _, _ in throw DNSSwitcherError.networksetupFailed("x") }
        #expect(throws: DNSSwitcherError.self) { try failing.restore() }
        #expect(failing.isSwitched)
    }

    @Test func errorMessagesIncludeOutput() {
        #expect(DNSSwitcherError.networksetupFailed("Wi-Fi is not a recognized network service.").localizedDescription
            .contains("Wi-Fi is not a recognized network service."))
        #expect(DNSSwitcherError.nothingToSwitch.localizedDescription == "There is no manual DNS to remove.")
    }

    @Test func liveBackupPath() {
        #expect(DNSSwitcherCore.live.backupURL.path.hasSuffix("Library/Application Support/ConnectNow/dns-backup.json"))
    }
}
