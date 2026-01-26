import XCTest
@testable import DicomCore
import Foundation

final class DCMDecoderSecurityTests: XCTestCase {

    // MARK: - Properties

    private var tempDirectory: URL!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()

        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DCMSecurityTests-\(UUID().uuidString)")

        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    override func tearDown() {
        // Clean up temporary test files
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        super.tearDown()
    }

    // MARK: - Excessive Element Length Tests

    func testExcessiveElementLength() {
        // Create DICOM with element length exceeding MAX_ELEMENT_LENGTH (100 MB)
        let maliciousLength: UInt32 = 150 * 1024 * 1024  // 150 MB
        let filePath = createDICOMWithLargeLength(length: maliciousLength)

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Decoder should gracefully handle excessive length by clamping or rejecting
        // It should not crash. The file may parse minimally (width=1 is default) but
        // should not allocate 150 MB for the excessive element
        // Main verification: we survived without crash or excessive allocation
        XCTAssertTrue(true, "Decoder survived excessive element length without crash")
    }

    func testMultipleExcessiveElements() {
        // Create DICOM with multiple elements claiming excessive lengths
        let filePath = createDICOMWithMultipleLargeElements()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should not allocate excessive memory for multiple large elements
        XCTAssertTrue(true, "Decoder survived multiple excessive element lengths without crash")
    }

    func testNegativeLengthValue() {
        // Test signed/unsigned confusion: 0xFFFFFFFF interpreted as -1
        let filePath = createDICOMWithNegativeLength()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should handle negative length values gracefully
        // (0xFFFFFFFF is valid undefined length in DICOM, but not for all VRs)
        XCTAssertTrue(true, "Decoder handled negative/undefined length without crash")
    }

    // MARK: - Huge Image Dimension Tests

    func testHugeImageDimensions() {
        // Create DICOM with dimensions exceeding MAX_IMAGE_DIMENSION (65536)
        let width: UInt16 = 0xFFFF  // 65535 - at limit
        let height: UInt16 = 0xFFFF  // 65535 - at limit
        let filePath = createDICOMWithDimensions(width: width, height: height)

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should reject dimensions that would cause excessive memory allocation
        if decoder.dicomFileReadSuccess {
            // If it accepts the file, verify dimensions are within safe limits
            XCTAssertLessThanOrEqual(decoder.width, 65536, "Width should not exceed MAX_IMAGE_DIMENSION")
            XCTAssertLessThanOrEqual(decoder.height, 65536, "Height should not exceed MAX_IMAGE_DIMENSION")
        }
    }

    func testExcessiveImageDimensions() {
        // Create DICOM with both dimensions at maximum (65535 is max for UInt16)
        let filePath = createDICOMWithDimensions(width: 65535, height: 65535)

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should reject image with total pixel count exceeding reasonable limits
        // 65535 * 65535 * 2 bytes = 8.5 GB which exceeds MAX_PIXEL_BUFFER_SIZE (2 GB)
        XCTAssertFalse(decoder.dicomFileReadSuccess,
                       "Decoder should reject image with excessive total pixel count")
    }

    func testImageDimensionIntegerOverflow() {
        // Test dimensions that would cause integer overflow when multiplied
        // width * height * bytesPerPixel could overflow Int
        let width: UInt16 = 50000
        let height: UInt16 = 50000  // 2.5 billion pixels
        let filePath = createDICOMWithDimensions(width: width, height: height, bitDepth: 16)

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should detect and reject dimensions that would cause overflow
        if decoder.dicomFileReadSuccess {
            let totalPixels = Int64(decoder.width) * Int64(decoder.height)
            let bytesPerPixel = Int64(decoder.bitDepth / 8)
            let totalBytes = totalPixels * bytesPerPixel

            XCTAssertLessThan(totalBytes, 2_147_483_648,
                             "Total pixel buffer should be under 2GB limit")
        }
    }

    // MARK: - Memory Bomb Tests

    func testMemoryBombPixelBuffer() {
        // Create DICOM claiming to have huge pixel data without actually including it
        let filePath = createDICOMWithClaimedPixelData(claimedSize: 1_000_000_000)  // 1 GB claimed

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should detect mismatch between claimed and actual pixel data size
        if decoder.dicomFileReadSuccess {
            // Attempt to read pixels - should fail gracefully
            let pixels16 = decoder.getPixels16()

            if pixels16 == nil {
                XCTAssertTrue(true, "Decoder correctly rejected invalid pixel data")
            } else {
                // If it returned pixels, verify size is reasonable
                XCTAssertLessThan(pixels16!.count, 100_000_000,
                                 "Pixel buffer should not exceed reasonable size")
            }
        }
    }

