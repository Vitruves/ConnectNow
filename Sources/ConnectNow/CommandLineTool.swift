import AppKit

/// Installs `connectnow` in the PATH as a symlink to the copy inside the app bundle,
/// so it always matches the installed app version.
enum CommandLineTool {
    static let linkURL = URL(filePath: "/usr/local/bin/connectnow")
    private static let helperSuffix = "/Contents/Helpers/connectnow"

    enum Failure: LocalizedError {
        case notBundled
        case translocated
        case occupied
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notBundled: "This copy of ConnectNow doesn't include the command-line tool."
            case .translocated: "Move ConnectNow to the Applications folder and open it from there first: macOS is running it from a temporary location."
            case .occupied: "\(CommandLineTool.linkURL.path) already exists and doesn't belong to ConnectNow. Remove it first."
            case .cancelled: "Cancelled."
            case .failed(let detail): detail
            }
        }
    }

    /// The tool shipped in this bundle; nil when running from .build.
    static var helperURL: URL? {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Helpers/connectnow")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// What the link currently points to, if it is a symlink.
    private static var linkDestination: String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)
    }

    static var isInstalled: Bool {
        guard let helperURL, let destination = linkDestination else { return false }
        return destination == helperURL.path
    }

    static func install() throws(Failure) {
        guard let helperURL else { throw .notBundled }
        guard !helperURL.path.contains("/AppTranslocation/") else { throw .translocated }
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: linkURL.path) || linkDestination != nil
        // Replace only our own link (an older or moved ConnectNow), never someone else's file.
        if exists, linkDestination?.hasSuffix(helperSuffix) != true { throw .occupied }
        do {
            if exists { try fm.removeItem(at: linkURL) }
            try fm.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: linkURL, withDestinationURL: helperURL)
        } catch {
            // /usr/local/bin usually belongs to root: ask for an administrator password.
            try runAsAdministrator("mkdir -p \(shellQuoted(linkURL.deletingLastPathComponent().path)) && ln -sfn \(shellQuoted(helperURL.path)) \(shellQuoted(linkURL.path))")
        }
    }

    static func uninstall() throws(Failure) {
        guard let destination = linkDestination else { return }
        guard destination.hasSuffix(helperSuffix) else { throw .occupied }
        do { try FileManager.default.removeItem(at: linkURL) } catch {
            try runAsAdministrator("rm -f \(shellQuoted(linkURL.path))")
        }
    }

    // MARK: PATH check

    /// The user's login shell, from the account database (the app's own environment comes from launchd).
    static var loginShell: URL {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell, let path = String(validatingCString: shell), !path.isEmpty {
            return URL(filePath: path)
        }
        return URL(filePath: "/bin/zsh")
    }

    /// Whether a new terminal finds `connectnow`: asks the login shell for its PATH, as it is after
    /// reading the user's configuration. nil when the shell didn't answer within a few seconds. Blocking.
    static func isLinkDirectoryInShellPATH() -> Bool? {
        guard let path = shellPATH() else { return nil }
        let directory = linkURL.deletingLastPathComponent().path
        return path.split(separator: ":").contains { $0 == directory || $0 == directory + "/" }
    }

    private static func shellPATH() -> String? {
        let process = Process()
        process.executableURL = loginShell
        // Interactive + login: zsh, bash and fish then read the files where PATH is usually set.
        // printenv prints the exported, colon-separated PATH whatever the shell's own syntax.
        process.arguments = ["-l", "-i", "-c", "/usr/bin/printenv PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        // Shell start-up files may print things first: PATH is the last line.
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).last.map(String.init)
    }

    /// The line to add to the shell configuration so `connectnow` is found.
    static var pathAdvice: String {
        let directory = linkURL.deletingLastPathComponent().path
        switch loginShell.lastPathComponent {
        case "fish": return "Run: fish_add_path \(directory)"
        case "bash": return "Add this line to ~/.bash_profile:\nexport PATH=\"\(directory):$PATH\""
        default: return "Add this line to ~/.zshrc:\nexport PATH=\"\(directory):$PATH\""
        }
    }

    private static func runAsAdministrator(_ command: String) throws(Failure) {
        // The command goes in an AppleScript string literal: escape backslashes and quotes.
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(literal)\" with administrator privileges")?.executeAndReturnError(&error)
        guard let error else { return }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { throw .cancelled }
        throw .failed(error[NSAppleScript.errorMessage] as? String ?? "The command failed.")
    }

    /// Single-quoted for /bin/sh.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
