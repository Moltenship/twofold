// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Twofold",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Twofold",
            path: "Sources/Twofold",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
