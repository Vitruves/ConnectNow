import Foundation
import Testing
@testable import ConnectNowCore

@Test func comparesVersionsNumerically() {
    #expect(UpdateCheck.isVersion("1.10.0", newerThan: "1.9.3"))
    #expect(UpdateCheck.isVersion("1.0.1", newerThan: "1.0"))
    #expect(!UpdateCheck.isVersion("1.0", newerThan: "1.0.0"))
    #expect(!UpdateCheck.isVersion("0.9", newerThan: "1.0.0"))
    #expect(!UpdateCheck.isVersion("1.1.0-beta", newerThan: "1.1.0"))
    #expect(!UpdateCheck.isVersion("garbage", newerThan: "1.0.0"))
}

@Test func developmentBuildsAreNotReleases() {
    #expect(UpdateCheck.isReleaseVersion("1.0.0"))
    #expect(!UpdateCheck.isReleaseVersion("0.0.0"))
    #expect(!UpdateCheck.isReleaseVersion("0.0.0-abc1234"))
    #expect(!UpdateCheck.isReleaseVersion(""))
}

@Test func parsesGitHubRelease() throws {
    let json = #"{"tag_name":"v1.2.0","html_url":"https://github.com/Vitruves/ConnectNow/releases/tag/v1.2.0","draft":false}"#
    let release = try UpdateCheck.parse(Data(json.utf8))
    #expect(release == AppRelease(version: "1.2.0", pageURL: URL(string: "https://github.com/Vitruves/ConnectNow/releases/tag/v1.2.0")!))
}
