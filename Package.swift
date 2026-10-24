// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KIndicator",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure logic: the keyboard protocol, lighting decisions, layouts and keymaps.
        // Foundation only, so everything in it can be tested without a keyboard.
        .target(
            name: "KIndicatorCore",
            path: "Sources/KIndicatorCore"
        ),
        // The app: HID, Core Audio, settings and UI, running what the core decides.
        .executableTarget(
            name: "KIndicator",
            dependencies: ["KIndicatorCore"],
            path: "Sources/KIndicator"
        ),
        .testTarget(
            name: "KIndicatorCoreTests",
            dependencies: ["KIndicatorCore"],
            path: "Tests/KIndicatorCoreTests"
        ),
    ]
)
