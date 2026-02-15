# Architecture

Learn about DicomCore's architectural design, components, and design decisions.

## Overview

DicomCore is built on a protocol-based architecture that prioritizes testability, maintainability, and performance. The library uses only Apple frameworks (Foundation, CoreGraphics, ImageIO, Accelerate, Metal) with zero external dependencies.

### Design Principles

- **Protocol-based architecture**: All services implement protocols for testability and dependency injection
- **Memory efficiency**: Files >10MB are memory-mapped automatically
- **Lazy loading**: Pixel data loaded on first access, not at file open
- **Performance**: Tag caching and optional Metal GPU acceleration
- **Type safety**: Swift-idiomatic throwing initializers and type-safe value types
- **Async/await**: All blocking operations have async variants (iOS 13+)

---

## Core Components

DicomCore is organized into several key components that work together to parse, process, and analyze DICOM files:

### DCMDecoder

**Location:** `DCMDecoder.swift`

The main DICOM parser that reads files, extracts metadata via tag IDs, and provides pixel buffers.

**Key Responsibilities:**
- Parse DICOM file headers (Little/Big Endian, Explicit/Implicit VR)
- Extract metadata using tag IDs
- Lazy-load pixel data on first access
- Handle 8-bit, 16-bit grayscale, and 24-bit RGB formats
- Decode JPEG Lossless (Process 14, Selection Value 1)
- Provide access to geometry data (Image Position/Orientation)

**Usage Example:**

```swift
// Modern API with throwing initializer
do {
    let decoder = try DCMDecoder(contentsOfFile: "/path/to/image.dcm")
    print("Dimensions: \(decoder.width) x \(decoder.height)")

    // Type-safe metadata access
    let patientName = decoder.info(for: .patientName)
    let modality = decoder.info(for: .modality)

    // Lazy pixel loading
    if let pixels = decoder.getPixels16() {
        print("Loaded \(pixels.count) pixels")
    }
} catch {
    print("Error: \(error)")
}
```

### DCMWindowingProcessor

**Location:** `DCMWindowingProcessor.swift`

Image processing utilities for window/level adjustments with CPU (vDSP) or GPU (Metal) backends.

**Key Responsibilities:**
- Apply window/level transformations to 16-bit grayscale data
- Provide 13 medical presets (CT Brain, Lung, Bone, etc.)
- Calculate optimal window/level values automatically
- Compute quality metrics (SNR, contrast, dynamic range)
- Support both CPU (vDSP) and GPU (Metal) processing backends

**Performance:**
- **vDSP (CPU):** Optimal for images <800×800 pixels (~2ms for 512×512)
- **Metal (GPU):** 3.94× speedup for 1024×1024 images (~2.20ms vs 8.67ms)
- **Auto mode:** Automatically selects best backend based on image size

**Usage Example:**

```swift
// Apply window/level with automatic backend selection
let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: 50.0,
    width: 400.0,
    processingMode: .auto  // Auto-selects Metal for large images
)

// Use medical presets
let lungSettings = DCMWindowingProcessor.getPresetValuesV2(preset: .lung)
let processedPixels = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: lungSettings.center,
    width: lungSettings.width
)
```

### MetalWindowingProcessor

**Location:** `MetalWindowingProcessor.swift`

GPU-accelerated windowing using Metal compute shaders for high-performance image processing.

**Key Responsibilities:**
- Implement window/level transformations on GPU
- Manage Metal pipeline state and command buffers
- Provide fallback to CPU when Metal is unavailable
- Optimize for large medical images (≥800×800 pixels)

**Performance Characteristics:**

| Image Size | vDSP (CPU) | Metal (GPU) | Speedup |
|------------|------------|-------------|---------|
| 512×512 | ~2ms | ~1.16ms | 1.84× |
| 1024×1024 | ~8.67ms | ~2.20ms | **3.94×** |
| 2048×2048 | ~35ms | ~8ms | 4.38× |

