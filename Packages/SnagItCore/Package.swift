// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnagItCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SnagItCore", targets: ["SnagItCore"]),
    ],
    targets: [
        .target(
            name: "SnagItCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SnagItCoreTests",
            dependencies: ["SnagItCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
