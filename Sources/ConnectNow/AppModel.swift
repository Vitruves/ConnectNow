import os
import AppKit
import SwiftUI
import ConnectNowCore

/// App state: drives the scan loop, the portal window and the temporary DNS switch.
@MainActor @Observable
final class AppModel {
    struct AlertContent: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    static let forcedHTTPURL = URL(string: "http://example.com/")!
    private static let fastInterval: Duration = .seconds(4)   // captive, offline, no network
    private static let slowInterval: Duration = .seconds(30)  // online: be frugal

    private(set) var scan = ScanResult()
    private(set) var isScanning = false
    private(set) var lastScan: Date?
    private(set) var notice: String?
    private(set) var portalRequest: PortalRequest?
    private(set) var isSwitchingDNS = false
    /// Third-party network extensions found at launch (filters, VPNs, proxies).
    private(set) var networkExtensions: [String] = []
    /// Hints produced by the app itself (DNS switched, restore failed).
    private(set) var appHints: [Hint] = []
    var selectedPortalURL: URL?
    var alert: AlertContent?
    /// A newer release found on GitHub.
    private(set) var availableUpdate: AppRelease?
    private(set) var isCLIInstalled = CommandLineTool.isInstalled
    /// The portal window opens by itself when a new portal is found. On by default.
    var opensPortalAutomatically: Bool {
        get { access(keyPath: \.opensPortalAutomatically); return !UserDefaults.standard.bool(forKey: Self.noAutoOpenKey) }
        set { withMutation(keyPath: \.opensPortalAutomatically) { UserDefaults.standard.set(!newValue, forKey: Self.noAutoOpenKey) } }
    }
    /// Checked once per launch, as soon as a scan says the Internet works. On by default.
    var checksForUpdates: Bool {
        get { access(keyPath: \.checksForUpdates); return !UserDefaults.standard.bool(forKey: Self.noUpdateCheckKey) }
        set {
            withMutation(keyPath: \.checksForUpdates) { UserDefaults.standard.set(!newValue, forKey: Self.noUpdateCheckKey) }
            if newValue { checkForUpdatesIfDue() }
        }
    }

