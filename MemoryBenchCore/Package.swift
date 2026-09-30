// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MemoryBenchCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MemoryBenchCore",
            targets: ["MemoryBenchCore"]
        )
    ],
    targets: [
        .target(
            name: "MemoryBenchCore"
        ),
        .testTarget(
            name: "MemoryBenchCoreTests",
            dependencies: ["MemoryBenchCore"]
        )
    ]
)
