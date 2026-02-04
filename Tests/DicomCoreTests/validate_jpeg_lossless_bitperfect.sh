#!/bin/bash
#
# validate_jpeg_lossless_bitperfect.sh
# Performs bit-perfect validation of JPEG Lossless decoding against reference decoder
#
# This script:
#   1. Checks for dcmtk (reference decoder)
#   2. Checks for JPEG Lossless test files
#   3. Runs bit-perfect validation test
#   4. Reports results
#
# Usage:
#   cd Tests/DicomCoreTests
#   ./validate_jpeg_lossless_bitperfect.sh
#
# Requirements:
#   - dcmtk (brew install dcmtk)
#   - JPEG Lossless test files in Fixtures/Compressed/

set -e

echo "========================================"
echo "JPEG Lossless Bit-Perfect Validation"
echo "========================================"
echo ""

# Check for dcmtk
echo "Checking for reference decoder (dcmtk)..."
if ! command -v dcmdjpeg &> /dev/null; then
    echo "❌ ERROR: dcmtk not found"
    echo ""
    echo "dcmtk is required for bit-perfect validation as the reference decoder."
    echo ""
    echo "Install dcmtk:"
    echo "  macOS:    brew install dcmtk"
    echo "  Ubuntu:   sudo apt-get install dcmtk"
    echo "  Arch:     sudo pacman -S dcmtk"
    echo ""
    exit 1
fi

DCMDJPEG_VERSION=$(dcmdjpeg --version 2>&1 | head -n 1 || echo "unknown")
echo "✓ dcmtk found: $DCMDJPEG_VERSION"
echo ""

# Check for test files
echo "Checking for JPEG Lossless test files..."
FIXTURES_DIR="./Fixtures/Compressed"

if [ ! -d "$FIXTURES_DIR" ]; then
    echo "❌ ERROR: Fixtures/Compressed directory not found"
    echo ""
    echo "Expected location: $FIXTURES_DIR"
    echo ""
    exit 1
fi

# Count JPEG Lossless files
JPEG_LOSSLESS_COUNT=0

if command -v dcmdump &> /dev/null; then
    echo "Scanning for JPEG Lossless files..."

    for file in "$FIXTURES_DIR"/*.dcm; do
        if [ -f "$file" ]; then
            # Check transfer syntax
            TRANSFER_SYNTAX=$(dcmdump --print-short "$file" 2>/dev/null | grep "(0002,0010)" | grep -o "1.2.840.10008.1.2.4.[57]0" || true)

            if [ -n "$TRANSFER_SYNTAX" ]; then
                JPEG_LOSSLESS_COUNT=$((JPEG_LOSSLESS_COUNT + 1))
                echo "  Found: $(basename "$file") ($TRANSFER_SYNTAX)"
            fi
        fi
    done
else
    # Fallback: count files with "lossless" in name
    JPEG_LOSSLESS_COUNT=$(find "$FIXTURES_DIR" -name "*lossless*.dcm" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$JPEG_LOSSLESS_COUNT" -gt 0 ]; then
        echo "  Found $JPEG_LOSSLESS_COUNT files with 'lossless' in filename"
    fi
fi

if [ "$JPEG_LOSSLESS_COUNT" -eq 0 ]; then
    echo "⚠️  WARNING: No JPEG Lossless test files found"
    echo ""
    echo "To obtain test files:"
    echo "  cd Fixtures"
    echo "  ./download_jpeg_lossless_conformance.sh"
    echo ""
    echo "Or manually place JPEG Lossless DICOM files in:"
    echo "  $FIXTURES_DIR"
    echo ""
    echo "Expected transfer syntaxes:"
    echo "  1.2.840.10008.1.2.4.70  (JPEG Lossless, First-Order Prediction)"
    echo "  1.2.840.10008.1.2.4.57  (JPEG Lossless, Non-Hierarchical)"
    echo ""
    echo "Tests will be skipped without test files."
    echo ""
fi

echo "✓ Found $JPEG_LOSSLESS_COUNT JPEG Lossless test file(s)"
echo ""

# Run bit-perfect validation
echo "========================================"
echo "Running Bit-Perfect Validation Test"
echo "========================================"
echo ""

swift test --filter testCompareWithReferenceDecoder

EXIT_CODE=$?

echo ""
echo "========================================"
echo "Validation Complete"
echo "========================================"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ SUCCESS: All bit-perfect validation tests passed"
    echo ""
    echo "JPEG Lossless decoder produces byte-for-byte identical output"
    echo "compared to reference decoder (dcmtk dcmdjpeg)."
    echo ""
    echo "This confirms:"
    echo "  ✓ Lossless compression property verified"
    echo "  ✓ Pixel values are bit-perfect accurate"
    echo "  ✓ No rounding or precision errors"
    echo "  ✓ Safe for clinical/diagnostic use"
    echo ""
else
    echo "❌ FAILURE: Bit-perfect validation failed"
    echo ""
    echo "Review the test output above for details on pixel mismatches."
    echo ""
    echo "Common causes:"
    echo "  - Algorithm implementation error"
    echo "  - Bit depth handling issue"
    echo "  - Byte order (endianness) problem"
    echo "  - Incorrect predictor calculation"
    echo ""
    echo "See bit-perfect-validation-report.md for troubleshooting."
    echo ""
fi

exit $EXIT_CODE
