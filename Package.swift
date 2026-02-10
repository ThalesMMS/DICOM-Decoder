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
            ],
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: [.iOS, .macOS]))
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
