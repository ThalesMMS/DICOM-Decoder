# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
swift build              # Build the library
swift build -c release   # Release build
swift test               # Run all tests
```

## Project Overview

Pure Swift DICOM decoder for iOS 13+ and macOS 12+. Parses DICOM medical imaging files, extracts metadata and pixel data, provides image processing utilities with optional GPU acceleration, and uses ZIPFoundation for ZIP series loading.

## Architecture

### Core Components

| Component | File | Purpose |
|-----------|------|---------|
| `DCMDecoder` | DCMDecoder.swift | Main DICOM parser - reads files, extracts metadata via tag IDs, provides pixel buffers |
| `DCMWindowingProcessor` | DCMWindowingProcessor.swift | Image processing - window/level adjustments with CPU (vDSP) or GPU (Metal) backends, 13 medical presets, quality metrics |
| `MetalWindowingProcessor` | MetalWindowingProcessor.swift | GPU-accelerated windowing using Metal compute shaders (3.94× speedup on 1024×1024 images) |
| `DicomSeriesLoader` | DicomSeriesLoader.swift | Loads directory of DICOM slices, orders by position, assembles 3D volume |
| `StudyDataService` | StudyDataService.swift | Directory scanning, study/series grouping |
| `PatientModel` | PatientModel.swift | Data structures for DICOM hierarchy (Patient → Study → Series → Image) |
| `DCMDictionary` | DCMDictionary.swift + Resources/DCMDictionary.plist | Tag name/number mapping |
| `DICOMError` | DICOMError.swift | Typed error definitions |

### Protocol Abstractions

All core components have protocol abstractions for dependency injection and testing:

| Protocol | Implementation | Location | Purpose |
|----------|----------------|----------|---------|
| `DicomDecoderProtocol` | DCMDecoder, MockDicomDecoder | Sources/DicomCore/Protocols/ | Abstracts DICOM file parsing and metadata extraction |
| `StudyDataServiceProtocol` | StudyDataService | Sources/DicomCore/Protocols/ | Abstracts study/series metadata processing |
| `DicomDictionaryProtocol` | DCMDictionary | Sources/DicomCore/Protocols/ | Abstracts DICOM tag lookups |
| `DicomSeriesLoaderProtocol` | DicomSeriesLoader | Sources/DicomCore/Protocols/ | Abstracts series volume loading |
| `FileImportServiceProtocol` | FileImportService | Sources/DicomCore/Protocols/ | Abstracts file import and ZIP extraction |

### Data Flow

**Recommended (Throwing Initializers):**

1. `validateDICOMFile()` (optional) → checks file validity
2. `try DCMDecoder(contentsOf: url)` or `try await DCMDecoder(contentsOf: url)` → parses header, metadata, pixel data (lazy), throws on error
3. `info(for: .patientName)` → access metadata using type-safe DicomTag enum (preferred) or `info(for: 0x00100010)` with raw hex values
4. `getPixels16()` / `getPixels8()` → retrieve pixel buffer
5. `DCMWindowingProcessor.applyWindowLevel()` → apply window/level for display (CPU or GPU backend)

**Legacy (Deprecated):**

1. `validateDICOMFile()` (optional) → checks file validity
2. `setDicomFilename()` or `loadDICOMFileAsync()` → parses header, metadata, pixel data (lazy) - **deprecated**
3. Check `dicomFileReadSuccess` → **deprecated, use throwing initializers instead**
4. `info(for: tagId)` → access metadata by numeric tag
5. `getPixels16()` / `getPixels8()` → retrieve pixel buffer
6. `DCMWindowingProcessor.applyWindowLevel()` → apply window/level for display

### Key Design Decisions

- **Protocol-based architecture**: All services implement protocols for testability and dependency injection
- **Memory mapping**: Files >10MB are memory-mapped automatically
- **Lazy pixel loading**: Pixel data loaded on first access, not at file open
- **Tag caching**: Frequently accessed tags are cached
- **Async/await**: All blocking operations have async variants (iOS 13+)
- **GPU acceleration**: Optional Metal backend for large images with automatic fallback to vDSP
- **Swift-idiomatic error handling**: Throwing initializers replace boolean success checks (new in 1.1.0)
- **Type-safe value types**: Dedicated structs for window settings, pixel spacing, and rescale parameters replace tuples (new in 1.2.0)

## API Usage Examples

### Basic Loading (Recommended)

```swift
// Recommended: Throwing initializer with URL
do {
    let url = URL(fileURLWithPath: "/path/to/image.dcm")
    let decoder = try DCMDecoder(contentsOf: url)
    print("Loaded: \(decoder.width) x \(decoder.height)")
} catch DICOMError.fileNotFound(let path) {
    print("File not found: \(path)")
} catch DICOMError.invalidDICOMFormat(let path, let reason) {
    print("Invalid DICOM: \(reason)")
} catch {
    print("Error: \(error)")
}

