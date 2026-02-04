# DICOM Test Fixtures

This directory contains DICOM sample files for integration testing. Due to file size, DICOM files are not included in the repository. Follow the instructions below to obtain public DICOM samples for testing.

## Purpose

Integration tests use these fixtures to verify:
- Different DICOM modalities (CT, MR, XR, US, etc.)
- Various transfer syntaxes (Little/Big Endian, Explicit/Implicit VR, compressed formats)
- Different image dimensions and bit depths
- Real-world DICOM files from medical imaging systems

## Quick Start

1. Download DICOM samples from sources below
2. Place files in this directory: `Tests/DicomCoreTests/Fixtures/`
3. Run integration tests: `swift test --filter Integration`

## Where to Obtain DICOM Samples

### 1. The Cancer Imaging Archive (TCIA)

**Best for:** Large, real-world medical datasets

- **URL:** https://www.cancerimagingarchive.net/
- **License:** Most datasets are public domain or CC-BY
- **Modalities:** CT, MR, PET, XR, and more
- **How to use:**
  1. Browse collections: https://www.cancerimagingarchive.net/collections/
  2. Download DICOM Imaging Data using NBIA Data Retriever
  3. Extract samples and place in this directory

**Recommended collections:**
- **LIDC-IDRI:** CT lung scans (great for testing Hounsfield units)
- **TCGA-BRCA:** Breast MRI (multi-sequence, varied dimensions)
- **CT COLONOGRAPHY:** CT scans with multiple series

### 2. OsiriX DICOM Sample Files

**Best for:** Quick testing with common formats

- **URL:** https://www.osirix-viewer.com/resources/dicom-image-library/
- **License:** Public domain samples
- **Modalities:** CT, MR, XR, US, angio, PET/CT
- **How to use:**
  1. Visit the OsiriX DICOM Image Library
  2. Download individual ZIP archives or complete datasets
  3. Extract .dcm files to this directory

**Recommended samples:**
- **MANIX:** Multi-modality comprehensive dataset (CT, MR, angio)
- **KNEE:** MRI knee studies (multiple series, good for series loading tests)
- **CARDIX:** Cardiac CT angiography

### 3. dcm4che Test Data

**Best for:** Testing transfer syntaxes and edge cases

- **URL:** https://github.com/dcm4che/dcm4che/tree/master/dcm4che-test-data
- **License:** Apache 2.0 or public domain
- **Coverage:** Various transfer syntaxes, compressed formats
- **How to use:**
  ```bash
  git clone https://github.com/dcm4che/dcm4che.git
  cp dcm4che/dcm4che-test-data/src/main/data/*.dcm Tests/DicomCoreTests/Fixtures/
  ```

### 4. DICOM Library Sample Data

**Best for:** Standard test images with known properties

- **URL:** https://dicomlibrary.com/
- **License:** Public samples
- **Modalities:** Various medical imaging types
- **How to use:**
  1. Browse the DICOM Library
  2. Download individual DICOM files
  3. Save to this directory

### 5. Sample DICOM Files from Medical Device Vendors

Many medical imaging equipment vendors provide sample files:
- **GE Healthcare:** Sample DICOM files for testing
- **Siemens Healthineers:** Test datasets
- **Philips Healthcare:** Development samples

Check vendor developer portals for test datasets.

### 6. JPEG Lossless Test Files

**Best for:** Testing JPEG Lossless compression support (Task 003)

JPEG Lossless is a lossless compression format commonly used for medical imaging (especially CT and MRI) where image quality must be preserved. It provides 2-3x compression ratios while maintaining bit-perfect pixel data.

**Transfer Syntax UIDs:**
- `1.2.840.10008.1.2.4.70` - JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14) - Most common
- `1.2.840.10008.1.2.4.57` - JPEG Lossless, Non-Hierarchical (Any Process)

#### Option A: dcm4che Test Data (Recommended)

The dcm4che project includes JPEG Lossless test files:

```bash
# Clone dcm4che repository
git clone https://github.com/dcm4che/dcm4che.git

# Look for JPEG Lossless files (transfer syntax 1.2.840.10008.1.2.4.70)
find dcm4che/dcm4che-test-data -name "*.dcm" -exec dcmdump --print-short {} \; | grep -B5 "1.2.840.10008.1.2.4.70"

# Copy JPEG Lossless files to fixtures
cp dcm4che/dcm4che-test-data/src/main/data/*lossless*.dcm Tests/DicomCoreTests/Fixtures/Compressed/
```

