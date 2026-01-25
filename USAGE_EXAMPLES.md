# DICOM Decoder - Usage Examples

This document provides detailed examples of using the Swift DICOM Decoder in various scenarios.

## Table of Contents

- [Basic Usage](#basic-usage)
- [Async/Await Usage](#asyncawait-usage)
- [Validation and Error Handling](#validation-and-error-handling)
- [Window/Level Operations](#windowlevel-operations)
- [Medical Presets](#medical-presets)
- [Metadata Extraction](#metadata-extraction)
- [Image Quality Metrics](#image-quality-metrics)
- [Batch Processing](#batch-processing)
- [Advanced Features](#advanced-features)

## Basic Usage

### Loading a DICOM File (Synchronous)

```swift
import DicomCore

// Create decoder instance
let decoder = DCMDecoder()

// Load DICOM file
decoder.setDicomFilename("/path/to/image.dcm")

// Check if loading was successful
guard decoder.dicomFileReadSuccess else {
    print("Failed to load DICOM file")
    return
}

// Access image properties
print("Image dimensions: \(decoder.width) x \(decoder.height)")
print("Bit depth: \(decoder.bitDepth)")
print("Modality: \(decoder.info(for: 0x00080060))")
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

### Loading Files Asynchronously (iOS 13+, macOS 10.15+)

```swift
import DicomCore

func loadDICOMAsync(path: String) async {
    let decoder = DCMDecoder()

    // Load file asynchronously
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
    await loadDICOMAsync(path: "/path/to/image.dcm")
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
// Get suggested presets based on modality and body part
let modality = decoder.info(for: 0x00080060)  // Modality tag
let bodyPart = decoder.info(for: 0x00180015)  // Body Part Examined

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
// String values
let patientName = decoder.info(for: 0x00100010)

// Integer values
if let rows = decoder.intValue(for: 0x00280010) {
    print("Rows: \(rows)")
}

// Double values
if let sliceThickness = decoder.doubleValue(for: 0x00180050) {
    print("Slice thickness: \(sliceThickness) mm")
}

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

    // Verify required metadata
    let studyUID = decoder.info(for: 0x0020000D)
    if studyUID.isEmpty {
        throw DICOMError.missingRequiredTag(
            tag: "0020000D",
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

        // Get suggested presets
        let modality = seriesInfo["Modality"] ?? "CT"
        let bodyPart = decoder.info(for: 0x00180015)
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
