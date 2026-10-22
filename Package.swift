// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KIndicator",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "KIndicator",
            path: "Sources/KIndicator"
        )
    ]
)
