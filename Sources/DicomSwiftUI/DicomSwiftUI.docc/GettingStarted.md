# Getting Started

Learn how to integrate DicomSwiftUI components into your SwiftUI app for medical imaging display and interaction.

## Overview

DicomSwiftUI provides four main components that can be used individually or combined to create complete DICOM viewers:

- **DicomImageView**: Display DICOM images with automatic windowing
- **WindowingControlView**: Interactive window/level controls with medical presets
- **SeriesNavigatorView**: Navigate through DICOM series with thumbnails
- **MetadataView**: Display formatted DICOM metadata

## Platform Requirements

- **iOS**: 13.0 or later
- **macOS**: 12.0 or later
- **Swift**: 5.9 or later

## DICOM Loading APIs (Recommended vs Legacy)

Use the throwing initializers in new code so failures are handled through `throw`/`catch`.

| Recommended | Legacy |
| --- | --- |
| `try DCMDecoder(contentsOf: url)` / `try DCMDecoder(contentsOfFile: path)` | `setDicomFilename(_:)` + `dicomFileReadSuccess` |
| `try await DCMDecoder(contentsOf: url)` / `try await DCMDecoder(contentsOfFile: path)` | `await loadDICOMFileAsync(_:)` |

- `setDicomFilename(_:)` and `dicomFileReadSuccess` are deprecated.
- `loadDICOMFileAsync(_:)` is a legacy compatibility wrapper and is not recommended for new code.

### Migration Example

```swift
// Recommended
do {
    let decoder = try await DCMDecoder(contentsOf: dicomURL)
    // Use decoder
} catch {
    // Handle DICOMError (file not found, invalid format, etc.)
}

// Legacy (avoid in new code)
let legacyDecoder = DCMDecoder()
legacyDecoder.setDicomFilename(dicomURL.path)
guard legacyDecoder.dicomFileReadSuccess else { return }
```

## Installation

### Swift Package Manager

Add DicomSwiftUI to your project using Xcode:

1. Open your project in Xcode
2. Go to File > Add Packages...
3. Enter the repository URL
4. Select your version requirements
5. Add the DicomSwiftUI target to your app

### Import

```swift
import SwiftUI
import DicomSwiftUI
```

## Basic Usage

### Display a Single DICOM Image

The simplest way to display a DICOM image is to use `DicomImageView` with a URL:

```swift
import SwiftUI
import DicomSwiftUI

struct ContentView: View {
    let dicomURL: URL

    var body: some View {
        DicomImageView(url: dicomURL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`DicomImageView` automatically:
- Loads the DICOM file asynchronously
- Applies optimal window/level settings
- Handles rendering and display
- Shows loading and error states

### Add Interactive Windowing Controls

Combine `DicomImageView` with `WindowingControlView` to allow users to adjust brightness and contrast:

```swift
struct DicomViewerView: View {
    let dicomURL: URL
    @StateObject private var viewModel = DicomImageViewModel()

    var body: some View {
        VStack {
            DicomImageView(url: dicomURL, viewModel: viewModel)

            if let decoder = viewModel.decoder {
                WindowingControlView(decoder: decoder)
            }
        }
    }
}
```

The windowing controls include:
- Sliders for window center and width
- Medical preset buttons (Lung, Bone, Brain, etc.)
- Automatic optimal window calculation
- Real-time preview

### Navigate a DICOM Series

Use `SeriesNavigatorView` to navigate through multiple DICOM images in a series:

```swift
struct SeriesViewerView: View {
    let seriesURLs: [URL]
    @State private var currentIndex = 0

    var body: some View {
        VStack {
            // Display current image
            DicomImageView(url: seriesURLs[currentIndex])

            // Series navigation controls
            SeriesNavigatorView(
                currentIndex: $currentIndex,
                totalCount: seriesURLs.count
            )
        }
    }
}
```

`SeriesNavigatorView` features:
- Thumbnail strip with current slice indicator
- Previous/Next buttons
- Keyboard shortcuts (arrow keys, Page Up/Down)
- Slice counter display
- Customizable thumbnail size

### Display DICOM Metadata

Show patient information, study details, and image properties using `MetadataView`:

```swift
struct MetadataDisplayView: View {
    let dicomURL: URL