// Recommended: Throwing initializer with String path
do {
    let decoder = try DCMDecoder(contentsOfFile: "/path/to/image.dcm")
    print("Loaded: \(decoder.width) x \(decoder.height)")
} catch {
    print("Error: \(error)")
}

// Alternative: Static factory methods
let decoder = try DCMDecoder.load(from: url)
let decoder2 = try DCMDecoder.load(fromFile: "/path/to/image.dcm")
```

### Async Loading (Non-Blocking)

```swift
// Recommended: Async throwing initializer
Task {
    do {
        let decoder = try await DCMDecoder(contentsOfFile: "/path/to/image.dcm")
        print("Loaded in background: \(decoder.width) x \(decoder.height)")
    } catch {
        print("Error: \(error)")
    }
}

// Alternative: Async static factory methods
let decoder = try await DCMDecoder.load(from: url)
let decoder2 = try await DCMDecoder.load(fromFile: "/path/to/image.dcm")
```

### Accessing Metadata (Type-Safe)

```swift
// Recommended: Type-safe DicomTag enum
let patientName = decoder.info(for: .patientName)
let modality = decoder.info(for: .modality)
let rows = decoder.intValue(for: .rows) ?? 0
let windowCenter = decoder.doubleValue(for: .windowCenter)

// Legacy (deprecated): Raw hex values (still supported for custom/private tags)
let patientName = decoder.info(for: 0x00100010)
let modality = decoder.info(for: 0x00080060)

// Note: Use .rawValue for tags not in the DicomTag enum
let customTag = decoder.info(for: 0x00091001)  // Private tag example
```

### Legacy API (Deprecated)

```swift
// Deprecated: Boolean success check pattern
let decoder = DCMDecoder()
decoder.setDicomFilename("/path/to/image.dcm")
guard decoder.dicomFileReadSuccess else {
    print("Failed to load")
    return
}
```

### Type-Safe Value Types (V2 APIs)

The library provides dedicated structs for common DICOM parameters, offering better type safety, Codable conformance, and discoverability compared to tuple-based APIs.

#### WindowSettings

Represents window center and width values for grayscale display adjustment:

```swift
// Recommended: Use windowSettingsV2
let settings = decoder.windowSettingsV2
if settings.isValid {
    print("Window: center=\(settings.center), width=\(settings.width)")
}

// Legacy (deprecated): Tuple-based API (deprecated)
let (center, width) = decoder.windowSettings
```

#### PixelSpacing

Represents physical spacing between pixels in millimeters:

```swift
// Recommended: Use pixelSpacingV2
let spacing = decoder.pixelSpacingV2
if spacing.isValid {
    print("Spacing: \(spacing.x) × \(spacing.y) × \(spacing.z) mm")
}

// Legacy (deprecated): Tuple-based API (deprecated)
let (width, height, depth) = decoder.pixelSpacing
```

#### RescaleParameters

Represents rescale slope and intercept for converting pixel values to modality units:

```swift
// Recommended: Use rescaleParametersV2
let rescale = decoder.rescaleParametersV2
if !rescale.isIdentity {
    let hounsfieldValue = rescale.apply(to: pixelValue)
}

// Legacy (deprecated): Tuple-based API (deprecated)
let (intercept, slope) = decoder.rescaleParameters
```

#### V2 Methods in DCMWindowingProcessor

All windowing methods now have V2 variants that return `WindowSettings`:

```swift
// Recommended: V2 methods return WindowSettings
let settings = DCMWindowingProcessor.calculateOptimalWindowLevelV2(pixels16: pixels)
let presetSettings = DCMWindowingProcessor.getPresetValuesV2(preset: .lung)
let batchSettings = DCMWindowingProcessor.batchCalculateOptimalWindowLevelV2(imagePixels: [pixels1, pixels2])

