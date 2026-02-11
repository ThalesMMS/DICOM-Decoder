# Migration Guide

Upgrade your code to use the latest DicomCore APIs with improved type safety, error handling, and Swift idioms.

## Overview

DicomCore has evolved to provide more Swift-idiomatic APIs while maintaining backward compatibility. This guide helps you migrate from deprecated patterns to modern, recommended approaches.

**What's New:**
- **Throwing initializers** (v1.1.0+) - Swift-idiomatic error handling
- **Type-safe DicomTag enum** (v1.2.0+) - Semantic tag names replace hex values
- **Type-safe value types** (v1.2.0+) - Structs replace tuples for better type safety
- **V2 windowing methods** (v1.2.0+) - Return WindowSettings instead of tuples

All deprecated APIs remain functional for backward compatibility, but new code should use the recommended patterns.

---

## Migration Path 1: Throwing Initializers

**Status:** Recommended since v1.1.0
**Replaces:** `setDicomFilename()` + `dicomFileReadSuccess` pattern

### Old Pattern (Deprecated)

```swift
// ❌ Old: Boolean success check pattern
let decoder = DCMDecoder()
decoder.setDicomFilename("/path/to/image.dcm")

guard decoder.dicomFileReadSuccess else {
    print("Failed to load DICOM file")
    return
}

print("Dimensions: \(decoder.width) x \(decoder.height)")
```

**Problems with old pattern:**
- No information about *why* the load failed
- Easy to forget the success check (no compiler enforcement)
- Decoder exists in invalid state if load fails
- Not idiomatic Swift error handling

### New Pattern (Recommended)

```swift
// ✅ New: Throwing initializer with String path
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

**Alternative: URL-based initializer**

```swift
// ✅ Alternative: Throwing initializer with URL
do {
    let url = URL(fileURLWithPath: "/path/to/image.dcm")
    let decoder = try DCMDecoder(contentsOf: url)
    print("Loaded: \(decoder.width) x \(decoder.height)")
} catch {
    print("Error: \(error)")
}
```

**Alternative: Static factory methods**

```swift
// ✅ Alternative: Static factory methods
do {
    let url = URL(fileURLWithPath: "/path/to/image.dcm")
    let decoder = try DCMDecoder.load(from: url)
    // Or: let decoder = try DCMDecoder.load(fromFile: "/path/to/image.dcm")

    print("Successfully loaded: \(decoder.width) x \(decoder.height)")
} catch {
    print("Failed to load: \(error)")
}
```

### Migration Benefits

1. **Type-safe error handling** - Catch specific `DICOMError` cases instead of boolean flags
2. **Compiler-enforced** - Swift requires `try` or `try?`, preventing forgotten error checks
3. **Immediate validity** - If initialization succeeds, decoder is guaranteed valid
4. **Clearer intent** - Throwing initializers signal fallible operations at the API level
5. **Better async support** - Seamless integration with Swift Concurrency

### Async Migration

The old async API also has a modern replacement:

```swift
// ❌ Old: Async with completion handler
let decoder = DCMDecoder()
decoder.loadDICOMFileAsync(path: "/path/to/image.dcm") {
    guard decoder.dicomFileReadSuccess else {
        print("Failed to load")
        return
    }
    print("Loaded: \(decoder.width) x \(decoder.height)")
}

// ✅ New: Async throwing initializer
Task {
    do {
        let decoder = try await DCMDecoder(contentsOfFile: "/path/to/image.dcm")
        print("Loaded: \(decoder.width) x \(decoder.height)")
    } catch {
        print("Error: \(error)")
    }
}

