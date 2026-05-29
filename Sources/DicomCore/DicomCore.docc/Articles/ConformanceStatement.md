# DICOM Conformance Statement

Comprehensive DICOM conformance documentation detailing supported transfer syntaxes, SOP classes, and implementation capabilities.

## Overview

This DICOM Conformance Statement describes the capabilities and limitations of the DicomCore library (version 1.2.0) in accordance with DICOM Part 2: Conformance. DicomCore is a pure Swift DICOM file library for iOS 13+ and macOS 12+ that parses DICOM medical imaging files, extracts metadata, provides pixel data access with optional GPU-accelerated image processing, and writes controlled Part 10 datasets.

**Implementation Type:** DICOM File Decoder/Writer Library with transport-injected JPIP progressive pixel streaming

**Primary Use Case:** Local DICOM file parsing, metadata extraction, media-directory import, dataset writing, image processing, and progressive JPIP pixel update integration for iOS and macOS applications

**Regulatory Status:** This library is provided for development purposes and explicitly disclaims medical diagnostic use. Organizations integrating this library into medical devices are responsible for their own regulatory compliance and validation.

---

## 1. Implementation Model

### 1.1 Application Data Flow

DicomCore operates primarily as a file-level DICOM decoder. JPIP progressive pixel delivery is exposed through a transport-injected client so applications can provide their own network stack:

```
DICOM File(s) → DCMDecoder → Metadata Extraction
                          → Pixel Data Extraction
                          → DCMWindowingProcessor → Display-Ready Image
```

**Key Characteristics:**
- **Local file access by default** - no DIMSE support
- **JPIP referenced pixel data** - metadata parsing recognizes Pixel Data Provider URL and streams progressive updates through caller-provided transport
- **Controlled write operations** - Part 10 dataset writing and DICOMDIR writing for native and deflated local media workflows
- **Native image frame access** - optimized for CT/MR single-frame images and uncompressed Enhanced Multi-frame metadata/frame workflows
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
| **DICOMDIR Media Import** | Read/write DICOMDIR records and resolve local file references | ✅ Supported |
| **Enhanced Multi-frame Functional Groups** | Parse shared/per-frame geometry, timing, pixel measures, and source references | ✅ Supported for uncompressed native pixel data |
| **Quantitative Values** | Parse Real World Value Mapping linear/LUT items and calculate PET SUV variants when required metadata is present | ✅ Supported for uncompressed native pixel data |
| **Encapsulated Pixel Data Indexing** | Parse Basic Offset Table, Extended Offset Table, fragments, and frame-to-fragment mappings | Supported before codec decode |
| **DICOM Segmentation** | Parse binary/fractional SEG frames, preserve segment/source/geometry metadata, and build synthetic SEG datasets | ✅ Synthetic binary and fractional |
| **Radiotherapy Objects** | Parse RTSTRUCT contours, RTDOSE scaled volumes, and RTPLAN beam/control point metadata | ✅ Synthetic RT objects |
| **Parametric Map** | Parse integer, Float Pixel Data, and Double Float Pixel Data scalar maps with units, quantity definitions, RWV, geometry, and source references | ✅ Synthetic PM |
| **Structured Reports and Key Objects** | Parse SR/KOS content trees, measurements, ROI/source references, CAD findings, and key image references; build controlled SR/KOS datasets | ✅ Synthetic SR/KOS |
| **Secondary Capture Objects** | Build RGB/monochrome snapshot datasets, parse SC metadata/source references, and write Part 10 SC files | ✅ Synthetic SC |
| **Inference Output Objects** | Build external inference outputs as SR findings, SEG masks, GSPS graphics, and derived images with source references and tracking identifiers | ✅ Synthetic SR/SEG/GSPS |
| **Encapsulated Documents** | Build, parse, and export Encapsulated PDF/CDA/STL payloads with MIME, title, concept, and source instance metadata | ✅ Synthetic DOC |
| **Waveform Objects** | Build and parse ECG/related temporal signal objects with channel samples, sampling frequency, units, and waveform references | ✅ Synthetic ECG |
| **Video Objects** | Build and parse Video Endoscopic/Microscopic/Photographic objects, preserving MPEG-2/H.264/H.265 streams and timing metadata for player handoff | ✅ Synthetic video |
| **JPEG 2000 Part 2 Volume Documents** | Decode multi-component component collections into `DicomSeriesVolume` buffers with geometry metadata | ⚠️ Best-Effort OpenJPEG runtime |
| **JPIP Progressive Pixel Data** | Recognize referenced pixel URLs and expose ordered progressive volume update streams with cancellation/backpressure | ⚠️ Transport-injected client |
| **Transfer Syntax Conversion** | Plan safe conversion paths with codec diagnostics; compressed encoders are not implemented | Planning API only |
| **Network Communication** | DICOM C-STORE, C-FIND, C-MOVE, etc. | ❌ Not Supported |
| **DICOM File Creation** | Write native and Deflated Explicit VR Little Endian Part 10 datasets, DICOMDIR files, and encapsulated caller-provided video streams | ✅ Supported |

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

