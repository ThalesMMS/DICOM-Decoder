# DICOM Conformance Statement

Comprehensive DICOM conformance documentation detailing supported transfer syntaxes, SOP classes, and implementation capabilities.

## Overview

This DICOM Conformance Statement describes the capabilities and limitations of the DicomCore library (version 1.2.0) in accordance with DICOM Part 2: Conformance. DicomCore is a pure Swift DICOM decoder library for iOS 13+ and macOS 12+ that parses DICOM medical imaging files, extracts metadata, and provides pixel data access with optional GPU-accelerated image processing.

**Implementation Type:** DICOM File Decoder Library (Non-Network, Non-Interactive)

**Primary Use Case:** Local DICOM file parsing, metadata extraction, and image processing for iOS and macOS applications

**Regulatory Status:** This library is provided for development purposes and explicitly disclaims medical diagnostic use. Organizations integrating this library into medical devices are responsible for their own regulatory compliance and validation.

---

## 1. Implementation Model

### 1.1 Application Data Flow

DicomCore operates as a file-level DICOM decoder with no network capabilities:

```
DICOM File(s) → DCMDecoder → Metadata Extraction
                          → Pixel Data Extraction
                          → DCMWindowingProcessor → Display-Ready Image
```

**Key Characteristics:**
- **Local file access only** - no network DICOM (DIMSE) support
- **Read-only operations** - no DICOM file creation or modification
- **Single-frame focus** - optimized for CT/MR single-frame images
- **Modality-agnostic parsing** - reads any valid DICOM file format

### 1.2 Functional Definition

DicomCore provides the following functional capabilities:

| Capability | Description | Status |
|------------|-------------|--------|
| **File Format Parsing** | Read DICOM Part 10 files with preamble and File Meta Information | ✅ Supported |
| **Metadata Extraction** | Extract DICOM data elements by tag ID | ✅ Supported |
| **Pixel Data Decoding** | Decompress and decode pixel data to raw buffers | ✅ Supported |
| **Image Processing** | Apply window/level transformations with CPU or GPU | ✅ Supported |
| **Series Loading** | Load and order multi-slice series into 3D volumes | ✅ Supported |
| **Transfer Syntax Conversion** | Convert between transfer syntaxes | ❌ Not Supported |
| **Network Communication** | DICOM C-STORE, C-FIND, C-MOVE, etc. | ❌ Not Supported |
| **DICOM File Creation** | Write DICOM files | ❌ Not Supported |

### 1.3 Sequencing of Real-World Activities

Typical usage sequence:

1. **File Validation (Optional):** Verify file is valid DICOM format
2. **File Loading:** Parse DICOM header and metadata
3. **Metadata Access:** Query specific data elements by tag ID
4. **Pixel Loading (Lazy):** Load and decompress pixel data on demand
5. **Image Processing (Optional):** Apply window/level for display
6. **Display:** Present processed image to user

---

## 2. Transfer Syntax Support

DicomCore supports the following DICOM Transfer Syntaxes for reading:

### 2.1 Uncompressed Transfer Syntaxes

| Transfer Syntax Name | UID | Endianness | VR | Support Level |
|---------------------|-----|------------|-----|---------------|
| **Implicit VR Little Endian** | 1.2.840.10008.1.2 | Little | Implicit | ✅ Full Support |
| **Explicit VR Little Endian** | 1.2.840.10008.1.2.1 | Little | Explicit | ✅ Full Support |
| **Explicit VR Big Endian** | 1.2.840.10008.1.2.2 | Big | Explicit | ✅ Full Support |

### 2.2 Compressed Transfer Syntaxes

