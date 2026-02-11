# Swift DICOM Decoder

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" />
  <img src="https://img.shields.io/badge/iOS-13.0+-blue.svg" />
  <img src="https://img.shields.io/badge/macOS-12.0+-blue.svg" />
  <img src="https://img.shields.io/badge/license-MIT-green.svg" />
</p>

Pure Swift DICOM decoder for iOS and macOS. Read DICOM files, extract medical metadata, and process pixel data without UIKit or Objective-C dependencies.

Suitable for lightweight DICOM viewers, PACS clients, telemedicine apps, and research tools.

- Repository: [`ThalesMMS/DICOM-Decoder`](https://github.com/ThalesMMS/DICOM-Decoder)
- Latest release: [`1.0.0`](https://github.com/ThalesMMS/DICOM-Decoder/releases/tag/1.0.0)
- Documentation: [API Reference](https://thalesmms.github.io/DICOM-Decoder/documentation/dicomcore/) | [Getting Started](GETTING_STARTED.md) | [Glossary](DICOM_GLOSSARY.md) | [Troubleshooting](TROUBLESHOOTING.md)

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Performance](#performance)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Usage Examples](#usage-examples)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [Integration](#integration)
- [Contributing](#contributing)
- [License](#license)
- [Support](#support)

---

## Overview

This project is a full DICOM decoder written in Swift, modernized from a legacy medical viewer. It provides:

- Complete DICOM file parsing (metadata and pixels)
- Pixel extraction for 8-bit, 16-bit grayscale and 24-bit RGB images
- Window/level with medical presets and automatic suggestions
- Modern async/await APIs for non-blocking operations
- File validation before processing
- Zero external dependencies

DICOM (Digital Imaging and Communications in Medicine) is the standard for medical imaging used by CT, MRI, X-ray, ultrasound, and hospital PACS systems.

---

## Features

### DICOM Decoding

- Little/Big Endian, Explicit/Implicit VR
- Grayscale 8/16-bit and RGB 24-bit
- Native JPEG Lossless decoding (Process 14, Selection Value 1) for transfer syntaxes 1.2.840.10008.1.2.4.57 and 1.2.840.10008.1.2.4.70
- Best-effort single-frame JPEG and JPEG2000 decoding via ImageIO
- Automatic memory mapping for large files (>10MB)
- Downsampling for fast thumbnail generation

### Geometry & Metadata

- Parses Image Orientation (Patient) (0020,0037) and Image Position (Patient) (0020,0032); exposes normalized row/column vectors and origin.
- Reads Pixel Spacing (0028,0030) and slice spacing/thickness; exposes spacingX/Y/Z.
- Exposes width/height, bitsAllocated, pixelRepresentation (signed/unsigned), rescale slope/intercept.
- Returns Series Description and raw tag access via `info(for:)`.

### Series Loading (new)

- Directory-level loader that scans `.dcm` files, orders slices by IPP projection on the IOP normal (fallback: Instance Number), and computes Z spacing from IPP deltas.
- Validates single-channel 16-bit geometry consistency and assembles a contiguous volume buffer (signed/unsigned preserved).
- Progress callback per slice and lightweight `DicomSeriesVolume` with voxels, spacing, orientation matrix, origin, rescale parameters, and description.

### Image Processing

- Window/Level with medical presets (CT, mammography, PET, and more)
- Automatic preset suggestions based on modality and body part
- Quality metrics (SNR, contrast, dynamic range)
- Basic helpers for contrast stretching and noise reduction (CLAHE placeholder, simple blur)
- Hounsfield Unit conversions for CT images

### Modern APIs

- **Swift-idiomatic throwing initializers** for type-safe error handling
- **Type-safe DicomTag enum** for metadata access (preferred over raw hex values)
- **Type-safe value types** (WindowSettings, PixelSpacing, RescaleParameters) with Codable support
- **V2 APIs** returning structs instead of tuples for better type safety
- **Async/await** support (iOS 13+, macOS 10.15+) with async throwing initializers
- **Static factory methods** for alternative initialization patterns
- **Validation** before loading
- **Convenience metadata helpers** (patient, study, series)
- **Tag caching** for frequent lookups

### Developer Experience

- Complete documentation with practical examples
- DICOM glossary
- Troubleshooting guide for common issues
- Tests covering parsing and series loading

---

## Performance

### Window/Level Processing Performance

The library uses **vDSP** (Accelerate framework) as the baseline CPU implementation for window/level operations. vDSP leverages hand-tuned **ARM NEON assembly** for SIMD operations, providing optimal CPU performance on Apple Silicon and Intel processors.

For applications requiring higher throughput, **Metal GPU acceleration** delivers significant performance gains over the vDSP baseline:

| Image Size | vDSP (CPU) | Metal (GPU) | Speedup |
|------------|------------|-------------|---------|
| 512×512    | 2.14 ms    | 1.16 ms     | 1.84×   |
| 1024×1024  | 8.67 ms    | 2.20 ms     | **3.94×** |

**Benchmark Environment:**
- Hardware: Apple M4 (2024)
- OS: macOS 15+
- Iterations: 100 (after 20 warmup iterations)
- Algorithm: Window/level transformation on 16-bit grayscale DICOM pixels

**Key Findings:**
- **vDSP baseline is optimal** - Uses ARM NEON assembly; further CPU SIMD optimizations yield negligible gains
- **Metal GPU shines on larger images** - 3.94× speedup on 1024×1024 images (typical CT/MRI size)
- **Small images favor CPU** - 512×512 images show 1.84× speedup due to GPU setup overhead
- **Production recommendation** - Use `.auto` mode for automatic backend selection, or choose `.metal`/`.vdsp` explicitly

**Usage:**

Metal GPU acceleration is integrated into `DCMWindowingProcessor.applyWindowLevel()` via the `processingMode` parameter:

```swift
// Default behavior (backward compatible) - uses vDSP
let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: 50.0,
    width: 400.0
)

// Explicit Metal GPU acceleration
let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: 50.0,
    width: 400.0,
    processingMode: .metal  // Force GPU (falls back to vDSP if unavailable)
)

// Automatic selection (recommended)
let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: 50.0,
    width: 400.0,
    processingMode: .auto  // Auto-selects Metal for ≥800×800 images
)
```

See [CLAUDE.md](CLAUDE.md#gpu-acceleration) for detailed usage examples and performance characteristics.

---

## Quick Start

### Fast Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ThalesMMS/DICOM-Decoder.git", from: "1.0.0")
]
```

### First Example (Modern API)

```swift
import DicomCore

do {
    // Load DICOM file with throwing initializer (recommended)
    let decoder = try DCMDecoder(contentsOfFile: "/path/to/image.dcm")

    print("Dimensions: \(decoder.width) x \(decoder.height)")

    // ✅ Recommended: Use type-safe DicomTag enum
    print("Modality: \(decoder.info(for: .modality))")
    print("Patient: \(decoder.info(for: .patientName))")

    // ⚠️ Legacy: Raw hex values (still supported for custom/private tags)
    // print("Modality: \(decoder.info(for: 0x00080060))")

    if let pixels = decoder.getPixels16() {
        print("\(pixels.count) pixels loaded")
    }
} catch DICOMError.fileNotFound(let path) {
    print("File not found: \(path)")
} catch DICOMError.invalidDICOMFormat(let path, let reason) {
    print("Invalid DICOM file: \(reason)")
} catch {
    print("Error: \(error)")
}
```

**Alternative patterns:**

```swift
// Static factory method
let decoder = try DCMDecoder.load(fromFile: "/path/to/image.dcm")

// Async for non-blocking load
let decoder = try await DCMDecoder(contentsOfFile: "/path/to/image.dcm")

// URL-based initialization
let url = URL(fileURLWithPath: "/path/to/image.dcm")
let decoder = try DCMDecoder(contentsOf: url)
```

For a detailed walkthrough, see [GETTING_STARTED.md](GETTING_STARTED.md) and [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md).

### Type-Safe Metadata Access

The library provides a **type-safe `DicomTag` enum** for accessing DICOM metadata, eliminating the need for raw hex values:

```swift
// ✅ Recommended: Type-safe and discoverable via autocomplete
let patientName = decoder.info(for: .patientName)
let modality = decoder.info(for: .modality)
let studyUID = decoder.info(for: .studyInstanceUID)
let rows = decoder.intValue(for: .rows) ?? 0
let windowCenter = decoder.doubleValue(for: .windowCenter)

// ⚠️ Legacy: Raw hex values (still supported for custom/private tags)
let customTag = decoder.info(for: 0x00091001)  // Private tag
```

**Benefits:**
- **Type safety** - Compiler-checked tag names
- **Discoverability** - Autocomplete shows all available tags
- **Readability** - Semantic names instead of hex codes
- **Backward compatible** - Raw hex values still work for custom/private tags

See [Common DICOM Tags](#common-dicom-tags) for a full list of supported tags.

### Type-Safe Value Types (V2 APIs)

The library provides dedicated structs for common DICOM parameters, offering better type safety and Codable conformance than tuple-based APIs:

```swift
// ✅ Window settings as a struct (recommended)
let settings = decoder.windowSettingsV2  // WindowSettings struct
if settings.isValid {
    print("Window: center=\(settings.center), width=\(settings.width)")
}

// ✅ Pixel spacing as a struct (recommended)
let spacing = decoder.pixelSpacingV2  // PixelSpacing struct
if spacing.isValid {
    print("Spacing: \(spacing.x) × \(spacing.y) × \(spacing.z) mm")
}

// ✅ Rescale parameters as a struct (recommended)
let rescale = decoder.rescaleParametersV2  // RescaleParameters struct
if !rescale.isIdentity {
    let hounsfieldValue = rescale.apply(to: pixelValue)
}

// ✅ V2 windowing methods return WindowSettings
let optimal = DCMWindowingProcessor.calculateOptimalWindowLevelV2(pixels16: pixels)
let preset = DCMWindowingProcessor.getPresetValuesV2(preset: .lung)

// ⚠️ Legacy: Tuple-based APIs (deprecated but still supported)
let (center, width) = decoder.windowSettings  // Returns tuple
```

**Benefits of V2 APIs:**
- **Type safety** - Structs prevent parameter order mistakes
- **Codable support** - Serialize to JSON for persistence
- **Sendable conformance** - Safe across concurrency boundaries
- **Computed properties** - `.isValid`, `.isIdentity` checks
- **Methods** - `.apply(to:)` for transformations
- **Better autocomplete** - Named properties instead of tuple labels

See [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md#type-safe-value-types-v2-apis) for detailed migration examples.

---

## Installation

### Via Xcode

1. File -> Add Packages...
2. Paste `https://github.com/ThalesMMS/DICOM-Decoder.git`
3. Select version `1.0.0` or later
4. Add Package

### Via Package.swift

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/ThalesMMS/DICOM-Decoder.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "DicomCore", package: "DICOM-Decoder")
        ]
    )
]
```

### Requirements

- Swift 5.9+
- iOS 13.0+ or macOS 12.0+
- Xcode 14.0+

---

## Usage Examples

### 1. Basic Reading

```swift
import DicomCore

do {
    // ✅ Recommended: Use throwing initializer
    let decoder = try DCMDecoder(contentsOfFile: "/path/to/ct_scan.dcm")

    // ✅ Use type-safe DicomTag enum for metadata access
    print("Patient: \(decoder.info(for: .patientName))")
    print("Modality: \(decoder.info(for: .modality))")
    print("Dimensions: \(decoder.width) x \(decoder.height)")

    if let pixels = decoder.getPixels16() {
        // Process image...
    }
} catch {
    print("Load error: \(error)")
}
```

### 2. Async/Await (iOS 13+)

```swift
func loadDICOM() async {
    let decoder = DCMDecoder()
    let success = await decoder.loadDICOMFileAsync("/path/to/image.dcm")

    guard success else { return }

    if let pixels = await decoder.getPixels16Async() {
        await showImage(pixels, decoder.width, decoder.height)
    }
}
```

### 3. Window/Level with Medical Presets

```swift
guard let pixels = decoder.getPixels16() else { return }

// ✅ Use type-safe DicomTag enum
let modality = decoder.info(for: .modality)
let suggestions = DCMWindowingProcessor.suggestPresets(for: modality)

let lungPreset = DCMWindowingProcessor.getPresetValues(preset: .lung)
let lungImage = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels,
    center: lungPreset.center,
    width: lungPreset.width
)

if let optimal = decoder.calculateOptimalWindow() {
    let optimizedImage = DCMWindowingProcessor.applyWindowLevel(
        pixels16: pixels,
        center: optimal.center,
        width: optimal.width
    )
}
```

### 4. Validate Before Loading

```swift
let validation = decoder.validateDICOMFile("/path/to/image.dcm")

if !validation.isValid {
    print("Invalid file:")
    for issue in validation.issues {
        print("  - \(issue)")
    }
    return
}

decoder.setDicomFilename("/path/to/image.dcm")
```

### 5. Structured Metadata

```swift
let patient = decoder.getPatientInfo()
let study = decoder.getStudyInfo()
let series = decoder.getSeriesInfo()
```

### 6. Fast Thumbnail

```swift
if let thumb = decoder.getDownsampledPixels16(maxDimension: 150) {
    let thumbWindowed = DCMWindowingProcessor.applyWindowLevel(
        pixels16: thumb.pixels,
        center: 40.0,
        width: 80.0
    )
}
```

### 7. Quality Metrics

```swift
if let metrics = decoder.getQualityMetrics() {
    print("Image quality:")
    print("  Mean: \(metrics["mean"] ?? 0)")
    print("  Standard deviation: \(metrics["std_deviation"] ?? 0)")
    print("  SNR: \(metrics["snr"] ?? 0)")
    print("  Contrast: \(metrics["contrast"] ?? 0)")
    print("  Dynamic range: \(metrics["dynamic_range"] ?? 0) dB")
}
```

### 8. Hounsfield Units (CT)

```swift
let pixelValue: Double = 1024.0
let hu = decoder.applyRescale(to: pixelValue)

if hu < -500 {
    print("Likely air or lung")
} else if hu > 700 {
    print("Likely bone")
}
```

More examples: [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md).

---

## Architecture

### Main Components

| Component | Description | Primary Use |
|-----------|-------------|-------------|
| `DCMDecoder` | Core DICOM decoder | Load files, extract pixels and metadata |
| `DCMWindowingProcessor` | Image processing | Window/level, presets, quality metrics |
| `StudyDataService` | Data service | Scan directories, group studies |
| `DICOMError` | Error system | Typed error handling |
| `DCMDictionary` | Tag dictionary | Map numeric tags to names |

### Workflow

```
1. DICOM file
        |
2. validateDICOMFile() (optional but recommended)
        |
3. setDicomFilename() / loadDICOMFileAsync()
        |
4. Decoder parses:
   - Header (128 bytes + "DICM")
   - Meta Information
   - Dataset (tags + values)
   - Pixel Data (lazy loading)
        |
5. Access data:
   - info(for:) -> Metadata
   - getPixels16() -> Pixel buffer
   - applyWindowLevel() -> Processed pixels
```

### Project Structure

```
DICOM-Decoder/
|-- Package.swift
|-- Sources/DicomCore/
|   |-- DCMDecoder.swift
|   |-- DCMWindowingProcessor.swift
|   |-- DICOMError.swift
|   |-- StudyDataService.swift
|   |-- PatientModel.swift
|   |-- Protocols.swift
|   |-- DCMDictionary.swift
|   `-- Resources/DCMDictionary.plist
|-- Tests/DicomCoreTests/
`-- ViewerReference/
```

### Common DICOM Tags

Use the type-safe `DicomTag` enum for accessing standard DICOM tags:

**Patient Information:**
```swift
.patientName                 // (0010,0010) - Patient Name
.patientID                   // (0010,0020) - Patient ID
.patientBirthDate            // (0010,0030) - Patient Birth Date
.patientSex                  // (0010,0040) - Patient Sex
.patientAge                  // (0010,1010) - Patient Age
```

**Study/Series Information:**
```swift
.studyInstanceUID            // (0020,000D) - Study Instance UID
.seriesInstanceUID           // (0020,000E) - Series Instance UID
.modality                    // (0008,0060) - Modality (CT, MR, XR, etc.)
.studyDescription            // (0008,1030) - Study Description
.seriesDescription           // (0008,103E) - Series Description
```

**Image Properties:**
```swift
.rows                        // (0028,0010) - Rows (height)
.columns                     // (0028,0011) - Columns (width)
.bitsAllocated               // (0028,0100) - Bits Allocated
.bitsStored                  // (0028,0101) - Bits Stored
.pixelRepresentation         // (0028,0103) - Pixel Representation
```

**Spatial Information:**
```swift
.imagePositionPatient        // (0020,0032) - Image Position (Patient)
.imageOrientationPatient     // (0020,0037) - Image Orientation (Patient)
.pixelSpacing                // (0028,0030) - Pixel Spacing
.sliceThickness              // (0018,0050) - Slice Thickness
```

**Window/Level:**
```swift
.windowCenter                // (0028,1050) - Window Center
.windowWidth                 // (0028,1051) - Window Width
.rescaleSlope                // (0028,1053) - Rescale Slope
.rescaleIntercept            // (0028,1052) - Rescale Intercept
```

For custom or private tags not in the enum, use raw hex values:
```swift
let privateTag = decoder.info(for: 0x00091001)  // Private manufacturer tag
```

---

## Documentation

### API Reference

Complete API documentation generated with DocC is available online:

**[📚 Swift DICOM Decoder API Reference](https://thalesmms.github.io/DICOM-Decoder/documentation/dicomcore/)**

The API reference includes:
- Detailed class and method documentation
- Code examples and usage patterns
- Type definitions and protocols
- Complete symbol index

### Beginner Guides

| Document | Description | Best For |
|----------|-------------|----------|
| [Getting Started](GETTING_STARTED.md) | End-to-end tutorial | New to DICOM |
| [DICOM Glossary](DICOM_GLOSSARY.md) | Terminology reference | Understanding terms |
| [Troubleshooting](TROUBLESHOOTING.md) | Common issues and fixes | Debugging problems |

### Advanced Guides

| Document | Description | Best For |
|----------|-------------|----------|
| [Usage Examples](USAGE_EXAMPLES.md) | Complete, ready-to-use code samples | Copy and adapt |
| [CHANGELOG](CHANGELOG.md) | Release history | Tracking changes |

### Key Concepts

#### Window/Level

Controls brightness and contrast of DICOM images:
- Level (Center): brightness
- Width: contrast

```swift
// Lung: Center -600 HU, Width 1500 HU
// Bone: Center  400 HU, Width 1800 HU
// Brain: Center  40 HU, Width   80 HU
```

#### DICOM Tags

The library provides a type-safe `DicomTag` enum for accessing metadata:

```swift
// ✅ Recommended: Type-safe DicomTag enum
decoder.info(for: .patientName)       // Patient Name
decoder.info(for: .modality)          // Modality (CT, MR, etc.)
decoder.info(for: .rows)              // Image height
decoder.intValue(for: .columns)       // Image width (as Int)
decoder.doubleValue(for: .windowCenter)  // Window center (as Double)

// ⚠️ Legacy: Raw hex values (still supported for custom/private tags)
decoder.info(for: 0x00100010)  // Patient Name
decoder.info(for: 0x00080060)  // Modality
decoder.info(for: 0x00280010)  // Rows
```

#### Hounsfield Units (CT)

Density scale in CT imaging:
- Air: -1000 HU
- Lung: -500 HU
- Water: 0 HU
- Muscle: +40 HU
- Bone: +700 to +3000 HU

---

## Integration

### Integration Tips

- Use background processing for large files:
```swift
Task.detached {
    await decoder.loadDICOMFileAsync(path)
}
```

- Validate before loading to improve UX:
```swift
let validation = decoder.validateDICOMFile(path)
if !validation.isValid {
    showError(validation.issues)
}
```

- Use thumbnails for image lists:
```swift
let thumb = decoder.getDownsampledPixels16(maxDimension: 150)
```

- Cache decoder instances per study:
```swift
var decoders: [String: DCMDecoder] = [:]
decoders[studyUID] = decoder
```

- Release memory during batch processing:
```swift
autoreleasepool {
    // Process file
}
```

### Known Limitations

- Compressed transfer syntaxes: Native support for JPEG Lossless (Process 14, Selection Value 1). Best-effort single-frame JPEG/JPEG2000 via ImageIO. RLE and multi-frame encapsulated compression are not supported - convert first if needed.
- Thread safety: The decoder is not thread-safe. Use one instance per thread or synchronize access.
- Very large files (>1GB): May consume significant memory. Process in chunks or downsample.

### Frameworks Used

Native Apple frameworks only:
- `Foundation`
- `CoreGraphics`
- `ImageIO`
- `Accelerate`

---

## Contributing

Contributions are welcome.

### How to Contribute

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/MyFeature`).
3. Update code in `Sources/DicomCore/` and add tests.
4. Run the tests:
   ```bash
   swift test
   swift build
   ```
5. Commit with a clear message.
6. Push to your branch.
7. Open a Pull Request.

### Areas That Need Help

- Documentation improvements
- Additional test cases
- Bug fixes
- Performance optimizations
- New medical presets
- Internationalization

### Code of Conduct

- Be respectful and constructive.
- Follow Swift code conventions.
- Add tests for new functionality.
- Preserve backward compatibility.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

```
MIT License

Copyright (c) 2024 ThalesMMS

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software...
```

---

## Acknowledgments

This project originates from the Objective-C DICOM decoder by [kesalin](https://github.com/kesalin/DicomViewer). The Swift package modernizes that codebase while preserving credit to the original author.

---

## Support

- Documentation: [GETTING_STARTED.md](GETTING_STARTED.md)
- Bug reports: [GitHub Issues](https://github.com/ThalesMMS/DICOM-Decoder/issues)
- Discussions: [GitHub Discussions](https://github.com/ThalesMMS/DICOM-Decoder/discussions)
- Email: Please open an issue first

---

If this project is useful, consider starring the repository or contributing improvements.