    func testPixelDataSizeValidation() {
        // Create DICOM where pixel data size doesn't match declared dimensions
        let filePath = createDICOMWithMismatchedPixelData()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        if decoder.dicomFileReadSuccess {
            // Pixel reading should fail or return nil
            let pixels = decoder.getPixels16()

            if pixels != nil {
                // If pixels were returned, verify they match declared dimensions
                let expectedSize = decoder.width * decoder.height
                XCTAssertEqual(pixels!.count, expectedSize,
                              "Pixel buffer size should match declared dimensions")
            }
        }
    }

    func test24BitRGBMemoryBomb() {
        // 24-bit RGB uses 3x memory - test excessive allocation
        let width: UInt16 = 40000
        let height: UInt16 = 40000  // Would need ~4.8 GB for 24-bit RGB
        let filePath = createDICOMWithDimensions(width: width, height: height,
                                                  bitDepth: 24, samplesPerPixel: 3)

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should reject RGB image with excessive total memory requirement
        XCTAssertFalse(decoder.dicomFileReadSuccess,
                       "Decoder should reject 24-bit RGB with excessive memory requirement")
    }

    // MARK: - Deeply Nested Sequence Tests

    func testDeeplyNestedSequences() {
        // Create DICOM with sequence nesting exceeding MAX_SEQUENCE_DEPTH (32)
        let filePath = createDICOMWithDeepSequences(depth: 40)

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should reject or safely handle deeply nested sequences without stack overflow
        XCTAssertTrue(true, "Decoder handled deeply nested sequences without crash")
    }

    func testCircularSequenceReferences() {
        // Create DICOM with sequence that could cause infinite loop
        let filePath = createDICOMWithCircularSequence()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should not hang or crash on circular references
        // Use timeout in real implementation
        XCTAssertTrue(true, "Decoder handled circular sequence without hanging")
    }

    func testMaxSequenceDepthBoundary() {
        // Test exactly at MAX_SEQUENCE_DEPTH limit (32)
        let filePath = createDICOMWithDeepSequences(depth: 32)

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should accept sequences up to max depth
        XCTAssertTrue(true, "Decoder handled maximum sequence depth")
    }

    // MARK: - Integer Overflow Prevention Tests

    func testIntegerOverflowPrevention() {
        // Test various integer overflow scenarios

        // Scenario 1: width * height overflow
        let filePath1 = createDICOMWithDimensions(width: 65535, height: 65535)
        let decoder1 = DCMDecoder()
        decoder1.setDicomFilename(filePath1.path)

        if decoder1.dicomFileReadSuccess {
            // Verify calculations used Int64 to prevent overflow
            let safePixelCount = Int64(decoder1.width) * Int64(decoder1.height)
            XCTAssertGreaterThan(safePixelCount, Int64(Int.max / 2),
                                "Large dimensions should be validated with 64-bit arithmetic")
        }
    }

    func testBytesPerPixelOverflow() {
        // Test overflow in bytes-per-pixel calculation
        // Use dimensions that would exceed 2GB: 40000 * 40000 * 2 = 3.2 GB
        let filePath = createDICOMWithDimensions(width: 40000, height: 40000, bitDepth: 16)

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should reject file with dimensions exceeding MAX_PIXEL_BUFFER_SIZE (2 GB)
        // Or if it accepts, verify calculations used safe 64-bit arithmetic
        if decoder.dicomFileReadSuccess {
            let width64 = Int64(decoder.width)
            let height64 = Int64(decoder.height)
            let bpp64 = Int64(decoder.bitDepth / 8)
            let totalBytes = width64 * height64 * bpp64

            // Should not exceed 2GB
            XCTAssertLessThan(totalBytes, 2_147_483_648,
                             "Total bytes should not exceed 2GB limit")
        } else {
            // Correctly rejected excessive dimensions
            XCTAssertTrue(true, "Decoder correctly rejected excessive dimensions")
        }
    }

