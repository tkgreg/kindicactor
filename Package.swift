// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KIndicator",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.99.2"),
    ],
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
        // The program inside every command app: one terminal window running the app's command.
        // KIndicator copies it into each app it makes.
        .executableTarget(
            name: "CommandHost",
            dependencies: ["KIndicatorCore", "SwiftTerm"],
            path: "Sources/CommandHost"
        ),
        .testTarget(
            name: "KIndicatorCoreTests",
            dependencies: ["KIndicatorCore"],
            path: "Tests/KIndicatorCoreTests"
        ),
    ]
)
