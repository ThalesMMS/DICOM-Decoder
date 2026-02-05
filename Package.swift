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
        .library(name: "DicomCore", targets: ["DicomCore"])
    ],
    targets: [
        .target(
            name: "DicomCore",
            path: "Sources/DicomCore",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DicomCoreTests",
            dependencies: ["DicomCore"],
            path: "Tests/DicomCoreTests",
            exclude: ["Fixtures"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
