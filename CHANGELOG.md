# Changelog

All notable changes to the Swift DICOM Decoder project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### DCMDecoder Enhancements

- **Validation Methods**:
  - `validateDICOMFile(_:)` - Validates DICOM file structure before loading
  - `isValid()` - Checks if decoder has successfully read and parsed DICOM data
  - `getValidationStatus()` - Returns detailed validation status including dimensions and pixel availability

- **Async/Await Support** (iOS 13+, macOS 10.15+):
  - `loadDICOMFileAsync(_:)` - Asynchronously loads and decodes DICOM files
  - `getPixels16Async()` - Asynchronously retrieves 16-bit pixel data
  - `getPixels8Async()` - Asynchronously retrieves 8-bit pixel data
  - `getPixels24Async()` - Asynchronously retrieves 24-bit RGB pixel data
  - `getDownsampledPixels16Async(maxDimension:)` - Asynchronously retrieves downsampled thumbnail pixels

- **Convenience Methods**:
  - `intValue(for:)` - Retrieves integer values for DICOM tags
  - `doubleValue(for:)` - Retrieves double values for DICOM tags
  - `getAllTags()` - Returns all DICOM tags as a dictionary
  - `getPatientInfo()` - Returns structured patient demographics
  - `getStudyInfo()` - Returns structured study information
  - `getSeriesInfo()` - Returns structured series information

- **Convenience Properties**:
  - `isGrayscale` - Quick check for grayscale images
  - `isColorImage` - Quick check for RGB/color images
  - `isMultiFrame` - Quick check for multi-frame images
  - `imageDimensions` - Returns width and height as tuple
  - `pixelSpacing` - Returns pixel spacing (width, height, depth) as tuple
  - `windowSettings` - Returns window center and width as tuple
  - `rescaleParameters` - Returns rescale intercept and slope as tuple

- **Image Analysis**:
  - `applyRescale(to:)` - Applies rescale slope and intercept to pixel values (for Hounsfield Units)
  - `calculateOptimalWindow()` - Calculates optimal window/level based on pixel statistics
  - `getQualityMetrics()` - Returns comprehensive image quality metrics

#### DCMWindowingProcessor Enhancements

- **Extended Medical Presets**:
  - Added CT presets: `mediastinum`, `abdomen`, `spine`, `pelvis`
  - Added angiography presets: `angiography`, `pulmonaryEmbolism`
  - Added other modality presets: `mammography`, `petScan`
  - Total of 13 presets (up from 6)

- **Preset Metadata**:
  - `MedicalPreset.displayName` - Human-readable preset names
  - `MedicalPreset.associatedModality` - Typical modality for each preset
  - Made `MedicalPreset` public and `CaseIterable`

- **Intelligent Preset Suggestions**:
  - `suggestPresets(for:bodyPart:)` - Auto-suggests appropriate presets based on modality and body part
  - Provides context-aware preset recommendations (e.g., lung preset for chest CT)

- **Enhanced Preset Management**:
  - `allPresets` - Returns all available presets (now public)
  - `ctPresets` - Returns CT-specific presets
  - `getPresetValues(named:)` - Case-insensitive preset lookup by name (now public)
  - `getPreset(for:)` - Returns complete preset information (name, values, modality)
  - Enhanced `getPresetName(center:width:tolerance:)` to use display names

- **Improved Preset Values**:
  - Enhanced lung preset window width (1200 -> 1500 HU) for better visualization
  - Added appropriate values for all new presets based on radiological standards

#### Testing Improvements

- **Comprehensive Test Suite**:
  - Dictionary loading and tag validation tests
  - Decoder validation and state tests
  - Convenience method tests
  - Windowing preset tests
  - Preset suggestion tests
  - Hounsfield unit conversion tests
  - Quality metrics calculation tests
  - Error handling tests
  - Performance benchmarks for windowing operations

#### Documentation

- **New Files**:
  - `USAGE_EXAMPLES.md` - Comprehensive usage examples covering all features
  - `CHANGELOG.md` - This changelog documenting all improvements

- **Enhanced Examples**:
  - Basic synchronous and asynchronous usage
  - Validation and error handling
  - Window/level operations
  - Medical preset usage
  - Metadata extraction
  - Image quality metrics
  - Batch processing
  - Advanced features (HU conversion, image enhancement, optimization)
  - Complete DICOM viewer component example

### Improved

#### Performance Optimizations

- **Metadata Caching** (Already present):
  - Intelligent caching of frequently accessed DICOM tags
  - Reduced string processing overhead for repeated tag access
  - Static set of frequent tags for cache hit optimization

- **Memory-Mapped File I/O** (Already present):
  - Automatic memory mapping for files >10MB
  - Dramatically faster loading for large DICOM files
  - Performance logging for load times

- **Optimized Pixel Reading** (Already present):
  - `withUnsafeBytes` for zero-copy pixel access
  - Fast path for aligned memory access
  - Optimized MONOCHROME1 inversion

#### API Improvements

- Made key types and methods public for better library integration:
  - `MedicalPreset` enum and its properties
  - Preset management methods
  - Window/level calculation methods

- Improved method signatures for consistency and clarity
- Enhanced parameter documentation

### Fixed

- Improved error messages and recovery suggestions in `DICOMError`
- Better handling of edge cases in preset recognition
- More robust validation of DICOM file structure

---

## [1.0.0] - Initial Release

### Added

- Core DICOM decoder (`DCMDecoder`) with support for:
  - Little and big endian byte order
  - Explicit and implicit VR
  - 8-bit and 16-bit grayscale images
  - 24-bit RGB images
  - Uncompressed transfer syntaxes
  - Memory-mapped file I/O for large files
  - Downsampled pixel reading for thumbnails

- Window/level processor (`DCMWindowingProcessor`) with:
  - Medical imaging window/level transformations
  - Basic medical presets (lung, bone, soft tissue, brain, liver)
  - Image enhancement (CLAHE, noise reduction)
  - Statistical analysis (histogram, quality metrics)
  - Batch processing capabilities
  - Hounsfield unit conversion utilities

- Error handling system (`DICOMError`):
  - Comprehensive error types
  - Error severity classification
  - Recovery suggestions
  - Objective-C bridge

- Study data service (`StudyDataService`):
  - Metadata extraction
  - Batch processing
  - DICOM validation
  - Study grouping

- Resource management:
  - DICOM tag dictionary (`DCMDictionary`)
  - Bundled tag definitions
  - Protocol abstractions

- Testing:
  - Basic unit tests for dictionary loading
  - Package structure validation

### Technical Details

- Swift 5.9+ support
- iOS 13+ and macOS 12+ compatibility
- Pure Swift implementation
- No UIKit or Objective-C dependencies in core
- SwiftPM package structure

---

## Version History

- **Unreleased**: Current improvements (this update)
- **1.0.0**: Initial release with core functionality

[Unreleased]: https://github.com/ThalesMMS/DICOM-Decoder/compare/1.0.0...HEAD
[1.0.0]: https://github.com/ThalesMMS/DICOM-Decoder/releases/tag/1.0.0
