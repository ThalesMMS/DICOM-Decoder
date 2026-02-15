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

### The Cancer Imaging Archive (TCIA)

- **URL:** https://www.cancerimagingarchive.net/
- **License:** Most datasets are public domain or CC-BY
- **Recommended:** LIDC-IDRI (CT lung), TCGA-BRCA (breast MRI), CT COLONOGRAPHY

### OsiriX DICOM Sample Files

- **URL:** https://www.osirix-viewer.com/resources/dicom-image-library/
- **License:** Public domain samples
- **Recommended:** MANIX (multi-modality), KNEE (MRI series), CARDIX (cardiac CT)

### dcm4che Test Data

- **URL:** https://github.com/dcm4che/dcm4che/tree/master/dcm4che-test-data
- **License:** Apache 2.0 or public domain
- **Includes:** Various transfer syntaxes, JPEG Lossless files

```bash
git clone https://github.com/dcm4che/dcm4che.git
cp dcm4che/dcm4che-test-data/src/main/data/*.dcm Tests/DicomCoreTests/Fixtures/
```

### DICOM Library

- **URL:** https://dicomlibrary.com/
- **License:** Public samples

### JPEG Lossless Test Files

The library supports JPEG Lossless (Process 14, Selection Value 1). To obtain test files:

1. **dcm4che** (recommended): Clone the dcm4che repository above; look for files with transfer syntax `1.2.840.10008.1.2.4.70`
2. **Convert existing files** using dcmtk: `dcmcjpeg +e14 input.dcm output_lossless.dcm`
3. **Verify**: `dcmdump --print-short file.dcm | grep "TransferSyntaxUID"` should show `1.2.840.10008.1.2.4.70`

## Directory Structure

```
Fixtures/
├── CT/
│   ├── chest_ct_001.dcm
│   └── abdomen_ct_002.dcm
├── MR/
│   ├── brain_mr_001.dcm
│   └── knee_mr_002.dcm
├── XR/
│   └── chest_xr_001.dcm
├── US/
│   └── cardiac_us_001.dcm
├── Compressed/
│   ├── jpeg_baseline_001.dcm
│   ├── jpeg2000_002.dcm
│   └── jpeg_lossless_ct_001.dcm
└── EdgeCases/
    ├── very_large_image.dcm
    └── minimal_metadata.dcm
```

## Recommended Test Coverage

### By Transfer Syntax
- Little Endian Implicit VR (1.2.840.10008.1.2) - Most common
- Little Endian Explicit VR (1.2.840.10008.1.2.1) - Standard
- Big Endian Explicit VR (1.2.840.10008.1.2.2) - Legacy
- JPEG Lossless, First-Order Prediction (1.2.840.10008.1.2.4.70) - Process 14
- JPEG Baseline (1.2.840.10008.1.2.4.50)
- JPEG 2000 (1.2.840.10008.1.2.4.90 / .91)

### By Image Properties
- 8-bit grayscale, 16-bit grayscale, 24-bit RGB
- Large (512x512+) and small (<256x256) dimensions
- Multi-frame sequences

## Usage in Tests

Integration tests skip gracefully if fixtures are missing:

```swift
func testLoadRealCTImage() throws {
    let fixturesPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/CT")

    guard FileManager.default.fileExists(atPath: fixturesPath.path) else {
        throw XCTSkip("DICOM fixtures not available. See Fixtures/README.md")
    }

    let files = try FileManager.default.contentsOfDirectory(at: fixturesPath,
        includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "dcm" }

    guard let firstFile = files.first else {
        throw XCTSkip("No .dcm files found in Fixtures/CT")
    }

    let decoder = try DCMDecoder(contentsOf: firstFile)
    XCTAssertEqual(decoder.info(for: .modality), "CT")
    XCTAssertGreaterThan(decoder.width, 0)
}
```

## File Size and Privacy

- **Do not commit** DICOM files to the repository (`.gitignore` excludes `*.dcm`)
- **Never use real patient data** without proper de-identification
- **Verify license terms** for public datasets
- Use anonymization tools if handling clinical data (DICOM Anonymizer, dcm4che deid, CTP)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Tests skipped | Download samples from sources above |
| Transfer syntax not supported | Convert: `dcmconv input.dcm output.dcm --write-xfer-little` |
| Files too large for repo | `git rm --cached Tests/DicomCoreTests/Fixtures/*.dcm` |
| Integration tests fail | Validate: `dcmdump --print-short file.dcm` |

## Resources

- [DICOM Standard](https://www.dicomstandard.org/)
- [dcmtk Tools](https://dicom.offis.de/dcmtk.php.en)
- [pydicom Documentation](https://pydicom.github.io/)

---

**Note:** This directory should remain empty in version control. DICOM test files must be downloaded locally by developers.