### DicomSeriesLoader

**Location:** `DicomSeriesLoader.swift`

Loads directories of DICOM slices, orders them by position, and assembles 3D volumes.

**Key Responsibilities:**
- Scan directories for `.dcm` files
- Order slices by Image Position (Patient) projection
- Validate geometry consistency across slices
- Assemble contiguous volume buffers
- Compute Z spacing from slice positions
- Provide progress callbacks during loading

**Usage Example:**

```swift
let loader = DicomSeriesLoader()
let volume = try await loader.loadSeries(
    fromDirectory: seriesURL,
    progressHandler: { current, total in
        print("Loading slice \(current)/\(total)")
    }
)

print("Volume: \(volume.width) × \(volume.height) × \(volume.depth)")
print("Spacing: \(volume.spacing.x) × \(volume.spacing.y) × \(volume.spacing.z) mm")
```

### StudyDataService

**Location:** `StudyDataService.swift`

Directory scanning and study/series grouping for PACS-like organization.

**Key Responsibilities:**
- Scan directories for DICOM files
- Group files by Patient → Study → Series hierarchy
- Extract study/series metadata
- Support dependency injection for testing

### PatientModel

**Location:** `PatientModel.swift`

Data structures representing the DICOM hierarchy (Patient → Study → Series → Image).

**Key Structures:**
- `Patient`: Top-level patient information
- `Study`: Study-level metadata (Study Instance UID, date, description)
- `Series`: Series-level metadata (Series Instance UID, modality, number)
- `ImageInfo`: Individual image metadata

### DCMDictionary

**Location:** `DCMDictionary.swift` + `Resources/DCMDictionary.plist`

Tag name/number mapping and DICOM standard tag definitions.

**Key Responsibilities:**
- Map tag numbers to human-readable names
- Provide tag lookup by number or name
- Load tag definitions from plist resource

### DICOMError

**Location:** `DICOMError.swift`

Typed error definitions for Swift-idiomatic error handling.

**Error Types:**
- `fileNotFound(String)`: File does not exist
- `invalidDICOMFormat(String, String)`: Invalid DICOM file with reason
- `unsupportedFormat(String)`: Unsupported compression or format
- `corruptedData(String)`: Data integrity issues

---

## Protocol Abstractions

DicomCore uses protocol-based abstractions for all major components, enabling dependency injection, testing, and flexibility.

### Protocol Overview

| Protocol | Implementation | Purpose |
|----------|----------------|---------|
| `DicomDecoderProtocol` | `DCMDecoder`, `MockDicomDecoder` | Abstracts DICOM file parsing and metadata extraction |
| `StudyDataServiceProtocol` | `StudyDataService` | Abstracts study/series metadata processing |
| `DicomDictionaryProtocol` | `DCMDictionary` | Abstracts DICOM tag lookups |
| `DicomSeriesLoaderProtocol` | `DicomSeriesLoader` | Abstracts series volume loading |
| `FileImportServiceProtocol` | `FileImportService` | Abstracts file import and ZIP extraction |

### Dependency Injection Pattern

Services use factory closures to create decoder instances, ensuring thread-safe concurrent file processing:

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

**Benefits:**
- **Testability**: Replace real implementations with mocks
- **Thread safety**: Each file gets a fresh decoder instance
- **Flexibility**: Swap implementations without changing client code
- **Maintainability**: Clear separation of concerns

---

## Data Flow

### Recommended Flow (Throwing Initializers)

Modern API using Swift-idiomatic error handling:

1. **Validation (optional):** `validateDICOMFile()` checks file validity
2. **Loading:** `try DCMDecoder(contentsOf: url)` or `try await DCMDecoder(contentsOf: url)`
3. **Metadata Access:** `info(for: .patientName)` using type-safe `DicomTag` enum
4. **Pixel Retrieval:** `getPixels16()` / `getPixels8()` (lazy-loaded)
5. **Image Processing:** `DCMWindowingProcessor.applyWindowLevel()` with CPU or GPU backend

