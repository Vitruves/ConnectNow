// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConnectNow",
    defaultLocalization: "fr",
    platforms: [.macOS(.v14)],
    targets: [
        // Logique réseau pure, sans interface : testable avec `swift test`.
        .target(name: "ConnectNowCore"),
        // Application SwiftUI ; emballée en .app par le Makefile.
        .executableTarget(name: "ConnectNow", dependencies: ["ConnectNowCore"]),
        // Outil `connectnow` ; embarqué dans ConnectNow.app/Contents/Helpers par le Makefile.
        .executableTarget(name: "ConnectNowCLI", dependencies: ["ConnectNowCore"]),
        .testTarget(name: "ConnectNowCoreTests", dependencies: ["ConnectNowCore"]),
        .testTarget(name: "ConnectNowCLITests", dependencies: ["ConnectNowCLI"]),
    ]
)
