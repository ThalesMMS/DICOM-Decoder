# DICOM Test Fixtures

This directory contains DICOM sample files for integration testing. Small synthetic non-PHI fixtures are committed for
deterministic default CI. Larger public or locally generated optional fixtures can be added locally for extended
conformance testing.

## Curated parity fixtures (issue #1224)

`DecoderParity/jpeg_lossless_sv1_parity.dcm`, `DecoderParity/rle_parity.dcm`,
`StructuredReports/sr_tid1500_measurement_report.dcm` and
`StructuredReports/kos_key_object_selection.dcm` are committed curated
fixtures bound to `ClinicalParityFixtureManifest.json`.

- **Provenance/license**: generated in-repo by the deterministic builders in
  `ClinicalParityCuratedFixtureTests` (no external data; same license as the
  repository). Regenerate with `DICOM_REGENERATE_PARITY_FIXTURES=1 swift test
  --filter ClinicalParityCuratedFixtureTests`.
- **Privacy**: synthetic non-PHI; identifiers use `PARITY` placeholders only.
- **Drift gates**: the same suite fails when the committed bytes, expected
  UIDs, frame counts, pixel hashes, or SR tree content change.
- The compressed parity files live under `DecoderParity/` (not
  `Compressed/`) so the JPEG Lossless conformance-sample scanner keeps
  targeting real conformance files only.

## Purpose

Integration tests use these fixtures to verify:
- Different DICOM modalities (CT, MR, XR, US, etc.)
- Various transfer syntaxes (Little/Big Endian, Explicit/Implicit VR, compressed formats)
- Different image dimensions and bit depths
- Real-world DICOM files from medical imaging systems

## Quick Start

1. Use the committed synthetic fixtures for default tests.
2. Download optional public DICOM samples from sources below when running extended conformance tests.
3. Place optional files in this directory: `Tests/DicomCoreTests/Fixtures/`
4. Run integration tests: `swift test --filter Integration`

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

The library supports JPEG Lossless (Process 14, all selection values 0-7). To obtain test files:

1. **dcm4che** (recommended): Clone the dcm4che repository above; look for files with transfer syntax `1.2.840.10008.1.2.4.70`
2. **Convert existing files** with DCMTK: `dcmcjpeg +e14 input.dcm output_lossless.dcm`
3. **Verify**: `dcmdump --print-short file.dcm | grep "TransferSyntaxUID"` should show `1.2.840.10008.1.2.4.70`

## Directory Structure

Committed synthetic fixtures:

```
Fixtures/
├── CT/
│   └── ct_synthetic.dcm
├── MR/
│   └── mr_synthetic.dcm
├── XR/
│   └── xr_synthetic.dcm
├── US/
│   └── us_synthetic.dcm
├── Compressed/
│   └── jpeg_baseline_synthetic.dcm
└── DecoderParity/
    ├── ct_explicit_vr_le_rescale.dcm
    ├── ct_missing_optional_voi.dcm
    ├── mr_implicit_vr_le.dcm
    ├── mr_utf8_specific_charset.dcm
    ├── secondary_capture_rgb.dcm
    └── us_multiframe_metadata.dcm
```

Optional downloaded fixtures go into the matching modality folder (`CT/`, `MR/`, `XR/`, `US/`, `Compressed/`); additional local-only folders can be created as needed.

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

- **Do not commit** large or clinical DICOM files to the repository.
- Small synthetic fixtures listed in `Tests/DicomCoreTests/Resources/ReleaseGates/OptionalRuntimeFixtureManifest.json` and
  `Tests/DicomCoreTests/Resources/ReleaseGates/ClinicalParityFixtureManifest.json` are intentionally versioned.
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
- [pydicom Documentation](https://pydicom.github.io/)

---

**Note:** The committed fixtures are synthetic and non-PHI. Optional downloaded fixtures must remain local unless a
manifest explicitly approves them for version control.