| Transfer Syntax Name | UID | Compression | Support Level |
|---------------------|-----|-------------|---------------|
| **JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14, Selection Value 1)** | 1.2.840.10008.1.2.4.70 | JPEG Lossless | ✅ Full Support (Native) |
| **JPEG Lossless, Non-Hierarchical (Process 14)** | 1.2.840.10008.1.2.4.57 | JPEG Lossless | ✅ Full Support (Native) |
| **JPEG Baseline (Process 1)** | 1.2.840.10008.1.2.4.50 | JPEG Lossy | ⚠️ Best-Effort (ImageIO) |
| **JPEG Extended (Process 2 & 4)** | 1.2.840.10008.1.2.4.51 | JPEG Lossy | ⚠️ Best-Effort (ImageIO) |
| **JPEG-LS Lossless Image Compression** | 1.2.840.10008.1.2.4.80 | JPEG-LS | ❌ Not Supported |
| **JPEG-LS Lossy (Near-Lossless) Image Compression** | 1.2.840.10008.1.2.4.81 | JPEG-LS | ❌ Not Supported |
| **JPEG 2000 Image Compression (Lossless Only)** | 1.2.840.10008.1.2.4.90 | JPEG 2000 | ⚠️ Best-Effort (ImageIO) |
| **JPEG 2000 Image Compression** | 1.2.840.10008.1.2.4.91 | JPEG 2000 | ⚠️ Best-Effort (ImageIO) |
| **RLE Lossless** | 1.2.840.10008.1.2.5 | RLE | ❌ Not Supported |

**Support Levels:**
- **✅ Full Support:** Native implementation, thoroughly tested
- **⚠️ Best-Effort:** Relies on Apple's ImageIO framework, support varies by platform/OS version
- **❌ Not Supported:** Transfer syntax cannot be decoded

### 2.3 JPEG Lossless Implementation Details

DicomCore includes a native JPEG Lossless decoder supporting DICOM's most common lossless compression format:

**Supported Features:**
- **Process 14, Selection Values 0-7:** All 8 predictor modes (no prediction, left, top, diagonal, planar, and gradient-based predictors)
- **Precision:** 8-bit, 12-bit, and 16-bit samples
- **Color Space:** Grayscale and RGB (single-frame)
- **Huffman Coding:** Both default and custom Huffman tables

**Limitations:**
- **Multi-frame encapsulated images:** Not supported (single-frame only)
- **Hierarchical encoding:** Not supported (Process 14 non-hierarchical only)
- **Other JPEG processes:** Only Process 14 is supported

---

## 3. SOP Class Support

**IMPORTANT: DicomCore is a DECODER-ONLY library.** It can READ and PARSE DICOM files but cannot ENCODE, CREATE, or MODIFY DICOM files. All SOP Classes listed below are supported for READING only.

As a file-level decoder library, DicomCore does not implement DICOM Service Class Users (SCU) or Service Class Providers (SCP). However, it can successfully parse and extract data from DICOM files conforming to the following SOP Classes:

### 3.1 Image Storage SOP Classes (Read-Only)

DicomCore can read files from any DICOM Image Storage SOP Class. The library is modality-agnostic and will attempt to parse any valid DICOM file format, regardless of the SOP Class UID. The following table lists commonly encountered Image Storage SOP Classes:

**Cross-Sectional Imaging:**

| SOP Class | UID | Typical Use | Tested |
|-----------|-----|-------------|--------|
| **CT Image Storage** | 1.2.840.10008.5.1.4.1.1.2 | Computed Tomography | ✅ Yes |
| **Enhanced CT Image Storage** | 1.2.840.10008.5.1.4.1.1.2.1 | CT with enhanced metadata | ⚠️ Limited |
| **MR Image Storage** | 1.2.840.10008.5.1.4.1.1.4 | Magnetic Resonance Imaging | ✅ Yes |
| **Enhanced MR Image Storage** | 1.2.840.10008.5.1.4.1.1.4.1 | MR with enhanced metadata | ⚠️ Limited |
| **Enhanced MR Color Image Storage** | 1.2.840.10008.5.1.4.1.1.4.3 | Color MR images | ⚠️ Limited |

**Projection Radiography:**