    var body: some View {
        VStack {
            DicomImageView(url: dicomURL)

            MetadataView(url: dicomURL)
                .frame(maxHeight: 200)
        }
    }
}
```

`MetadataView` displays:
- Patient name, ID, age, sex
- Study date, description, modality
- Image dimensions, spacing, position
- Window/level settings
- Formatted and localized values

## Complete Example

Here's a complete example combining all components:

```swift
import SwiftUI
import DicomSwiftUI

struct CompleteDicomViewerView: View {
    let seriesURLs: [URL]
    @State private var currentIndex = 0
    @StateObject private var viewModel = DicomImageViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Main image display
            DicomImageView(
                url: seriesURLs[currentIndex],
                viewModel: viewModel
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Metadata panel
            MetadataView(url: seriesURLs[currentIndex])
                .frame(height: 150)

            Divider()

            // Windowing controls
            if let decoder = viewModel.decoder {
                WindowingControlView(decoder: decoder)
                    .padding()
            }

            Divider()

            // Series navigation
            SeriesNavigatorView(
                currentIndex: $currentIndex,
                totalCount: seriesURLs.count
            )
            .frame(height: 80)
        }
    }
}
```

## Customization

All components support customization through view modifiers and configuration:

### Custom Styling

```swift
DicomImageView(url: dicomURL)
    .background(Color.black)
    .cornerRadius(8)
    .shadow(radius: 4)
```

### Custom Window Settings

```swift
DicomImageView(
    url: dicomURL,
    windowingMode: .custom(center: 50.0, width: 400.0)
)
```

### Custom Error Handling

```swift
DicomImageView(url: dicomURL)
    .overlay {
        if let error = viewModel.error {
            VStack {
                Image(systemName: "exclamationmark.triangle")
                Text("Failed to load: \(error.localizedDescription)")
            }
        }
    }
```

## Accessibility

All DicomSwiftUI components include built-in accessibility support:

- **VoiceOver**: Semantic labels and hints
- **Dynamic Type**: Text scales with system settings
- **Keyboard Navigation**: Full keyboard support
- **High Contrast**: Adapts to accessibility display modes
- **Reduced Motion**: Respects animation preferences

Enable additional accessibility features:

```swift
DicomImageView(url: dicomURL)
    .accessibilityLabel("CT scan image")
    .accessibilityHint("Double tap to zoom")
```

## Performance Tips

### Async Loading

Components load DICOM files asynchronously by default, but you can preload for smoother navigation:

```swift
// Preload adjacent slices in background
Task {
    for offset in [-2, -1, 1, 2] {
        let index = currentIndex + offset
        guard index >= 0 && index < seriesURLs.count else { continue }
        let decoder = try? await DCMDecoder(contentsOf: seriesURLs[index])
        // Cache decoder...
    }
}
```

### GPU Acceleration

Enable GPU acceleration for large images:

```swift
// GPU automatically used for images ≥800×800 pixels
let pixels8bit = DCMWindowingProcessor.applyWindowLevel(
    pixels16: pixels16,
    center: center,
    width: width,
    processingMode: .auto  // Auto-selects best backend
)
```

### Memory Management

For large series, implement pagination:

```swift
// Load only visible range
let visibleRange = (currentIndex - 5)...(currentIndex + 5)
let visibleURLs = seriesURLs[safe: visibleRange]
```

## Next Steps

- Learn how to customize component appearance in <doc:CustomizingViews>
- Build a complete viewer application in <doc:BuildingAViewer>
- Implement accessibility features in <doc:AccessibilityGuide>
- Explore advanced techniques in ``DicomCore``

## See Also

- ``DicomImageView``
- ``WindowingControlView``
- ``SeriesNavigatorView``
- ``MetadataView``
- ``DicomCore``