Use ``DicomTransferSyntaxRegistry`` to inspect encapsulation, fragmentation, decoder/encoder availability, and safe transcode planning before converting pixel data. Use ``DicomEncapsulatedPixelDataParser`` or `DCMDecoder.getEncapsulatedFrame(_:)` to extract a compressed frame payload before passing it to a codec.

### 2.1 Uncompressed Transfer Syntaxes

| Transfer Syntax Name | UID | Endianness | VR | Support Level |
|---------------------|-----|------------|-----|---------------|
| **Implicit VR Little Endian** | 1.2.840.10008.1.2 | Little | Implicit | ✅ Full Support |
| **Explicit VR Little Endian** | 1.2.840.10008.1.2.1 | Little | Explicit | ✅ Full Support |
| **Explicit VR Big Endian** | 1.2.840.10008.1.2.2 | Big | Explicit | ✅ Full Support |

### 2.2 Compressed Transfer Syntaxes

| Transfer Syntax Name | UID | Compression | Support Level |
|---------------------|-----|-------------|---------------|
| **Deflated Explicit VR Little Endian** | 1.2.840.10008.1.2.1.99 | Dataset deflate | ✅ Full Support (zlib raw deflate) |
| **JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14, Selection Value 1)** | 1.2.840.10008.1.2.4.70 | JPEG Lossless | ✅ Full Support (Native) |
| **JPEG Lossless, Non-Hierarchical (Process 14)** | 1.2.840.10008.1.2.4.57 | JPEG Lossless | ✅ Full Support (Native) |
| **JPEG Baseline (Process 1)** | 1.2.840.10008.1.2.4.50 | JPEG Lossy | ⚠️ Explicit ImageIO backend for 8-bit payloads |
| **JPEG Extended (Process 2 & 4)** | 1.2.840.10008.1.2.4.51 | JPEG Lossy | ⚠️ Explicit ImageIO backend for <=8-bit payloads; 12-bit rejected with diagnostics |
| **JPEG-LS Lossless Image Compression** | 1.2.840.10008.1.2.4.80 | JPEG-LS | ⚠️ Best-Effort (CharLS runtime) |
| **JPEG-LS Lossy (Near-Lossless) Image Compression** | 1.2.840.10008.1.2.4.81 | JPEG-LS | ⚠️ Best-Effort (CharLS runtime) |
| **JPEG 2000 Image Compression (Lossless Only)** | 1.2.840.10008.1.2.4.90 | JPEG 2000 | ⚠️ Explicit OpenJPEG backend up to 16-bit grayscale; ImageIO 8-bit fallback |
| **JPEG 2000 Image Compression** | 1.2.840.10008.1.2.4.91 | JPEG 2000 | ⚠️ Explicit OpenJPEG backend up to 16-bit grayscale; ImageIO 8-bit fallback |
| **JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only)** | 1.2.840.10008.1.2.4.92 | JPEG 2000 Part 2 | ⚠️ Explicit OpenJPEG backend for `DicomJP3DVolumeDocument` |
| **JPEG 2000 Part 2 Multi-component Image Compression** | 1.2.840.10008.1.2.4.93 | JPEG 2000 Part 2 | ⚠️ Explicit OpenJPEG backend for `DicomJP3DVolumeDocument` |
| **DICOM JPIP Referenced Transfer Syntax** | 1.2.840.10008.1.2.4.94 | JPIP referenced pixel data | ⚠️ Metadata and progressive stream contract; transport supplied by application |
| **DICOM JPIP Referenced Deflate Transfer Syntax** | 1.2.840.10008.1.2.4.95 | JPIP referenced pixel data with dataset deflate | ⚠️ Metadata inflation plus progressive stream contract; transport supplied by application |
| **HTJ2K Image Compression (Lossless Only)** | 1.2.840.10008.1.2.4.201 | HTJ2K | ❌ Not Supported |
| **HTJ2K Image Compression (Lossless RPCL)** | 1.2.840.10008.1.2.4.202 | HTJ2K | ❌ Not Supported |
| **HTJ2K Image Compression** | 1.2.840.10008.1.2.4.203 | HTJ2K | ❌ Not Supported |
| **RLE Lossless** | 1.2.840.10008.1.2.5 | RLE | ✅ Full Support (Native) |

