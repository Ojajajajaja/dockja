// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "dockja",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DockjaCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "dockja",
            dependencies: ["DockjaCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DockjaCoreTests",
            dependencies: ["DockjaCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
