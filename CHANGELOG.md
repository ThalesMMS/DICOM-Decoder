## 1.0.1 - DICOM Streaming & Security Enhancements

### New Features

- Add range-based pixel access methods to enable efficient streaming of DICOM image data without loading entire files into memory

- Implement JPEG Lossless decoder with full specification support including Huffman table decoding, first-order predictor, and bit unpacking

- Introduce DicomDecoderProtocol and dependency injection patterns for improved testability and modularity across FileImportService, StudyDataService, and DicomSeriesLoader

### Improvements

- Refactor DICOM decoder with modular reader architecture and async support for better separation of concerns

- Optimize range-based reading for memory-mapped file access to improve performance with large DICOM datasets

- Replace print statements with logger.debug for consistent diagnostic output in DCMDictionary

### Bug Fixes

- Add comprehensive security validation including bounds checking, sequence depth tracking, pixel buffer allocation validation, and malicious length detection to prevent stack overflow and buffer overflow attacks

- Guard reference decoder test on macOS to handle platform-specific compatibility issues

---

## What's Changed

- feat: add range-based pixel access methods to DicomDecoderProtocol by @Thales Matheus in 0994381
- feat: add range-based readPixels methods to DCMPixelReader by @Thales Matheus in 8df6718
- feat: optimize range-based reading for memory-mapped file by @Thales Matheus in 66e5052
- feat: implement range-based getPixels methods in DCMDecoder by @Thales Matheus in c89c2ba
- feat: research JPEG Lossless specification and create algorithm documentation by @Thales Matheus in a001bb5
- feat: create JPEGLosslessDecoder class with JPEG marker parsing by @Thales Matheus in fbed227
- feat: implement Huffman table decoder for JPEG Lossless by @Thales Matheus in d1ef665
- feat: implement first-order predictor for JPEG Lossless by @Thales Matheus in 3684756
- feat: implement main decode() method with bit unpacking by @Thales Matheus in 54de290
- feat: add JPEG Lossless detection to decodeCompressedPixels by @Thales Matheus in 6e4cfd2
- feat: create DicomDecoderProtocol to abstract DCMDecoder by @Thales Matheus in 68d0a6d
- feat: create StudyDataServiceProtocol by @Thales Matheus in 53cf7e6
- feat: create DicomDictionaryProtocol by @Thales Matheus in 9d75abb
- feat: create DicomSeriesLoaderProtocol by @Thales Matheus in e2ebd5a
- feat: make DCMDecoder conform to DicomDecoderProtocol by @Thales Matheus in e095a2a
- feat: make StudyDataService conform to protocol and inject decoder by @Thales Matheus in 6e5b32f
- feat: update DCMDictionary to support DI and deprecate singleton by @Thales Matheus in 1d8c8aa
- feat: make DicomSeriesLoader conform to protocol and inject decoder by @Thales Matheus in 0d92a7b
- feat: define FileImportServiceProtocol by @Thales Matheus in 1fd9ea5
- feat: update FileImportService to inject decoder by @Thales Matheus in c3f25a1
- feat: update SeriesBusinessLogic to inject decoder by @Thales Matheus in 948c7fb
- fix: add safety limit constants to DCMDecoder by @Thales Matheus in 4e52c00
- fix: add validateLength() helper method for bounds validation by @Thales Matheus in 5de26e6
- fix: enhance getLength() with malicious length detection by @Thales Matheus in 954693c
- fix: add image dimension validation in readFileInfoUnsafe() by @Thales Matheus in 132b305
- fix: add pixel buffer allocation validation in readPixelsUnsafe() by @Thales Matheus in 6816f4c
- fix: add sequence depth tracking to prevent stack overflow by @Thales Matheus in a96841f
- fix: add bounds checking error cases to DICOMError enum by @Thales Matheus in 7028847
- fix: guard reference decoder test on macOS by @Thales Matheus in 4e22e6b
- fix: skip reference decoder comparison on non-macOS by @Thales Matheus in 043f8a1
- docs: use logger.debug instead of print in DCMDictionary by @Thales Matheus in 7a0c374
- test: validate pixel ranges/bytes and add mmap tests by @Thales Matheus in ad0dcf5
- test: add docstrings to auto-claude/002-streaming-pixel-data-access by @Thales Matheus in cc25fa3
- test: verify memory-mapped file compatibility by @Thales Matheus in 0386732
- test: run full test suite to verify backward compatibility by @Thales Matheus in 986c042
- test: add performance benchmarks for streaming access by @Thales Matheus in 1e4a067
- test: add memory usage tests for streaming access by @Thales Matheus in d9b83ed
- test: create DCMDecoderStreamingTests with basic range access tests by @Thales Matheus in 765dbd8
- test: create unit tests for JPEGLosslessDecoder by @Thales Matheus in 6d61309
- test: create integration tests with synthetic JPEG Lossless DICOM files by @Thales Matheus in e10c8ae
- test: add performance benchmarks for JPEG Lossless decoder by @Thales Matheus in 610d4aa
- test: create test fixtures documentation for obtaining JPEG Lossless samples by @Thales Matheus in 5d7ebed
- test: test with DICOM conformance test suite by @Thales Matheus in b329240
- test: verify bit-perfect output against reference decoders by @Thales Matheus in fefd890
- test: create MockDicomDecoder for testing by @Thales Matheus in c9f1e98
- test: add dependency injection tests for StudyDataService by @Thales Matheus in 425b2a0
- test: add integration test verifying protocol usage by @Thales Matheus in cab79be
- test: create DCMDecoderSecurityTests.swift test file by @Thales Matheus in a24ac46
- test: add error type tests for new DICOMError cases by @Thales Matheus in 39c620a
- docs: update CLAUDE.md with new DI patterns by @Thales Matheus in f04eea8
- docs: update USAGE_EXAMPLES.md with protocol examples by @Thales Matheus in 085e34c
- docs: update documentation and CHANGELOG by @Thales Matheus in 7c440c6
- docs: modify DCMPixelReader to call JPEGLosslessDecoder by @Thales Matheus in 9fdac68
- docs: update DCMDecoder to handle JPEG Lossless transfer by @Thales Matheus in 4ddd200
- refactor: refactor DICOM decoder with modular readers and async support by @Thales Matheus in 9f139b2
- chore: add DICOM test fixture files to repository by @Thales Matheus in 6c39ca0
- chore: initial commit of Swift DICOM Decoder library by @Thales Matheus in 17c0f5f
- chore: initial commit by @Thales Matheus in d4bcc77

## Thanks to all contributors

@Thales Matheus

# Changelog

All notable changes to the Swift DICOM Decoder project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### JPEG Lossless Compression Support

- **Native JPEG Lossless Decoder**:
  - `JPEGLosslessDecoder` - Native implementation of JPEG Lossless (Process 14, Selection Value 1)
  - Support for transfer syntaxes 1.2.840.10008.1.2.4.57 (JPEG Lossless) and 1.2.840.10008.1.2.4.70 (JPEG Lossless First-Order Prediction)
  - Full JPEG marker parsing (SOI, SOF3, DHT, SOS, EOI)
  - Huffman table decoding following ITU-T T.81 specification
  - First-order prediction algorithm with edge case handling
  - Bit-perfect decoding with byte stuffing removal
  - Support for 8-bit, 12-bit, and 16-bit precision
  - Integrated with `DCMPixelReader` for automatic format detection
  - Comprehensive test suite with unit, integration, and performance benchmarks
  - Performance within acceptable limits for medical imaging workflows
  - Validation infrastructure for bit-perfect comparison with reference decoders (dcmtk, GDCM)

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