**Support Levels:**
- **✅ Full Support:** Native implementation, thoroughly tested
- **⚠️ Best-Effort/Explicit Backend:** Uses a named backend with documented limits; unsupported depth/syntax combinations return diagnostics
- **❌ Not Supported:** Transfer syntax cannot be decoded

### 2.3 JPEG Lossless Implementation Details

DicomCore includes a native JPEG Lossless decoder supporting DICOM's most common lossless compression format:

**Supported Features:**
- **Process 14, Selection Values 0-7:** All 8 predictor modes (no prediction, left, top, diagonal, planar, and gradient-based predictors)
- **Precision:** 8-bit, 12-bit, and 16-bit samples
- **Color Space:** Grayscale and RGB (single-frame)
- **Huffman Coding:** Both default and custom Huffman tables

**Limitations:**
- **Multi-frame encapsulated images:** Frame indexing and compressed frame extraction are supported; full decode still depends on the codec for the transfer syntax.
- **Hierarchical encoding:** Not supported (Process 14 non-hierarchical only)
- **Other JPEG processes:** Only Process 14 is supported

---

## 3. SOP Class Support

DicomCore can read and parse DICOM files and can write controlled Part 10 datasets for uncompressed local workflows. Network service classes are not implemented.

As a file-level decoder library, DicomCore does not implement DICOM Service Class Users (SCU) or Service Class Providers (SCP). However, it can successfully parse and extract data from DICOM files conforming to the following SOP Classes:

### 3.1 Image Storage SOP Classes

DicomCore can read files from any DICOM Image Storage SOP Class. The library is modality-agnostic and will attempt to parse any valid DICOM file format, regardless of the SOP Class UID. The following table lists commonly encountered Image Storage SOP Classes:

**Cross-Sectional Imaging:**