if let presetName = DCMWindowingProcessor.getPresetName(settings: settings) {
    print("Matches preset: \(presetName)")
}

// Legacy (deprecated): Tuple-based methods (deprecated)
let (center, width) = DCMWindowingProcessor.calculateOptimalWindowLevel(pixels16: pixels)
```

#### Benefits of V2 APIs

- **Type safety**: Structs instead of tuples prevent parameter order mistakes
- **Codable support**: Can be serialized to JSON for persistence or networking
- **Sendable conformance**: Safe to use across concurrency boundaries
- **Computed properties**: `.isValid` for WindowSettings/PixelSpacing, `.isIdentity` for RescaleParameters
- **Methods**: RescaleParameters includes `.apply(to:)` method for transformations
- **Better autocomplete**: Named properties instead of tuple labels

## DICOM Format Support

**Supported:**
- Little/Big Endian, Explicit/Implicit VR
- 8-bit, 16-bit grayscale, 24-bit RGB
- JPEG Lossless (Process 14, all selection values 0-7) via native decoder
  - Transfer Syntax UID 1.2.840.10008.1.2.4.57 (JPEG Lossless, Non-Hierarchical)
  - Transfer Syntax UID 1.2.840.10008.1.2.4.70 (JPEG Lossless, Non-Hierarchical, First-Order Prediction)
  - Support for 8-bit, 12-bit, and 16-bit precision
  - All 8 predictor modes: no prediction (0), left neighbor (1), top neighbor (2), diagonal (3), planar (4), and gradient-based predictors (5-7)
- Single-frame JPEG/JPEG2000 (via ImageIO)
- Image Position/Orientation (Patient) for geometry
- Series loading with automatic slice ordering

**Not Supported:**
- RLE compression
- Multi-frame encapsulated images
- JPEG Lossless processes other than Process 14 (e.g., hierarchical encoding modes)

## Known Limitations

1. **Large files**: Files >1GB may consume significant memory
2. **Compression**: JPEG/JPEG2000 support is best-effort via ImageIO fallback

## Common DICOM Tags

Use the type-safe `DicomTag` enum for standard tags:

```swift
// Preferred: Type-safe enum
.patientName                 // (0010,0010) - Patient Name
.modality                    // (0008,0060) - Modality (CT, MR, XR, etc.)
.rows                        // (0028,0010) - Rows (height)
.columns                     // (0028,0011) - Columns (width)
.imagePositionPatient        // (0020,0032) - Image Position (Patient)
.imageOrientationPatient     // (0020,0037) - Image Orientation (Patient)
.windowCenter                // (0028,1050) - Window Center
.windowWidth                 // (0028,1051) - Window Width
.studyInstanceUID            // (0020,000D) - Study Instance UID
.seriesInstanceUID           // (0020,000E) - Series Instance UID