Alternatively, browse the repository directly:
- **URL:** https://github.com/dcm4che/dcm4che/tree/master/dcm4che-test-data/src/main/data
- Look for files with "lossless" in the name or check transfer syntax in file metadata

#### Option B: Convert Existing Files to JPEG Lossless

If you have uncompressed DICOM files, convert them to JPEG Lossless using dcmtk:

```bash
# Install dcmtk
brew install dcmtk  # macOS
# or
apt-get install dcmtk  # Linux

# Convert to JPEG Lossless Process 14 (most common)
dcmcjpeg +e14 input.dcm output_jpeg_lossless.dcm

# Verify transfer syntax
dcmdump --print-short output_jpeg_lossless.dcm | grep "TransferSyntaxUID"
# Should show: (0002,0010) UI [1.2.840.10008.1.2.4.70]

# Copy to fixtures
cp output_jpeg_lossless.dcm Tests/DicomCoreTests/Fixtures/Compressed/
```

**Conversion options:**
- `+e14` - JPEG Lossless Process 14 (First-Order Prediction) - Recommended
- `+el` - JPEG Lossless (Any Process)

#### Option C: Create Synthetic JPEG Lossless Files

Create a minimal test file with known properties:

```bash
# Create a simple 16-bit grayscale DICOM
cat > create_test.py << 'EOF'
import pydicom
from pydicom.dataset import Dataset, FileDataset, FileMetaInformation
from pydicom.uid import generate_uid
import numpy as np
from datetime import datetime

# Create file meta information
file_meta = FileMetaInformation()
file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'  # CT Image Storage
file_meta.MediaStorageSOPInstanceUID = generate_uid()
file_meta.TransferSyntaxUID = '1.2.840.10008.1.2.1'  # Explicit VR Little Endian (uncompressed)
file_meta.ImplementationClassUID = generate_uid()

# Create dataset
ds = FileDataset("test.dcm", {}, file_meta=file_meta, preamble=b"\0" * 128)
ds.PatientName = "Test^JPEG^Lossless"
ds.PatientID = "JPEGLossless001"
ds.Modality = "CT"
ds.SeriesInstanceUID = generate_uid()
ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
ds.StudyInstanceUID = generate_uid()
ds.Rows = 512
ds.Columns = 512
ds.BitsAllocated = 16
ds.BitsStored = 16
ds.HighBit = 15
ds.PixelRepresentation = 0  # Unsigned
ds.SamplesPerPixel = 1
ds.PhotometricInterpretation = "MONOCHROME2"

# Create test pattern (gradient with features)
pixels = np.zeros((512, 512), dtype=np.uint16)
pixels[:256, :] = np.linspace(0, 4095, 512, dtype=np.uint16)  # Gradient
pixels[256:, 256:] = 2048  # Uniform region
ds.PixelData = pixels.tobytes()

ds.save_as("synthetic_ct_uncompressed.dcm")
print("Created synthetic_ct_uncompressed.dcm")
EOF

python3 create_test.py

# Convert to JPEG Lossless
dcmcjpeg +e14 synthetic_ct_uncompressed.dcm Tests/DicomCoreTests/Fixtures/Compressed/jpeg_lossless_ct_001.dcm

# Verify
dcmdump --print-short Tests/DicomCoreTests/Fixtures/Compressed/jpeg_lossless_ct_001.dcm | grep -E "(TransferSyntax|Rows|Columns|BitsStored)"
```

#### Verification

After obtaining JPEG Lossless files, verify they're correct:

```bash
# Check transfer syntax
dcmdump --print-short file.dcm | grep "TransferSyntaxUID"
# Should show: (0002,0010) UI [1.2.840.10008.1.2.4.70] or [1.2.840.10008.1.2.4.57]

# Check pixel data is compressed
dcmdump --print-short file.dcm | grep "PixelData"
# Should show: (7fe0,0010) OB (EncapsulatedPixelData) ...

# Test with decoder
swift test --filter testJPEGLosslessDecoding
```

#### Common Sources for JPEG Lossless Files