| SOP Class | UID | Typical Use | Tested |
|-----------|-----|-------------|--------|
| **CT Image Storage** | 1.2.840.10008.5.1.4.1.1.2 | Computed Tomography | ✅ Yes |
| **Enhanced CT Image Storage** | 1.2.840.10008.5.1.4.1.1.2.1 | CT with enhanced metadata | ✅ Synthetic Functional Groups |
| **MR Image Storage** | 1.2.840.10008.5.1.4.1.1.4 | Magnetic Resonance Imaging | ✅ Yes |
| **Enhanced MR Image Storage** | 1.2.840.10008.5.1.4.1.1.4.1 | MR with enhanced metadata | ✅ Synthetic Functional Groups |
| **Enhanced MR Color Image Storage** | 1.2.840.10008.5.1.4.1.1.4.3 | Color MR images | ⚠️ Limited |
| **Segmentation Storage** | 1.2.840.10008.5.1.4.1.1.66.4 | Binary and fractional labelmaps | ✅ Synthetic SEG |
| **RT Structure Set Storage** | 1.2.840.10008.5.1.4.1.1.481.3 | Structure contours | ✅ Synthetic RTSTRUCT |
| **RT Dose Storage** | 1.2.840.10008.5.1.4.1.1.481.2 | Scaled dose grids | ✅ Synthetic RTDOSE |
| **RT Plan Storage** | 1.2.840.10008.5.1.4.1.1.481.5 | Beam/control point inspection | ✅ Synthetic RTPLAN |
| **Parametric Map Storage** | 1.2.840.10008.5.1.4.1.1.30 | Quantitative scalar maps | ✅ Synthetic PM |
| **Basic Text SR Storage** | 1.2.840.10008.5.1.4.1.1.88.11 | Navigable text SR content trees | ✅ Synthetic SR |
| **Enhanced SR Storage** | 1.2.840.10008.5.1.4.1.1.88.22 | Navigable SR content trees | ✅ Synthetic SR |
| **Comprehensive SR Storage** | 1.2.840.10008.5.1.4.1.1.88.33 | TID 1500-style measurements and ROIs | ✅ Synthetic SR |
| **Comprehensive 3D SR Storage** | 1.2.840.10008.5.1.4.1.1.88.34 | 3D SR content tree metadata | ✅ Synthetic SR |
| **Extensible SR Storage** | 1.2.840.10008.5.1.4.1.1.88.35 | Extensible SR content tree metadata | ✅ Synthetic SR |
| **Mammography CAD SR Storage** | 1.2.840.10008.5.1.4.1.1.88.50 | CAD finding containers | ✅ Synthetic SR |
| **Chest CAD SR Storage** | 1.2.840.10008.5.1.4.1.1.88.65 | CAD finding containers | ✅ Synthetic SR |
| **Colon CAD SR Storage** | 1.2.840.10008.5.1.4.1.1.88.69 | CAD finding containers | ✅ Synthetic SR |
| **Key Object Selection Document Storage** | 1.2.840.10008.5.1.4.1.1.88.59 | Key image/object references | ✅ Synthetic KOS |
| **Grayscale Softcopy Presentation State Storage** | 1.2.840.10008.5.1.4.1.1.11.1 | Image-relative graphic annotations | ✅ Synthetic GSPS |
| **Encapsulated PDF Storage** | 1.2.840.10008.5.1.4.1.1.104.1 | Encapsulated PDF documents | ✅ Synthetic DOC |
| **Encapsulated CDA Storage** | 1.2.840.10008.5.1.4.1.1.104.2 | Encapsulated CDA documents | ✅ Synthetic DOC |
| **Encapsulated STL Storage** | 1.2.840.10008.5.1.4.1.1.104.3 | Encapsulated STL models | ✅ Synthetic DOC |
| **12-lead ECG Waveform Storage** | 1.2.840.10008.5.1.4.1.1.9.1.1 | ECG temporal samples | ✅ Synthetic ECG |
| **General ECG Waveform Storage** | 1.2.840.10008.5.1.4.1.1.9.1.2 | ECG temporal samples | ✅ Synthetic ECG |
| **Ambulatory ECG Waveform Storage** | 1.2.840.10008.5.1.4.1.1.9.1.3 | Ambulatory ECG temporal samples | ✅ Synthetic ECG |
| **Hemodynamic Waveform Storage** | 1.2.840.10008.5.1.4.1.1.9.2.1 | Hemodynamic temporal samples | ⚠️ Parser model |
| **Video Endoscopic Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.1.1 | Encoded visible-light video stream | ✅ Synthetic video |
| **Video Microscopic Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.2.1 | Encoded visible-light video stream | ✅ Synthetic video |
| **Video Photographic Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.4.1 | Encoded visible-light video stream | ✅ Synthetic video |

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
| **Enhanced PET Image Storage** | 1.2.840.10008.5.1.4.1.1.130 | PET with enhanced metadata | ✅ Synthetic Functional Groups |

**Fluoroscopy & Angiography:**

| SOP Class | UID | Typical Use | Tested |
|-----------|-----|-------------|--------|
| **X-Ray Angiographic Image Storage** | 1.2.840.10008.5.1.4.1.1.12.1 | Angiography (XA) | ⚠️ Limited |
| **X-Ray Radiofluoroscopic Image Storage** | 1.2.840.10008.5.1.4.1.1.12.2 | Fluoroscopy (RF) | ⚠️ Limited |
| **Enhanced XA Image Storage** | 1.2.840.10008.5.1.4.1.1.12.1.1 | Enhanced angiography | ⚠️ Limited |

**Other Modalities:**

