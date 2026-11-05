import Foundation

/// Command line of `connectnow`, parsed without any dependency.
struct Options: Equatable {
    enum Command: String, CaseIterable { case status, watch, open, help, version }
    enum ColorMode: String, CaseIterable { case auto, always, never }

    var command = Command.status
    var json = false
    var verbose = false
    var quiet = false
    var color = ColorMode.auto

    struct UsageError: Error, Equatable { let message: String }

    static func parse(_ arguments: [String]) throws(UsageError) -> Options {
        var options = Options()
        var commandSet = false
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "-h", "--help": options.command = .help; return options
            case "-V", "--version": options.command = .version; return options
            case "--json": options.json = true
            case "-v", "--verbose": options.verbose = true
            case "-q", "--quiet": options.quiet = true
            case "--no-color": options.color = .never
            case "--color": options.color = try colorMode(iterator.next())
            case _ where argument.hasPrefix("--color="):
                options.color = try colorMode(String(argument.dropFirst("--color=".count)))
            case _ where argument.hasPrefix("-"):
                throw UsageError(message: "unknown option: \(argument)")
            default:
                guard !commandSet, let command = Command(rawValue: argument) else {
                    throw UsageError(message: commandSet ? "unexpected argument: \(argument)" : "unknown command: \(argument)")
                }
                options.command = command
                commandSet = true
            }
        }
        if options.json && options.quiet { throw UsageError(message: "--json and --quiet can't be combined") }
        return options
    }

    private static func colorMode(_ value: String?) throws(UsageError) -> ColorMode {
        guard let value, let mode = ColorMode(rawValue: value) else {
            throw UsageError(message: "--color expects auto, always or never")
        }
        return mode
    }

    /// Colours: --color wins, then NO_COLOR / CLICOLOR_FORCE (no-color.org, bixense.com/clicolors), then the terminal.
    static func usesColor(_ mode: ColorMode, environment: [String: String], isTerminal: Bool) -> Bool {
        switch mode {
        case .always: return true
        case .never: return false
        case .auto:
            if let value = environment["NO_COLOR"], !value.isEmpty { return false }
            if let value = environment["CLICOLOR_FORCE"], !value.isEmpty, value != "0" { return true }
            if environment["TERM"] == "dumb" { return false }
            return isTerminal
        }
    }

    static let usage = """
        Usage: connectnow [command] [options]

        Finds the sign-in page of a public Wi-Fi and explains what blocks it.

        Commands:
          status     Scan the network once and show the result (default)
          watch      Keep scanning; print a line each time the situation changes
          open       Open the detected sign-in page in the default browser
          help       Show this help
          version    Show the version

        Options:
          -v, --verbose          Also show the interface, DNS and every probe
          -q, --quiet            Print nothing; only set the exit code
              --json             Machine-readable output (one object per line with watch)
              --color <when>     auto (default), always or never
              --no-color         Same as --color never
          -h, --help             Show this help
          -V, --version          Show the version

        Environment:
          NO_COLOR=1             Disable colours (unless --color always)
          CLICOLOR_FORCE=1       Force colours even when not writing to a terminal

        Exit status (status):
          0 online · 1 portal detected · 2 no Internet access · 3 no network · 64 usage error
        Exit status (open): 0 portal opened or already online · 1 no portal found
        """
}
