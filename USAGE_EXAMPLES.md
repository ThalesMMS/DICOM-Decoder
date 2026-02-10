# DICOM Decoder - Usage Examples

This document provides detailed examples of using the Swift DICOM Decoder in various scenarios.

## Table of Contents

- [Recommended API (Throwing Initializers)](#recommended-api-throwing-initializers)
- [Migration from Legacy API](#migration-from-legacy-api)
- [Type-Safe DicomTag Enum](#type-safe-dicomtag-enum)
- [Basic Usage](#basic-usage)
- [Async/Await Usage](#asyncawait-usage)
- [Validation and Error Handling](#validation-and-error-handling)
- [Window/Level Operations](#windowlevel-operations)
- [Medical Presets](#medical-presets)
- [Metadata Extraction](#metadata-extraction)
- [Image Quality Metrics](#image-quality-metrics)
- [Batch Processing](#batch-processing)
- [Protocol-Based Dependency Injection](#protocol-based-dependency-injection)
- [Advanced Features](#advanced-features)

## Recommended API (Throwing Initializers)

The library provides Swift-idiomatic throwing initializers for error handling. This is the **recommended approach** for new code.

### Loading with Throwing Initializer (Recommended)

```swift
import DicomCore

do {
    // Load DICOM file with throwing initializer (URL variant)
    let url = URL(fileURLWithPath: "/path/to/image.dcm")
    let decoder = try DCMDecoder(contentsOf: url)

    // Access image properties immediately - no need to check success boolean
    print("Image dimensions: \(decoder.width) x \(decoder.height)")
    print("Bit depth: \(decoder.bitDepth)")

    // ✅ Recommended: Use type-safe DicomTag enum
    print("Modality: \(decoder.info(for: .modality))")
    print("Patient: \(decoder.info(for: .patientName))")

    // ⚠️ Legacy: Raw hex values (still supported for custom/private tags)
    // print("Modality: \(decoder.info(for: 0x00080060))")

    // Get pixels
    if let pixels16 = decoder.getPixels16() {
        print("Loaded \(pixels16.count) 16-bit pixels")
    }
} catch DICOMError.fileNotFound(let path) {
    print("File not found: \(path)")
} catch DICOMError.invalidDICOMFormat(let path, let reason) {
    print("Invalid DICOM file at \(path): \(reason)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Loading with String Path

```swift
do {
    // Load DICOM file from String path
    let decoder = try DCMDecoder(contentsOfFile: "/path/to/image.dcm")

    print("Image dimensions: \(decoder.width) x \(decoder.height)")
} catch DICOMError.fileNotFound(let path) {
    print("File not found: \(path)")
} catch DICOMError.invalidDICOMFormat(let path, let reason) {
    print("Invalid DICOM file: \(reason)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Static Factory Methods

```swift
do {
    // Alternative: Use static factory method
    let url = URL(fileURLWithPath: "/path/to/image.dcm")
    let decoder = try DCMDecoder.load(from: url)

    // Or with String path
    let decoder2 = try DCMDecoder.load(fromFile: "/path/to/image.dcm")

    print("Successfully loaded: \(decoder.width) x \(decoder.height)")
} catch {
    print("Failed to load: \(error)")
}
```

### Async Throwing Initializers (Non-Blocking)

```swift
import DicomCore

func loadDICOMAsync() async {
    do {
        // Load asynchronously without blocking the main thread
        let url = URL(fileURLWithPath: "/path/to/image.dcm")
        let decoder = try await DCMDecoder(contentsOf: url)

        print("Loaded asynchronously: \(decoder.width) x \(decoder.height)")

        // Get pixels
        if let pixels = decoder.getPixels16() {
            print("Pixel count: \(pixels.count)")
        }
    } catch DICOMError.fileNotFound(let path) {
        print("File not found: \(path)")
    } catch DICOMError.invalidDICOMFormat(let path, let reason) {
        print("Invalid DICOM: \(reason)")
    } catch {
        print("Error: \(error)")
    }
}

// Usage in SwiftUI or async context
Task {
    await loadDICOMAsync()
}
```

### Async Static Factory Methods

```swift
do {
    // Async factory methods for non-blocking load
    let url = URL(fileURLWithPath: "/path/to/image.dcm")
    let decoder = try await DCMDecoder.load(from: url)

    // Or with String path
    let decoder2 = try await DCMDecoder.load(fromFile: "/path/to/image.dcm")

    print("Loaded in background: \(decoder.width) x \(decoder.height)")
} catch {
    print("Failed: \(error)")
}
```

## Migration from Legacy API

The legacy `setDicomFilename()` + `dicomFileReadSuccess` pattern is deprecated. Here's how to migrate:

### Old Pattern (Deprecated)

```swift
// ❌ Old pattern - deprecated
let decoder = DCMDecoder()
decoder.setDicomFilename("/path/to/image.dcm")

guard decoder.dicomFileReadSuccess else {
    print("Failed to load DICOM file")
    return
}

print("Dimensions: \(decoder.width) x \(decoder.height)")
```

### New Pattern (Recommended)

```swift
// ✅ New pattern - recommended
do {
    let decoder = try DCMDecoder(contentsOfFile: "/path/to/image.dcm")
    print("Dimensions: \(decoder.width) x \(decoder.height)")
} catch DICOMError.fileNotFound(let path) {
    print("File not found: \(path)")
} catch DICOMError.invalidDICOMFormat(let path, let reason) {
    print("Invalid DICOM: \(reason)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Migration Benefits

1. **Type-safe error handling**: Catch specific `DICOMError` cases instead of checking boolean flags
2. **Compiler-enforced error handling**: Swift requires `try` or `try?` - no forgotten error checks
3. **Immediate validity**: If initialization succeeds, the decoder is guaranteed to be valid
4. **Clearer intent**: Throwing initializers signal fallible operations at the API level
5. **Better async support**: Async throwing initializers integrate seamlessly with Swift Concurrency

## Type-Safe DicomTag Enum

The library provides a **type-safe `DicomTag` enum** for accessing DICOM metadata, replacing error-prone raw hex values with semantic, discoverable tag names.

### Why Use DicomTag Enum?

**Benefits:**
- **Type safety** - Compiler-checked tag names prevent typos
- **Discoverability** - Autocomplete shows all available standard tags
- **Readability** - Semantic names like `.patientName` instead of `0x00100010`
- **No magic numbers** - Self-documenting code
- **Backward compatible** - Raw hex values still work for custom/private tags

### Basic Tag Access

```swift
import DicomCore

do {
    let decoder = try DCMDecoder(contentsOfFile: "/path/to/image.dcm")

    // ✅ Recommended: Type-safe DicomTag enum
    let patientName = decoder.info(for: .patientName)
    let modality = decoder.info(for: .modality)
    let studyUID = decoder.info(for: .studyInstanceUID)
    let seriesDesc = decoder.info(for: .seriesDescription)

    print("Patient: \(patientName)")
    print("Modality: \(modality)")
    print("Study: \(studyUID)")
    print("Series: \(seriesDesc)")

} catch {
    print("Error: \(error)")
}
```

### Typed Value Access

The DicomTag enum works with all metadata access methods:

```swift
// String values (default)
let patientName = decoder.info(for: .patientName)
let modality = decoder.info(for: .modality)

// Integer values
if let rows = decoder.intValue(for: .rows) {
    print("Height: \(rows) pixels")
}

if let columns = decoder.intValue(for: .columns) {
    print("Width: \(columns) pixels")
}

if let bitsAllocated = decoder.intValue(for: .bitsAllocated) {
    print("Bits per pixel: \(bitsAllocated)")
}

// Double values
if let windowCenter = decoder.doubleValue(for: .windowCenter) {
    print("Window center: \(windowCenter)")
}

if let windowWidth = decoder.doubleValue(for: .windowWidth) {
    print("Window width: \(windowWidth)")
}

if let sliceThickness = decoder.doubleValue(for: .sliceThickness) {
    print("Slice thickness: \(sliceThickness) mm")
}
```

### Common Tags by Category

**Patient Information:**
```swift
decoder.info(for: .patientName)          // (0010,0010) Patient Name
decoder.info(for: .patientID)            // (0010,0020) Patient ID
decoder.info(for: .patientBirthDate)     // (0010,0030) Birth Date
decoder.info(for: .patientSex)           // (0010,0040) Sex
decoder.info(for: .patientAge)           // (0010,1010) Age
```

**Study/Series:**
```swift
decoder.info(for: .studyInstanceUID)     // (0020,000D) Study UID
decoder.info(for: .seriesInstanceUID)    // (0020,000E) Series UID
decoder.info(for: .modality)             // (0008,0060) Modality
decoder.info(for: .studyDescription)     // (0008,1030) Study Description
decoder.info(for: .seriesDescription)    // (0008,103E) Series Description
decoder.info(for: .studyDate)            // (0008,0020) Study Date
decoder.info(for: .studyTime)            // (0008,0030) Study Time
```

**Image Geometry:**
```swift
decoder.intValue(for: .rows)             // (0028,0010) Height
decoder.intValue(for: .columns)          // (0028,0011) Width
decoder.info(for: .pixelSpacing)         // (0028,0030) Pixel Spacing
decoder.doubleValue(for: .sliceThickness)  // (0018,0050) Slice Thickness
decoder.info(for: .imagePositionPatient)   // (0020,0032) Position
decoder.info(for: .imageOrientationPatient) // (0020,0037) Orientation
```

**Window/Level:**
```swift
decoder.doubleValue(for: .windowCenter)    // (0028,1050) Window Center
decoder.doubleValue(for: .windowWidth)     // (0028,1051) Window Width
decoder.doubleValue(for: .rescaleSlope)    // (0028,1053) Rescale Slope
decoder.doubleValue(for: .rescaleIntercept) // (0028,1052) Rescale Intercept
```

**Pixel Data:**
```swift
decoder.intValue(for: .bitsAllocated)      // (0028,0100) Bits Allocated
decoder.intValue(for: .bitsStored)         // (0028,0101) Bits Stored
decoder.intValue(for: .highBit)            // (0028,0102) High Bit
decoder.intValue(for: .pixelRepresentation) // (0028,0103) Signed/Unsigned
decoder.intValue(for: .samplesPerPixel)    // (0028,0002) Samples Per Pixel
```

### Custom and Private Tags

For custom or private tags not in the standard enum, use raw hex values:

```swift
// ⚠️ Use raw hex for custom/private tags
let manufacturerTag = decoder.info(for: 0x00091001)  // Private tag
let customData = decoder.info(for: 0x00111234)       // Custom tag

// Standard tags should use the enum
let patientName = decoder.info(for: .patientName)  // ✅ Preferred
// Not: decoder.info(for: 0x00100010)               // ❌ Discouraged for standard tags
```

### Migration from Hex Values

Replace hex values with semantic enum cases:

```swift
// ❌ Old: Magic hex numbers
let patient = decoder.info(for: 0x00100010)
let modality = decoder.info(for: 0x00080060)
let rows = decoder.intValue(for: 0x00280010)
let columns = decoder.intValue(for: 0x00280011)

// ✅ New: Semantic, discoverable tag names
let patient = decoder.info(for: .patientName)
let modality = decoder.info(for: .modality)
let rows = decoder.intValue(for: .rows)
let columns = decoder.intValue(for: .columns)
```

### Autocomplete Support

The DicomTag enum provides full IDE autocomplete:

```swift
// Start typing "decoder.info(for: ." and get autocomplete suggestions:
decoder.info(for: .pa...)  // Shows: .patientName, .patientID, .patientAge, etc.
decoder.info(for: .study...)  // Shows: .studyInstanceUID, .studyDescription, etc.
decoder.info(for: .window...)  // Shows: .windowCenter, .windowWidth
```

### Complete Example

```swift
import DicomCore

do {
    let decoder = try DCMDecoder(contentsOfFile: "/path/to/ct_scan.dcm")

    // Patient demographics using type-safe tags
    print("=== Patient Information ===")
    print("Name: \(decoder.info(for: .patientName))")
    print("ID: \(decoder.info(for: .patientID))")
    print("Sex: \(decoder.info(for: .patientSex))")
    print("Age: \(decoder.info(for: .patientAge))")

    // Study information
    print("\n=== Study Information ===")
    print("Date: \(decoder.info(for: .studyDate))")
    print("Description: \(decoder.info(for: .studyDescription))")
    print("Modality: \(decoder.info(for: .modality))")

    // Image geometry with typed access
    print("\n=== Image Properties ===")
    if let rows = decoder.intValue(for: .rows),
       let cols = decoder.intValue(for: .columns) {
        print("Dimensions: \(cols) x \(rows)")
    }

    if let bits = decoder.intValue(for: .bitsAllocated) {
        print("Bit depth: \(bits)")
    }

    // Window/level settings
    print("\n=== Display Settings ===")
    if let center = decoder.doubleValue(for: .windowCenter),
       let width = decoder.doubleValue(for: .windowWidth) {
        print("Window: C=\(center) W=\(width)")
    }

    // Spatial information
    print("\n=== Spatial Information ===")
    print("Position: \(decoder.info(for: .imagePositionPatient))")
    print("Spacing: \(decoder.info(for: .pixelSpacing))")

    if let thickness = decoder.doubleValue(for: .sliceThickness) {
        print("Slice thickness: \(thickness) mm")
    }

} catch {
    print("Error loading DICOM: \(error)")
}
```

## Basic Usage

### Loading a DICOM File (Legacy Pattern)

> **Note:** This pattern is deprecated. Use the [throwing initializers](#recommended-api-throwing-initializers) for new code.

```swift
import DicomCore

// ⚠️ Legacy pattern - still works but deprecated
let decoder = DCMDecoder()
decoder.setDicomFilename("/path/to/image.dcm")

guard decoder.dicomFileReadSuccess else {
    print("Failed to load DICOM file")
    return
}

// Access image properties
print("Image dimensions: \(decoder.width) x \(decoder.height)")
print("Bit depth: \(decoder.bitDepth)")

// ✅ Use type-safe DicomTag enum (recommended)
print("Modality: \(decoder.info(for: .modality))")
// Or legacy hex values: decoder.info(for: 0x00080060)
```

### Reading Pixel Data

```swift
// For 16-bit grayscale images (most common for CT, MR)
if let pixels16 = decoder.getPixels16() {
    print("Loaded \(pixels16.count) 16-bit pixels")

    // Apply window/level transformation
    let windowedData = DCMWindowingProcessor.applyWindowLevel(
        pixels16: pixels16,
        center: decoder.windowCenter,
        width: decoder.windowWidth
    )
}

// For 8-bit grayscale images
if let pixels8 = decoder.getPixels8() {
    print("Loaded \(pixels8.count) 8-bit pixels")
}

// For color/RGB images (ultrasound, etc.)
if let pixels24 = decoder.getPixels24() {
    print("Loaded \(pixels24.count / 3) RGB pixels")
}
```

## Async/Await Usage

### Loading Files Asynchronously with Throwing Initializers (Recommended)

```swift
import DicomCore

func loadDICOMAsync(path: String) async {
    do {
        // ✅ Recommended: Use async throwing initializer
        let decoder = try await DCMDecoder(contentsOfFile: path)

        print("Loaded \(decoder.width) x \(decoder.height)")

        // Get pixels asynchronously (if needed)
        if let pixels = await decoder.getPixels16Async() {
            print("Loaded \(pixels.count) pixels")
        }
    } catch DICOMError.fileNotFound(let filePath) {
        print("File not found: \(filePath)")
    } catch DICOMError.invalidDICOMFormat(let filePath, let reason) {
        print("Invalid DICOM at \(filePath): \(reason)")
    } catch {
        print("Error: \(error)")
    }
}

// Usage
Task {
    await loadDICOMAsync(path: "/path/to/image.dcm")
}
```

### Loading Files Asynchronously (Legacy Pattern)

> **Note:** This pattern is deprecated. Use the [async throwing initializers](#recommended-api-throwing-initializers) for new code.

```swift
import DicomCore

func loadDICOMAsyncLegacy(path: String) async {
    let decoder = DCMDecoder()

    // ⚠️ Legacy pattern - deprecated
    let success = await decoder.loadDICOMFileAsync(path)

    guard success else {
        print("Failed to load DICOM file")
        return
    }

    // Get pixels asynchronously
    if let pixels = await decoder.getPixels16Async() {
        print("Loaded \(pixels.count) pixels")

        // Process pixels...
    }
}

// Usage
Task {
    await loadDICOMAsyncLegacy(path: "/path/to/image.dcm")
}
```

### Thumbnail Generation

```swift
// Get downsampled pixels for thumbnail (much faster than full resolution)
if let thumbnail = await decoder.getDownsampledPixels16Async(maxDimension: 150) {
    print("Thumbnail size: \(thumbnail.width) x \(thumbnail.height)")

    // Apply window/level to thumbnail
    let windowedThumb = DCMWindowingProcessor.applyWindowLevel(
        pixels16: thumbnail.pixels,
        center: decoder.windowCenter,
        width: decoder.windowWidth
    )
}
```

## Validation and Error Handling

### Validating DICOM Files

```swift
let decoder = DCMDecoder()

// Validate file structure before loading
let validation = decoder.validateDICOMFile("/path/to/image.dcm")

if !validation.isValid {
    print("Validation failed:")
    for issue in validation.issues {
        print("  - \(issue)")
    }
    return
}

// Load the validated file
decoder.setDicomFilename("/path/to/image.dcm")

// Check detailed validation status
let status = decoder.getValidationStatus()
print("Valid: \(status.isValid)")
print("Dimensions: \(status.width) x \(status.height)")
print("Has pixels: \(status.hasPixels)")
print("Compressed: \(status.isCompressed)")
```

### Using Convenience Methods

```swift
// Check image type
if decoder.isGrayscale {
    print("Grayscale image")
} else if decoder.isColorImage {
    print("Color image")
}

if decoder.isMultiFrame {
    print("Multi-frame image with \(decoder.nImages) frames")
}

// Check validity
if decoder.isValid() {
    print("Decoder has valid DICOM data")
}
```

## Window/Level Operations

### Applying Window/Level

```swift
guard let pixels16 = decoder.getPixels16() else { return }

// Use default window/level from DICOM header
let defaultWindowed = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: decoder.windowCenter,
    width: decoder.windowWidth
)

// Use custom window/level
let customWindowed = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: 40.0,  // Brain window center
    width: 80.0    // Brain window width
)
```

### Calculating Optimal Window/Level

```swift
guard let pixels16 = decoder.getPixels16() else { return }

// Calculate optimal window based on image statistics
let optimal = DCMWindowingProcessor.calculateOptimalWindowLevel(pixels16: pixels16)
print("Optimal window - Center: \(optimal.center), Width: \(optimal.width)")

// Or use decoder convenience method
if let optimal = decoder.calculateOptimalWindow() {
    let windowed = DCMWindowingProcessor.applyWindowLevel(
        pixels16: pixels16,
        center: optimal.center,
        width: optimal.width
    )
}
```

## Medical Presets

### Using CT Presets

```swift
// Get all available presets
let allPresets = DCMWindowingProcessor.allPresets
for preset in allPresets {
    let values = DCMWindowingProcessor.getPresetValues(preset: preset)
    print("\(preset.displayName): C:\(values.center) W:\(values.width)")
}

// Get CT-specific presets
let ctPresets = DCMWindowingProcessor.ctPresets
// Returns: [.lung, .bone, .softTissue, .brain, .liver, .mediastinum, etc.]

// Apply a specific preset
let brainPreset = DCMWindowingProcessor.getPresetValues(preset: .brain)
let brainWindowed = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: brainPreset.center,
    width: brainPreset.width
)
```

### Auto-Suggesting Presets

```swift
// ✅ Use type-safe DicomTag enum for metadata access
let modality = decoder.info(for: .modality)
let bodyPart = decoder.info(for: .bodyPartExamined)

let suggestions = DCMWindowingProcessor.suggestPresets(
    for: modality,
    bodyPart: bodyPart
)

print("Suggested presets:")
for preset in suggestions {
    print("  - \(preset.displayName)")
}
```

### Preset Lookup by Name

```swift
// Case-insensitive preset lookup
if let lungPreset = DCMWindowingProcessor.getPresetValues(named: "lung") {
    print("Lung preset: C:\(lungPreset.center) W:\(lungPreset.width)")
}

// Multi-word presets
if let tissuePreset = DCMWindowingProcessor.getPresetValues(named: "soft tissue") {
    print("Soft tissue preset: C:\(tissuePreset.center) W:\(tissuePreset.width)")
}
```

## Metadata Extraction

### Patient Information

```swift
let patientInfo = decoder.getPatientInfo()
print("Patient Name: \(patientInfo["Name"] ?? "Unknown")")
print("Patient ID: \(patientInfo["ID"] ?? "Unknown")")
print("Patient Sex: \(patientInfo["Sex"] ?? "Unknown")")
print("Patient Age: \(patientInfo["Age"] ?? "Unknown")")
```

### Study Information

```swift
let studyInfo = decoder.getStudyInfo()
print("Study UID: \(studyInfo["StudyInstanceUID"] ?? "")")
print("Study Date: \(studyInfo["StudyDate"] ?? "")")
print("Study Time: \(studyInfo["StudyTime"] ?? "")")
print("Description: \(studyInfo["StudyDescription"] ?? "")")
```

### Series Information

```swift
let seriesInfo = decoder.getSeriesInfo()
print("Series UID: \(seriesInfo["SeriesInstanceUID"] ?? "")")
print("Series Number: \(seriesInfo["SeriesNumber"] ?? "")")
print("Modality: \(seriesInfo["Modality"] ?? "")")
print("Description: \(seriesInfo["SeriesDescription"] ?? "")")
```

### Accessing Individual Tags

```swift
// ✅ Recommended: Use type-safe DicomTag enum

// String values
let patientName = decoder.info(for: .patientName)
let modality = decoder.info(for: .modality)

// Integer values
if let rows = decoder.intValue(for: .rows) {
    print("Rows: \(rows)")
}

if let columns = decoder.intValue(for: .columns) {
    print("Columns: \(columns)")
}

// Double values
if let sliceThickness = decoder.doubleValue(for: .sliceThickness) {
    print("Slice thickness: \(sliceThickness) mm")
}

if let windowCenter = decoder.doubleValue(for: .windowCenter) {
    print("Window center: \(windowCenter)")
}

// ⚠️ Legacy: Raw hex values (use only for custom/private tags)
let privateTag = decoder.info(for: 0x00091001)  // Private manufacturer tag

// Get all tags
let allTags = decoder.getAllTags()
for (tag, value) in allTags {
    print("\(tag): \(value)")
}
```

### Using Convenience Properties

```swift
// Image dimensions
let dims = decoder.imageDimensions
print("Size: \(dims.width) x \(dims.height)")

// Pixel spacing
let spacing = decoder.pixelSpacing
print("Spacing: \(spacing.width) x \(spacing.height) x \(spacing.depth) mm")

// Window settings
let window = decoder.windowSettings
print("Window: C:\(window.center) W:\(window.width)")

// Rescale parameters (for Hounsfield Units in CT)
let rescale = decoder.rescaleParameters
print("Rescale: slope=\(rescale.slope) intercept=\(rescale.intercept)")
```

## Image Quality Metrics

### Calculating Quality Metrics

```swift
guard let pixels16 = decoder.getPixels16() else { return }

let metrics = DCMWindowingProcessor.calculateQualityMetrics(pixels16: pixels16)

print("Mean intensity: \(metrics["mean"] ?? 0)")
print("Standard deviation: \(metrics["std_deviation"] ?? 0)")
print("Min value: \(metrics["min_value"] ?? 0)")
print("Max value: \(metrics["max_value"] ?? 0)")
print("Contrast: \(metrics["contrast"] ?? 0)")
print("SNR: \(metrics["snr"] ?? 0)")
print("Dynamic range: \(metrics["dynamic_range"] ?? 0) dB")

// Or use decoder convenience method
if let metrics = decoder.getQualityMetrics() {
    print("Image quality metrics: \(metrics)")
}
```

## Batch Processing

### Processing Multiple Images

```swift
let filePaths = [
    "/path/to/image1.dcm",
    "/path/to/image2.dcm",
    "/path/to/image3.dcm"
]

// Sequential processing
for path in filePaths {
    let decoder = DCMDecoder()
    decoder.setDicomFilename(path)

    if decoder.dicomFileReadSuccess {
        print("Processed: \(path)")
        // Process image...
    }
}

// Parallel processing with async/await
await withTaskGroup(of: Bool.self) { group in
    for path in filePaths {
        group.addTask {
            let decoder = DCMDecoder()
            return await decoder.loadDICOMFileAsync(path)
        }
    }

    for await success in group {
        if success {
            print("Successfully loaded a file")
        }
    }
}
```

### Batch Window/Level Application

```swift
// Process multiple images with different window settings
let imagePixels: [[UInt16]] = [/* array of pixel arrays */]
let centers = [40.0, 50.0, 60.0]  // Different centers for each image
let widths = [80.0, 350.0, 400.0]  // Different widths for each image

let results = DCMWindowingProcessor.batchApplyWindowLevel(
    imagePixels: imagePixels,
    centers: centers,
    widths: widths
)

for (index, result) in results.enumerated() {
    if let windowed = result {
        print("Image \(index): \(windowed.count) bytes")
    }
}
```

## Protocol-Based Dependency Injection

The library uses protocol-based dependency injection to enable testability, flexibility, and clean architecture. All core services implement protocols that can be mocked or replaced with custom implementations.

### Why Use Dependency Injection?

- **Testability**: Replace real implementations with mocks for unit testing
- **Flexibility**: Swap implementations without changing client code
- **Maintainability**: Clear separation of concerns and dependencies
- **Isolation**: Test components independently without file I/O

### Available Protocols

All core components have protocol abstractions:

- `DicomDecoderProtocol` - Abstracts DICOM file parsing (implemented by `DCMDecoder`, `MockDicomDecoder`)
- `StudyDataServiceProtocol` - Abstracts study/series processing (implemented by `StudyDataService`)
- `DicomSeriesLoaderProtocol` - Abstracts series volume loading (implemented by `DicomSeriesLoader`)
- `DicomDictionaryProtocol` - Abstracts DICOM tag lookups (implemented by `DCMDictionary`)
- `FileImportServiceProtocol` - Abstracts file import operations (implemented by `FileImportService`)

### Basic Dependency Injection

Services accept decoder factories instead of creating decoders directly:

```swift
import DicomCore

// Production: Inject real decoder factory
let studyService = StudyDataService(
    decoderFactory: { DCMDecoder() }
)

// Testing: Inject mock decoder factory
let mockStudyService = StudyDataService(
    decoderFactory: { MockDicomDecoder() }
)

// Use the service (same API regardless of implementation)
let studies = studyService.loadStudiesFromDirectory("/path/to/dicom/files")
```

### Testing with MockDicomDecoder

The `MockDicomDecoder` provides a fully configurable implementation for testing:

```swift
import XCTest
@testable import DicomCore

class MyDicomTests: XCTestCase {
    func testStudyLoading() {
        // Create and configure mock decoder
        let mock = MockDicomDecoder()
        mock.width = 512
        mock.height = 512
        mock.bitDepth = 16
        mock.dicomFileReadSuccess = true

        // Configure metadata tags (using raw values for mocking)
        // Note: Use DicomTag enum values in production code
        mock.setTag(0x00100010, value: "Test^Patient")       // .patientName
        mock.setTag(0x0020000D, value: "1.2.3.4.5.6.7.8.9")  // .studyInstanceUID
        mock.setTag(0x0020000E, value: "1.2.3.4.5.6.7.8.10") // .seriesInstanceUID
        mock.setTag(0x00080060, value: "CT")                 // .modality

        // Configure pixel data
        let testPixels = [UInt16](repeating: 1000, count: 512 * 512)
        mock.setPixels16(testPixels)

        // Inject mock into service
        let service = StudyDataService(
            decoderFactory: { mock }
        )

        // Test the service with mock data
        let studies = service.loadStudiesFromDirectory("/test/path")

        // Verify results
        XCTAssertEqual(studies.count, 1)
        XCTAssertEqual(studies[0].studyInstanceUID, "1.2.3.4.5.6.7.8.9")
    }
}
```

### Factory Pattern for Multiple Files

Services use factories instead of single instances to ensure clean state per file:

```swift
// ❌ Wrong: Single decoder instance (state leakage)
let decoder = DCMDecoder()
let service = StudyDataService(decoder: decoder)  // Not the actual API!

// ✅ Correct: Factory creates fresh decoder per file
let service = StudyDataService(
    decoderFactory: { DCMDecoder() }
)

// Each file gets its own decoder instance
// Thread-safe for concurrent file processing
// No state leakage between files
```

### Custom Protocol Implementations

You can create custom implementations for specialized use cases:

```swift
// Custom decoder that adds logging
class LoggingDicomDecoder: DicomDecoderProtocol {
    private let underlying: DicomDecoderProtocol
    private let logger: Logger

    init(underlying: DicomDecoderProtocol = DCMDecoder(), logger: Logger) {
        self.underlying = underlying
        self.logger = logger
    }

    func setDicomFilename(_ filename: String) {
        logger.info("Loading DICOM file: \(filename)")
        underlying.setDicomFilename(filename)

        if underlying.dicomFileReadSuccess {
            logger.info("Successfully loaded \(width)x\(height) image")
        } else {
            logger.error("Failed to load DICOM file")
        }
    }

    // Forward all other protocol methods to underlying
    var width: Int { underlying.width }
    var height: Int { underlying.height }
    // ... implement remaining protocol requirements ...
}

// Use custom implementation
let service = StudyDataService(
    decoderFactory: { LoggingDicomDecoder(logger: myLogger) }
)
```

### Injecting Dependencies in DicomSeriesLoader

Load 3D volumes with custom decoders:

```swift
// Production usage with real decoder
let seriesLoader = DicomSeriesLoader(
    decoderFactory: { DCMDecoder() }
)

// Test usage with mock decoder
let mockLoader = DicomSeriesLoader(
    decoderFactory: {
        let mock = MockDicomDecoder()
        mock.width = 512
        mock.height = 512
        mock.setPixels16([/* test data */])
        mock.setTag(0x00200032, value: "0\\0\\0")  // .imagePositionPatient
        return mock
    }
)

// Load series (same API)
let result = try await seriesLoader.loadSeries(
    from: seriesMetadata,
    progressHandler: { progress in
        print("Loading: \(Int(progress * 100))%")
    }
)
```

### Testing FileImportService

Inject decoders into file import operations:

```swift
func testZipExtraction() {
    // Create mock decoder
    let mock = MockDicomDecoder()
    mock.dicomFileReadSuccess = true
    mock.setTag(0x0020000D, value: "1.2.3.4.5")  // .studyInstanceUID

    // Inject into FileImportService
    let importService = FileImportService(
        decoderFactory: { mock }
    )

    // Test import
    let result = importService.importFile(at: URL(fileURLWithPath: "/test.zip"))

    XCTAssertEqual(result.success, true)
}
```

### Integration Testing with Mixed Implementations

Combine real and mock implementations:

```swift
func testIntegration() {
    // Use real dictionary for tag lookups
    let realDictionary = DCMDictionary()

    // Use mock decoder for file I/O
    let mockDecoder = MockDicomDecoder()
    mockDecoder.setTag(0x00100010, value: "Test^Patient")  // .patientName

    // Combine in service
    let service = StudyDataService(
        decoderFactory: { mockDecoder }
    )

    // Dictionary works with real tag database
    let tagName = realDictionary.description(forKey: "00100010")
    XCTAssertEqual(tagName, "Patient's Name")

    // Service uses mock for testing
    let studies = service.loadStudiesFromDirectory("/test")
    XCTAssertEqual(studies[0].patientName, "Test^Patient")
}
```

### Backward Compatibility

The library maintains backward compatibility with default initializers:

```swift
// Modern DI approach (recommended)
let service = StudyDataService(
    decoderFactory: { DCMDecoder() }
)

// Legacy approach (still works, uses default factory internally)
let legacyService = StudyDataService()

// Both work identically for production code
```

### Best Practices

1. **Always use factories in services**: Each file should get a fresh decoder
2. **Configure mocks completely**: Set all required properties and tags
3. **Test with protocols**: Write tests against protocol types, not concrete classes
4. **Use default factories for production**: Only inject custom factories for testing
5. **Thread safety**: Services using factories are thread-safe for concurrent operations

### Complete Testing Example

```swift
import XCTest
@testable import DicomCore

class CompleteDIExample: XCTestCase {
    func testCompleteWorkflow() async throws {
        // 1. Setup mock decoder with complete data
        let mock = MockDicomDecoder()

        // Configure image properties
        mock.width = 512
        mock.height = 512
        mock.bitDepth = 16
        mock.dicomFileReadSuccess = true

        // Configure spatial properties
        mock.pixelWidth = 0.5
        mock.pixelHeight = 0.5
        mock.pixelDepth = 1.0

        // Configure display properties
        mock.windowCenter = 40.0
        mock.windowWidth = 80.0

        // Configure metadata (using raw hex for mocking)
        // In production code, access these with DicomTag enum (e.g., .patientName)
        mock.setTag(0x00100010, value: "Doe^John")            // .patientName
        mock.setTag(0x00100020, value: "12345")               // .patientID
        mock.setTag(0x0020000D, value: "1.2.840.113619.2.1.1") // .studyInstanceUID
        mock.setTag(0x0020000E, value: "1.2.840.113619.2.1.2") // .seriesInstanceUID
        mock.setTag(0x00080060, value: "CT")                  // .modality
        mock.setTag(0x00200032, value: "0\\0\\0")             // .imagePositionPatient
        mock.setTag(0x00200037, value: "1\\0\\0\\0\\1\\0")    // .imageOrientationPatient

        // Configure pixel data
        let pixels = [UInt16](repeating: 1000, count: 512 * 512)
        mock.setPixels16(pixels)

        // 2. Inject into services
        let studyService = StudyDataService(
            decoderFactory: { mock }
        )

        let seriesLoader = DicomSeriesLoader(
            decoderFactory: { mock }
        )

        // 3. Test complete workflow
        let studies = studyService.loadStudiesFromDirectory("/test")

        XCTAssertEqual(studies.count, 1)
        XCTAssertEqual(studies[0].patientName, "Doe^John")
        XCTAssertEqual(studies[0].series.count, 1)

        let series = studies[0].series[0]
        XCTAssertEqual(series.modality, "CT")

        // 4. Test series loading
        let result = try await seriesLoader.loadSeries(from: series.images)

        XCTAssertEqual(result.width, 512)
        XCTAssertEqual(result.height, 512)
        XCTAssertEqual(result.slices.count, 1)

        // 5. Verify pixel data
        XCTAssertEqual(result.slices[0].count, 512 * 512)
        XCTAssertEqual(result.slices[0][0], 1000)
    }
}
```

## Advanced Features

### Hounsfield Unit Conversion (CT Images)

```swift
let rescale = decoder.rescaleParameters

// Convert pixel value to Hounsfield Units
let pixelValue = 1024.0
let hu = decoder.applyRescale(to: pixelValue)
print("Pixel \(pixelValue) = \(hu) HU")

// Or use static method
let hu2 = DCMWindowingProcessor.pixelValueToHU(
    pixelValue: pixelValue,
    rescaleSlope: rescale.slope,
    rescaleIntercept: rescale.intercept
)

// Convert HU to pixel value
let pixelVal = DCMWindowingProcessor.huToPixelValue(
    hu: 0.0,  // Water
    rescaleSlope: rescale.slope,
    rescaleIntercept: rescale.intercept
)
```

### Image Enhancement

```swift
guard let pixels16 = decoder.getPixels16() else { return }

// Apply window/level first
let windowed = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: 40.0,
    width: 80.0
)

guard let windowedData = windowed else { return }

// Apply CLAHE (Contrast Limited Adaptive Histogram Equalization)
let enhanced = DCMWindowingProcessor.applyCLAHE(
    imageData: windowedData,
    width: decoder.width,
    height: decoder.height,
    clipLimit: 2.0
)

// Apply noise reduction
let denoised = DCMWindowingProcessor.applyNoiseReduction(
    imageData: windowedData,
    width: decoder.width,
    height: decoder.height,
    strength: 0.5
)
```

### Performance Optimization

```swift
guard let pixels16 = decoder.getPixels16() else { return }

// Use optimized windowing for large datasets
let optimized = DCMWindowingProcessor.optimizedApplyWindowLevel(
    pixels16: pixels16,
    center: 40.0,
    width: 80.0,
    useParallel: true  // Enable parallel processing for large images
)

// Use downsampled pixels for preview/thumbnail
if let thumbnail = decoder.getDownsampledPixels16(maxDimension: 150) {
    // Much faster than processing full resolution
    let windowedThumb = DCMWindowingProcessor.applyWindowLevel(
        pixels16: thumbnail.pixels,
        center: 40.0,
        width: 80.0
    )
}
```

### Error Handling with DICOMError

```swift
import DicomCore

func loadDICOM(path: String) throws {
    let decoder = DCMDecoder()

    // Validate file first
    let validation = decoder.validateDICOMFile(path)
    if !validation.isValid {
        throw DICOMError.invalidFileFormat(
            path: path,
            expectedFormat: "Valid DICOM file with proper header"
        )
    }

    // Load file
    decoder.setDicomFilename(path)

    guard decoder.dicomFileReadSuccess else {
        throw DICOMError.fileReadError(
            path: path,
            underlyingError: "Failed to parse DICOM data"
        )
    }

    // Check for compressed images
    if decoder.compressedImage {
        throw DICOMError.unsupportedTransferSyntax(
            syntax: "Compressed transfer syntax not supported"
        )
    }

    // Verify required metadata using type-safe DicomTag enum
    let studyUID = decoder.info(for: .studyInstanceUID)
    if studyUID.isEmpty {
        throw DICOMError.missingRequiredTag(
            tag: "StudyInstanceUID",
            description: "Study Instance UID"
        )
    }
}

// Usage with error handling
do {
    try loadDICOM(path: "/path/to/image.dcm")
    print("DICOM loaded successfully")
} catch let error as DICOMError {
    print("Error: \(error.localizedDescription)")
    print("Suggestion: \(error.recoverySuggestion ?? "None")")
    print("Category: \(error.category)")
    print("Severity: \(error.severity)")
} catch {
    print("Unknown error: \(error)")
}
```

## Complete Example: DICOM Viewer Component

```swift
import DicomCore
import Foundation

class DICOMImageProcessor {
    private let decoder = DCMDecoder()

    func loadAndProcess(path: String) async throws -> ProcessedImage {
        // Validate file
        let validation = decoder.validateDICOMFile(path)
        guard validation.isValid else {
            throw DICOMError.invalidFileFormat(
                path: path,
                expectedFormat: "Valid DICOM file"
            )
        }

        // Load file asynchronously
        let success = await decoder.loadDICOMFileAsync(path)
        guard success else {
            throw DICOMError.fileReadError(
                path: path,
                underlyingError: "Failed to load DICOM data"
            )
        }

        // Get metadata
        let patientInfo = decoder.getPatientInfo()
        let studyInfo = decoder.getStudyInfo()
        let seriesInfo = decoder.getSeriesInfo()

        // Get suggested presets using type-safe DicomTag enum
        let modality = decoder.info(for: .modality)
        let bodyPart = decoder.info(for: .bodyPartExamined)
        let suggestedPresets = DCMWindowingProcessor.suggestPresets(
            for: modality,
            bodyPart: bodyPart
        )

        // Get pixels
        guard let pixels16 = await decoder.getPixels16Async() else {
            throw DICOMError.invalidPixelData(reason: "No pixel data available")
        }

        // Calculate optimal window
        let optimal = DCMWindowingProcessor.calculateOptimalWindowLevel(
            pixels16: pixels16
        )

        // Apply window/level
        guard let windowedData = DCMWindowingProcessor.applyWindowLevel(
            pixels16: pixels16,
            center: optimal.center,
            width: optimal.width
        ) else {
            throw DICOMError.imageProcessingFailed(
                operation: "Window/Level",
                reason: "Failed to apply window/level transformation"
            )
        }

        // Get quality metrics
        let metrics = DCMWindowingProcessor.calculateQualityMetrics(
            pixels16: pixels16
        )

        return ProcessedImage(
            imageData: windowedData,
            width: decoder.width,
            height: decoder.height,
            patientInfo: patientInfo,
            studyInfo: studyInfo,
            seriesInfo: seriesInfo,
            suggestedPresets: suggestedPresets,
            currentWindow: optimal,
            qualityMetrics: metrics
        )
    }
}

struct ProcessedImage {
    let imageData: Data
    let width: Int
    let height: Int
    let patientInfo: [String: String]
    let studyInfo: [String: String]
    let seriesInfo: [String: String]
    let suggestedPresets: [MedicalPreset]
    let currentWindow: (center: Double, width: Double)
    let qualityMetrics: [String: Double]
}
```

---

For more information, see the main [README.md](README.md) and inline code documentation.