// ✅ Alternative: Async static factory methods
Task {
    do {
        let url = URL(fileURLWithPath: "/path/to/image.dcm")
        let decoder = try await DCMDecoder.load(from: url)
        // Or: let decoder = try await DCMDecoder.load(fromFile: "/path/to/image.dcm")

        print("Loaded in background: \(decoder.width) x \(decoder.height)")
    } catch {
        print("Failed: \(error)")
    }
}
```

---

## Migration Path 2: Type-Safe DicomTag Enum

**Status:** Recommended since v1.2.0
**Replaces:** Raw hex tag values (e.g., `0x00100010`)

### Old Pattern (Discouraged)

```swift
// ❌ Old: Magic hex numbers
let patientName = decoder.info(for: 0x00100010)
let modality = decoder.info(for: 0x00080060)
let rows = decoder.intValue(for: 0x00280010)
let columns = decoder.intValue(for: 0x00280011)
let windowCenter = decoder.doubleValue(for: 0x00281050)
let windowWidth = decoder.doubleValue(for: 0x00281051)
```

**Problems with old pattern:**
- No IDE autocomplete or discoverability
- Easy to make typos in hex values
- Requires referencing DICOM standard for tag numbers
- Not self-documenting code
- No compiler validation

### New Pattern (Recommended)

```swift
// ✅ New: Semantic, type-safe tag names
let patientName = decoder.info(for: .patientName)
let modality = decoder.info(for: .modality)
let rows = decoder.intValue(for: .rows)
let columns = decoder.intValue(for: .columns)
let windowCenter = decoder.doubleValue(for: .windowCenter)
let windowWidth = decoder.doubleValue(for: .windowWidth)
```

### Migration Benefits

1. **Type safety** - Compiler-checked tag names prevent typos
2. **Discoverability** - IDE autocomplete shows all available tags
3. **Readability** - Self-documenting code
4. **No magic numbers** - Semantic names are clearer than hex values
5. **Backward compatible** - Raw hex still works for custom/private tags

### Common Tag Migrations

**Patient Information:**
```swift
// ❌ Old
decoder.info(for: 0x00100010)  // Patient Name
decoder.info(for: 0x00100020)  // Patient ID
decoder.info(for: 0x00100030)  // Birth Date
decoder.info(for: 0x00100040)  // Sex

// ✅ New
decoder.info(for: .patientName)
decoder.info(for: .patientID)
decoder.info(for: .patientBirthDate)
decoder.info(for: .patientSex)
```

**Study/Series:**
```swift
// ❌ Old
decoder.info(for: 0x0020000D)  // Study Instance UID
decoder.info(for: 0x0020000E)  // Series Instance UID
decoder.info(for: 0x00080060)  // Modality
decoder.info(for: 0x00081030)  // Study Description

// ✅ New
decoder.info(for: .studyInstanceUID)
decoder.info(for: .seriesInstanceUID)
decoder.info(for: .modality)
decoder.info(for: .studyDescription)
```

**Image Geometry:**
```swift
// ❌ Old
decoder.intValue(for: 0x00280010)      // Rows
decoder.intValue(for: 0x00280011)      // Columns
decoder.info(for: 0x00280030)          // Pixel Spacing
decoder.doubleValue(for: 0x00180050)   // Slice Thickness

// ✅ New
decoder.intValue(for: .rows)
decoder.intValue(for: .columns)
decoder.info(for: .pixelSpacing)
decoder.doubleValue(for: .sliceThickness)
```

**Window/Level:**
```swift
// ❌ Old
decoder.doubleValue(for: 0x00281050)  // Window Center
decoder.doubleValue(for: 0x00281051)  // Window Width
decoder.doubleValue(for: 0x00281053)  // Rescale Slope
decoder.doubleValue(for: 0x00281052)  // Rescale Intercept

// ✅ New
decoder.doubleValue(for: .windowCenter)
decoder.doubleValue(for: .windowWidth)
decoder.doubleValue(for: .rescaleSlope)
decoder.doubleValue(for: .rescaleIntercept)
```

### Custom and Private Tags

For custom or manufacturer-specific tags not in the standard, continue using hex values:

```swift
// ⚠️ Use hex for custom/private tags only
let manufacturerTag = decoder.info(for: 0x00091001)  // Private tag
let customData = decoder.info(for: 0x00111234)       // Custom tag

