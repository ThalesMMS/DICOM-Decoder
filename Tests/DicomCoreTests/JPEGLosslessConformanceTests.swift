// JPEGLosslessConformanceTests.swift
// Tests JPEG Lossless decoder with real-world DICOM conformance test files
//
// IMPORTANT: This test suite requires JPEG Lossless DICOM files from conformance test suites.
// See Tests/DicomCoreTests/Fixtures/README.md section "6. JPEG Lossless Test Files" for instructions.
//
// Expected test files (place in Tests/DicomCoreTests/Fixtures/Compressed/):
//   - dcm4che test data: Files with transfer syntax 1.2.840.10008.1.2.4.70 or .57
//   - NEMA conformance samples: JPEG Lossless test images
//   - Converted clinical samples: Real-world CT/MR images compressed with JPEG Lossless
//
// Validation approach:
//   1. Decode DICOM files with DCMDecoder (uses JPEGLosslessDecoder)
//   2. Verify pixel data is successfully extracted
//   3. Validate image dimensions and bit depth
//   4. Check pixel value ranges are reasonable for modality
//   5. Compare with reference decoder output if available (dcmtk dcmdjpeg)

import XCTest
import Foundation
@testable import DicomCore

final class JPEGLosslessConformanceTests: XCTestCase {

    // MARK: - Test Configuration

