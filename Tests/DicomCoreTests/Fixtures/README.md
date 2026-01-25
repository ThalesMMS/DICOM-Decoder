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
│   └── jpeg2000_002.dcm
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