**Example:**

```swift
do {
    // Step 2: Load file (parses header, metadata; pixel data lazy-loaded)
    let decoder = try DCMDecoder(contentsOf: url)

    // Step 3: Access metadata with type-safe tags
    let patientName = decoder.info(for: .patientName)
    let modality = decoder.info(for: .modality)

    // Step 4: Get pixel data (loaded on first access)
    guard let pixels16 = decoder.getPixels16() else {
        throw DICOMError.corruptedData("Failed to load pixel data")
    }

    // Step 5: Apply window/level for display
    let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
        pixels16: pixels16,
        center: 50.0,
        width: 400.0,
        processingMode: .auto
    )
} catch {
    print("Error: \(error)")
}
```

### Legacy Flow (Deprecated)

Older API using boolean success checks (maintained for backward compatibility):

1. `validateDICOMFile()` (optional)
2. `setDicomFilename()` or `loadDICOMFileAsync()`
3. Check `dicomFileReadSuccess` boolean
4. `info(for: tagId)` with raw hex values
5. `getPixels16()` / `getPixels8()`
6. `DCMWindowingProcessor.applyWindowLevel()`

---

## Key Design Decisions

### 1. Protocol-Based Architecture

**Decision:** All services implement protocols for dependency injection.

**Rationale:**
- Enables unit testing with mock implementations
- Allows flexible service composition
- Supports concurrent file processing without state leakage
- Improves maintainability through clear interfaces

### 2. Memory Mapping for Large Files

**Decision:** Files >10MB are automatically memory-mapped.

**Rationale:**
- Reduces memory footprint for large datasets
- Improves performance for sequential access patterns
- Leverages OS virtual memory management
- Transparent to API consumers

### 3. Lazy Pixel Loading

**Decision:** Pixel data is loaded on first access, not during file opening.

**Rationale:**
- Faster initial file loading for metadata extraction
- Reduces memory usage when only metadata is needed
- Enables efficient directory scanning
- Supports thumbnail generation without full pixel loading

### 4. Tag Caching

**Decision:** Frequently accessed tags are cached in memory.

**Rationale:**
- Reduces repeated file I/O for common tags
- Improves performance for metadata-heavy operations
- Minimal memory overhead (only accessed tags cached)
- Transparent to API consumers

### 5. Async/Await Support

**Decision:** All blocking operations have async variants (iOS 13+).

**Rationale:**
- Prevents UI blocking during file loading
- Enables concurrent file processing
- Modern Swift concurrency model
- Backward compatible with synchronous APIs

### 6. GPU Acceleration

**Decision:** Optional Metal backend for window/level operations with automatic fallback.

**Rationale:**
- 3.94× speedup for 1024×1024 images
- Automatic backend selection based on image size
- Graceful fallback to vDSP (CPU) when Metal unavailable
- Zero performance regression for small images

**Auto-Selection Threshold:**
- Images ≥800×800 pixels use Metal (if available)
- Smaller images use vDSP
- Transparent fallback if Metal unavailable

### 7. Swift-Idiomatic Error Handling

**Decision:** Throwing initializers replace boolean success checks (v1.1.0).

**Rationale:**
- Type-safe error handling with Swift's native error system
- Eliminates ambiguous boolean state checks
- Provides detailed error context (file path, failure reason)
- Follows Swift API design guidelines

**Migration Path:**
```swift
// Deprecated: Boolean success check
let decoder = DCMDecoder()
decoder.setDicomFilename(path)
guard decoder.dicomFileReadSuccess else { return }

// Recommended: Throwing initializer
do {
    let decoder = try DCMDecoder(contentsOfFile: path)
} catch DICOMError.fileNotFound(let path) {
    print("File not found: \(path)")
} catch {
    print("Error: \(error)")
}
```