// Standard tags should use the enum
let patientName = decoder.info(for: .patientName)    // ✅ Preferred
// Not: decoder.info(for: 0x00100010)                // ❌ Discouraged
```

---

## Migration Path 3: Type-Safe Value Types (V2 APIs)

**Status:** Recommended since v1.2.0
**Replaces:** Tuple-based APIs

### Overview

V2 APIs introduce dedicated structs (`WindowSettings`, `PixelSpacing`, `RescaleParameters`) that replace tuple return values, providing better type safety, Codable conformance, and validation.

### WindowSettings Migration

**Old Pattern:**
```swift
// ❌ Old: Tuple-based API
let (center, width) = decoder.windowSettings

if center != 0.0 && width != 0.0 {
    print("Window: C=\(center) W=\(width)")
}

// Easy to accidentally swap parameters
applyWindow(width, center)  // Bug! Wrong order
```

**New Pattern:**
```swift
// ✅ New: WindowSettings struct
let settings = decoder.windowSettingsV2

if settings.isValid {
    print("Window: C=\(settings.center) W=\(settings.width)")
}

// Impossible to swap parameters
applyWindow(settings)

// Serialize to JSON
let jsonData = try JSONEncoder().encode(settings)
// Output: {"center":50.0,"width":400.0}
```

**Migration benefits:**
- No parameter order mistakes
- Built-in `.isValid` validation
- Codable support for JSON serialization
- Named properties instead of tuple indices

### PixelSpacing Migration

**Old Pattern:**
```swift
// ❌ Old: Tuple-based API
let (width, height, depth) = decoder.pixelSpacing

if width != 0.0 && height != 0.0 {
    print("Spacing: \(width) × \(height) × \(depth) mm")
}
```

**New Pattern:**
```swift
// ✅ New: PixelSpacing struct
let spacing = decoder.pixelSpacingV2

if spacing.isValid {
    print("Spacing: \(spacing.x) × \(spacing.y) × \(spacing.z) mm")

    // Calculate physical dimensions
    let physicalWidth = Double(decoder.width) * spacing.x
    let physicalHeight = Double(decoder.height) * spacing.y
    print("Physical size: \(physicalWidth) × \(physicalHeight) mm")
}
```

**Migration benefits:**
- Semantic names (`.x`, `.y`, `.z`) instead of generic tuple labels
- Built-in `.isValid` validation
- Codable for persistence

### RescaleParameters Migration

**Old Pattern:**
```swift
// ❌ Old: Tuple-based API
let (intercept, slope) = decoder.rescaleParameters

if slope != 1.0 || intercept != 0.0 {
    let hounsfieldValue = slope * Double(pixelValue) + intercept
    print("HU: \(hounsfieldValue)")
}
```

**New Pattern:**
```swift
// ✅ New: RescaleParameters struct
let rescale = decoder.rescaleParametersV2

if !rescale.isIdentity {
    // Use built-in apply() method
    let hounsfieldValue = rescale.apply(to: Double(pixelValue))
    print("HU: \(hounsfieldValue)")

    // Transform array of pixels
    if let pixels = decoder.getPixels16() {
        let huValues = pixels.map { rescale.apply(to: Double($0)) }
    }
}
```

**Migration benefits:**
- Built-in `.apply(to:)` method encapsulates transformation logic
- `.isIdentity` property for checking if transformation is needed
- Clearer semantics than raw slope/intercept values

---

## Migration Path 4: Windowing Processor V2 Methods

**Status:** Recommended since v1.2.0
**Replaces:** Tuple-based windowing methods

### Calculate Optimal Window/Level

**Old Pattern:**
```swift
// ❌ Old: Returns tuple
let (center, width) = DCMWindowingProcessor.calculateOptimalWindowLevel(pixels16: pixels)

