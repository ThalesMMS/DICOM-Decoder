// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetalBenchmark",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "MetalBenchmark", targets: ["MetalBenchmark"])
    ],
    targets: [
        .executableTarget(
            name: "MetalBenchmark",
            path: "Sources",
            resources: [
                .process("Shaders.metal")
            ]
        ),
        .testTarget(
            name: "MetalBenchmarkTests",
            dependencies: ["MetalBenchmark"],
            path: "Tests"
        )
    ]
)