| SOP Class | UID | Typical Use | Tested |
|-----------|-----|-------------|--------|
| **Secondary Capture Image Storage** | 1.2.840.10008.5.1.4.1.1.7 | Screen captures, processed images | ✅ Synthetic SC |
| **Multi-frame Single Bit Secondary Capture Image Storage** | 1.2.840.10008.5.1.4.1.1.7.1 | Binary images (e.g., CAD) | ⚠️ Limited |
| **RT Image Storage** | 1.2.840.10008.5.1.4.1.1.481.1 | Radiation therapy portal images | ⚠️ Limited |
| **Ophthalmic Photography 8 Bit Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.5.1 | Fundus photography | ⚠️ Limited |
| **VL Endoscopic Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.1.1 | Endoscopy | ⚠️ Limited |
| **VL Microscopic Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.2.1 | Pathology microscopy | ⚠️ Limited |
| **VL Photographic Image Storage** | 1.2.840.10008.5.1.4.1.1.77.1.4.1 | Clinical photography | ⚠️ Limited |

### 3.2 Media Storage SOP Classes

| SOP Class | UID | Typical Use | Tested |
|-----------|-----|-------------|--------|
| **Media Storage Directory Storage** | 1.2.840.10008.1.3.10 | DICOMDIR patient/study/series/image directory records | ✅ Yes |

**Testing Legend:**
- **✅ Yes:** Extensively tested with real-world datasets
- **⚠️ Limited:** Basic compatibility verified, but not extensively tested
- **❌ No:** Known incompatibilities or not tested

**Note:** DicomCore's modality-agnostic parser can read any DICOM Image Storage SOP Class not explicitly listed above. The primary compatibility factor is the Transfer Syntax (see Section 2) and Photometric Interpretation (see Section 4), not the SOP Class UID itself.

### 3.3 Parsed Attributes

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

**Segmentation Module:**
- Segmentation Type (0062,0001)
- Segment Sequence (0062,0002)
- Segment Identification Sequence (0062,000A)
- Tracking UID (0062,0021)
- Segmentation Fractional Type (0062,0010)
- Maximum Fractional Value (0062,000E)

**Radiotherapy Modules:**
- Structure Set ROI Sequence (3006,0020)
- ROI Contour Sequence (3006,0039)
- Contour Data (3006,0050)
- Dose Units (3004,0002)
- Dose Grid Scaling (3004,000E)
- Beam Sequence (300A,00B0)
- Control Point Sequence (300A,0111)

**Structured Reporting Modules:**
- Content Sequence (0040,A730)
- Relationship Type (0040,A010)
- Value Type (0040,A040)
- Concept Name Code Sequence (0040,A043)
- Measured Value Sequence (0040,A300)
- Content Template Sequence (0040,A504)
- Current Requested Procedure Evidence Sequence (0040,A375)
- Graphic Data (0070,0022)
- Graphic Type (0070,0023)

**Presentation State Modules:**
- Referenced Series Sequence (0008,1115)
- Referenced Image Sequence (0008,1140)
- Graphic Annotation Sequence (0070,0001)
- Graphic Object Sequence (0070,0009)
- Graphic Layer Sequence (0070,0060)
- Displayed Area Selection Sequence (0070,005A)
- Presentation LUT Shape (2050,0020)

**Secondary Capture Modules:**
- Image Type (0008,0008)
- Conversion Type (0008,0064)
- Source Image Sequence (0008,2112)
- Date of Secondary Capture (0018,1012)
- Time of Secondary Capture (0018,1014)
- Secondary Capture Device ID (0018,1010)
- Secondary Capture Device Manufacturer (0018,1016)
- Secondary Capture Device Manufacturer's Model Name (0018,1018)
- Secondary Capture Device Software Version(s) (0018,1019)

**Encapsulated Document Modules:**
- Document Title (0042,0010)
- Encapsulated Document (0042,0011)
- MIME Type of Encapsulated Document (0042,0012)
- Source Instance Sequence (0042,0013)
- List of MIME Types (0042,0014)
- Encapsulated Document Length (0042,0015)
- Concept Name Code Sequence (0040,A043)

**Waveform Modules:**
- Waveform Sequence (5400,0100)
- Number of Waveform Channels (003A,0005)
- Number of Waveform Samples (003A,0010)
- Sampling Frequency (003A,001A)
- Channel Definition Sequence (003A,0200)
- Channel Source Sequence (003A,0208)
- Channel Sensitivity Units Sequence (003A,0211)
- Waveform Bits Allocated (5400,1004)
- Waveform Sample Interpretation (5400,1006)
- Waveform Data (5400,1010)
- Source Waveform Sequence (003A,020A)

**VOI LUT Module:**
- Window Center (0028,1050)
- Window Width (0028,1051)
- Rescale Intercept (0028,1052)
- Rescale Slope (0028,1053)