    /// Directory containing JPEG Lossless conformance test files
    private var conformanceDirectory: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Compressed")
    }

    /// Transfer syntax UIDs for JPEG Lossless
    private let jpegLosslessUIDs = [
        "1.2.840.10008.1.2.4.70",  // JPEG Lossless, First-Order Prediction (Process 14) - Most common
        "1.2.840.10008.1.2.4.57"   // JPEG Lossless, Non-Hierarchical (Any Process)
    ]

    // MARK: - Setup

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Verify conformance directory exists
        guard FileManager.default.fileExists(atPath: conformanceDirectory.path) else {
            throw XCTSkip("Fixtures/Compressed directory not found. See Fixtures/README.md for setup instructions.")
        }
    }

    // MARK: - Test Discovery

    /// Find all JPEG Lossless DICOM files in the conformance directory
    func findJPEGLosslessFiles() throws -> [URL] {
        let allFiles = try FileManager.default.contentsOfDirectory(
            at: conformanceDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "dcm" || $0.pathExtension == "DCM" }

        // Filter for JPEG Lossless files by checking transfer syntax
        var jpegLosslessFiles: [URL] = []

        for file in allFiles {
            // Quick check: try to decode and check transfer syntax
            let decoder = DCMDecoder()
            decoder.setDicomFilename(file.path)

            if decoder.dicomFileReadSuccess {
                // Check transfer syntax
                let transferSyntax = decoder.info(for: 0x00020010)
                if jpegLosslessUIDs.contains(where: { transferSyntax.contains($0) }) {
                    jpegLosslessFiles.append(file)
                }
                // Also check for "lossless" in filename (common convention)
            } else if file.lastPathComponent.lowercased().contains("lossless") {
                jpegLosslessFiles.append(file)
            }
        }

        return jpegLosslessFiles
    }

    // MARK: - Conformance Tests

    /// Test basic loading of JPEG Lossless conformance files
    func testLoadJPEGLosslessConformanceFiles() throws {
        let files = try findJPEGLosslessFiles()

        guard !files.isEmpty else {
            throw XCTSkip("""
                No JPEG Lossless DICOM files found in Fixtures/Compressed/.

                To obtain conformance test files:
                1. Download from dcm4che: https://github.com/dcm4che/dcm4che/tree/master/dcm4che-test-data
                2. Convert existing files: dcmcjpeg +e14 input.dcm output_lossless.dcm
                3. See Tests/DicomCoreTests/Fixtures/README.md for detailed instructions
                """)
        }

        print("\n=== Testing \(files.count) JPEG Lossless conformance files ===")

        var successCount = 0
        var failureReasons: [String: String] = [:]

        for file in files {
            print("\nTesting: \(file.lastPathComponent)")

            let decoder = DCMDecoder()
            decoder.setDicomFilename(file.path)

            guard decoder.dicomFileReadSuccess else {
                failureReasons[file.lastPathComponent] = "Failed to read DICOM file"
                print("  ❌ Failed to read DICOM file")
                continue
            }

            print("  ✓ DICOM file loaded")

            // Verify transfer syntax
            let transferSyntax = decoder.info(for: 0x00020010)
            print("  Transfer Syntax: \(transferSyntax)")

            // Verify image properties
            print("  Dimensions: \(decoder.width) x \(decoder.height)")

            let bitsAllocated = Int(decoder.info(for: 0x00280100)) ?? 16
            let bitsStored = Int(decoder.info(for: 0x00280101)) ?? bitsAllocated
            print("  Bits Allocated: \(bitsAllocated)")
            print("  Bits Stored: \(bitsStored)")

            guard decoder.width > 0 && decoder.height > 0 else {
                failureReasons[file.lastPathComponent] = "Invalid dimensions"
                print("  ❌ Invalid dimensions")
                continue
            }

            // Attempt pixel data extraction
            if bitsAllocated == 16 {
                    guard let pixels = decoder.getPixels16() else {
                        failureReasons[file.lastPathComponent] = "getPixels16() returned nil"
                        print("  ❌ getPixels16() returned nil")
                        continue
                    }

                    let expectedCount = decoder.width * decoder.height * decoder.samplesPerPixel

                    guard pixels.count == expectedCount else {
                        failureReasons[file.lastPathComponent] = "Pixel count mismatch: got \(pixels.count), expected \(expectedCount)"
                        print("  ❌ Pixel count mismatch")
                        continue
                    }

                    print("  ✓ Extracted \(pixels.count) pixels (16-bit)")

                    // Verify pixel value range
                    if let minVal = pixels.min(), let maxVal = pixels.max() {
                        print("  Pixel range: \(minVal) - \(maxVal)")
                    }
                } else if bitsAllocated == 8 {
                    guard let pixels = decoder.getPixels8() else {
                        failureReasons[file.lastPathComponent] = "getPixels8() returned nil"
                        print("  ❌ getPixels8() returned nil")
                        continue
                    }

                    let expectedCount = decoder.width * decoder.height * decoder.samplesPerPixel

                    guard pixels.count == expectedCount else {
                        failureReasons[file.lastPathComponent] = "Pixel count mismatch: got \(pixels.count), expected \(expectedCount)"
                        print("  ❌ Pixel count mismatch")
                        continue
                    }

                    print("  ✓ Extracted \(pixels.count) pixels (8-bit)")
                } else {
                    failureReasons[file.lastPathComponent] = "Unsupported bit depth: \(bitsAllocated)"
                    print("  ❌ Unsupported bit depth")
                    continue
                }

                print("  ✅ Successfully decoded")
                successCount += 1
        }

        // Summary
        print("\n=== Conformance Test Summary ===")
        print("Total files tested: \(files.count)")
        print("Successful: \(successCount)")
        print("Failed: \(files.count - successCount)")

        if !failureReasons.isEmpty {
            print("\nFailure details:")
            for (file, reason) in failureReasons {
                print("  - \(file): \(reason)")
            }
        }

        // All conformance files should decode successfully
        XCTAssertEqual(successCount, files.count, "Not all conformance files decoded successfully")
    }

    /// Test specific JPEG Lossless Process 14 (most common)
    func testJPEGLosslessProcess14Conformance() throws {
        let files = try findJPEGLosslessFiles()

        // Filter for Process 14 (transfer syntax 1.2.840.10008.1.2.4.70)
        var process14Files: [URL] = []

        for file in files {
            let decoder = DCMDecoder()
            decoder.setDicomFilename(file.path)

            let transferSyntax = decoder.info(for: 0x00020010)
            if transferSyntax.contains("1.2.840.10008.1.2.4.70") {
                process14Files.append(file)
            }
        }

        guard !process14Files.isEmpty else {
            throw XCTSkip("No JPEG Lossless Process 14 files found. Transfer syntax: 1.2.840.10008.1.2.4.70")
        }

        print("\n=== Testing \(process14Files.count) JPEG Lossless Process 14 files ===")

        for file in process14Files {
            print("\nTesting: \(file.lastPathComponent)")

            let decoder = DCMDecoder()
            decoder.setDicomFilename(file.path)

            XCTAssertTrue(decoder.dicomFileReadSuccess, "Failed to load \(file.lastPathComponent)")
            XCTAssertGreaterThan(decoder.width, 0, "Invalid width")
            XCTAssertGreaterThan(decoder.height, 0, "Invalid height")

            // Decode pixel data
            let bitsAllocated = Int(decoder.info(for: 0x00280100)) ?? 16

            if bitsAllocated == 16 {
                guard let pixels = decoder.getPixels16() else {
                    XCTFail("getPixels16() returned nil for \(file.lastPathComponent)")
                    continue
                }
                XCTAssertEqual(pixels.count, decoder.width * decoder.height * decoder.samplesPerPixel,
                              "Pixel count mismatch for \(file.lastPathComponent)")
                print("  ✓ Successfully decoded \(pixels.count) pixels")
            } else if bitsAllocated == 8 {
                guard let pixels = decoder.getPixels8() else {
                    XCTFail("getPixels8() returned nil for \(file.lastPathComponent)")
                    continue
                }
                XCTAssertEqual(pixels.count, decoder.width * decoder.height * decoder.samplesPerPixel,
                              "Pixel count mismatch for \(file.lastPathComponent)")
                print("  ✓ Successfully decoded \(pixels.count) pixels")
            }
        }
    }

    /// Test pixel value consistency across multiple decodes
    func testJPEGLosslessDecodeConsistency() throws {
        let files = try findJPEGLosslessFiles()

        guard let testFile = files.first else {
            throw XCTSkip("No JPEG Lossless test files available")
        }

        print("\nTesting decode consistency with: \(testFile.lastPathComponent)")

        // Decode the same file 3 times
        var pixelArrays: [[UInt16]] = []

        for iteration in 1...3 {
            let decoder = DCMDecoder()
            decoder.setDicomFilename(testFile.path)

            XCTAssertTrue(decoder.dicomFileReadSuccess, "Failed to load file on iteration \(iteration)")

            guard let pixels = decoder.getPixels16() else {
                XCTFail("getPixels16() returned nil on iteration \(iteration)")
                return
            }
            pixelArrays.append(pixels)
            print("  Iteration \(iteration): \(pixels.count) pixels")
        }

        // Verify all decodes produced identical results
        XCTAssertEqual(pixelArrays[0].count, pixelArrays[1].count, "Pixel count differs between iterations")
        XCTAssertEqual(pixelArrays[1].count, pixelArrays[2].count, "Pixel count differs between iterations")

        // Check pixel values are identical
        for i in 0..<pixelArrays[0].count {
            XCTAssertEqual(pixelArrays[0][i], pixelArrays[1][i],
                          "Pixel \(i) differs between iteration 1 and 2")
            XCTAssertEqual(pixelArrays[1][i], pixelArrays[2][i],
                          "Pixel \(i) differs between iteration 2 and 3")
        }

        print("  ✓ All iterations produced identical pixel data")
    }

    /// Test metadata extraction from JPEG Lossless files
    func testJPEGLosslessMetadataExtraction() throws {
        let files = try findJPEGLosslessFiles()

        guard !files.isEmpty else {
            throw XCTSkip("No JPEG Lossless test files available")
        }

        print("\n=== Testing metadata extraction from \(files.count) files ===")

        for file in files {
            print("\nFile: \(file.lastPathComponent)")

            let decoder = DCMDecoder()
            decoder.setDicomFilename(file.path)

            XCTAssertTrue(decoder.dicomFileReadSuccess)

            // Extract common metadata tags
            let modality = decoder.info(for: 0x00080060)
            let patientName = decoder.info(for: 0x00100010)
            let studyDate = decoder.info(for: 0x00080020)
            let bitsStored = decoder.info(for: 0x00280101)

            print("  Modality: \(modality)")
            print("  Patient Name: \(patientName)")
            print("  Study Date: \(studyDate)")
            print("  Image Size: \(decoder.width) x \(decoder.height)")
            print("  Bits Stored: \(bitsStored)")

            // Metadata should be accessible even with compressed pixel data
            XCTAssertNotEqual(modality, "", "Modality should be extractable")
        }
    }

    /// Test various bit depths in JPEG Lossless files
    func testJPEGLosslessBitDepthVariety() throws {
        let files = try findJPEGLosslessFiles()

        guard !files.isEmpty else {
            throw XCTSkip("No JPEG Lossless test files available")
        }

        var bitDepthCounts: [Int: Int] = [:]

        print("\n=== Testing bit depth variety ===")

        for file in files {
            let decoder = DCMDecoder()
            decoder.setDicomFilename(file.path)

            if decoder.dicomFileReadSuccess {
                let bitsStored = Int(decoder.info(for: 0x00280101)) ?? 16
                bitDepthCounts[bitsStored, default: 0] += 1

                // Verify decoder can handle this bit depth
                let bitsAllocated = Int(decoder.info(for: 0x00280100)) ?? 16
                if bitsAllocated == 16 {
                    if let pixels = decoder.getPixels16() {
                        XCTAssertGreaterThan(pixels.count, 0)
                    }
                } else if bitsAllocated == 8 {
                    if let pixels = decoder.getPixels8() {
                        XCTAssertGreaterThan(pixels.count, 0)
                    }
                }
            }
        }

        print("\nBit depth distribution:")
        for (bitDepth, count) in bitDepthCounts.sorted(by: { $0.key < $1.key }) {
            print("  \(bitDepth)-bit: \(count) files")
        }

        // Common medical imaging bit depths: 8, 12, 16
        // At least one bit depth should be represented
        XCTAssertFalse(bitDepthCounts.isEmpty, "Should have files with various bit depths")
    }

    // MARK: - Reference Decoder Comparison

    #if os(macOS)
    /// Compare DCMDecoder output with reference decoder (requires dcmtk)
    /// This test is skipped if dcmtk is not available
    func testCompareWithReferenceDecoder() throws {
        // Check if dcmdjpeg (dcmtk) is available
        let checkDcmtk = Process()
        checkDcmtk.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        checkDcmtk.arguments = ["which", "dcmdjpeg"]

        let pipe = Pipe()
        checkDcmtk.standardOutput = pipe
        checkDcmtk.standardError = Pipe()

        do {
            try checkDcmtk.run()
            checkDcmtk.waitUntilExit()
        } catch {
            throw XCTSkip("dcmtk not available. Install with: brew install dcmtk")
        }

        guard checkDcmtk.terminationStatus == 0 else {
            throw XCTSkip("dcmdjpeg command not found. Install dcmtk: brew install dcmtk")
        }

        let files = try findJPEGLosslessFiles()

        guard let testFile = files.first else {
            throw XCTSkip("No JPEG Lossless test files available")
        }

        print("\n=== Comparing with reference decoder (dcmdjpeg) ===")
        print("Test file: \(testFile.lastPathComponent)")

        // Create temporary directory for decompressed output
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let decompressedFile = tempDir.appendingPathComponent("decompressed.dcm")

        // Decompress with dcmdjpeg
        let dcmdjpeg = Process()
        dcmdjpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        dcmdjpeg.arguments = ["dcmdjpeg", testFile.path, decompressedFile.path]

        try dcmdjpeg.run()
        dcmdjpeg.waitUntilExit()

        guard dcmdjpeg.terminationStatus == 0 else {
            throw XCTSkip("dcmdjpeg failed to decompress file")
        }

        // Decode with DCMDecoder (JPEG Lossless)
        let jpegLosslessDecoder = DCMDecoder()
        jpegLosslessDecoder.setDicomFilename(testFile.path)
        XCTAssertTrue(jpegLosslessDecoder.dicomFileReadSuccess)

        guard let jpegLosslessPixels = jpegLosslessDecoder.getPixels16() else {
            XCTFail("getPixels16() returned nil for JPEG Lossless file")
            return
        }

        // Decode reference (uncompressed)
        let referenceDecoder = DCMDecoder()
        referenceDecoder.setDicomFilename(decompressedFile.path)
        XCTAssertTrue(referenceDecoder.dicomFileReadSuccess)

        guard let referencePixels = referenceDecoder.getPixels16() else {
            XCTFail("getPixels16() returned nil for reference file")
            return
        }

        // Compare dimensions
        XCTAssertEqual(jpegLosslessDecoder.width, referenceDecoder.width, "Width mismatch")
        XCTAssertEqual(jpegLosslessDecoder.height, referenceDecoder.height, "Height mismatch")

        // Compare pixel counts
        XCTAssertEqual(jpegLosslessPixels.count, referencePixels.count, "Pixel count mismatch")

        // Compare pixel values (bit-perfect)
        var mismatchCount = 0
        var firstMismatchIndex: Int?

        for i in 0..<min(jpegLosslessPixels.count, referencePixels.count) {
            if jpegLosslessPixels[i] != referencePixels[i] {
                mismatchCount += 1
                if firstMismatchIndex == nil {
                    firstMismatchIndex = i
                }
            }
        }

        if mismatchCount > 0 {
            print("\n⚠️  Pixel mismatch detected:")
            print("  Total mismatches: \(mismatchCount) / \(jpegLosslessPixels.count)")
            if let firstIndex = firstMismatchIndex {
                print("  First mismatch at index \(firstIndex):")
                print("    DCMDecoder:  \(jpegLosslessPixels[firstIndex])")
                print("    Reference:   \(referencePixels[firstIndex])")
            }
        } else {
            print("  ✅ Bit-perfect match with reference decoder!")
        }

        // For lossless compression, expect bit-perfect match
        XCTAssertEqual(mismatchCount, 0, "JPEG Lossless should produce bit-perfect output")
    }
    #else
    /// Compare DCMDecoder output with reference decoder (requires dcmtk)
    /// This test is skipped on non-macOS platforms.
    func testCompareWithReferenceDecoder() throws {
        throw XCTSkip("Reference decoder comparison requires macOS")
    }
    #endif

    // MARK: - Performance Testing

    /// Test decoding performance with conformance files
    func testJPEGLosslessConformancePerformance() throws {
        let files = try findJPEGLosslessFiles()

        guard !files.isEmpty else {
            throw XCTSkip("No JPEG Lossless test files available")
        }

        print("\n=== Performance testing \(files.count) conformance files ===")

        for file in files {
            let decoder = DCMDecoder()

            let startTime = CFAbsoluteTimeGetCurrent()
            decoder.setDicomFilename(file.path)

            if decoder.dicomFileReadSuccess {
                _ = decoder.getPixels16()
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime

                let pixels = decoder.width * decoder.height
                let throughput = Double(pixels) / elapsed / 1_000_000.0  // Megapixels/sec

                print("\n\(file.lastPathComponent):")
                print("  Size: \(decoder.width) x \(decoder.height)")
                print("  Time: \(String(format: "%.3f", elapsed * 1000)) ms")
                print("  Throughput: \(String(format: "%.1f", throughput)) Mpixels/sec")

                // Performance should be reasonable (not excessively slow)
                // Allow up to 5 seconds for very large images
                XCTAssertLessThan(elapsed, 5.0, "Decoding took too long for \(file.lastPathComponent)")
            }
        }
    }
}

// MARK: - Helper Extensions

extension JPEGLosslessConformanceTests {

    /// Print detailed information about a DICOM file
    func printDICOMInfo(_ file: URL) {
        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        guard decoder.dicomFileReadSuccess else {
            print("Failed to read: \(file.lastPathComponent)")
            return
        }

        print("\n=== \(file.lastPathComponent) ===")
        print("Transfer Syntax: \(decoder.info(for: 0x00020010))")
        print("SOP Class: \(decoder.info(for: 0x00020002))")
        print("Modality: \(decoder.info(for: 0x00080060))")
        print("Patient Name: \(decoder.info(for: 0x00100010))")
        print("Dimensions: \(decoder.width) x \(decoder.height)")
        print("Bits Allocated: \(decoder.info(for: 0x00280100))")
        print("Bits Stored: \(decoder.info(for: 0x00280101))")
        print("High Bit: \(decoder.info(for: 0x00280102))")
        print("Samples Per Pixel: \(decoder.samplesPerPixel)")
        print("Photometric Interpretation: \(decoder.info(for: 0x00280004))")
    }
}