### 8. Type-Safe Value Types

**Decision:** Dedicated structs for window settings, pixel spacing, and rescale parameters (v1.2.0).

**Rationale:**
- Better type safety than tuple-based APIs
- Codable conformance for serialization
- Sendable conformance for concurrency
- Improved discoverability and autocomplete
- Named properties instead of tuple labels

**Examples:**

```swift
// WindowSettings: Window center and width
let settings = decoder.windowSettingsV2
if settings.isValid {
    print("Window: center=\(settings.center), width=\(settings.width)")
}

// PixelSpacing: Physical spacing in millimeters
let spacing = decoder.pixelSpacingV2
if spacing.isValid {
    print("Spacing: \(spacing.x) × \(spacing.y) × \(spacing.z) mm")
}

// RescaleParameters: Slope and intercept for modality unit conversion
let rescale = decoder.rescaleParametersV2
if !rescale.isIdentity {
    let hounsfieldValue = rescale.apply(to: pixelValue)
}
```

---

## Component Relationships

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Application Layer                   │
│           (SwiftUI Views, ViewModels, etc.)             │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                    DicomCore Services                   │
│                                                         │
│  ┌─────────────────┐  ┌───────────────────────┐       │
│  │ StudyDataService│  │ DicomSeriesLoader     │       │
│  │  (Scanning)     │  │  (Volume Assembly)    │       │
│  └────────┬────────┘  └───────────┬───────────┘       │
│           │                        │                    │
│           ▼                        ▼                    │
│  ┌────────────────────────────────────────────┐       │
│  │           DCMDecoder                       │       │
│  │        (DICOM Parser)                      │       │
│  └────────────────┬───────────────────────────┘       │
│                   │                                    │
│                   ▼                                    │
│  ┌────────────────────────────────────────────┐       │
│  │      DCMWindowingProcessor                 │       │
│  │    (Image Processing)                      │       │
│  │                                            │       │
│  │  ┌──────────┐         ┌─────────────────┐ │       │
│  │  │  vDSP    │         │ Metal (GPU)     │ │       │
│  │  │  (CPU)   │         │                 │ │       │
│  │  └──────────┘         └─────────────────┘ │       │
│  └────────────────────────────────────────────┘       │
│                                                         │
│  ┌────────────────┐  ┌───────────────┐                │
│  │ DCMDictionary  │  │ PatientModel  │                │
│  │ (Tag Lookup)   │  │ (Data Model)  │                │
│  └────────────────┘  └───────────────┘                │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                  Apple Frameworks                       │
│  Foundation • CoreGraphics • ImageIO •                 │
│  Accelerate (vDSP) • Metal                             │
└─────────────────────────────────────────────────────────┘
```

### Data Flow Diagram

```
User Request
     │
     ▼
┌─────────────────┐
│ Validate File   │ (Optional)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Load File      │ DCMDecoder(contentsOf:)
│  Parse Header   │ - Read transfer syntax
│  Extract        │ - Parse data elements
│  Metadata       │ - Build tag cache
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Access Metadata │ info(for: .patientName)
│ (Tag Cache)     │ intValue(for: .rows)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Load Pixels    │ getPixels16() (lazy)
│  (On Demand)    │ - Decompress if needed
└────────┬────────┘ - Apply rescale slope/intercept
         │
         ▼
┌─────────────────┐
│ Apply Window/   │ DCMWindowingProcessor
│ Level           │ - Select backend (vDSP/Metal/Auto)
└────────┬────────┘ - Transform to 8-bit
         │
         ▼
┌─────────────────┐
│ Display Image   │ CGImage / SwiftUI Image
└─────────────────┘
```

---

## See Also

- <doc:GettingStarted>
- <doc:PerformanceOptimization>
- ``DCMDecoder``
- ``DCMWindowingProcessor``
- ``DicomSeriesLoader``