### 3.4 Private Attributes

DicomCore preserves private data elements (odd group numbers) as typed dataset
elements and models private creator namespaces through `DicomPrivateCreator`.
Unknown private payloads remain accessible as raw string or binary values.

Known private dictionaries are intentionally small and clinically scoped. The
current built-in dictionary identifies Siemens CSA image/series headers and
selected Siemens MR diffusion fields. `SiemensCSAParser` can extract common CSA
values such as b-value, diffusion gradient direction, and image orientation
from CSA payloads without coupling renderer code to private tag details.

---

## 4. Pixel Data Formats

### 4.1 Supported Photometric Interpretations

| Photometric Interpretation | Bits Allocated | Support Level |
|----------------------------|----------------|---------------|
| **MONOCHROME1** | 8, 16 | ✅ Full Support |
| **MONOCHROME2** | 8, 16 | ✅ Full Support |
| **RGB** | 8 per channel | ✅ Full Support |
| **PALETTE COLOR** | 8, 16 index | ✅ Display RGB + native CLUT metadata |
| **YBR_FULL** | 8 per sample | ✅ Display RGB |
| **YBR_FULL_422** | 8 per sample | ✅ Display RGB |

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

DicomCore decodes textual VRs through `DicomSpecificCharacterSet` and exposes
`DicomTextSanitizer` helpers for display-safe strings. Display sanitization
removes control characters and normalizes Unicode form; it does not redact or
anonymize values.

| Character Set | Specific Character Set (0008,0005) | Support |
|---------------|-----------------------------------|---------|
| **ASCII** | ISO_IR 6 (default) | ✅ Full Support |
| **UTF-8** | ISO_IR 192 | ✅ Full Support |
| **Latin-1** | ISO_IR 100 | ✅ Full Support |
| **Latin-2** | ISO_IR 101 | ✅ Foundation-backed |
| **Japanese** | ISO 2022 IR 13, 87, 159 | ⚠️ Foundation-backed best effort |
| **Korean** | ISO 2022 IR 149 | ⚠️ Best-Effort |
| **Chinese** | GB18030, GBK | ⚠️ Best-Effort |

Person Name (PN) values preserve alphabetic, ideographic, and phonetic
representation groups when present.

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

DicomCore uses Apple-provided frameworks for its core pipeline:

- **Foundation:** Core Swift types, file I/O
- **CoreGraphics:** Image representation (CGImage)
- **ImageIO:** Explicit JPEG Baseline decompression backend and 8-bit JPEG 2000 fallback
- **Accelerate (vDSP):** CPU-based image processing
- **Metal:** GPU-based image processing (optional)

Deflated Explicit VR Little Endian uses system zlib for raw deflate/inflate. JPEG-LS decoding can use CharLS when that runtime library is available. JPEG 2000 decoding can use OpenJPEG when that runtime library is available. The Swift package does not add SPM dependencies for these codecs; the codec bridges load runtimes dynamically.

---

## 8. Known Limitations

### 8.1 Format Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| **Encapsulated multi-frame images** | Frame indexing is supported; full decode depends on codec support for the transfer syntax | Extract frames with `getEncapsulatedFrame(_:)` and decode with a supported codec |
| **JPEG-LS Runtime Availability** | JPEG-LS requires CharLS to be available at runtime | Install CharLS or convert to a native lossless syntax |
| **JPEG Hierarchical** | JPEG processes other than Process 14 unsupported | Convert to supported transfer syntax |
| **Unsupported color combinations** | `DicomColorConversionError` documents unsupported bit depth, planar layout, or missing CLUT cases | Convert through a supported transfer syntax/color layout |
| **Incomplete PET SUV metadata** | SUV helpers return no physical value and report missing DICOM tags | Preserve Units, Patient Weight/Size/Sex, radiopharmaceutical dose, decay, and timing metadata |
| **Large Files** | Files >1GB may consume significant memory | Use memory-efficient workflows, process in chunks |

### 8.2 Functional Limitations

