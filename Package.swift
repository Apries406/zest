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
        .executableTarget(
            name: "ZestApp",
            dependencies: ["ZestCore"]
        ),
        .testTarget(
            name: "ZestCoreTests",
            dependencies: ["ZestCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
