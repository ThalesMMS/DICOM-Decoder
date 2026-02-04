#!/bin/bash
#
# download_jpeg_lossless_conformance.sh
# Downloads JPEG Lossless conformance test files for real-world validation
#
# Usage:
#   ./download_jpeg_lossless_conformance.sh
#
# This script:
#   1. Downloads dcm4che test data repository
#   2. Finds JPEG Lossless DICOM files
#   3. Copies them to Tests/DicomCoreTests/Fixtures/Compressed/
#   4. Creates synthetic JPEG Lossless files for additional coverage
#
# Requirements:
#   - git
#   - dcmtk (for file conversion and verification)
#     Install: brew install dcmtk (macOS) or apt-get install dcmtk (Linux)

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR"
COMPRESSED_DIR="$FIXTURES_DIR/Compressed"
TEMP_DIR="$(mktemp -d)"

echo "=== JPEG Lossless Conformance Test Files Downloader ==="
echo ""
echo "Fixtures directory: $FIXTURES_DIR"
echo "Compressed directory: $COMPRESSED_DIR"
echo "Temporary directory: $TEMP_DIR"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up temporary directory..."
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Check for required tools
check_requirements() {
    echo "Checking requirements..."

    if ! command -v git &> /dev/null; then
        echo "❌ Error: git is not installed"
        exit 1
    fi
    echo "  ✓ git found"

    if ! command -v dcmdump &> /dev/null; then
        echo "⚠️  Warning: dcmtk not found. Install with: brew install dcmtk"
        echo "  Continuing without dcmtk (some features will be unavailable)"
        return
    fi
    echo "  ✓ dcmtk found"
}

# Create compressed directory if it doesn't exist
mkdir -p "$COMPRESSED_DIR"

check_requirements

# Step 1: Download dcm4che test data
echo ""
echo "=== Step 1: Downloading dcm4che test data ==="
echo ""

cd "$TEMP_DIR"

if [ -d "dcm4che" ]; then
    echo "dcm4che repository already exists, pulling latest..."
    cd dcm4che
    git pull
    cd ..
else
    echo "Cloning dcm4che repository (this may take a few minutes)..."
    git clone --depth 1 https://github.com/dcm4che/dcm4che.git
fi

echo "  ✓ dcm4che repository ready"

# Step 2: Find JPEG Lossless files
echo ""
echo "=== Step 2: Finding JPEG Lossless files ==="
echo ""

JPEG_LOSSLESS_FILES=()

if command -v dcmdump &> /dev/null; then
    echo "Scanning DICOM files for JPEG Lossless transfer syntax..."

    # Find all .dcm files in test data
    while IFS= read -r -d '' file; do
        # Check transfer syntax
        TRANSFER_SYNTAX=$(dcmdump --print-short "$file" 2>/dev/null | grep "(0002,0010)" | grep -o "1.2.840.10008.1.2.4.[57]0" || true)

        if [ -n "$TRANSFER_SYNTAX" ]; then
            JPEG_LOSSLESS_FILES+=("$file")
            echo "  Found: $(basename "$file") - Transfer Syntax: $TRANSFER_SYNTAX"
        fi
    done < <(find "$TEMP_DIR/dcm4che" -name "*.dcm" -print0 2>/dev/null || true)
else
    # Fallback: search by filename patterns
    echo "Searching for files with 'lossless' in filename..."

    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file")" == *lossless* ]]; then
            JPEG_LOSSLESS_FILES+=("$file")
            echo "  Found: $(basename "$file")"
        fi
    done < <(find "$TEMP_DIR/dcm4che" -name "*lossless*.dcm" -print0 2>/dev/null || true)
fi

echo ""
echo "Found ${#JPEG_LOSSLESS_FILES[@]} JPEG Lossless file(s)"

# Step 3: Copy files to fixtures
echo ""
echo "=== Step 3: Copying files to Fixtures/Compressed/ ==="
echo ""

COPY_COUNT=0

for file in "${JPEG_LOSSLESS_FILES[@]}"; do
    BASENAME=$(basename "$file")
    DEST="$COMPRESSED_DIR/$BASENAME"

    cp "$file" "$DEST"
    echo "  ✓ Copied: $BASENAME"
    COPY_COUNT=$((COPY_COUNT + 1))
done

if [ $COPY_COUNT -eq 0 ]; then
    echo "⚠️  No files copied from dcm4che repository"
    echo "  This may be because dcm4che doesn't include JPEG Lossless samples"
    echo "  We'll create synthetic test files instead"
fi

# Step 4: Create synthetic JPEG Lossless files
echo ""
echo "=== Step 4: Creating synthetic JPEG Lossless test files ==="
echo ""