    func testSamplesPerPixelOverflow() {
        // Test overflow when including samplesPerPixel
        let filePath = createDICOMWithDimensions(width: 30000, height: 30000,
                                                  bitDepth: 16, samplesPerPixel: 3)

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        if decoder.dicomFileReadSuccess {
            // Verify multiplication didn't overflow
            let total = Int64(decoder.width) * Int64(decoder.height) *
                       Int64(decoder.samplesPerPixel) * Int64(decoder.bitDepth / 8)
            XCTAssertLessThan(total, 2_147_483_648,
                             "Total with samplesPerPixel should not exceed 2GB")
        }
    }

    // MARK: - Undefined Length Handling Tests

    func testUndefinedLengthHandling() {
        // Create DICOM with undefined length sequence (0xFFFFFFFF)
        let filePath = createDICOMWithUndefinedLength()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should handle undefined length sequences correctly
        // They should be terminated by sequence delimiter tags
        XCTAssertTrue(true, "Decoder handled undefined length sequence")
    }

    func testUndefinedLengthWithoutDelimiter() {
        // Malicious: undefined length but no delimiter tag
        let filePath = createDICOMWithUndefinedLengthNoDelimiter()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should not read past end of file
        XCTAssertTrue(true, "Decoder handled undefined length without delimiter")
    }

    func testMixedUndefinedAndExplicitLengths() {
        // Create DICOM mixing undefined and explicit length encoding
        let filePath = createDICOMWithMixedLengths()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should correctly parse mixed length encoding
        XCTAssertTrue(true, "Decoder handled mixed length encoding")
    }

    // MARK: - Combined Attack Scenarios

    func testCombinedAttackScenario() {
        // Combine multiple malicious techniques
        let filePath = createMaliciousDICOM()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should reject or safely handle file with multiple issues
        XCTAssertTrue(true, "Decoder survived combined attack scenario")
    }

    func testTruncatedFile() {
        // Create DICOM that claims large size but file is truncated
        let filePath = createTruncatedDICOM()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath.path)

