// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanSlate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CleanSlate",
            path: "Sources/CleanSlate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