- **Medical imaging archives:** Many CT/MRI datasets use JPEG Lossless for archival
- **PACS systems:** Enterprise medical archives often compress with JPEG Lossless
- **Research datasets:** Look for "lossless compressed" in dataset descriptions

## Recommended Test Coverage

Place at least one sample from each category in this directory:

### By Modality
- **CT** (Computed Tomography): Body scans, lung, abdomen
- **MR** (Magnetic Resonance): Brain, knee, spine
- **XR** (X-Ray): Chest, hand, dental
- **US** (Ultrasound): Cardiac, obstetric
- **CR/DX** (Digital Radiography): Chest X-rays
- **MG** (Mammography): Breast imaging
- **PT** (PET): Metabolic imaging
- **NM** (Nuclear Medicine): SPECT scans

### By Transfer Syntax
- **Little Endian Implicit VR** (1.2.840.10008.1.2) - Most common
- **Little Endian Explicit VR** (1.2.840.10008.1.2.1) - Standard
- **Big Endian Explicit VR** (1.2.840.10008.1.2.2) - Legacy
- **JPEG Baseline** (1.2.840.10008.1.2.4.50) - 8-bit lossy
- **JPEG Lossless, Non-Hierarchical, First-Order Prediction** (1.2.840.10008.1.2.4.70) - 16-bit lossless (Process 14)
- **JPEG Lossless, Non-Hierarchical** (1.2.840.10008.1.2.4.57) - Any Process
- **JPEG 2000 Lossless** (1.2.840.10008.1.2.4.90)
- **JPEG 2000 Lossy** (1.2.840.10008.1.2.4.91)

### By Image Properties
- **8-bit grayscale:** X-rays, ultrasound
- **16-bit grayscale:** CT, MRI (most common for volumetric imaging)
- **24-bit RGB:** Color ultrasound, secondary captures
- **Large dimensions:** 512×512 or higher (CT, MRI)
- **Small dimensions:** <256×256 (thumbnails, ultrasound)
- **Multi-frame sequences:** Cine loops, dynamic studies

## Directory Structure

Organize files by modality for easy management:

```
Fixtures/
├── CT/
│   ├── chest_ct_001.dcm
│   ├── abdomen_ct_002.dcm
│   └── lung_ct_003.dcm
├── MR/
│   ├── brain_mr_001.dcm
│   ├── knee_mr_002.dcm
│   └── spine_mr_003.dcm
├── XR/
│   ├── chest_xr_001.dcm
│   └── hand_xr_002.dcm
├── US/
│   └── cardiac_us_001.dcm
├── Compressed/
│   ├── jpeg_baseline_001.dcm
│   ├── jpeg2000_002.dcm
│   ├── jpeg_lossless_ct_001.dcm
│   ├── jpeg_lossless_mr_001.dcm
│   └── jpeg_lossless_process14_001.dcm
└── EdgeCases/
    ├── very_large_image.dcm
    ├── minimal_metadata.dcm
    └── unusual_transfer_syntax.dcm
```

## Usage in Tests

Integration tests check for fixture availability and skip gracefully if files are missing:

```swift
import XCTest
@testable import DicomCore

final class DCMDecoderIntegrationTests: XCTestCase {

    func testLoadRealCTImage() throws {
        let fixturesPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CT")

        // Skip test if no fixtures available
        guard FileManager.default.fileExists(atPath: fixturesPath.path) else {
            throw XCTSkip("DICOM fixtures not available. See Fixtures/README.md")
        }

        let files = try FileManager.default.contentsOfDirectory(at: fixturesPath,
            includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "dcm" }

        guard let firstFile = files.first else {
            throw XCTSkip("No .dcm files found in Fixtures/CT")
        }

        let decoder = DCMDecoder()
        decoder.setDicomFilename(firstFile.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess)
        XCTAssertEqual(decoder.info(for: 0x00080060), "CT")
        XCTAssertGreaterThan(decoder.width, 0)
        XCTAssertGreaterThan(decoder.height, 0)
    }
}
```

## File Size Considerations

DICOM files can be large (1-100MB+ per file). To prevent repository bloat:

1. **Do not commit DICOM files** to the repository
2. Files matching `*.dcm`, `*.DCM`, `*.dicom`, `*.DICOM` are automatically ignored by `.gitignore`
3. Compressed datasets are in `.gitignore`: `*.zip`, `*.tar.gz`
4. Keep fixtures local to your development environment
5. CI/CD pipelines should download fixtures during test setup if needed

## Continuous Integration

For automated testing in CI/CD:

### Option 1: Download During CI
```yaml
# .github/workflows/tests.yml
- name: Download DICOM fixtures
  run: |
    curl -L https://example.com/test-fixtures.zip -o fixtures.zip
    unzip fixtures.zip -d Tests/DicomCoreTests/Fixtures/
```

### Option 2: Use Small Embedded Samples
Create minimal synthetic DICOM files (10-50KB) for basic CI testing, while developers use full datasets locally.

### Option 3: Skip Integration Tests in CI
```bash
swift test --filter '!Integration'  # Run all tests except integration
```

## Privacy and Legal Considerations

When using DICOM files for testing:

1. **Never use real patient data** without proper de-identification and consent
2. **Verify license terms** for public datasets (most are public domain or CC-BY)
3. **Remove PHI** (Protected Health Information) if handling clinical data:
   - Patient Name (0010,0010)
   - Patient ID (0010,0020)
   - Patient Birth Date (0010,0030)
   - Physician names
   - Institution names
4. **Use anonymization tools:**
   - DICOM Anonymizer: https://www.dicomlibrary.com/dicom/dicom-anonymizer/
   - CTP (Clinical Trial Processor)
   - dcm4che deid utility

## Creating Synthetic Test Files

For specific edge cases, create synthetic DICOM files:

### Using dcmtk
```bash
# Install dcmtk
brew install dcmtk  # macOS
apt-get install dcmtk  # Linux

# Create a test file
dcmconv input.dcm output.dcm --write-xfer-little

# Modify specific tags
dcmodify --modify "0008,0060=CT" input.dcm
```

### Creating JPEG Lossless Test Files

**Method 1: Convert with dcmcjpeg (dcmtk)**

```bash
# Convert uncompressed DICOM to JPEG Lossless Process 14
dcmcjpeg +e14 uncompressed.dcm jpeg_lossless_p14.dcm

# Create different bit depths for testing
# 16-bit CT image
dcmcjpeg +e14 ct_16bit.dcm jpeg_lossless_ct_16bit.dcm

# 12-bit MR image
dcmcjpeg +e14 mr_12bit.dcm jpeg_lossless_mr_12bit.dcm

# Verify compression
dcmdump jpeg_lossless_p14.dcm | grep -A2 "TransferSyntaxUID"
# Expected: (0002,0010) UI [1.2.840.10008.1.2.4.70]
```

**Method 2: Batch convert multiple files**

```bash
# Convert all uncompressed files in a directory
for file in Fixtures/CT/*.dcm; do
    output="${file%.dcm}_lossless.dcm"
    dcmcjpeg +e14 "$file" "$output"
    echo "Converted $file -> $output"
done

# Move to Compressed folder
mv Fixtures/CT/*_lossless.dcm Fixtures/Compressed/
```

**Method 3: Create from scratch with specific properties**