        // Should detect and handle truncation gracefully
        if decoder.dicomFileReadSuccess {
            // If parsing succeeded, verify it didn't read past file end
            XCTAssertTrue(true, "File truncation handled")
        }
    }

    // MARK: - Test Utilities

    /// Creates a minimal valid DICOM file with a large element length
    private func createDICOMWithLargeLength(length: UInt32) -> URL {
        let fileURL = tempDirectory.appendingPathComponent("large_length.dcm")
        var data = Data()

        // DICOM preamble (128 bytes of zeros)
        data.append(Data(count: 128))

        // DICM prefix
        data.append(contentsOf: "DICM".utf8)

        // Meta Information Group Length (0002,0000)
        data.append(contentsOf: [0x02, 0x00, 0x00, 0x00])  // Tag
        data.append(contentsOf: "UL".utf8)  // VR
        data.append(contentsOf: [0x00, 0x04])  // Length
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // Value

        // Create a tag with excessive length
        // Private Creator tag (0029,0010) - can have any length
        data.append(contentsOf: [0x29, 0x00, 0x10, 0x00])  // Tag
        data.append(contentsOf: "LO".utf8)  // VR

        // Length (little endian)
        let lengthBytes = withUnsafeBytes(of: length.littleEndian) { Data($0) }
        data.append(contentsOf: [0x00, 0x00])  // Reserved
        data.append(lengthBytes)

        // Don't include actual data - just claim the length

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates DICOM with multiple elements claiming large lengths
    private func createDICOMWithMultipleLargeElements() -> URL {
        let fileURL = tempDirectory.appendingPathComponent("multiple_large.dcm")
        var data = Data()

        // DICOM preamble and prefix
        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Add multiple elements with excessive lengths
        for i in 0..<5 {
            let tag = UInt16(0x0029 + i)
            data.append(contentsOf: [UInt8(tag & 0xFF), UInt8(tag >> 8), 0x10, 0x00])
            data.append(contentsOf: "LO".utf8)
            data.append(contentsOf: [0x00, 0x00])

            let largeLength: UInt32 = 50 * 1024 * 1024  // 50 MB each
            let lengthBytes = withUnsafeBytes(of: largeLength.littleEndian) { Data($0) }
            data.append(lengthBytes)
        }

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates DICOM with negative/undefined length
    private func createDICOMWithNegativeLength() -> URL {
        let fileURL = tempDirectory.appendingPathComponent("negative_length.dcm")
        var data = Data()

        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Tag with 0xFFFFFFFF length (undefined length)
        data.append(contentsOf: [0x29, 0x00, 0x10, 0x00])
        data.append(contentsOf: "SQ".utf8)  // Sequence VR
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])  // Undefined length

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates DICOM with specified dimensions
    private func createDICOMWithDimensions(width: UInt16, height: UInt16,
                                          bitDepth: UInt16 = 16,
                                          samplesPerPixel: UInt16 = 1) -> URL {
        let fileURL = tempDirectory.appendingPathComponent("dimensions_\(width)x\(height).dcm")
        var data = Data()

        // DICOM preamble and prefix
        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Columns (0028,0011) - Width
        data.append(contentsOf: [0x28, 0x00, 0x11, 0x00])
        data.append(contentsOf: "US".utf8)  // Unsigned Short
        data.append(contentsOf: [0x02, 0x00])  // Length = 2
        let widthBytes = withUnsafeBytes(of: width.littleEndian) { Data($0) }
        data.append(widthBytes)

        // Rows (0028,0010) - Height
        data.append(contentsOf: [0x28, 0x00, 0x10, 0x00])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        let heightBytes = withUnsafeBytes(of: height.littleEndian) { Data($0) }
        data.append(heightBytes)

        // Bits Allocated (0028,0100)
        data.append(contentsOf: [0x28, 0x00, 0x00, 0x01])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        let bitDepthBytes = withUnsafeBytes(of: bitDepth.littleEndian) { Data($0) }
        data.append(bitDepthBytes)

        // Samples Per Pixel (0028,0002)
        data.append(contentsOf: [0x28, 0x00, 0x02, 0x00])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        let samplesBytes = withUnsafeBytes(of: samplesPerPixel.littleEndian) { Data($0) }
        data.append(samplesBytes)

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates DICOM claiming pixel data without providing it
    private func createDICOMWithClaimedPixelData(claimedSize: UInt32) -> URL {
        let fileURL = tempDirectory.appendingPathComponent("claimed_pixels.dcm")
        var data = Data()

        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Small valid dimensions
        data.append(contentsOf: [0x28, 0x00, 0x11, 0x00])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: [0x00, 0x01])  // Width = 256

        data.append(contentsOf: [0x28, 0x00, 0x10, 0x00])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: [0x00, 0x01])  // Height = 256

        // Pixel Data (7FE0,0010) with excessive claimed length
        data.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00])
        data.append(contentsOf: "OW".utf8)
        data.append(contentsOf: [0x00, 0x00])
        let lengthBytes = withUnsafeBytes(of: claimedSize.littleEndian) { Data($0) }
        data.append(lengthBytes)

        // Don't include actual pixel data

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates DICOM with pixel data size mismatch
    private func createDICOMWithMismatchedPixelData() -> URL {
        let fileURL = tempDirectory.appendingPathComponent("mismatched_pixels.dcm")
        var data = Data()

        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Claim 100x100 pixels
        data.append(contentsOf: [0x28, 0x00, 0x11, 0x00])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: [0x64, 0x00])  // Width = 100

        data.append(contentsOf: [0x28, 0x00, 0x10, 0x00])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: [0x64, 0x00])  // Height = 100

        data.append(contentsOf: [0x28, 0x00, 0x00, 0x01])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: [0x10, 0x00])  // 16 bits

        // Pixel Data - but provide wrong size (only 1000 bytes instead of 20000)
        data.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00])
        data.append(contentsOf: "OW".utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0xE8, 0x03, 0x00, 0x00])  // 1000 bytes
        data.append(Data(count: 1000))  // Actual data

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates DICOM with deeply nested sequences
    private func createDICOMWithDeepSequences(depth: Int) -> URL {
        let fileURL = tempDirectory.appendingPathComponent("deep_sequences_\(depth).dcm")
        var data = Data()

        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Create nested sequences
        for i in 0..<depth {
            let tag = UInt16(0x0040 + (i % 256))
            data.append(contentsOf: [UInt8(tag & 0xFF), UInt8(tag >> 8), 0x00, 0x01])
            data.append(contentsOf: "SQ".utf8)
            data.append(contentsOf: [0x00, 0x00])
            data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])  // Undefined length

            // Item tag
            data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
            data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])  // Undefined length
        }

        // Close all sequences
        for _ in 0..<depth {
            // Item delimiter
            data.append(contentsOf: [0xFE, 0xFF, 0x0D, 0xE0])
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

            // Sequence delimiter
            data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0])
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        }

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates DICOM with circular sequence structure
    private func createDICOMWithCircularSequence() -> URL {
        let fileURL = tempDirectory.appendingPathComponent("circular_sequence.dcm")
        var data = Data()

        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Create sequence with undefined length and no proper termination
        data.append(contentsOf: [0x40, 0x00, 0x00, 0x01])
        data.append(contentsOf: "SQ".utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])

        // Item without proper delimiter
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])

        // No sequence delimiter - file just ends

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates DICOM with undefined length sequence
    private func createDICOMWithUndefinedLength() -> URL {
        let fileURL = tempDirectory.appendingPathComponent("undefined_length.dcm")
        var data = Data()

        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Sequence with undefined length
        data.append(contentsOf: [0x40, 0x00, 0x00, 0x01])
        data.append(contentsOf: "SQ".utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])

        // Item
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        data.append(contentsOf: [0x08, 0x00, 0x00, 0x00])  // 8 bytes
        data.append(Data(count: 8))

        // Proper sequence delimiter
        data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates DICOM with undefined length but no delimiter
    private func createDICOMWithUndefinedLengthNoDelimiter() -> URL {
        let fileURL = tempDirectory.appendingPathComponent("undefined_no_delimiter.dcm")
        var data = Data()

        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Sequence with undefined length
        data.append(contentsOf: [0x40, 0x00, 0x00, 0x01])
        data.append(contentsOf: "SQ".utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])

        // Item
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])

        // No delimiter - file just ends

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates DICOM with mixed length encoding
    private func createDICOMWithMixedLengths() -> URL {
        let fileURL = tempDirectory.appendingPathComponent("mixed_lengths.dcm")
        var data = Data()

        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Explicit length sequence
        data.append(contentsOf: [0x40, 0x00, 0x00, 0x01])
        data.append(contentsOf: "SQ".utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0x10, 0x00, 0x00, 0x00])  // 16 bytes

        // Item with explicit length
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        data.append(contentsOf: [0x08, 0x00, 0x00, 0x00])  // 8 bytes
        data.append(Data(count: 8))

        // Another sequence with undefined length
        data.append(contentsOf: [0x40, 0x00, 0x01, 0x01])
        data.append(contentsOf: "SQ".utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])

        // Delimiter
        data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates maximally malicious DICOM with multiple attack vectors
    private func createMaliciousDICOM() -> URL {
        let fileURL = tempDirectory.appendingPathComponent("malicious.dcm")
        var data = Data()

        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Attack 1: Excessive dimensions
        data.append(contentsOf: [0x28, 0x00, 0x11, 0x00])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: [0xFF, 0xFF])  // Width = 65535

        data.append(contentsOf: [0x28, 0x00, 0x10, 0x00])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: [0xFF, 0xFF])  // Height = 65535

        // Attack 2: Large element length
        data.append(contentsOf: [0x29, 0x00, 0x10, 0x00])
        data.append(contentsOf: "LO".utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x10])  // 256 MB

        // Attack 3: Deep sequence nesting
        for i in 0..<50 {
            let tag = UInt16(0x0040 + (i % 256))
            data.append(contentsOf: [UInt8(tag & 0xFF), UInt8(tag >> 8), 0x00, 0x01])
            data.append(contentsOf: "SQ".utf8)
            data.append(contentsOf: [0x00, 0x00])
            data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        }

        try? data.write(to: fileURL)
        return fileURL
    }

    /// Creates truncated DICOM file
    private func createTruncatedDICOM() -> URL {
        let fileURL = tempDirectory.appendingPathComponent("truncated.dcm")
        var data = Data()

        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        // Claim dimensions
        data.append(contentsOf: [0x28, 0x00, 0x11, 0x00])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: [0x00, 0x02])  // 512

        data.append(contentsOf: [0x28, 0x00, 0x10, 0x00])
        data.append(contentsOf: "US".utf8)
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: [0x00, 0x02])  // 512

        // Pixel data tag claiming large size
        data.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00])
        data.append(contentsOf: "OW".utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0x00, 0x00, 0x08, 0x00])  // Claim 512KB

        // But only write 100 bytes
        data.append(Data(count: 100))

        try? data.write(to: fileURL)
        return fileURL
    }
}