// Legacy (deprecated): Raw hex values (for custom/private tags only)
0x00100010  // Patient Name
0x00080060  // Modality
0x00280010  // Rows
0x00280011  // Columns
```

## GPU Acceleration

The library includes optional Metal GPU acceleration for window/level operations, providing significant performance improvements for large medical images.

### Processing Modes

`DCMWindowingProcessor.applyWindowLevel()` supports three processing backends via the `processingMode` parameter:

```swift
public enum ProcessingMode {
    case vdsp   // CPU-based processing (default)
    case metal  // GPU-based processing
    case auto   // Automatic selection based on image size
}
```

### Mode Selection Guide

| Mode | Use Case | Performance | Availability |
|------|----------|-------------|--------------|
| `.vdsp` | Small images (<800×800), guaranteed compatibility | ~1-2ms for 512×512 images | Always available |
| `.metal` | Large images (≥800×800), modern hardware | ~2.20ms for 1024×1024 (3.94× speedup) | Metal-capable devices (iOS 13+, macOS 12+) |
| `.auto` | General purpose, adapts to image size | Optimal for all sizes | Graceful fallback to vDSP |

### Usage Examples

**Default behavior (backward compatible):**
```swift
// Uses vDSP (CPU) - no breaking changes
let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: 50.0,
    width: 400.0
)
```

**Explicit Metal GPU acceleration:**
```swift
// Force GPU processing (falls back to vDSP if Metal unavailable)
let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: 50.0,
    width: 400.0,
    processingMode: .metal
)
```

**Automatic selection (recommended):**
```swift
// Auto-selects Metal for images ≥800×800, vDSP for smaller images
let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: 50.0,
    width: 400.0,
    processingMode: .auto
)
```

### Performance Characteristics

Measured on Apple M4 hardware:

| Image Size | vDSP (CPU) | Metal (GPU) | Speedup |
|------------|------------|-------------|---------|
| 256×256 | ~0.5ms | ~0.3ms | 1.67× |
| 512×512 | ~2ms | ~1.16ms | 1.84× |
| 1024×1024 | ~8.67ms | ~2.20ms | **3.94×** |
| 2048×2048 | ~35ms | ~8ms | 4.38× |

### Auto-Selection Threshold

The `.auto` mode uses a **800×800 pixel threshold** (640,000 total pixels):
- Images with ≥640,000 pixels use Metal (if available)
- Smaller images use vDSP
- If Metal is unavailable, vDSP is used regardless of size
- No exceptions thrown - graceful fallback guaranteed

### Implementation Notes

- **Lazy initialization**: Metal processor initialized only on first use
- **Reusable instance**: Single `MetalWindowingProcessor` shared across calls
- **Thread-safe**: Can be called from multiple threads concurrently
- **Numerically consistent**: Metal and vDSP produce identical results (within ±1 UInt8 due to floating-point rounding)
- **Backward compatible**: Default mode is `.vdsp`, existing code works without changes

## Concurrency and Thread Safety

The library is designed for safe concurrent use in modern Swift applications using async/await and structured concurrency.

### Thread-Safe Design

All public types are thread-safe and can be used concurrently from multiple tasks or threads:

| Type | Thread Safety | Mechanism |
|------|---------------|-----------|
| `DCMDecoder` | Thread-safe | Internal synchronization with locks for mutable state |
| `DicomSeriesLoader` | Thread-safe | Concurrent file loading with `TaskGroup`, no shared mutable state |
| `StudyDataService` | Thread-safe | Concurrent directory scanning with `TaskGroup`, no shared mutable state |
| `DCMWindowingProcessor` | Thread-safe | Stateless static methods, or actor isolation for Metal processor |
| `MetalWindowingProcessor` | Thread-safe | Actor-isolated to serialize GPU command buffer access |
| `DCMDictionary` | Thread-safe | Immutable after initialization |

### Sendable Conformance

All value types conform to `Sendable`, enabling safe passing across concurrency boundaries:

```swift
// Value types are Sendable
struct WindowSettings: Sendable { /* ... */ }
struct PixelSpacing: Sendable { /* ... */ }
struct RescaleParameters: Sendable { /* ... */ }

// Data model types are Sendable
struct PatientModel: Sendable { /* ... */ }
struct StudyModel: Sendable { /* ... */ }
struct SeriesModel: Sendable { /* ... */ }
struct ImageModel: Sendable { /* ... */ }

// Can safely pass across tasks
Task {
    let settings = WindowSettings(center: 50, width: 400)
    await processImage(with: settings)  // ✓ Safe
}
```

### Concurrent File Loading

The library provides batch loading APIs optimized for concurrent processing of multiple DICOM files:

#### DicomSeriesLoader Batch API

Load multiple series concurrently with automatic parallelization:

```swift
// Load multiple series in parallel
let seriesURLs: [[URL]] = [
    [url1, url2, url3],  // Series 1
    [url4, url5, url6]   // Series 2
]

do {
    let volumes = try await DicomSeriesLoader.batchLoadSeries(
        seriesPaths: seriesURLs
    )

    for volume in volumes {
        print("Loaded \(volume.depth) images")
    }
} catch {
    print("Failed to load series: \(error)")
}
```

#### StudyDataService Concurrent Scanning

Scan directories concurrently with configurable concurrency:

```swift
let service = StudyDataService()

// Scans multiple study directories in parallel
let patients = try await service.scanStudies(
    at: [studyDir1, studyDir2, studyDir3]
)