| SOP Class | UID | Typical Use | Tested |
|-----------|-----|-------------|--------|
| **Computed Radiography Image Storage** | 1.2.840.10008.5.1.4.1.1.1 | Computed Radiography (CR) | ⚠️ Limited |
| **Digital X-Ray Image Storage - For Presentation** | 1.2.840.10008.5.1.4.1.1.1.1 | Digital Radiography (DX) | ⚠️ Limited |
| **Digital X-Ray Image Storage - For Processing** | 1.2.840.10008.5.1.4.1.1.1.1.1 | Raw DX images | ⚠️ Limited |
| **Digital Mammography X-Ray Image Storage - For Presentation** | 1.2.840.10008.5.1.4.1.1.1.2 | Mammography (MG) | ⚠️ Limited |
| **Digital Mammography X-Ray Image Storage - For Processing** | 1.2.840.10008.5.1.4.1.1.1.2.1 | Raw mammography | ⚠️ Limited |

**Ultrasound:**

| SOP Class | UID | Typical Use | Tested |
|-----------|-----|-------------|--------|
| **Ultrasound Image Storage** | 1.2.840.10008.5.1.4.1.1.6.1 | 2D Ultrasound | ⚠️ Limited |
| **Ultrasound Multi-frame Image Storage** | 1.2.840.10008.5.1.4.1.1.3.1 | Cine ultrasound loops | ⚠️ Limited |
| **Enhanced US Volume Storage** | 1.2.840.10008.5.1.4.1.1.6.2 | 3D ultrasound volumes | ⚠️ Limited |

**Nuclear Medicine & PET:**

| SOP Class | UID | Typical Use | Tested |
|-----------|-----|-------------|--------|
| **Nuclear Medicine Image Storage** | 1.2.840.10008.5.1.4.1.1.20 | Planar scintigraphy, SPECT | ⚠️ Limited |
| **PET Image Storage** | 1.2.840.10008.5.1.4.1.1.128 | Positron Emission Tomography | ⚠️ Limited |
| **Enhanced PET Image Storage** | 1.2.840.10008.5.1.4.1.1.130 | PET with enhanced metadata | ⚠️ Limited |

**Fluoroscopy & Angiography:**

| SOP Class | UID | Typical Use | Tested |
|-----------|-----|-------------|--------|
| **X-Ray Angiographic Image Storage** | 1.2.840.10008.5.1.4.1.1.12.1 | Angiography (XA) | ⚠️ Limited |
| **X-Ray Radiofluoroscopic Image Storage** | 1.2.840.10008.5.1.4.1.1.12.2 | Fluoroscopy (RF) | ⚠️ Limited |
| **Enhanced XA Image Storage** | 1.2.840.10008.5.1.4.1.1.12.1.1 | Enhanced angiography | ⚠️ Limited |

**Other Modalities:**

| SOP Class | UID | Typical Use | Tested |
|-----------|-----|-------------|--------|
| **Secondary Capture Image Storage** | 1.2.840.10008.5.1.4.1.1.7 | Screen captures, processed images | ✅ Yes |
| **Multi-frame Single Bit Secondary Capture Image Storage** | 1.2.840.10008.5.1.4.1.1.7.1 | Binary images (e.g., CAD) | ⚠️ Limited |
| **RT Image Storage** | 1.2.840.10008.5.1.4.1.1.481.1 | Radiation therapy portal images | ⚠️ Limited |
| **Ophthalmic Photography 8 Bit Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.5.1 | Fundus photography | ⚠️ Limited |
| **VL Endoscopic Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.1.1 | Endoscopy | ⚠️ Limited |
| **VL Microscopic Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.2.1 | Pathology microscopy | ⚠️ Limited |
| **VL Photographic Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.4.1 | Clinical photography | ⚠️ Limited |

**Testing Legend:**
- **✅ Yes:** Extensively tested with real-world datasets
- **⚠️ Limited:** Basic compatibility verified, but not extensively tested
- **❌ No:** Known incompatibilities or not tested

**Note:** DicomCore's modality-agnostic parser can read any DICOM Image Storage SOP Class not explicitly listed above. The primary compatibility factor is the Transfer Syntax (see Section 2) and Photometric Interpretation (see Section 4), not the SOP Class UID itself.

