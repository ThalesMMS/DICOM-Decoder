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
- Documentation: [Getting Started](GETTING_STARTED.md) | [Glossary](DICOM_GLOSSARY.md) | [Troubleshooting](TROUBLESHOOTING.md)

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
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
- Best-effort single-frame JPEG and JPEG2000 decoding via ImageIO (no JPEG Lossless/RLE)
- Automatic memory mapping for large files (>10MB)
- Downsampling for fast thumbnail generation

### Image Processing

- Window/Level with medical presets (CT, mammography, PET, and more)
- Automatic preset suggestions based on modality and body part
- Quality metrics (SNR, contrast, dynamic range)
- Basic helpers for contrast stretching and noise reduction (CLAHE placeholder, simple blur)
- Hounsfield Unit conversions for CT images

### Modern APIs

- Async/await (iOS 13+, macOS 10.15+)
- Validation before loading
- Convenience metadata helpers (patient, study, series)
- Parallel processing for large datasets
- Tag caching for frequent lookups

### Developer Experience

- Complete documentation with practical examples
- DICOM glossary
- Troubleshooting guide for common issues
- Extensive tests
- Step-by-step tutorials

---

## Quick Start

### Fast Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ThalesMMS/DICOM-Decoder.git", from: "1.0.0")
]
```

### First Example

```swift
import DicomCore

let decoder = DCMDecoder()
decoder.setDicomFilename("/path/to/image.dcm")

guard decoder.dicomFileReadSuccess else {
    print("Failed to load file")
    return
}

print("Dimensions: \(decoder.width) x \(decoder.height)")
print("Modality: \(decoder.info(for: 0x00080060))")
print("Patient: \(decoder.info(for: 0x00100010))")

if let pixels = decoder.getPixels16() {
    print("\(pixels.count) pixels loaded")
}
```

For a detailed walkthrough, see [GETTING_STARTED.md](GETTING_STARTED.md).

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

let decoder = DCMDecoder()
decoder.setDicomFilename("/path/to/ct_scan.dcm")

guard decoder.dicomFileReadSuccess else {
    print("Load error")
    return
}

print("Patient: \(decoder.info(for: 0x00100010))")
print("Modality: \(decoder.info(for: 0x00080060))")
print("Dimensions: \(decoder.width) x \(decoder.height)")

if let pixels = decoder.getPixels16() {
    // Process image...
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

let modality = decoder.info(for: 0x00080060)
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

---

## Documentation

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

Numeric identifiers for metadata:

```swift
0x00100010  // Patient Name
0x00080060  // Modality (CT, MR, etc.)
0x00280010  // Image height
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

- Compressed transfer syntaxes: best-effort single-frame JPEG/JPEG2000 via ImageIO only. JPEG Lossless, RLE, and multi-frame encapsulated compression are not supported - convert first if needed.
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
