// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "zest",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZestCore", targets: ["ZestCore"]),
        .executable(name: "zest", targets: ["zest"]),
        .executable(name: "ZestApp", targets: ["ZestApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "ZestCore",
            dependencies: [.product(name: "Yams", package: "Yams")]
        ),
        .executableTarget(
            name: "zest",
            dependencies: [
                "ZestCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "ZestUI",
            dependencies: ["ZestCore"]
        ),
        .executableTarget(
            name: "ZestApp",
            dependencies: ["ZestCore", "ZestUI"],
            // AppKit and the Accessibility API are not annotated for Swift 6 concurrency yet.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Renders docs/images/demo.gif with the real engine and popup (`make demo`).
        .executableTarget(
            name: "ZestDemo",
            dependencies: ["ZestCore", "ZestUI"]
        ),
        .testTarget(
            name: "ZestCoreTests",
            dependencies: ["ZestCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
