// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftDICOMDecoder",
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
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "DicomCore",
            path: "Sources/DicomCore",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: [.iOS, .macOS]))
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
            path: "Examples/DicomSwiftUIExample"
        ),
        .testTarget(
            name: "DicomCoreTests",
            dependencies: ["DicomCore"],
            path: "Tests/DicomCoreTests",
            exclude: ["Fixtures"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DicomSwiftUITests",
            dependencies: ["DicomSwiftUI", "DicomCore"],
            path: "Tests/DicomSwiftUITests"
        ),
        .testTarget(
            name: "dicomtoolTests",
            dependencies: [
                "dicomtool",
                "DicomCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Tests/dicomtoolTests"
        ),
        .testTarget(
            name: "dicomtoolIntegrationTests",
            dependencies: [
                "dicomtool",
                "DicomCore"
            ],
            path: "Tests/dicomtoolIntegrationTests"
        )
    ]
)