    private static let log = Logger(subsystem: "com.connectnow.app", category: "scan")
    @ObservationIgnored private let scanWork: @Sendable () async -> ScanResult
    @ObservationIgnored private let monitor = NetworkMonitor()
    /// False in demo mode: no DNS changes, no network monitor, no automatic portal window, no timer.
    @ObservationIgnored private let isLive: Bool
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var sleeper: Task<Void, Error>?
    @ObservationIgnored private var pendingRescan = false
    @ObservationIgnored private var wakeDelay: Duration?
    @ObservationIgnored private var autoOpenedURL: URL?
    @ObservationIgnored private var didCheckForUpdates = false
    private static let noUpdateCheckKey = "updateCheckDisabled"
    private static let noAutoOpenKey = "portalAutoOpenDisabled"
    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }

    init(launchURL: URL? = nil) {
        let scanner = NetworkScanner()
        var work: @Sendable () async -> ScanResult = { await scanner.scan() }
        var live = true
        #if DEBUG
        if let demo = DemoData.requested {
            work = { await DemoData.scan(demo) }
            live = false
        }
        #endif
        scanWork = work
        isLive = live
        if let launchURL { portalRequest = PortalRequest(url: launchURL) }
    }

    // MARK: Derived state

    var hints: [Hint] {
        var all = appHints + scan.hints
        // Checked once at launch; only relevant while the portal is what's missing.
        if !networkExtensions.isEmpty, scan.status == .captive || scan.status == .offline {
            all.append(.networkExtensions(networkExtensions))
        }
        return all
    }
    var subtitle: String { notice ?? scan.status.subtitle }
    var selectedPortal: Portal? {
        scan.portals.first { $0.url == selectedPortalURL } ?? scan.portals.first
    }

    func canPerform(_ action: Hint.Action) -> Bool {
        switch action {
        case .switchDNSToAutomatic: scan.canSwitchDNS && !isSwitchingDNS
        case .forceHTTPPage, .downloadUpdate: true
        }
    }

    // MARK: Lifecycle

    func start() {
        guard loop == nil else { return }
        if isLive {
            Task { networkExtensions = await Task.detached { SystemChecks.networkExtensions() }.value }
        }
        loop = Task {
            await restoreDNSIfSwitched()  // left over by an interrupted session
            while !Task.isCancelled {
                await scanOnce()
                await waitForNextScan()
            }
        }
        if isLive {
            monitorTask = Task { [monitor] in
                // Let the interface settle (DHCP, routes) before rescanning.
                for await _ in monitor.changes() { self.rescan(after: .seconds(1)) }
            }
        }
    }

    /// Called from applicationWillTerminate: must be synchronous.
    func shutdown() {
        loop?.cancel()
        monitorTask?.cancel()
        sleeper?.cancel()
        guard isLive else { return }
        do { try DNSSwitcher.restore() } catch { NSLog("ConnectNow: DNS not restored: \(error)") }
    }

    // MARK: Scan loop

    /// Requests a scan; coalesced if one is already running.
    func rescan(after delay: Duration = .zero) {
        if isScanning { pendingRescan = true; return }
        wakeDelay = delay > .zero ? delay : nil
        sleeper?.cancel()
    }

    private func scanOnce() async {
        withAnimation(.smooth) { isScanning = true }
        let clock = ContinuousClock.now
        var result = await scanWork()
        Self.log.notice("scan: \(result.status.rawValue, privacy: .public) in \(clock.duration(to: .now), privacy: .public)")
        guard !Task.isCancelled else { return }
        if result.status == .online, isLive, DNSSwitcher.isSwitched {
            await restoreDNSIfSwitched()
        }
        if appHints.contains(where: { $0.id == "dns-switched" }), !DNSSwitcher.isSwitched {
            appHints.removeAll { $0.id == "dns-switched" }
        }
        if result.status == .scanning { result.status = .offline }  // a finished scan always concludes
        withAnimation(.smooth(duration: 0.45)) {
            scan = result
            isScanning = false
            notice = nil
            lastScan = .now
            if !result.portals.contains(where: { $0.url == selectedPortalURL }) {
                selectedPortalURL = result.portals.first?.url
            }
        }
        if result.status == .online { checkForUpdatesIfDue() }
        // The portal opens by itself the first time a new top address shows up.
        if isLive, opensPortalAutomatically, result.status == .captive,
           let top = result.portals.first?.url, top != autoOpenedURL {
            autoOpenedURL = top
            show(top)
        }
    }

    private func waitForNextScan() async {
        var delay = scan.status == .online ? Self.slowInterval : Self.fastInterval
        if !isLive { delay = .seconds(3600) }  // demo: rescan on demand only
        while !pendingRescan, !Task.isCancelled {
            let timer = Task { [delay] in try await Task.sleep(for: delay) }
            sleeper = timer
            let fired = (try? await timer.value) != nil
            sleeper = nil
            guard !fired, let debounce = wakeDelay else { break }
            wakeDelay = nil
            delay = debounce
        }
        pendingRescan = false
    }

    // MARK: Actions

    func openSelectedPortal() {
        if let url = selectedPortal?.url { show(url) }
    }

    func openSelectedInBrowser() {
        if let url = selectedPortal?.url { NSWorkspace.shared.open(url) }
    }

    func forceHTTPPage() { show(Self.forcedHTTPURL) }

    func perform(_ action: Hint.Action) {
        switch action {
        case .switchDNSToAutomatic: switchDNSToAutomatic()
        case .forceHTTPPage: forceHTTPPage()
        case .downloadUpdate: if let url = availableUpdate?.pageURL { NSWorkspace.shared.open(url) }
        }
    }

    /// A new request (fresh id) makes the portal window open and load it.
    private func show(_ url: URL) { portalRequest = PortalRequest(url: url) }

    private func switchDNSToAutomatic() {
        guard let service = scan.service, !scan.manualDNS.isEmpty, !isSwitchingDNS else { return }
        let servers = scan.manualDNS
        isSwitchingDNS = true
        Task {
            defer { isSwitchingDNS = false }
            do {
                if isLive {
                    try await Self.offMain { try DNSSwitcher.switchToAutomatic(service: service, servers: servers) }
                }
                setAppHint(Hint(id: "dns-switched",
                                title: "DNS temporarily set to automatic",
                                message: "Your DNS servers will be restored once the Internet works, or when you quit ConnectNow.",
                                severity: .info))
                autoOpenedURL = nil  // reload the portal found with the new DNS
                withAnimation { notice = "DNS set to automatic, scanning again…" }
                rescan()
            } catch {
                alert = AlertContent(
                    title: "Couldn't change the DNS",
                    message: "\(error.localizedDescription)\n\nChange it manually in System Settings → Wi-Fi → Details → DNS.")
            }
        }
    }

    // MARK: Updates

    /// Automatic check: once per launch, only once online (a portal would just block it), silent on failure.
    private func checkForUpdatesIfDue() {
        guard isLive, checksForUpdates, !didCheckForUpdates, scan.status == .online,
              UpdateCheck.isReleaseVersion(Self.appVersion) else { return }
        didCheckForUpdates = true
        Task { await checkForUpdates(reportResult: false) }
    }

    /// Menu command: says so when up to date or when the check fails.
    func checkForUpdatesNow() {
        Task { await checkForUpdates(reportResult: true) }
    }

    private func checkForUpdates(reportResult: Bool) async {
        let current = Self.appVersion
        guard UpdateCheck.isReleaseVersion(current) else {
            if reportResult { alert = AlertContent(title: "Development build", message: "This build (\(current)) isn't a release: there is nothing to compare it with.") }
            return
        }
        do {
            guard let release = try await UpdateCheck.newerRelease(than: current) else {
                if reportResult { alert = AlertContent(title: "ConnectNow is up to date", message: "Version \(current) is the latest.") }
                return
            }
            availableUpdate = release
            setAppHint(Hint(id: "update-available",
                            title: "ConnectNow \(release.version) is available",
                            message: "You have version \(current). Download the new version, then replace the app in Applications.",
                            severity: .info, action: .downloadUpdate))
        } catch {
            Self.log.notice("update check failed: \(error.localizedDescription, privacy: .public)")
            if reportResult { alert = AlertContent(title: "Couldn't check for updates", message: error.localizedDescription) }
        }
    }

    // MARK: Command-line tool

    var canInstallCLI: Bool { CommandLineTool.helperURL != nil }

    func toggleCLI() {
        let installing = !CommandLineTool.isInstalled
        do {
            if installing { try CommandLineTool.install() } else { try CommandLineTool.uninstall() }
            if installing {
                let message = "Open a new terminal window and run “connectnow --help”.\n\nIt is a link at \(CommandLineTool.linkURL.path): keep ConnectNow in Applications so the link keeps working."
                alert = AlertContent(title: "Command-line tool installed", message: message)
                Task { await warnIfNotInPATH(installedMessage: message) }
            } else {
                alert = AlertContent(title: "Command-line tool removed", message: "\(CommandLineTool.linkURL.path) was deleted.")
            }
        } catch .cancelled {
        } catch {
            alert = AlertContent(title: installing ? "Couldn't install the command-line tool" : "Couldn't remove the command-line tool",
                                 message: error.localizedDescription)
        }
        isCLIInstalled = CommandLineTool.isInstalled
    }

    /// The link works only if the shell looks in its folder: say so, with the line to add.
    private func warnIfNotInPATH(installedMessage: String) async {
        let inPATH = await Task.detached { CommandLineTool.isLinkDirectoryInShellPATH() }.value
        guard inPATH == false else { return }  // unknown (shell timed out): don't cry wolf
        let directory = CommandLineTool.linkURL.deletingLastPathComponent().path
        alert = AlertContent(
            title: "Installed, but \(directory) isn't in your PATH",
            message: "Your shell (\(CommandLineTool.loginShell.lastPathComponent)) won't find “connectnow” until \(directory) is in its PATH.\n\n\(CommandLineTool.pathAdvice)\n\nThen open a new terminal window.")
    }

    func refreshCLIState() { isCLIInstalled = CommandLineTool.isInstalled }

    private func restoreDNSIfSwitched() async {
        guard isLive, DNSSwitcher.isSwitched else { return }
        do {
            try await Self.offMain { try DNSSwitcher.restore() }
            appHints.removeAll { $0.id == "dns-switched" || $0.id == "dns-restore-failed" }
        } catch {
            setAppHint(Hint(id: "dns-restore-failed",
                            title: "Your manual DNS wasn't restored",
                            message: "\(error.localizedDescription) Restore it in System Settings → Wi-Fi → Details → DNS."))
        }
    }

    private func setAppHint(_ hint: Hint) {
        withAnimation(.smooth) {
            appHints.removeAll { $0.id == hint.id }
            appHints.insert(hint, at: 0)
        }
    }

    /// DNSSwitcher runs networksetup: keep it off the main thread.
    private nonisolated static func offMain(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await Task.detached(priority: .userInitiated, operation: work).value
    }
}