| Limitation | Impact |
|------------|--------|
| **No DICOM Network** | Cannot communicate with PACS, modalities, or workstations |
| **Limited Writing Scope** | General dataset writing is limited to native or Deflated Explicit VR Little Endian Part 10 datasets and DICOMDIR media records; video builders can also write caller-provided encapsulated MPEG-2/H.264/H.265 streams |
| **Limited Structured Report Semantics** | SR/KOS trees, measurements, ROI/source references, CAD finding containers, and key image references are parsed, but full template validation is not implemented |
| **Limited Secondary Capture Pixel Inputs** | SC writing supports native unsigned monochrome and interleaved RGB pixel payloads, including CGImage snapshots converted to RGB8 |
| **Limited Encapsulated Document Scope** | Document object writing is limited to Encapsulated PDF, CDA, and STL Part 10 datasets; embedded document contents are preserved but not rendered or semantically parsed |
| **Limited Waveform Sample Scope** | Waveform writing/parsing covers linear 8/16/32-bit integer sample interpretations and exposes temporal samples without converting them to image volumes |
| **Limited Video Scope** | Video writing/parsing encapsulates and exposes caller-provided MPEG-2/H.264/H.265 streams with metadata; native video decoding is delegated to the application/player backend |
| **Limited Presentation State Scope** | GSPS graphic annotations are parsed/built for object exchange; display application of GSPS transforms remains caller-owned |

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
- JPEG Baseline explicit ImageIO-backed support and JPEG 2000 explicit OpenJPEG-backed support
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
| 1.2.840.10008.1.2.1.99 | Deflated Explicit VR Little Endian | ✅ Full |
| 1.2.840.10008.1.2.2 | Explicit VR Big Endian | ✅ Full |
| 1.2.840.10008.1.2.4.50 | JPEG Baseline (Process 1) | ⚠️ Explicit ImageIO 8-bit |
| 1.2.840.10008.1.2.4.51 | JPEG Extended (Process 2 & 4) | ⚠️ Explicit ImageIO <=8-bit; 12-bit diagnostics |
| 1.2.840.10008.1.2.4.57 | JPEG Lossless, Non-Hierarchical (Process 14) | ✅ Full |
| 1.2.840.10008.1.2.4.70 | JPEG Lossless, Non-Hierarchical, First-Order Prediction | ✅ Full |
| 1.2.840.10008.1.2.4.80 | JPEG-LS Lossless Image Compression | ⚠️ Best-Effort |
| 1.2.840.10008.1.2.4.81 | JPEG-LS Lossy Near-Lossless Image Compression | ⚠️ Best-Effort |
| 1.2.840.10008.1.2.4.90 | JPEG 2000 Image Compression (Lossless Only) | ⚠️ Explicit OpenJPEG up to 16-bit grayscale |
| 1.2.840.10008.1.2.4.91 | JPEG 2000 Image Compression | ⚠️ Explicit OpenJPEG up to 16-bit grayscale |
| 1.2.840.10008.1.2.4.92 | JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only) | ⚠️ Explicit OpenJPEG volume document |
| 1.2.840.10008.1.2.4.93 | JPEG 2000 Part 2 Multi-component Image Compression | ⚠️ Explicit OpenJPEG volume document |
| 1.2.840.10008.1.2.4.201 | HTJ2K Image Compression (Lossless Only) | ❌ Not Supported |
| 1.2.840.10008.1.2.4.202 | HTJ2K Image Compression (Lossless RPCL) | ❌ Not Supported |
| 1.2.840.10008.1.2.4.203 | HTJ2K Image Compression | ❌ Not Supported |
| 1.2.840.10008.1.2.5 | RLE Lossless | ✅ Full |

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
| (0062,0001) | CS | Segmentation Type |
| (0062,0002) | SQ | Segment Sequence |
| (0062,000A) | SQ | Segment Identification Sequence |
| (0062,0021) | UI | Tracking UID |
| (3004,000E) | DS | Dose Grid Scaling |
| (3006,0020) | SQ | Structure Set ROI Sequence |
| (3006,0039) | SQ | ROI Contour Sequence |
| (3006,0050) | DS | Contour Data |
| (300A,00B0) | SQ | Beam Sequence |
| (300A,0111) | SQ | Control Point Sequence |
| (7FE0,0010) | OB/OW | Pixel Data |

---

## See Also

- <doc:Architecture>
- <doc:PerformanceGuide>
- <doc:MigrationGuide>
- ``DCMDecoder``
- ``DCMWindowingProcessor``
- ``DicomSeriesLoader``
