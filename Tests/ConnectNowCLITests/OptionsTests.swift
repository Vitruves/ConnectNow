import Testing
@testable import ConnectNowCLI

@Test func defaultsToStatus() throws {
    #expect(try Options.parse([]) == Options())
}

@Test func parsesCommandAndFlags() throws {
    let options = try Options.parse(["watch", "-v", "--color=never"])
    #expect(options.command == .watch)
    #expect(options.verbose)
    #expect(options.color == .never)
    #expect(try Options.parse(["--color", "always", "--json"]).color == .always)
    #expect(try Options.parse(["status", "--no-color"]).color == .never)
}

@Test func helpWinsOverEverythingAfterIt() throws {
    #expect(try Options.parse(["status", "--help", "--bogus"]).command == .help)
}

@Test func rejectsBadInput() {
    #expect(throws: Options.UsageError.self) { try Options.parse(["bogus"]) }
    #expect(throws: Options.UsageError.self) { try Options.parse(["--nope"]) }
    #expect(throws: Options.UsageError.self) { try Options.parse(["--color"]) }
    #expect(throws: Options.UsageError.self) { try Options.parse(["--color=pink"]) }
    #expect(throws: Options.UsageError.self) { try Options.parse(["status", "watch"]) }
    #expect(throws: Options.UsageError.self) { try Options.parse(["--json", "-q"]) }
}

@Test func colorFollowsFlagThenEnvironmentThenTerminal() {
    #expect(Options.usesColor(.auto, environment: [:], isTerminal: true))
    #expect(!Options.usesColor(.auto, environment: [:], isTerminal: false))
    #expect(!Options.usesColor(.auto, environment: ["NO_COLOR": "1"], isTerminal: true))
    #expect(Options.usesColor(.auto, environment: ["CLICOLOR_FORCE": "1"], isTerminal: false))
    #expect(!Options.usesColor(.auto, environment: ["CLICOLOR_FORCE": "0"], isTerminal: false))
    #expect(!Options.usesColor(.auto, environment: ["TERM": "dumb"], isTerminal: true))
    #expect(Options.usesColor(.always, environment: ["NO_COLOR": "1"], isTerminal: false))
    #expect(!Options.usesColor(.never, environment: [:], isTerminal: true))
}