let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels,
    center: center,
    width: width
)
```

**New Pattern:**
```swift
// ✅ New: Returns WindowSettings struct
let optimal = DCMWindowingProcessor.calculateOptimalWindowLevelV2(pixels16: pixels)

if optimal.isValid {
    let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
        pixels16: pixels,
        center: optimal.center,
        width: optimal.width
    )

    // Serialize optimal settings
    let jsonData = try JSONEncoder().encode(optimal)
}
```

### Medical Presets

**Old Pattern:**
```swift
// ❌ Old: Returns tuple
let (center, width) = DCMWindowingProcessor.getPresetValues(preset: .lung)

let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels,
    center: center,
    width: width
)
```

**New Pattern:**
```swift
// ✅ New: Returns WindowSettings struct
let lungSettings = DCMWindowingProcessor.getPresetValuesV2(preset: .lung)

let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels,
    center: lungSettings.center,
    width: lungSettings.width
)

// Detect which preset matches current settings
if let presetName = DCMWindowingProcessor.getPresetName(settings: lungSettings) {
    print("Using preset: \(presetName)")  // Output: "Lung"
}
```

### Batch Processing

**Old Pattern:**
```swift
// ❌ Old: Returns array of tuples
let results = DCMWindowingProcessor.batchCalculateOptimalWindowLevel(
    imagePixels: [pixels1, pixels2, pixels3]
)

for (center, width) in results {
    print("Window: C=\(center) W=\(width)")
}
```

**New Pattern:**
```swift
// ✅ New: Returns array of WindowSettings
let results = DCMWindowingProcessor.batchCalculateOptimalWindowLevelV2(
    imagePixels: [pixels1, pixels2, pixels3]
)

for settings in results {
    if settings.isValid {
        print("Window: C=\(settings.center) W=\(settings.width)")
    }
}

// Serialize all results to JSON
let jsonData = try JSONEncoder().encode(results)
```

---

## Complete Migration Example

Here's a comprehensive before/after example showing all migration paths:

### Before (All Deprecated APIs)

```swift
// ❌ Old pattern - all deprecated APIs
let decoder = DCMDecoder()
decoder.setDicomFilename("/path/to/ct_scan.dcm")

guard decoder.dicomFileReadSuccess else {
    print("Failed to load")
    return
}

// Magic hex numbers
let patientName = decoder.info(for: 0x00100010)
let modality = decoder.info(for: 0x00080060)
let rows = decoder.intValue(for: 0x00280010) ?? 0
let cols = decoder.intValue(for: 0x00280011) ?? 0

print("Patient: \(patientName), \(cols)×\(rows) \(modality)")

// Tuple-based value access
let (center, width) = decoder.windowSettings
let (spacingX, spacingY, spacingZ) = decoder.pixelSpacing
let (intercept, slope) = decoder.rescaleParameters

// Tuple-based windowing
guard let pixels = decoder.getPixels16() else { return }
let (optimalCenter, optimalWidth) = DCMWindowingProcessor.calculateOptimalWindowLevel(
    pixels16: pixels
)