```bash
# Create a synthetic file with known properties for regression testing
cat > create_jpeg_lossless_test.sh << 'EOF'
#!/bin/bash

# Create uncompressed base file
python3 << 'PYTHON'
import pydicom
from pydicom.dataset import Dataset, FileDataset, FileMetaInformation
from pydicom.uid import generate_uid
import numpy as np

file_meta = FileMetaInformation()
file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
file_meta.MediaStorageSOPInstanceUID = generate_uid()
file_meta.TransferSyntaxUID = '1.2.840.10008.1.2.1'  # Explicit VR Little Endian
file_meta.ImplementationClassUID = generate_uid()

ds = FileDataset("temp_base.dcm", {}, file_meta=file_meta, preamble=b"\0" * 128)
ds.PatientName = "TEST^JPEGLOSSLESS"
ds.PatientID = "JL001"
ds.Modality = "CT"
ds.SeriesInstanceUID = generate_uid()
ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
ds.StudyInstanceUID = generate_uid()
ds.Rows = 256
ds.Columns = 256
ds.BitsAllocated = 16
ds.BitsStored = 12
ds.HighBit = 11
ds.PixelRepresentation = 0
ds.SamplesPerPixel = 1
ds.PhotometricInterpretation = "MONOCHROME2"
ds.RescaleIntercept = -1024
ds.RescaleSlope = 1

# Create test pattern with known values
pixels = np.zeros((256, 256), dtype=np.uint16)
# Quadrants with different values
pixels[:128, :128] = 0      # Black
pixels[:128, 128:] = 1024   # Mid-gray
pixels[128:, :128] = 2048   # Light gray
pixels[128:, 128:] = 4095   # White
ds.PixelData = pixels.tobytes()

ds.save_as("temp_base.dcm")
PYTHON

# Convert to JPEG Lossless
dcmcjpeg +e14 temp_base.dcm jpeg_lossless_test_pattern.dcm

# Verify it can be read back
dcmdjpeg jpeg_lossless_test_pattern.dcm temp_verify.dcm

echo "Created jpeg_lossless_test_pattern.dcm"
echo "Transfer Syntax:"
dcmdump --print-short jpeg_lossless_test_pattern.dcm | grep "TransferSyntaxUID"

# Cleanup
rm temp_base.dcm temp_verify.dcm
EOF

chmod +x create_jpeg_lossless_test.sh
./create_jpeg_lossless_test.sh
```

### Using pydicom (Python)
```python
from pydicom.dataset import FileDataset
import numpy as np

ds = FileDataset("test.dcm", {}, file_meta=file_meta, preamble=b"\0" * 128)
ds.PatientName = "Test^Patient"
ds.Modality = "CT"
ds.Rows = 512
ds.Columns = 512
ds.PixelData = np.zeros((512, 512), dtype=np.uint16).tobytes()
ds.save_as("Tests/DicomCoreTests/Fixtures/synthetic_ct.dcm")
```

## Troubleshooting

### Tests Are Skipped
- **Cause:** No DICOM files in Fixtures/ directory
- **Solution:** Download samples from sources above

### Transfer Syntax Not Supported
- **Cause:** File uses compressed format not supported by this library
- **Solution:** Convert using dcmtk: `dcmconv input.dcm output.dcm --write-xfer-little`

### JPEG Lossless Files Won't Decode
- **Cause:** Missing JPEG Lossless decoder support or corrupted compression
- **Solution 1 (Test decompression):** Decompress to verify file integrity:
  ```bash
  dcmdjpeg input_lossless.dcm output_uncompressed.dcm
  dcmdump --print-short output_uncompressed.dcm | grep "TransferSyntaxUID"
  # Should show: (0002,0010) UI [1.2.840.10008.1.2.1]
  ```
- **Solution 2 (Check process):** Verify JPEG Lossless process:
  ```bash
  dcmdump input_lossless.dcm | grep -E "(TransferSyntax|BitsStored|BitsAllocated)"
  # Process 14 (most common): 1.2.840.10008.1.2.4.70
  ```
- **Solution 3 (Recreate):** Create fresh JPEG Lossless file from known good source:
  ```bash
  dcmcjpeg +e14 original_uncompressed.dcm new_lossless.dcm
  ```

### Files Too Large for Repository
- **Cause:** Accidentally committed .dcm files
- **Solution:** Remove from Git history:
  ```bash
  git rm --cached Tests/DicomCoreTests/Fixtures/*.dcm
  git commit -m "Remove large DICOM files"
  ```

### Integration Tests Fail
- **Cause:** File format incompatible or corrupted
- **Solution:** Validate file with dcmtk: `dcmdump --print-short file.dcm`

## Resources

- **DICOM Standard:** https://www.dicomstandard.org/
- **DICOM Transfer Syntaxes:** https://dicom.nema.org/medical/dicom/current/output/chtml/part05/chapter_10.html
- **dcmtk Tools:** https://dicom.offis.de/dcmtk.php.en
- **pydicom Documentation:** https://pydicom.github.io/
- **OsiriX Viewer:** https://www.osirix-viewer.com/

## Contact

For questions about test fixtures:
- Open an issue: https://github.com/ThalesMMS/DICOM-Decoder/issues
- Check existing tests: `Tests/DicomCoreTests/`

---

**Note:** This directory should remain empty in version control. DICOM test files must be downloaded locally by developers.
