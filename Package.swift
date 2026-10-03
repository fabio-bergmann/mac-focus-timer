// swift-tools-version: 5.9
import PackageDescription

// No package dependencies on purpose: the .app is assembled by hand
// (scripts/build-app.sh), and SwiftPM resource bundles from dependencies
// don't land where a hand-built bundle looks for them.
let package = Package(
    name: "FocusTimer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FocusTimerCore"),
        .executableTarget(name: "FocusTimer", dependencies: ["FocusTimerCore"]),
        .testTarget(name: "FocusTimerCoreTests", dependencies: ["FocusTimerCore"]),
    ]
)