let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels,
    center: optimalCenter,
    width: optimalWidth
)
```

### After (All Recommended APIs)

```swift
// ✅ New pattern - all recommended APIs
do {
    // Throwing initializer
    let decoder = try DCMDecoder(contentsOfFile: "/path/to/ct_scan.dcm")

    // Type-safe DicomTag enum
    let patientName = decoder.info(for: .patientName)
    let modality = decoder.info(for: .modality)
    let rows = decoder.intValue(for: .rows) ?? 0
    let cols = decoder.intValue(for: .columns) ?? 0

    print("Patient: \(patientName), \(cols)×\(rows) \(modality)")

    // Type-safe value structs
    let windowSettings = decoder.windowSettingsV2
    let spacing = decoder.pixelSpacingV2
    let rescale = decoder.rescaleParametersV2

    if windowSettings.isValid {
        print("Window: C=\(windowSettings.center) W=\(windowSettings.width)")
    }

    if spacing.isValid {
        print("Spacing: \(spacing.x)×\(spacing.y)×\(spacing.z) mm")
    }

    // V2 windowing methods
    guard let pixels = decoder.getPixels16() else { return }
    let optimal = DCMWindowingProcessor.calculateOptimalWindowLevelV2(pixels16: pixels)

    if optimal.isValid {
        let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
            pixels16: pixels,
            center: optimal.center,
            width: optimal.width
        )

        // Serialize settings to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(optimal)
        print("Optimal settings: \(String(data: jsonData, encoding: .utf8)!)")
    }

} catch DICOMError.fileNotFound(let path) {
    print("File not found: \(path)")
} catch DICOMError.invalidDICOMFormat(let path, let reason) {
    print("Invalid DICOM at \(path): \(reason)")
} catch {
    print("Unexpected error: \(error)")
}
```

---

## Quick Reference

### API Replacement Table

| Deprecated API | Recommended API | Version |
|----------------|-----------------|---------|
| `DCMDecoder()` + `setDicomFilename()` | `try DCMDecoder(contentsOfFile:)` | 1.1.0+ |
| `DCMDecoder()` + `setDicomFilename()` | `try DCMDecoder(contentsOf:)` | 1.1.0+ |
| `loadDICOMFileAsync()` | `try await DCMDecoder(contentsOfFile:)` | 1.1.0+ |
| `dicomFileReadSuccess` | Use `do-catch` with throwing initializers | 1.1.0+ |
| `info(for: 0x00100010)` | `info(for: .patientName)` | 1.2.0+ |
| `intValue(for: 0x00280010)` | `intValue(for: .rows)` | 1.2.0+ |
| `windowSettings` (tuple) | `windowSettingsV2` (struct) | 1.2.0+ |
| `pixelSpacing` (tuple) | `pixelSpacingV2` (struct) | 1.2.0+ |
| `rescaleParameters` (tuple) | `rescaleParametersV2` (struct) | 1.2.0+ |
| `calculateOptimalWindowLevel()` | `calculateOptimalWindowLevelV2()` | 1.2.0+ |
| `getPresetValues()` | `getPresetValuesV2()` | 1.2.0+ |
| `batchCalculateOptimalWindowLevel()` | `batchCalculateOptimalWindowLevelV2()` | 1.2.0+ |

### Migration Checklist

- [ ] Replace `setDicomFilename()` with throwing initializers
- [ ] Replace `dicomFileReadSuccess` checks with `do-catch`
- [ ] Replace `loadDICOMFileAsync()` with async throwing initializers
- [ ] Replace hex tag values with `DicomTag` enum cases
- [ ] Replace `windowSettings` with `windowSettingsV2`
- [ ] Replace `pixelSpacing` with `pixelSpacingV2`
- [ ] Replace `rescaleParameters` with `rescaleParametersV2`
- [ ] Replace windowing methods with V2 variants
- [ ] Update error handling to catch specific `DICOMError` cases
- [ ] Test thoroughly - all APIs are backward compatible

### Need Help?

- See <doc:GettingStarted> for basic usage examples
- See <doc:Architecture> for protocol-based dependency injection
- See <doc:PerformanceGuide> for optimization tips
- Check the API documentation for detailed method signatures

---

## Backward Compatibility Guarantee

All deprecated APIs will remain functional indefinitely. You can migrate at your own pace:

1. **No breaking changes** - Existing code continues to work
2. **Gradual migration** - Update one component at a time
3. **Incremental adoption** - Mix old and new APIs during transition
4. **Clear deprecation warnings** - Compiler guides you to modern APIs

**Recommendation:** New code should use recommended APIs exclusively. Existing code can be migrated incrementally as time permits.
