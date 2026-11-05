import Foundation
import ConnectNowCore

/// `connectnow`: the scan of the ConnectNow app, in the terminal.
/// Read-only: it never changes the DNS (the app does that, and restores it).
@main
enum ConnectNowCLI {
    static func main() async {
        let options: Options
        do {
            options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            printError("connectnow: \(error.message)\nTry 'connectnow --help'.")
            exit(64)
        }
        let environment = ProcessInfo.processInfo.environment
        let renderer = Renderer(
            color: Options.usesColor(options.color, environment: environment, isTerminal: isatty(STDOUT_FILENO) == 1),
            verbose: options.verbose)

        switch options.command {
        case .help:
            print(Options.usage)
        case .version:
            print("connectnow \(version)")
        case .status:
            let scan = await scanWithProgress(show: !options.quiet && !options.json)
            if options.json { print(renderer.json(scan, pretty: true)) }
            else if !options.quiet { print(renderer.report(scan)) }
            exit(scan.status.exitCode)
        case .open:
            let scan = await scanWithProgress(show: !options.quiet && !options.json)
            if scan.status == .online {
                if options.json { print(renderer.json(scan, pretty: true)) }
                else if !options.quiet { print(renderer.report(scan)) }
                exit(0)  // nothing to sign in to
            }
            guard let portal = scan.portals.first else {
                if options.json { print(renderer.json(scan, pretty: true)) }
                else if !options.quiet { print(renderer.report(scan)) }
                printError("connectnow: no portal found")
                exit(1)
            }
            if !options.quiet && !options.json { print("Opening \(renderer.paint(portal.url.absoluteString, .bold))") }
            if options.json { print(renderer.json(scan, pretty: true)) }
            exit(openInBrowser(portal.url) ? 0 : 1)
        case .watch:
            await watch(options: options, renderer: renderer)
        }
    }

    // MARK: Commands

    /// Same rhythm as the app: every 4 s while not online, every 30 s once online, and on each network change.
    static func watch(options: Options, renderer: Renderer) async {
        let (wakes, wake) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let monitor = Task {
            for await _ in NetworkMonitor().changes() {
                try? await Task.sleep(for: .seconds(1))  // let DHCP and routes settle
                wake.yield()
            }
        }
        defer { monitor.cancel() }

        var timer: Task<Void, Never>?
        var previous: String?
        wake.yield()
        for await _ in wakes {
            timer?.cancel()
            let scan = await scan()
            let key = ([scan.status.rawValue] + scan.portals.map(\.url.absoluteString) + scan.hints.map(\.id)).joined(separator: "|")
            if key != previous {
                previous = key
                if options.json { print(renderer.json(scan, pretty: false)) }
                else if options.verbose { print(renderer.report(scan) + "\n") }
                else if !options.quiet { print(renderer.line(scan, at: .now)) }
                fflush(stdout)
            }
            let delay: Duration = scan.status == .online ? .seconds(30) : .seconds(4)
            timer = Task {
                guard (try? await Task.sleep(for: delay)) != nil else { return }
                wake.yield()
            }
        }
    }

    // MARK: Scanning

    /// A scan with the hints the app adds itself (network extensions, checked only when they matter).
    static func scan() async -> ScanResult {
        var scan = await NetworkScanner().scan()
        if scan.status == .scanning { scan.status = .offline }  // a finished scan always concludes
        if scan.status == .captive || scan.status == .offline {
            let extensions = SystemChecks.networkExtensions()
            if !extensions.isEmpty { scan.hints.append(.networkExtensions(extensions)) }
        }
        return scan
    }

    /// Shows "Scanning…" on stderr while the scan runs, only when stderr is an interactive terminal.
    static func scanWithProgress(show: Bool) async -> ScanResult {
        let interactive = show && isatty(STDERR_FILENO) == 1 && ProcessInfo.processInfo.environment["TERM"] != "dumb"
        if interactive { FileHandle.standardError.write(Data("Scanning…".utf8)) }
        let result = await scan()
        if interactive { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }
        return result
    }

    // MARK: System

    static func openInBrowser(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            printError("connectnow: couldn't open \(url.absoluteString): \(error.localizedDescription)")
            return false
        }
    }

    /// Version of the enclosing ConnectNow.app (the tool lives in Contents/Helpers, often behind a symlink).
    static var version: String {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return "dev" }
        let plist = executable.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              let version = info["CFBundleShortVersionString"] as? String else { return "dev" }
        return version
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

extension NetworkStatus {
    var exitCode: Int32 {
        switch self {
        case .online: 0
        case .captive: 1
        case .offline, .scanning: 2
        case .noNetwork: 3
        }
    }
}