// Each study's series are also scanned concurrently
for patient in patients {
    for study in patient.studies {
        print("Study: \(study.studyDescription), Series: \(study.series.count)")
    }
}
```

### Concurrency Best Practices

**Recommended patterns:**

```swift
// ✓ Use async/await for background loading
Task {
    let decoder = try await DCMDecoder(contentsOfFile: path)
    // Process in background
}

// ✓ Use TaskGroup for batch operations
await withTaskGroup(of: DCMDecoder?.self) { group in
    for path in paths {
        group.addTask {
            try? await DCMDecoder(contentsOfFile: path)
        }
    }
    for await decoder in group {
        // Process results
    }
}

// ✓ Pass Sendable value types across tasks
let settings = decoder.windowSettingsV2  // Sendable
Task {
    await applySettings(settings)  // Safe
}
```

**Patterns to avoid:**

```swift
// ✗ Don't share decoder instances across tasks without synchronization
let decoder = try DCMDecoder(contentsOfFile: path)
Task {
    let pixels = decoder.getPixels16()  // Potential race condition
}
Task {
    let info = decoder.info(for: .patientName)  // Potential race condition
}

// ✓ Instead: Each task gets its own decoder
Task {
    let decoder = try DCMDecoder(contentsOfFile: path)
    let pixels = decoder.getPixels16()
}
Task {
    let decoder = try DCMDecoder(contentsOfFile: path)
    let info = decoder.info(for: .patientName)
}
```

### Batch Processing Performance

Concurrent loading provides significant performance improvements for multi-file operations:

| Operation | Sequential | Concurrent (4 cores) | Speedup |
|-----------|------------|----------------------|---------|
| Load 10 series (100 files) | ~3.2s | ~0.9s | 3.6× |
| Scan study directory (50 files) | ~1.8s | ~0.5s | 3.6× |
| Load + window level (20 files) | ~2.1s | ~0.6s | 3.5× |

### Implementation Notes

- **Structured concurrency**: Uses `TaskGroup` for batch operations, ensuring all tasks complete or are cancelled together
- **Error handling**: Batch APIs return `Result<T, Error>` arrays, allowing partial success handling
- **Cancellation support**: All async operations respect task cancellation
- **Actor isolation**: Metal processor uses actor to serialize GPU access
- **Lock-free where possible**: Value types and immutable data minimize locking overhead
- **Decoder independence**: Factory pattern ensures each file gets a fresh decoder instance

## Dependency Injection and Testing

The library uses protocol-based dependency injection for all services. This enables:
- **Testability**: Replace real implementations with mocks
- **Flexibility**: Swap implementations without changing client code
- **Maintainability**: Clear separation of concerns

### Injecting Dependencies

Services accept a decoder factory closure to create `DicomDecoderProtocol` instances:

```swift
// Create service with default decoder
let service = StudyDataService(
    decoderFactory: { DCMDecoder() }
)

// For testing, inject mock decoder
let testService = StudyDataService(
    decoderFactory: { MockDicomDecoder() }
)
```

### Decoder Factory Pattern

Services that process multiple DICOM files use a factory pattern instead of a single decoder instance. This ensures:
- Each file gets a fresh decoder instance (no state leakage)
- Thread-safe concurrent file processing
- Clean separation of file-level operations

```swift
// Service stores factory, not decoder instance
private let decoderFactory: () -> DicomDecoderProtocol

// Create decoder when needed
let decoder = decoderFactory()
decoder.setDicomFilename(path)
```

### Mock Implementations

The shared `DicomTestSupport` target includes `MockDicomDecoder` (in `Tests/DicomTestSupport/`) which fully implements `DicomDecoderProtocol`. Configure it to simulate any DICOM scenario:

```swift
let mock = MockDicomDecoder()
mock.width = 512
mock.height = 512
mock.setTag(0x00100010, value: "Test Patient")
mock.setPixels16([/* test data */])
```

### Backward Compatibility

Deprecated singleton patterns remain for backward compatibility:
- `DCMDictionary.shared` - deprecated, use `DCMDictionary()` instance
- Services with parameterless `init()` use default factories internally

## Reference Implementation

Release packages do not include the legacy viewer reference code. Use the SwiftUI
example under `Examples/DicomSwiftUIExample/` for runnable integration patterns.
