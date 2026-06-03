// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DICOMDecoder",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13),
        .macOS(.v12)
    ],
    products: [
        .library(name: "DicomCore", targets: ["DicomCore"]),
        .executable(name: "dicomtool", targets: ["dicomtool"]),
        .library(name: "DicomSwiftUI", targets: ["DicomSwiftUI"]),
        .executable(name: "DicomSwiftUIExample", targets: ["DicomSwiftUIExample"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "DicomCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/DicomCore",
            exclude: [
                "JPEGLossless_ALGORITHM.md"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: [.iOS, .macOS])),
                .linkedLibrary("z")
            ]
        ),
        .executableTarget(
            name: "dicomtool",
            dependencies: [
                "DicomCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicomtool"
        ),
        .target(
            name: "DicomSwiftUI",
            dependencies: ["DicomCore"],
            path: "Sources/DicomSwiftUI"
        ),
        .executableTarget(
            name: "DicomSwiftUIExample",
            dependencies: ["DicomSwiftUI", "DicomCore"],
            path: "Examples/DicomSwiftUIExample",
            exclude: [
                "Info.plist",
                "README.md"
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DicomTestSupport",
            dependencies: ["DicomCore"],
            // Shared test support target that owns MockDicomDecoder for all test targets.
            path: "Tests/DicomTestSupport"
        ),
        .testTarget(
            name: "DicomCoreTests",
            dependencies: [
                "DicomCore",
                "DicomTestSupport",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Tests/DicomCoreTests",
            exclude: [
                "Fixtures",
                "validate_jpeg_lossless_bitperfect.sh"
            ],
            resources: [
                .process("PerformanceBenchmarks/Baselines"),
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "DicomSwiftUITests",
            dependencies: ["DicomSwiftUI", "DicomCore", "DicomTestSupport"],
            path: "Tests/DicomSwiftUITests"
        ),
        .testTarget(
            name: "dicomtoolTests",
            dependencies: [
                "dicomtool",
                "DicomCore",
                "DicomTestSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Tests/dicomtoolTests"
        ),
        .testTarget(
            name: "dicomtoolIntegrationTests",
            dependencies: [
                "dicomtool",
                "DicomCore",
                "DicomTestSupport"
            ],
            path: "Tests/dicomtoolIntegrationTests"
        )
    ]
)