if command -v dcmcjpeg &> /dev/null; then
    # Create synthetic uncompressed DICOM files and compress them

    # Check if we can use Python to create base files
    if command -v python3 &> /dev/null && python3 -c "import pydicom" 2>/dev/null; then
        echo "Creating synthetic base files with pydicom..."

        # Create synthetic CT file (512x512, 16-bit)
        python3 <<'PYTHON'
import pydicom
from pydicom.dataset import Dataset, FileDataset, FileMetaInformation
from pydicom.uid import generate_uid
import numpy as np
import sys
import os

temp_dir = os.environ.get('TEMP_DIR', '/tmp')

# Create 512x512 CT image
file_meta = FileMetaInformation()
file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
file_meta.MediaStorageSOPInstanceUID = generate_uid()
file_meta.TransferSyntaxUID = '1.2.840.10008.1.2.1'
file_meta.ImplementationClassUID = generate_uid()

ds = FileDataset(f"{temp_dir}/ct_base.dcm", {}, file_meta=file_meta, preamble=b"\0" * 128)
ds.PatientName = "CONFORMANCE^TEST^JPEGLOSSLESS"
ds.PatientID = "CONF001"
ds.Modality = "CT"
ds.SeriesInstanceUID = generate_uid()
ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
ds.StudyInstanceUID = generate_uid()
ds.Rows = 512
ds.Columns = 512
ds.BitsAllocated = 16
ds.BitsStored = 12
ds.HighBit = 11
ds.PixelRepresentation = 0
ds.SamplesPerPixel = 1
ds.PhotometricInterpretation = "MONOCHROME2"
ds.RescaleIntercept = -1024
ds.RescaleSlope = 1

# Create test pattern
pixels = np.zeros((512, 512), dtype=np.uint16)
pixels[:256, :256] = 0
pixels[:256, 256:] = 1024
pixels[256:, :256] = 2048
pixels[256:, 256:] = 4095
ds.PixelData = pixels.tobytes()

ds.save_as(f"{temp_dir}/ct_base.dcm")
print(f"Created {temp_dir}/ct_base.dcm")
PYTHON

        if [ -f "$TEMP_DIR/ct_base.dcm" ]; then
            echo "  ✓ Created synthetic CT base file"

            # Compress to JPEG Lossless Process 14
            dcmcjpeg +e14 "$TEMP_DIR/ct_base.dcm" "$COMPRESSED_DIR/synthetic_ct_jpeg_lossless_p14.dcm" 2>/dev/null

            if [ -f "$COMPRESSED_DIR/synthetic_ct_jpeg_lossless_p14.dcm" ]; then
                echo "  ✓ Created synthetic_ct_jpeg_lossless_p14.dcm"
                COPY_COUNT=$((COPY_COUNT + 1))
            fi
        fi

    else
        echo "⚠️  pydicom not available (install with: pip3 install pydicom)"
        echo "  Skipping synthetic file creation"
    fi

else
    echo "⚠️  dcmcjpeg not found (install dcmtk: brew install dcmtk)"
    echo "  Skipping synthetic file creation"
fi

# Step 5: Verify files
echo ""
echo "=== Step 5: Verifying downloaded files ==="
echo ""

VERIFIED_COUNT=0

if command -v dcmdump &> /dev/null; then
    for file in "$COMPRESSED_DIR"/*.dcm; do
        if [ -f "$file" ]; then
            BASENAME=$(basename "$file")
            TRANSFER_SYNTAX=$(dcmdump --print-short "$file" 2>/dev/null | grep "(0002,0010)" | grep -o "1.2.840.10008.1.2.4.[57]0" || true)

            if [ -n "$TRANSFER_SYNTAX" ]; then
                echo "  ✓ $BASENAME - Transfer Syntax: $TRANSFER_SYNTAX"
                VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
            fi
        fi
    done
else
    echo "  (Verification skipped - dcmtk not available)"
fi

# Summary
echo ""
echo "=== Summary ==="
echo ""
echo "Total files downloaded/created: $COPY_COUNT"
if command -v dcmdump &> /dev/null; then
    echo "JPEG Lossless files verified: $VERIFIED_COUNT"
fi
echo "Location: $COMPRESSED_DIR"
echo ""

if [ $COPY_COUNT -gt 0 ]; then
    echo "✅ Success! You can now run conformance tests with:"
    echo "   swift test --filter JPEGLosslessConformanceTests"
else
    echo "⚠️  No JPEG Lossless files were downloaded or created."
    echo ""
    echo "Alternative options:"
    echo "  1. Manually download from: https://github.com/dcm4che/dcm4che/tree/master/dcm4che-test-data"
    echo "  2. Convert existing DICOM files: dcmcjpeg +e14 input.dcm output.dcm"
    echo "  3. See Tests/DicomCoreTests/Fixtures/README.md for more options"
fi

echo ""
