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
        .testTarget(name: "ConnectNowCoreTests", dependencies: ["ConnectNowCore"]),
    ]
)
