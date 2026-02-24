// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "C-Through",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CThroughEngine", targets: ["CThroughEngine"]),
        .executable(name: "C-Through", targets: ["C-Through"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CThroughEngine",
            dependencies: [],
            path: "Sources/CThroughEngine"
        ),
        .executableTarget(
            name: "C-Through",
            dependencies: ["CThroughEngine"],
            path: "Sources/C-Through"
        ),
        .testTarget(
            name: "CThroughEngineTests",
            dependencies: ["CThroughEngine"],
            path: "Tests/CThroughEngineTests"
        ),
    ]
)