### 3.2 Parsed Attributes

DicomCore can extract any DICOM attribute present in the file. Commonly accessed attributes include:

**Patient Module:**
- Patient Name (0010,0010)
- Patient ID (0010,0020)
- Patient Birth Date (0010,0030)
- Patient Sex (0010,0040)

**Study Module:**
- Study Instance UID (0020,000D)
- Study Date (0020,0008)
- Study Time (0020,0009)
- Study Description (0008,1030)
- Accession Number (0008,0050)

**Series Module:**
- Series Instance UID (0020,000E)
- Series Number (0020,0011)
- Modality (0008,0060)
- Series Description (0008,103E)

**Image Module:**
- SOP Instance UID (0008,0018)
- Image Position (Patient) (0020,0032)
- Image Orientation (Patient) (0020,0037)
- Slice Thickness (0018,0050)
- Slice Location (0020,1041)

**Image Pixel Module:**
- Rows (0028,0010)
- Columns (0028,0011)
- Bits Allocated (0028,0100)
- Bits Stored (0028,0101)
- High Bit (0028,0102)
- Pixel Representation (0028,0103)
- Samples Per Pixel (0028,0002)
- Photometric Interpretation (0028,0004)
- Pixel Data (7FE0,0010)

**VOI LUT Module:**
- Window Center (0028,1050)
- Window Width (0028,1051)
- Rescale Intercept (0028,1052)
- Rescale Slope (0028,1053)

### 3.3 Private Attributes

DicomCore can read private data elements (odd group numbers) but does not interpret their semantics. Private tags are returned as raw string or binary data.

---

## 4. Pixel Data Formats

### 4.1 Supported Photometric Interpretations

| Photometric Interpretation | Bits Allocated | Support Level |
|----------------------------|----------------|---------------|
| **MONOCHROME1** | 8, 16 | ✅ Full Support |
| **MONOCHROME2** | 8, 16 | ✅ Full Support |
| **RGB** | 24 (8 per channel) | ✅ Full Support |
| **PALETTE COLOR** | 8, 16 | ❌ Not Supported |
| **YBR_FULL** | 24 | ⚠️ Limited Support |
| **YBR_FULL_422** | 24 | ❌ Not Supported |

### 4.2 Pixel Data Processing

**Supported Operations:**
- **Rescale Slope/Intercept:** Automatic application to convert to modality units (e.g., Hounsfield Units for CT)
- **Window/Level:** CPU (vDSP) and GPU (Metal) accelerated windowing with 13 medical presets
- **Bit Depth Conversion:** 16-bit to 8-bit conversion for display
- **Inversion:** MONOCHROME1 to MONOCHROME2 conversion

**Image Processing Performance:**

| Image Size | vDSP (CPU) | Metal (GPU) | Use Case |
|------------|------------|-------------|----------|
| 256×256 | ~0.5ms | ~0.3ms | Preview/Thumbnail |
| 512×512 | ~2ms | ~1.16ms | Standard View |
| 1024×1024 | ~8.67ms | ~2.20ms | High-Res Display |
| 2048×2048 | ~35ms | ~8ms | Full-Resolution Export |

**Auto-Selection Threshold:** Images ≥800×800 pixels automatically use Metal GPU acceleration if available, with graceful fallback to vDSP.

---

## 5. Character Set Support

### 5.1 Default Character Repertoire

DicomCore uses Swift's native String encoding support:

| Character Set | Specific Character Set (0008,0005) | Support |
|---------------|-----------------------------------|---------|
| **ASCII** | ISO_IR 6 (default) | ✅ Full Support |
| **UTF-8** | ISO_IR 192 | ✅ Full Support |
| **Latin-1** | ISO_IR 100 | ✅ Full Support |
| **Latin-2** | ISO_IR 101 | ⚠️ Best-Effort |
| **Japanese** | ISO 2022 IR 13, 87, 159 | ⚠️ Best-Effort |
| **Korean** | ISO 2022 IR 149 | ⚠️ Best-Effort |
| **Chinese** | GB18030, GBK | ⚠️ Best-Effort |

