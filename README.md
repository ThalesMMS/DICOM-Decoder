# Swift DICOM Decoder

This directory packages the Swift-only DICOM decoding core extracted from the legacy viewer project. It delivers a clean SwiftPM target that can be embedded in new apps without any UIKit or Objective‑C baggage.

- Repository: [`ThalesMMS/DICOM-Decoder`](https://github.com/ThalesMMS/DICOM-Decoder)
- Latest release: [`1.0.0`](https://github.com/ThalesMMS/DICOM-Decoder/releases/tag/1.0.0)

## Module Layout

- `Package.swift` – defines a single library product, `DicomCore`, plus unit tests.
- `Sources/DicomCore/` – decoder (`DCMDecoder`), windowing utilities (`DCMWindowingProcessor`), shared models (`DICOMError`, `StudyDataService`, `PatientModel`), and lightweight protocols (e.g. `DicomWindowingSurface`) for downstream UI layers.
- `Sources/DicomCore/Resources/DCMDictionary.plist` – bundled tag dictionary consumed by the decoder.
- `Tests/DicomCoreTests/` – seed XCTest target validating resource loading.
- `ViewerReference/` – archived viewer-layer services (e.g. import + series helpers) kept for reference but excluded from the Swift package.

## Requirements

- Swift 5.9+
- Apple platforms: iOS 13+ or macOS 12+ (SwiftPM manifest target list)
- Frameworks pulled by the core: Foundation, CoreGraphics, ImageIO, Accelerate
- **Uncompressed DICOM only** – compressed transfer syntaxes are detected and reported as unsupported.

## Installation

Add the package to your project via SwiftPM:

```swift
.package(url: "https://github.com/ThalesMMS/DICOM-Decoder.git", from: "1.0.0")
```

and declare the dependency:

```swift
.target(
    name: "ViewerApp",
    dependencies: [
        .product(name: "DicomCore", package: "SwiftDICOMDecoder")
    ]
)
```

## Quick Start

```swift
import DicomCore

let decoder = DCMDecoder()
decoder.setDicomFilename("/path/to/image.dcm")

guard decoder.dicomFileReadSuccess else {
    throw DicomDecodingError.decodingFailed
}

// Access metadata
let width = decoder.width
let height = decoder.height
let modality = decoder.info(for: 0x00080060) // Modality tag

// Access pixel data (16-bit grayscale example)
if let pixels16 = decoder.getPixels16() {
    let mapped = DCMWindowingProcessor.applyWindowLevel(
        pixels16: pixels16,
        center: decoder.windowCenter,
        width: decoder.windowWidth
    )
    // Convert `mapped` (Data) into an image using your own rendering pipeline
}
```

Need UI components? Conform your own rendering surface to `DicomWindowingSurface` (declared in `Protocols.swift`) and integrate it inside your app. The archived UIKit implementations remain in `ViewerReference/` for reference but are intentionally excluded from the package.

## How It Works

- **Decoder flow** – `DCMDecoder` reads the file header, parses data elements, and lazily loads pixel data to keep memory usage predictable.
- **Metadata access** – Call `info(for:)` with numeric tags or rely on helpers in `StudyDataService` to materialize typed models.
- **Pixel processing** – Windowing math lives in `DCMWindowingProcessor`, returning `Data` buffers so you decide how to render on each platform.
- **Resource lookup** – `DCMDictionary.plist` is bundled and loaded at runtime to translate tags into friendly titles when needed.
- **Error handling** – Failures surface via `DICOMError`; inspect the associated reason and recover, rather than assuming the image loaded.

## Core Components

- `DCMDecoder` – synchronous decoder API that expects callers to manage threading; wrap it in a `Task` or background queue for UI apps.
- `DCMWindowingProcessor` – stateless functions for classic DICOM window/level math plus clamping helpers for 8/16-bit outputs.
- `StudyDataService` – convenience layer for scanning folders, grouping studies, and emitting lightweight structs for UI use.
- `DicomWindowingSurface` – protocol describing the minimal API a rendering surface must implement when you build UI on top.
- `DICOMError` – typed error enum used across the package, making it easy to switch on decoding, IO, or supportability failures.
- `DCMDictionary.plist` – tag dictionary consumed lazily; extend it if you need site-specific private tags.

## Extending the Package

- Build higher-level services (window/level presets, ROI tools, etc.) on top of the core by adding new Swift-only targets in your host project.
- Use `StudyDataService` to batch extract metadata when scanning folders of `.dcm` files.
- Fork `ViewerReference/` if you want to resurrect the UIKit helpers; they can live in a separate package.

## Integration Tips

- Offload decoding to a background queue when used inside apps; the API is synchronous and CPU-bound.
- Cache `DCMDecoder` instances per study if you need repeated pixel reads, but avoid sharing them across threads.
- Normalize window presets in your UI layer and feed them into `DCMWindowingProcessor` to keep rendering predictable.
- When importing many files, use `StudyDataService` to pre-flight metadata so your UI can stay responsive.
- Expand `Tests/DicomCoreTests` with modality-specific fixtures to guard against regressions in your workflow.

## Viewer Reference Code

- `ViewerReference/FileImportService.swift` – async/await importer used by the legacy viewer; useful if you plan to rebuild a UI shell.
- `ViewerReference/SeriesBusinessLogic.swift` – Combine-based series grouping logic; adapt pieces if you need similar behavior.
- Both files rely on viewer-side concepts (`StudyManager`, UIKit alerts) and are not compiled with the Swift package targets.

## Releasing

- Update `Package.swift` and tag versions according to [SemVer](https://semver.org/) before publishing.
- Run `swift test` (and any platform builds) to confirm the release candidate is green.
- Commit the changes, create an annotated tag (`git tag -a 1.0.0 -m "Swift DICOM Decoder 1.0.0"`) and push it (`git push --follow-tags`).
- Draft a GitHub release that references the tag; SwiftPM consumers resolve packages by git tags.
- Optional: publish API docs with DocC or attach a source archive generated via `swift package archive-source`.

## Limitations & TODOs

- Compressed pixel data (JPEG/JPEG2000) is not decoded.
- Minimal automated testing is bundled; expand `Tests/` with decoding/windowing scenarios that matter to your app.
- A public sample app is not included. Provide your own examples or demos if distributing this package.
- MIT license provided; review and update the copyright line if needed.

## Contributing

1. Fork the repository and create a branch for your change.
2. Modify code within `Sources/DicomCore` or extend the test suite in `Tests/DicomCoreTests`.
3. Run `swift test` (or platform-specific builds) to validate your updates.
4. Submit a pull request describing the changes and results.

This module now ships as a pure Swift core; UI layers, platform adaptations, or Objective‑C bridges can be maintained as separate packages when needed.

## Acknowledgments

This project is a fork of kesalin's Objective-C DICOM decoder (`https://github.com/kesalin/DicomViewer`). The Swift package rebuilds that foundation in Swift while preserving the original contributions.
