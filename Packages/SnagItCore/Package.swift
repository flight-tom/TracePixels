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
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // 渲染器的像素迴圈是效能關鍵：畫布每個畫面都要重繪（SC-004），
                // 即使在 Debug 組態也以最佳化編譯，開發時才不會卡。僅限本地套件可用 unsafeFlags。
                .unsafeFlags(["-O"], .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "SnagItCoreTests",
            dependencies: ["SnagItCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