**Note:** Character set handling relies on Swift's String encoding APIs. Support varies by platform and encoding complexity.

---

## 6. Security Features

### 6.1 Data Security

DicomCore operates entirely within the application sandbox with no network communication:

| Security Aspect | Implementation |
|-----------------|----------------|
| **Network Security** | N/A (no network capabilities) |
| **File Access** | Application sandbox only, respects iOS/macOS file permissions |
| **Data Encryption** | Files are read as-is; encryption/decryption is the caller's responsibility |
| **Authentication** | N/A (local library, no user authentication) |
| **Audit Trail** | None (logging is the caller's responsibility) |

### 6.2 Patient Privacy

**PHI (Protected Health Information) Handling:**
- DicomCore reads PHI from DICOM files but does not store, transmit, or log it
- Applications using DicomCore are responsible for:
  - Secure storage of files containing PHI
  - Compliance with HIPAA, GDPR, or other applicable regulations
  - Implementing appropriate access controls and audit logging

### 6.3 Vulnerability Mitigation

| Risk | Mitigation |
|------|------------|
| **Buffer Overflows** | Swift's memory safety prevents buffer overflows |
| **Integer Overflows** | Validated array sizing with overflow checks |
| **Malformed Files** | Defensive parsing with typed error handling |
| **Memory Exhaustion** | Memory mapping for large files (>10MB) |
| **Decompression Bombs** | Pixel data size validation against declared dimensions |

---

## 7. Configuration

### 7.1 Build-Time Configuration

DicomCore requires:
- **Minimum iOS Version:** 13.0
- **Minimum macOS Version:** 12.0
- **Swift Version:** 5.7 or later
- **Xcode Version:** 14.0 or later

### 7.2 Runtime Configuration

No runtime configuration files are required. Optional features:

| Feature | Default | Configuration |
|---------|---------|---------------|
| **Memory Mapping Threshold** | 10 MB | Hard-coded, not configurable |
| **Metal GPU Acceleration** | Auto-detect | Configurable per-call via `processingMode` parameter |
| **Tag Caching** | Enabled | Always enabled, not configurable |

### 7.3 Framework Dependencies

DicomCore uses only Apple-provided frameworks:

- **Foundation:** Core Swift types, file I/O
- **CoreGraphics:** Image representation (CGImage)
- **ImageIO:** JPEG/JPEG2000 decompression fallback
- **Accelerate (vDSP):** CPU-based image processing
- **Metal:** GPU-based image processing (optional)

**Zero External Dependencies:** No third-party libraries, CocoaPods, or SPM dependencies.

---

## 8. Known Limitations

### 8.1 Format Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| **Multi-frame images** | Cannot decode encapsulated multi-frame JPEG/JPEG2000 | Extract frames externally before loading |
| **RLE Compression** | Transfer Syntax 1.2.840.10008.1.2.5 unsupported | Convert to uncompressed or JPEG Lossless |
| **JPEG Hierarchical** | JPEG processes other than Process 14 unsupported | Convert to supported transfer syntax |
| **PALETTE COLOR** | Cannot decode palette-based images | Convert to RGB or grayscale |
| **Large Files** | Files >1GB may consume significant memory | Use memory-efficient workflows, process in chunks |

### 8.2 Functional Limitations

| Limitation | Impact |
|------------|--------|
| **No DICOM Network** | Cannot communicate with PACS, modalities, or workstations |
| **Read-Only** | Cannot create, modify, or anonymize DICOM files |
| **No Structured Reports** | SR documents can be parsed for text, but not semantically interpreted |
| **No DICOM Dir** | DICOMDIR files are not parsed |
| **No Presentation States** | GSPS, Structured Display annotations not applied |

### 8.3 Performance Considerations

| Scenario | Expected Performance | Recommendation |
|----------|---------------------|----------------|
| **File Opening** | <50ms for typical files | Use async APIs for UI responsiveness |
| **Pixel Loading** | 100-500ms for compressed data | Load pixels in background task |
| **Series Loading** | 2-5s for 100-slice CT series | Use progress callbacks, enable concurrency |
| **Window/Level (CPU)** | ~2ms per 512×512 image | Acceptable for interactive UI |
| **Window/Level (GPU)** | ~2.2ms per 1024×1024 image | Use for high-res or batch processing |

---

## 9. Version History

### Version 1.2.0 (Current)

**Release Date:** 2026-02-15

**Key Features:**
- Type-safe value types (WindowSettings, PixelSpacing, RescaleParameters)
- Enhanced concurrency support with Sendable conformance
- Batch loading APIs for concurrent file processing
- DicomTag enum for type-safe metadata access
- Improved error messages and diagnostics

**Conformance Changes:**
- No changes to transfer syntax support
- No changes to SOP class compatibility

### Version 1.1.0

**Release Date:** 2025-12-01 (estimated)

**Key Features:**
- Throwing initializers for Swift-idiomatic error handling
- Native JPEG Lossless decoder (Process 14, all selection values 0-7)
- Support for 12-bit and 16-bit precision in JPEG Lossless

**Conformance Changes:**
- Added full support for Transfer Syntax 1.2.840.10008.1.2.4.57 (JPEG Lossless, Non-Hierarchical)
- Expanded JPEG Lossless support to all selection values (0-7), not just selection value 1

### Version 1.0.0

**Release Date:** 2025-09-01 (estimated)

**Initial Release:**
- Basic DICOM parsing (Little/Big Endian, Explicit/Implicit VR)
- 8-bit, 16-bit grayscale, and 24-bit RGB support
- JPEG Lossless (Process 14, Selection Value 1) via native decoder
- JPEG/JPEG2000 best-effort support via ImageIO
- Window/Level processing with vDSP (CPU) backend

---

## 10. Support and Contact

### 10.1 Documentation

- **Architecture Overview:** See <doc:Architecture>
- **Performance Guide:** See <doc:PerformanceGuide>
- **Migration Guide:** See <doc:MigrationGuide>
- **API Reference:** See ``DCMDecoder``, ``DCMWindowingProcessor``

### 10.2 Issue Reporting

For bug reports, feature requests, or conformance issues, please file an issue on the project's GitHub repository.

**Information to Include:**
- Library version (e.g., 1.2.0)
- Platform and OS version (e.g., iOS 17.2, macOS 14.1)
- Minimal reproducible example
- Sample DICOM file (if applicable, ensure PHI is removed)
- Expected vs. actual behavior

### 10.3 Validation Testing

Organizations integrating DicomCore into medical devices should conduct their own validation testing:

**Recommended Tests:**
1. **Transfer Syntax Validation:** Test all transfer syntaxes used in your workflow
2. **Modality Coverage:** Test with representative images from all modalities in scope
3. **Edge Cases:** Test with malformed files, corrupt data, and boundary conditions
4. **Performance:** Benchmark with production-scale datasets
5. **Integration:** Validate within your application's security and privacy controls

**DICOM Test Images:**
- **NEMA DICOM Sample Images:** https://www.dicomstandard.org/resources/sample-images
- **OsiriX Sample Datasets:** https://www.osirix-viewer.com/resources/dicom-image-library/
- **TCIA (The Cancer Imaging Archive):** https://www.cancerimagingarchive.net/

---

## 11. Regulatory Disclaimer

**IMPORTANT: This library is not FDA-cleared, CE-marked, or approved for medical diagnostic use.**

DicomCore is provided as a software development library for creating applications that work with DICOM files. Organizations developing medical devices or diagnostic software using this library are solely responsible for:

- Obtaining necessary regulatory clearances (FDA 510(k), CE Mark, etc.)
- Conducting validation and verification activities
- Maintaining quality management systems (ISO 13485, FDA 21 CFR Part 820)
- Ensuring compliance with medical device software standards (IEC 62304)
- Implementing appropriate cybersecurity controls (FDA Premarket Guidance)
- Meeting privacy regulations (HIPAA, GDPR, etc.)

**Use at your own risk. No warranties are provided for fitness for any particular purpose, including medical diagnosis or patient care.**

---

## Appendix A: Transfer Syntax UID Reference

Complete list of DICOM Transfer Syntax UIDs mentioned in this document:

| UID | Name | Support |
|-----|------|---------|
| 1.2.840.10008.1.2 | Implicit VR Little Endian | ✅ Full |
| 1.2.840.10008.1.2.1 | Explicit VR Little Endian | ✅ Full |
| 1.2.840.10008.1.2.2 | Explicit VR Big Endian | ✅ Full |
| 1.2.840.10008.1.2.4.50 | JPEG Baseline (Process 1) | ⚠️ Best-Effort |
| 1.2.840.10008.1.2.4.51 | JPEG Extended (Process 2 & 4) | ⚠️ Best-Effort |
| 1.2.840.10008.1.2.4.57 | JPEG Lossless, Non-Hierarchical (Process 14) | ✅ Full |
| 1.2.840.10008.1.2.4.70 | JPEG Lossless, Non-Hierarchical, First-Order Prediction | ✅ Full |
| 1.2.840.10008.1.2.4.90 | JPEG 2000 Image Compression (Lossless Only) | ⚠️ Best-Effort |
| 1.2.840.10008.1.2.4.91 | JPEG 2000 Image Compression | ⚠️ Best-Effort |
| 1.2.840.10008.1.2.5 | RLE Lossless | ❌ Not Supported |

---

## Appendix B: Standard DICOM Tag Reference

Commonly used DICOM tags with group/element numbers and VR (Value Representation):

### Patient Information Elements (0010,xxxx)

| Tag | VR | Name |
|-----|-----|------|
| (0010,0010) | PN | Patient Name |
| (0010,0020) | LO | Patient ID |
| (0010,0030) | DA | Patient Birth Date |
| (0010,0040) | CS | Patient Sex |

### Study Information Elements (0020,xxxx and 0008,xxxx)

| Tag | VR | Name |
|-----|-----|------|
| (0020,000D) | UI | Study Instance UID |
| (0008,0020) | DA | Study Date |
| (0008,0030) | TM | Study Time |
| (0008,1030) | LO | Study Description |
| (0008,0050) | SH | Accession Number |

### Series Information Elements (0020,xxxx and 0008,xxxx)

| Tag | VR | Name |
|-----|-----|------|
| (0020,000E) | UI | Series Instance UID |
| (0020,0011) | IS | Series Number |
| (0008,0060) | CS | Modality |
| (0008,103E) | LO | Series Description |

### Image Information Elements (0020,xxxx and 0018,xxxx)

| Tag | VR | Name |
|-----|-----|------|
| (0008,0018) | UI | SOP Instance UID |
| (0020,0032) | DS | Image Position (Patient) |
| (0020,0037) | DS | Image Orientation (Patient) |
| (0020,0013) | IS | Instance Number |
| (0018,0050) | DS | Slice Thickness |
| (0020,1041) | DS | Slice Location |

### Image Pixel Elements (0028,xxxx)

| Tag | VR | Name |
|-----|-----|------|
| (0028,0010) | US | Rows |
| (0028,0011) | US | Columns |
| (0028,0100) | US | Bits Allocated |
| (0028,0101) | US | Bits Stored |
| (0028,0102) | US | High Bit |
| (0028,0103) | US | Pixel Representation |
| (0028,0002) | US | Samples Per Pixel |
| (0028,0004) | CS | Photometric Interpretation |
| (0028,1050) | DS | Window Center |
| (0028,1051) | DS | Window Width |
| (0028,1052) | DS | Rescale Intercept |
| (0028,1053) | DS | Rescale Slope |
| (7FE0,0010) | OB/OW | Pixel Data |

---

## See Also

- <doc:Architecture>
- <doc:PerformanceGuide>
- <doc:MigrationGuide>
- ``DCMDecoder``
- ``DCMWindowingProcessor``
- ``DicomSeriesLoader``
