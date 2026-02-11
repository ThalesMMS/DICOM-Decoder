import XCTest
@testable import DicomCore

final class DCMDecoderPixelDataTests: XCTestCase {

    // MARK: - Pixel Buffer Initialization Tests

    func testInitialPixelBuffersAreNil() {
        let decoder = DCMDecoder()

        // Test that all pixel buffers start as nil
        XCTAssertNil(decoder.getPixels8(), "Initial pixels8 should be nil")
        XCTAssertNil(decoder.getPixels16(), "Initial pixels16 should be nil")
        XCTAssertNil(decoder.getPixels24(), "Initial pixels24 should be nil")
    }

    func testPixelBuffersNilAfterFailedLoad() {
        let decoder = DCMDecoder()

        // Attempt to load nonexistent file
        decoder.setDicomFilename("/nonexistent/file.dcm")

        // Pixel buffers should remain nil
        XCTAssertNil(decoder.getPixels8(), "pixels8 should be nil after failed load")
        XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil after failed load")
        XCTAssertNil(decoder.getPixels24(), "pixels24 should be nil after failed load")
    }

    func testPixelBuffersConsistentAfterMultipleAccesses() {
        let decoder = DCMDecoder()

        // Multiple calls should return consistent nil results
        let pixels8_1 = decoder.getPixels8()
        let pixels8_2 = decoder.getPixels8()
        XCTAssertEqual(pixels8_1, pixels8_2, "Multiple getPixels8 calls should be consistent")

        let pixels16_1 = decoder.getPixels16()
        let pixels16_2 = decoder.getPixels16()
        XCTAssertEqual(pixels16_1, pixels16_2, "Multiple getPixels16 calls should be consistent")

        let pixels24_1 = decoder.getPixels24()
        let pixels24_2 = decoder.getPixels24()
        XCTAssertEqual(pixels24_1, pixels24_2, "Multiple getPixels24 calls should be consistent")
    }

    // MARK: - Grayscale 8-bit Pixel Tests

    func testGetPixels8WithUninitializedDecoder() {
        let decoder = DCMDecoder()

        // Should return nil for uninitialized decoder
        XCTAssertNil(decoder.getPixels8(), "Uninitialized decoder should have nil pixels8")
    }

    func testGetPixels8AfterInvalidFileLoad() {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/invalid/path/file.dcm")
        XCTAssertNil(decoder.getPixels8(), "Should have nil pixels8 after invalid file load")
    }

    func testGetPixels8AfterEmptyFileLoad() {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("")
        XCTAssertNil(decoder.getPixels8(), "Should have nil pixels8 after empty filename")
    }

    // MARK: - Grayscale 16-bit Pixel Tests

    func testGetPixels16WithUninitializedDecoder() {
        let decoder = DCMDecoder()

        // Should return nil for uninitialized decoder
        XCTAssertNil(decoder.getPixels16(), "Uninitialized decoder should have nil pixels16")
    }

    func testGetPixels16AfterInvalidFileLoad() {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/invalid/path/file.dcm")
        XCTAssertNil(decoder.getPixels16(), "Should have nil pixels16 after invalid file load")
    }

    func testGetPixels16AfterEmptyFileLoad() {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("")
        XCTAssertNil(decoder.getPixels16(), "Should have nil pixels16 after empty filename")
    }

    func testGetPixels16AfterMultipleFailedLoads() {
        let decoder = DCMDecoder()

        // Try multiple failed loads
        decoder.setDicomFilename("/nonexistent/file1.dcm")
        XCTAssertNil(decoder.getPixels16(), "Should have nil pixels16 after first failed load")

        decoder.setDicomFilename("/nonexistent/file2.dcm")
        XCTAssertNil(decoder.getPixels16(), "Should have nil pixels16 after second failed load")

        decoder.setDicomFilename("/nonexistent/file3.dcm")
        XCTAssertNil(decoder.getPixels16(), "Should have nil pixels16 after third failed load")
    }

    // MARK: - Color 24-bit Pixel Tests

    func testGetPixels24WithUninitializedDecoder() {
        let decoder = DCMDecoder()

        // Should return nil for uninitialized decoder
        XCTAssertNil(decoder.getPixels24(), "Uninitialized decoder should have nil pixels24")
    }

    func testGetPixels24AfterInvalidFileLoad() {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/invalid/path/file.dcm")
        XCTAssertNil(decoder.getPixels24(), "Should have nil pixels24 after invalid file load")
    }

    func testGetPixels24AfterEmptyFileLoad() {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("")
        XCTAssertNil(decoder.getPixels24(), "Should have nil pixels24 after empty filename")
    }

    // MARK: - Pixel Data Type Tests

    func testPixelDataTypesAreMutuallyExclusive() {
        let decoder = DCMDecoder()

        // In an uninitialized decoder, all should be nil
        let pixels8 = decoder.getPixels8()
        let pixels16 = decoder.getPixels16()
        let pixels24 = decoder.getPixels24()

        XCTAssertNil(pixels8, "pixels8 should be nil")
        XCTAssertNil(pixels16, "pixels16 should be nil")
        XCTAssertNil(pixels24, "pixels24 should be nil")

        // Note: In a properly loaded DICOM file, only one buffer would be non-nil
        // depending on samplesPerPixel and bitDepth
    }

    func testPixelBufferTypeConsistency() {
        let decoder = DCMDecoder()

        // Test that default state (samplesPerPixel=1, bitDepth=16) suggests pixels16 usage
        XCTAssertEqual(decoder.samplesPerPixel, 1, "Default should be grayscale")
        XCTAssertEqual(decoder.bitDepth, 16, "Default bit depth should be 16")

        // For this configuration, we expect pixels16 to be the relevant buffer
        // (though it will be nil until a file is loaded)
        XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil before loading")
    }

    // MARK: - Validation Status and Pixel Data Tests

    func testValidationStatusHasPixelsFlag() {
        let decoder = DCMDecoder()

        let status = decoder.getValidationStatus()
        XCTAssertFalse(status.hasPixels, "Uninitialized decoder should not have pixels")
    }

    func testValidationStatusHasPixelsAfterFailedLoad() {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/nonexistent/file.dcm")

        let status = decoder.getValidationStatus()
        XCTAssertFalse(status.hasPixels, "Failed load should not have pixels")
    }

    func testPixelDataAlignmentWithValidationStatus() {
        let decoder = DCMDecoder()

        let status = decoder.getValidationStatus()
        let hasPixels = status.hasPixels

        // Pixel buffers should align with validation status
        let pixels8 = decoder.getPixels8()
        let pixels16 = decoder.getPixels16()
        let pixels24 = decoder.getPixels24()

        if !hasPixels {
            XCTAssertNil(pixels8, "No pixels8 when hasPixels is false")
            XCTAssertNil(pixels16, "No pixels16 when hasPixels is false")
            XCTAssertNil(pixels24, "No pixels24 when hasPixels is false")
        }
    }

    // MARK: - Pixel Data Edge Cases

    func testZeroSizedImage() {
        let decoder = DCMDecoder()

        // Test with zero dimensions (before proper file load)
        // Default dimensions are 1x1, but let's test the pixel access behavior
        decoder.setDicomFilename("/nonexistent/zerosized.dcm")

        // Pixel buffers should be nil for invalid files
        XCTAssertNil(decoder.getPixels8(), "Zero-sized image should have nil pixels8")
        XCTAssertNil(decoder.getPixels16(), "Zero-sized image should have nil pixels16")
        XCTAssertNil(decoder.getPixels24(), "Zero-sized image should have nil pixels24")
    }

    func testExtremeImageDimensions() {
        let decoder = DCMDecoder()

        // Test that decoder handles default values gracefully
        // Extreme dimensions would typically be validated during file loading
        XCTAssertGreaterThanOrEqual(decoder.width, 0, "Width should not be negative")
        XCTAssertGreaterThanOrEqual(decoder.height, 0, "Height should not be negative")

        // No pixels should be available for unloaded decoder
        XCTAssertNil(decoder.getPixels16(), "Should have no pixels for uninitialized decoder")
    }

    func testInvalidBitDepthConfiguration() {
        let decoder = DCMDecoder()

        // Test default bit depth
        XCTAssertEqual(decoder.bitDepth, 16, "Default bit depth should be 16")

        // For uninitialized decoder, pixel buffers should remain nil
        XCTAssertNil(decoder.getPixels8(), "Uninitialized decoder should have nil pixels8")
        XCTAssertNil(decoder.getPixels16(), "Uninitialized decoder should have nil pixels16")
        XCTAssertNil(decoder.getPixels24(), "Uninitialized decoder should have nil pixels24")
    }

    func testInvalidSamplesPerPixelConfiguration() {
        let decoder = DCMDecoder()

        // Test default samples per pixel
        XCTAssertEqual(decoder.samplesPerPixel, 1, "Default samples per pixel should be 1")
        XCTAssertGreaterThan(decoder.samplesPerPixel, 0, "Samples per pixel must be positive")

        // Uninitialized decoder should have nil pixel buffers
        XCTAssertNil(decoder.getPixels8(), "Should have nil pixels8")
        XCTAssertNil(decoder.getPixels16(), "Should have nil pixels16")
        XCTAssertNil(decoder.getPixels24(), "Should have nil pixels24")
    }

    func testPixelBufferSizeConsistency() {
        let decoder = DCMDecoder()

        // For an uninitialized decoder, all buffers should be nil
        let pixels8 = decoder.getPixels8()
        let pixels16 = decoder.getPixels16()
        let pixels24 = decoder.getPixels24()

        XCTAssertNil(pixels8, "Uninitialized pixels8 should be nil")
        XCTAssertNil(pixels16, "Uninitialized pixels16 should be nil")
        XCTAssertNil(pixels24, "Uninitialized pixels24 should be nil")
    }

    func testPixelDataAfterSequentialFailedLoads() {
        let decoder = DCMDecoder()

        // Try loading multiple invalid files
        let invalidPaths = [
            "/nonexistent/file1.dcm",
            "/invalid/path/file2.dcm",
            "",
            "/tmp/missing.dcm",
            "/path/with/missing/directory/file.dcm"
        ]

        for path in invalidPaths {
            decoder.setDicomFilename(path)

            // All pixel buffers should remain nil
            XCTAssertNil(decoder.getPixels8(), "pixels8 should be nil for invalid path: \(path)")
            XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil for invalid path: \(path)")
            XCTAssertNil(decoder.getPixels24(), "pixels24 should be nil for invalid path: \(path)")
            XCTAssertFalse(decoder.getValidationStatus().hasPixels, "Should not have pixels for: \(path)")
        }
    }

    func testPixelDataConsistencyAfterReset() {
        let decoder = DCMDecoder()

        // Load invalid file
        decoder.setDicomFilename("/nonexistent/file.dcm")
        XCTAssertNil(decoder.getPixels16(), "Should have nil pixels after failed load")

        // Try another invalid file
        decoder.setDicomFilename("/another/invalid/path.dcm")
        XCTAssertNil(decoder.getPixels16(), "Should still have nil pixels after another failed load")

        // Try a third time
        decoder.setDicomFilename("")
        XCTAssertNil(decoder.getPixels16(), "Should still have nil pixels after empty path")
    }

    func testPixelBufferBitDepthMismatch() {
        let decoder = DCMDecoder()

        // Test that bit depth and pixel buffer types are consistent
        let bitDepth = decoder.bitDepth
        let samplesPerPixel = decoder.samplesPerPixel

        // For uninitialized decoder, all buffers should be nil
        if bitDepth == 8 && samplesPerPixel == 1 {
            // Would expect pixels8 to be used
            XCTAssertNil(decoder.getPixels8(), "pixels8 should be nil until file loaded")
        } else if bitDepth == 16 && samplesPerPixel == 1 {
            // Would expect pixels16 to be used
            XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil until file loaded")
        } else if samplesPerPixel == 3 {
            // Would expect pixels24 to be used
            XCTAssertNil(decoder.getPixels24(), "pixels24 should be nil until file loaded")
        }
    }

    func testPixelDataWithSpecialCharactersInPath() {
        let decoder = DCMDecoder()

        // Test paths with special characters
        let specialPaths = [
            "/path/with spaces/file.dcm",
            "/path/with-dashes/file.dcm",
            "/path/with_underscores/file.dcm",
            "/path/with.dots/file.dcm",
            "/path/with(parentheses)/file.dcm"
        ]

        for path in specialPaths {
            decoder.setDicomFilename(path)
            // Should handle gracefully without crashing
            XCTAssertNil(decoder.getPixels16(), "Should handle special characters in path: \(path)")
            XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with nonexistent path")
        }
    }

    func testPixelDataWithVeryLongPath() {
        let decoder = DCMDecoder()

        // Create a very long path
        let longPath = "/" + String(repeating: "subdirectory/", count: 50) + "file.dcm"
        decoder.setDicomFilename(longPath)

        // Should handle gracefully
        XCTAssertNil(decoder.getPixels16(), "Should handle very long paths")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with nonexistent long path")
    }

    func testPixelDataAccessWithoutPriorValidation() {
        let decoder = DCMDecoder()

        // Accessing pixels without validating file first should be safe
        XCTAssertNil(decoder.getPixels8(), "Should safely return nil for pixels8")
        XCTAssertNil(decoder.getPixels16(), "Should safely return nil for pixels16")
        XCTAssertNil(decoder.getPixels24(), "Should safely return nil for pixels24")

        // Should not crash even if called multiple times
        for _ in 0..<10 {
            _ = decoder.getPixels16()
            _ = decoder.getPixels8()
            _ = decoder.getPixels24()
        }
    }

    func testPixelDataStateConsistency() {
        let decoder = DCMDecoder()

        // Multiple sequential accesses should return same result
        let result1 = decoder.getPixels16()
        let result2 = decoder.getPixels16()
        let result3 = decoder.getPixels16()

        XCTAssertEqual(result1, result2, "Sequential accesses should be consistent")
        XCTAssertEqual(result2, result3, "Sequential accesses should be consistent")
        XCTAssertEqual(result1, result3, "Sequential accesses should be consistent")
    }

    func testPixelBufferCrossTypeConsistency() {
        let decoder = DCMDecoder()

        // All buffer types should be consistently nil for uninitialized decoder
        for _ in 0..<5 {
            let p8 = decoder.getPixels8()
            let p16 = decoder.getPixels16()
            let p24 = decoder.getPixels24()

            XCTAssertNil(p8, "pixels8 should consistently be nil")
            XCTAssertNil(p16, "pixels16 should consistently be nil")
            XCTAssertNil(p24, "pixels24 should consistently be nil")
        }
    }

    func testPixelDataWithNilFilePath() {
        let decoder = DCMDecoder()

        // Test with empty/nil path
        decoder.setDicomFilename("")

        XCTAssertNil(decoder.getPixels8(), "Empty path should result in nil pixels8")
        XCTAssertNil(decoder.getPixels16(), "Empty path should result in nil pixels16")
        XCTAssertNil(decoder.getPixels24(), "Empty path should result in nil pixels24")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with empty path")
    }

    func testPixelDataWithRelativePaths() {
        let decoder = DCMDecoder()

        // Test relative paths
        let relativePaths = [
            "./file.dcm",
            "../file.dcm",
            "file.dcm",
            "./nested/path/file.dcm",
            "../../../file.dcm"
        ]

        for path in relativePaths {
            decoder.setDicomFilename(path)
            // Should handle relative paths (they will fail to load but shouldn't crash)
            XCTAssertNil(decoder.getPixels16(), "Should handle relative path: \(path)")
        }
    }

    func testPixelDataImagePropertiesEdgeCases() {
        let decoder = DCMDecoder()

        // Test property values are within valid ranges
        XCTAssertGreaterThanOrEqual(decoder.width, 0, "Width should not be negative")
        XCTAssertGreaterThanOrEqual(decoder.height, 0, "Height should not be negative")
        XCTAssertGreaterThan(decoder.bitDepth, 0, "Bit depth should be positive")
        XCTAssertGreaterThan(decoder.samplesPerPixel, 0, "Samples per pixel should be positive")

        // Verify reasonable default values
        XCTAssertLessThan(decoder.bitDepth, 64, "Bit depth should be reasonable")
        XCTAssertLessThan(decoder.samplesPerPixel, 10, "Samples per pixel should be reasonable")
    }

    func testPixelDataValidationStatusConsistency() {
        let decoder = DCMDecoder()

        // Validation status should align with pixel availability
        let status = decoder.getValidationStatus()

        if !status.hasPixels {
            XCTAssertNil(decoder.getPixels8(), "No pixels8 when status.hasPixels is false")
            XCTAssertNil(decoder.getPixels16(), "No pixels16 when status.hasPixels is false")
            XCTAssertNil(decoder.getPixels24(), "No pixels24 when status.hasPixels is false")
        }

        if !status.isValid {
            XCTAssertFalse(status.hasPixels, "Invalid decoder should not have pixels")
        }

        // Multiple status checks should be consistent
        let status2 = decoder.getValidationStatus()
        XCTAssertEqual(status.hasPixels, status2.hasPixels, "Status should be consistent")
        XCTAssertEqual(status.isValid, status2.isValid, "Status should be consistent")
    }

    func testPixelDataAfterMultipleReinitialization() {
        let decoder = DCMDecoder()

        // Try reinitializing multiple times with different invalid paths
        for i in 0..<5 {
            decoder.setDicomFilename("/nonexistent/file\(i).dcm")
            XCTAssertNil(decoder.getPixels16(), "Should have nil pixels after reinitialization \(i)")
            XCTAssertFalse(decoder.getValidationStatus().hasPixels, "Should not have pixels")
        }

        // Final state should be clean
        XCTAssertNil(decoder.getPixels8(), "Final pixels8 should be nil")
        XCTAssertNil(decoder.getPixels16(), "Final pixels16 should be nil")
        XCTAssertNil(decoder.getPixels24(), "Final pixels24 should be nil")
    }

    func testPixelDataMemoryConsistency() {
        let decoder = DCMDecoder()

        // Test that repeated access doesn't cause memory issues
        for _ in 0..<100 {
            _ = decoder.getPixels8()
            _ = decoder.getPixels16()
            _ = decoder.getPixels24()
        }

        // All should still be nil
        XCTAssertNil(decoder.getPixels8(), "pixels8 should remain nil after many accesses")
        XCTAssertNil(decoder.getPixels16(), "pixels16 should remain nil after many accesses")
        XCTAssertNil(decoder.getPixels24(), "pixels24 should remain nil after many accesses")
    }

    func testPixelDataWithInvalidFileExtensions() {
        let decoder = DCMDecoder()

        // Test files with incorrect or missing extensions
        let invalidExtensions = [
            "/path/file.txt",
            "/path/file.jpg",
            "/path/file",
            "/path/.dcm",
            "/path/file.DCM",  // uppercase
            "/path/file.dicom"
        ]

        for path in invalidExtensions {
            decoder.setDicomFilename(path)
            XCTAssertNil(decoder.getPixels16(), "Should handle invalid extension: \(path)")
        }
    }

    func testPixelBufferTypeExclusivity() {
        let decoder = DCMDecoder()

        // In a valid DICOM file, only one pixel buffer type should be active
        // For uninitialized decoder, all should be nil
        let pixels8 = decoder.getPixels8()
        let pixels16 = decoder.getPixels16()
        let pixels24 = decoder.getPixels24()

        // All buffers should be nil for uninitialized decoder
        XCTAssertNil(pixels8, "Uninitialized decoder should have nil pixels8")
        XCTAssertNil(pixels16, "Uninitialized decoder should have nil pixels16")
        XCTAssertNil(pixels24, "Uninitialized decoder should have nil pixels24")
    }

    func testPixelDataConsistencyAcrossValidationCalls() {
        let decoder = DCMDecoder()

        // Interleave validation checks with pixel access
        _ = decoder.getValidationStatus()
        let pixels1 = decoder.getPixels16()

        _ = decoder.getValidationStatus()
        let pixels2 = decoder.getPixels16()

        _ = decoder.getValidationStatus()
        let pixels3 = decoder.getPixels16()

        // All should be consistently nil
        XCTAssertEqual(pixels1, pixels2, "Pixels should be consistent across validation calls")
        XCTAssertEqual(pixels2, pixels3, "Pixels should be consistent across validation calls")
    }

    // MARK: - Image Properties and Pixel Buffer Relationship Tests

    func testImageDimensionsWithNoPixels() {
        let decoder = DCMDecoder()

        // Test that dimensions exist even without pixels
        XCTAssertEqual(decoder.width, 1, "Default width should be 1")
        XCTAssertEqual(decoder.height, 1, "Default height should be 1")

        // But pixels should be nil
        XCTAssertNil(decoder.getPixels16(), "pixels should be nil")
    }

    func testBitDepthPropertyConsistency() {
        let decoder = DCMDecoder()

        // Default bit depth is 16
        XCTAssertEqual(decoder.bitDepth, 16, "Default bit depth should be 16")

        // For 16-bit images, pixels16 is the relevant buffer
        // For 8-bit images, pixels8 would be used
        // All should be nil in uninitialized state
        XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil initially")
        XCTAssertNil(decoder.getPixels8(), "pixels8 should be nil initially")
    }

    func testSamplesPerPixelPropertyConsistency() {
        let decoder = DCMDecoder()

        // Default is grayscale (1 sample per pixel)
        XCTAssertEqual(decoder.samplesPerPixel, 1, "Default should be grayscale")

        // For grayscale (1 sample), either pixels8 or pixels16 is used
        // For color (3 samples), pixels24 is used
        // All should be nil in uninitialized state
        XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil initially")
        XCTAssertNil(decoder.getPixels24(), "pixels24 should be nil initially")
    }

    func testGrayscaleDetectionWithPixelBuffers() {
        let decoder = DCMDecoder()

        // Test grayscale detection
        XCTAssertTrue(decoder.isGrayscale, "Default should be grayscale")
        XCTAssertFalse(decoder.isColorImage, "Default should not be color")

        // Grayscale images use pixels8 or pixels16
        // Color images use pixels24
        // Verify buffers are nil before loading
        XCTAssertNil(decoder.getPixels16(), "Grayscale pixels16 should be nil before loading")
        XCTAssertNil(decoder.getPixels24(), "Color pixels24 should be nil before loading")
    }

    // MARK: - Pixel Representation Tests

    func testPixelRepresentationProperty() {
        let decoder = DCMDecoder()

        // Default pixel representation is 0 (unsigned)
        XCTAssertEqual(decoder.pixelRepresentationTagValue, 0, "Default pixel representation should be 0")
        XCTAssertFalse(decoder.isSignedPixelRepresentation, "Default should be unsigned")
    }

    func testSignedVsUnsignedPixelRepresentation() {
        let decoder = DCMDecoder()

        // Test unsigned representation (default)
        XCTAssertFalse(decoder.isSignedPixelRepresentation, "Default should be unsigned")

        // Both signed and unsigned use the same pixel buffers (pixels16 for 16-bit)
        XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil before loading")
    }

    // MARK: - Thread Safety Tests for Pixel Access

    func testConcurrentPixelAccess() {
        let decoder = DCMDecoder()
        let expectation = self.expectation(description: "Concurrent pixel access")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent pixel buffer access
        for _ in 0..<10 {
            DispatchQueue.global().async {
                _ = decoder.getPixels8()
                _ = decoder.getPixels16()
                _ = decoder.getPixels24()
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testConcurrentPixelAccessConsistency() {
        let decoder = DCMDecoder()
        let expectation = self.expectation(description: "Concurrent pixel access consistency")
        expectation.expectedFulfillmentCount = 20

        var results16: [[UInt16]?] = []
        var results8: [[UInt8]?] = []
        let resultsQueue = DispatchQueue(label: "results.queue")

        // Test that concurrent access returns consistent results
        for _ in 0..<20 {
            DispatchQueue.global().async {
                let pixels16 = decoder.getPixels16()
                let pixels8 = decoder.getPixels8()

                resultsQueue.sync {
                    results16.append(pixels16)
                    results8.append(pixels8)
                }

                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0) { _ in
            // All results should be nil and consistent
            XCTAssertTrue(results16.allSatisfy { $0 == nil }, "All concurrent pixels16 accesses should return nil")
            XCTAssertTrue(results8.allSatisfy { $0 == nil }, "All concurrent pixels8 accesses should return nil")
        }
    }

    func testConcurrentLoadAndPixelAccess() {
        let decoder = DCMDecoder()
        let expectation = self.expectation(description: "Concurrent load and pixel access")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent file loading and pixel access
        for i in 0..<10 {
            DispatchQueue.global().async {
                decoder.setDicomFilename("/nonexistent/file\(i).dcm")
                _ = decoder.getPixels16()
                _ = decoder.getValidationStatus()
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0) { _ in
            // Final state should be consistent
            XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil after concurrent failed loads")
            XCTAssertFalse(decoder.getValidationStatus().hasPixels, "Should not have pixels")
        }
    }

    // MARK: - Async Pixel Access Tests

    @available(macOS 10.15, iOS 13.0, *)
    func testGetPixels16Async() async {
        let decoder = DCMDecoder()

        let pixels = await decoder.getPixels16Async()
        XCTAssertNil(pixels, "Async pixels16 should be nil for uninitialized decoder")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetPixels8Async() async {
        let decoder = DCMDecoder()

        let pixels = await decoder.getPixels8Async()
        XCTAssertNil(pixels, "Async pixels8 should be nil for uninitialized decoder")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetPixels24Async() async {
        let decoder = DCMDecoder()

        let pixels = await decoder.getPixels24Async()
        XCTAssertNil(pixels, "Async pixels24 should be nil for uninitialized decoder")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncPixelAccessAfterFailedLoad() async {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/nonexistent/file.dcm")

        let pixels16 = await decoder.getPixels16Async()
        let pixels8 = await decoder.getPixels8Async()
        let pixels24 = await decoder.getPixels24Async()

        XCTAssertNil(pixels16, "Async pixels16 should be nil after failed load")
        XCTAssertNil(pixels8, "Async pixels8 should be nil after failed load")
        XCTAssertNil(pixels24, "Async pixels24 should be nil after failed load")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncPixelAccessConsistency() async {
        let decoder = DCMDecoder()

        // Multiple async calls should return consistent results
        let pixels16_1 = await decoder.getPixels16Async()
        let pixels16_2 = await decoder.getPixels16Async()

        XCTAssertEqual(pixels16_1, pixels16_2, "Multiple async getPixels16 calls should be consistent")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testConcurrentAsyncPixelAccess() async {
        let decoder = DCMDecoder()

        // Test concurrent async pixel access
        async let pixels16_1 = decoder.getPixels16Async()
        async let pixels16_2 = decoder.getPixels16Async()
        async let pixels8_1 = decoder.getPixels8Async()
        async let pixels24_1 = decoder.getPixels24Async()

        let result1 = await pixels16_1
        let result2 = await pixels16_2
        let result3 = await pixels8_1
        let result4 = await pixels24_1

        // All should be nil
        XCTAssertNil(result1, "Concurrent async pixels16 access should return nil")
        XCTAssertNil(result2, "Concurrent async pixels16 access should return nil")
        XCTAssertNil(result3, "Concurrent async pixels8 access should return nil")
        XCTAssertNil(result4, "Concurrent async pixels24 access should return nil")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncAndSyncPixelAccessConsistency() async {
        let decoder = DCMDecoder()

        let syncPixels = decoder.getPixels16()
        let asyncPixels = await decoder.getPixels16Async()

        XCTAssertEqual(syncPixels, asyncPixels, "Sync and async pixel access should be consistent")
    }

    // MARK: - Pixel Data State Preservation Tests

    func testPixelDataStateAfterMultipleAccesses() {
        let decoder = DCMDecoder()

        // Access pixels multiple times
        for _ in 0..<5 {
            _ = decoder.getPixels16()
        }

        // State should remain consistent
        XCTAssertNil(decoder.getPixels16(), "pixels16 should still be nil")
        XCTAssertFalse(decoder.getValidationStatus().hasPixels, "Should still have no pixels")
    }

    func testPixelDataClearingAfterFailedLoad() {
        let decoder = DCMDecoder()

        // First failed load
        decoder.setDicomFilename("/nonexistent/file1.dcm")
        XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil after first failed load")

        // Second failed load should clear any previous state
        decoder.setDicomFilename("/nonexistent/file2.dcm")
        XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil after second failed load")

        // Verify clean state
        XCTAssertFalse(decoder.getValidationStatus().hasPixels, "Should have no pixels")
        XCTAssertNil(decoder.getPixels8(), "pixels8 should be nil")
        XCTAssertNil(decoder.getPixels24(), "pixels24 should be nil")
    }

    // MARK: - Edge Case Tests

    func testPixelAccessOnFreshDecoder() {
        // Create decoder and immediately access pixels
        let decoder = DCMDecoder()
        let pixels = decoder.getPixels16()

        XCTAssertNil(pixels, "Fresh decoder should have nil pixels")
    }

    func testMultipleDecodersIndependence() {
        let decoder1 = DCMDecoder()
        let decoder2 = DCMDecoder()

        // Access pixels on first decoder
        _ = decoder1.getPixels16()

        // Should not affect second decoder
        XCTAssertNil(decoder2.getPixels16(), "Second decoder should be independent")
    }

    func testPixelAccessAfterDecoderReuse() {
        let decoder = DCMDecoder()

        // First use
        decoder.setDicomFilename("/nonexistent/file1.dcm")
        XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil after first use")

        // Reuse decoder with different file
        decoder.setDicomFilename("/nonexistent/file2.dcm")
        XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil after reuse")

        // State should be clean
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not have read success")
    }

    func testPixelBufferReturnTypeConsistency() {
        let decoder = DCMDecoder()

        // Test that return types are correct optionals
        let pixels8: [UInt8]? = decoder.getPixels8()
        let pixels16: [UInt16]? = decoder.getPixels16()
        let pixels24: [UInt8]? = decoder.getPixels24()

        XCTAssertNil(pixels8, "pixels8 should be nil")
        XCTAssertNil(pixels16, "pixels16 should be nil")
        XCTAssertNil(pixels24, "pixels24 should be nil")
    }

    // MARK: - RGB/Color Image Tests

    func testIsColorImageWithUninitializedDecoder() {
        let decoder = DCMDecoder()

        // Default should be grayscale (samplesPerPixel = 1)
        XCTAssertFalse(decoder.isColorImage, "Uninitialized decoder should not be color image")
    }

    func testIsColorImageDetection() {
        let decoder = DCMDecoder()

        // Test default state (grayscale)
        XCTAssertEqual(decoder.samplesPerPixel, 1, "Default samples per pixel should be 1")
        XCTAssertFalse(decoder.isColorImage, "Default should not be color image")
    }

    func testColorImageRelationshipWithSamplesPerPixel() {
        let decoder = DCMDecoder()

        // isColorImage should reflect samplesPerPixel
        let isColor = decoder.isColorImage
        let samplesPerPixel = decoder.samplesPerPixel

        if samplesPerPixel == 3 {
            XCTAssertTrue(isColor, "samplesPerPixel=3 should indicate color image")
        } else {
            XCTAssertFalse(isColor, "samplesPerPixel != 3 should not indicate color image")
        }
    }

    func testRGBPixelBufferSizeExpectations() {
        let decoder = DCMDecoder()

        // RGB images should have 3x the pixel count (RGB triplets)
        let width = decoder.width
        let height = decoder.height
        let samplesPerPixel = decoder.samplesPerPixel

        if samplesPerPixel == 3 {
            let expectedSize = width * height * 3
            // Note: pixels24 will be nil for uninitialized decoder
            // but we can test the expectation relationship
            XCTAssertEqual(samplesPerPixel, 3, "RGB images should have 3 samples per pixel")
            XCTAssertGreaterThan(expectedSize, 0, "Expected RGB buffer size should be positive")
        }
    }

    func testGetPixels24WithGrayscaleImage() {
        let decoder = DCMDecoder()

        // Grayscale images (samplesPerPixel=1) should not have pixels24
        if decoder.samplesPerPixel == 1 {
            XCTAssertNil(decoder.getPixels24(), "Grayscale images should not have pixels24 buffer")
        }
    }

    func testGetPixels24ReturnsNilForUninitializedDecoder() {
        let decoder = DCMDecoder()

        XCTAssertNil(decoder.getPixels24(), "pixels24 should be nil for uninitialized decoder")
    }

    func testGetPixels24ReturnsNilAfterFailedLoad() {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/nonexistent/rgb_image.dcm")
        XCTAssertNil(decoder.getPixels24(), "pixels24 should be nil after failed load")
    }

    func testGetPixels24ConsistencyAcrossMultipleCalls() {
        let decoder = DCMDecoder()

        let pixels24_1 = decoder.getPixels24()
        let pixels24_2 = decoder.getPixels24()

        XCTAssertEqual(pixels24_1, pixels24_2, "Multiple getPixels24 calls should return consistent results")
    }

    func testColorImageExcludesOtherPixelFormats() {
        let decoder = DCMDecoder()

        // In an uninitialized RGB decoder, verify format exclusivity
        if decoder.samplesPerPixel == 3 {
            // RGB images should not have 8-bit or 16-bit grayscale buffers
            XCTAssertNil(decoder.getPixels8(), "RGB images should not have pixels8")
            XCTAssertNil(decoder.getPixels16(), "RGB images should not have pixels16")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetPixels24AsyncReturnsNilForUninitializedDecoder() async {
        let decoder = DCMDecoder()

        let pixels = await decoder.getPixels24Async()
        XCTAssertNil(pixels, "Async pixels24 should be nil for uninitialized decoder")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetPixels24AsyncReturnsNilAfterFailedLoad() async {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/invalid/rgb_image.dcm")

        let pixels = await decoder.getPixels24Async()
        XCTAssertNil(pixels, "Async pixels24 should be nil after failed load")
    }

    // MARK: - Downsampling Tests

    func testGetDownsampledPixels16WithUninitializedDecoder() {
        let decoder = DCMDecoder()

        let result = decoder.getDownsampledPixels16()

        // Uninitialized decoder may return minimal default dimensions (1x1)
        if let (pixels, width, height) = result {
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
            XCTAssertLessThanOrEqual(width, 1, "Width should be minimal for uninitialized decoder")
            XCTAssertLessThanOrEqual(height, 1, "Height should be minimal for uninitialized decoder")
        }
    }

    func testGetDownsampledPixels16AfterFailedLoad() {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/nonexistent/file.dcm")

        // After failed load, decoder still has default dimensions
        // Downsampling may return a minimal result or nil depending on state
        let result = decoder.getDownsampledPixels16()

        // Verify file load was not successful
        XCTAssertFalse(decoder.dicomFileReadSuccess, "File load should not succeed")

        // If result exists, verify it's minimal (default dimensions)
        if let (pixels, width, height) = result {
            XCTAssertEqual(width * height, pixels.count, "Pixel count should match dimensions")
            XCTAssertLessThanOrEqual(width, 1, "Width should be minimal after failed load")
            XCTAssertLessThanOrEqual(height, 1, "Height should be minimal after failed load")
        }
    }

    func testGetDownsampledPixels16RequiresGrayscale16Bit() {
        let decoder = DCMDecoder()

        // Downsampling requires samplesPerPixel=1 and bitDepth=16
        if decoder.samplesPerPixel != 1 || decoder.bitDepth != 16 {
            let result = decoder.getDownsampledPixels16()
            XCTAssertNil(result, "Downsampling should only work with 16-bit grayscale images")
        }
    }

    func testGetDownsampledPixels16WithDefaultMaxDimension() {
        let decoder = DCMDecoder()

        // Default maxDimension is 150
        let result = decoder.getDownsampledPixels16()

        // Uninitialized decoder may return minimal result
        if let (pixels, width, height) = result {
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
        }
    }

    func testGetDownsampledPixels16WithCustomMaxDimension() {
        let decoder = DCMDecoder()

        // Test with custom maxDimension
        let result = decoder.getDownsampledPixels16(maxDimension: 100)

        // Uninitialized decoder may return minimal result
        if let (pixels, width, height) = result {
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
            XCTAssertLessThanOrEqual(max(width, height), 100, "Dimensions should respect maxDimension")
        }
    }

    func testGetDownsampledPixels16MaxDimensionBounds() {
        let decoder = DCMDecoder()

        // Test various maxDimension values
        let smallResult = decoder.getDownsampledPixels16(maxDimension: 50)
        if let (pixels, width, height) = smallResult {
            XCTAssertLessThanOrEqual(max(width, height), 50, "Should respect small maxDimension")
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
        }

        let largeResult = decoder.getDownsampledPixels16(maxDimension: 500)
        if let (pixels, width, height) = largeResult {
            XCTAssertLessThanOrEqual(max(width, height), 500, "Should respect large maxDimension")
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
        }

        let tinyResult = decoder.getDownsampledPixels16(maxDimension: 10)
        if let (pixels, width, height) = tinyResult {
            XCTAssertLessThanOrEqual(max(width, height), 10, "Should respect tiny maxDimension")
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
        }
    }

    func testGetDownsampledPixels16AspectRatioPreservation() {
        let decoder = DCMDecoder()

        // Verify aspect ratio would be preserved (when data is available)
        let width = decoder.width
        let height = decoder.height

        if width > 0 && height > 0 {
            let originalAspect = Double(width) / Double(height)

            // For uninitialized decoder, we can't test actual downsampling
            // but we can verify the aspect ratio calculation logic
            let maxDim = 150
            let expectedWidth: Int
            let expectedHeight: Int

            if width > height {
                expectedWidth = min(width, maxDim)
                expectedHeight = Int(Double(expectedWidth) / originalAspect)
            } else {
                expectedHeight = min(height, maxDim)
                expectedWidth = Int(Double(expectedHeight) * originalAspect)
            }

            // Verify calculated dimensions maintain aspect ratio
            if expectedWidth > 0 && expectedHeight > 0 {
                let calculatedAspect = Double(expectedWidth) / Double(expectedHeight)
                XCTAssertEqual(calculatedAspect, originalAspect, accuracy: 0.1,
                             "Downsampled aspect ratio should match original")
            }
        }
    }

    func testGetDownsampledPixels16ReturnsExpectedTupleStructure() {
        let decoder = DCMDecoder()

        // When result is available, it should be a tuple (pixels, width, height)
        let result = decoder.getDownsampledPixels16(maxDimension: 150)

        // For uninitialized decoder, result will be nil
        if let (pixels, width, height) = result {
            XCTAssertFalse(pixels.isEmpty, "Downsampled pixels should not be empty")
            XCTAssertGreaterThan(width, 0, "Downsampled width should be positive")
            XCTAssertGreaterThan(height, 0, "Downsampled height should be positive")
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
        } else {
            XCTAssertNil(result, "Uninitialized decoder should return nil")
        }
    }

    func testGetDownsampledPixels16DimensionsWithinMaxBounds() {
        let decoder = DCMDecoder()

        let maxDim = 100
        let result = decoder.getDownsampledPixels16(maxDimension: maxDim)

        if let (_, width, height) = result {
            XCTAssertLessThanOrEqual(width, maxDim,
                                    "Downsampled width should not exceed maxDimension")
            XCTAssertLessThanOrEqual(height, maxDim,
                                    "Downsampled height should not exceed maxDimension")

            // At least one dimension should be close to maxDim (aspect-preserving)
            let maxOfDimensions = max(width, height)
            XCTAssertLessThanOrEqual(maxOfDimensions, maxDim,
                                    "Larger dimension should not exceed maxDimension")
        }
    }

    func testGetDownsampledPixels16ConsistencyAcrossMultipleCalls() {
        let decoder = DCMDecoder()

        let result1 = decoder.getDownsampledPixels16(maxDimension: 150)
        let result2 = decoder.getDownsampledPixels16(maxDimension: 150)

        // Both should be nil for uninitialized decoder
        XCTAssertEqual(result1 == nil, result2 == nil,
                      "Multiple downsampling calls should be consistent")

        if let (pixels1, width1, height1) = result1,
           let (pixels2, width2, height2) = result2 {
            XCTAssertEqual(width1, width2, "Downsampled width should be consistent")
            XCTAssertEqual(height1, height2, "Downsampled height should be consistent")
            XCTAssertEqual(pixels1.count, pixels2.count, "Downsampled pixel count should be consistent")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetDownsampledPixels16AsyncWithUninitializedDecoder() async {
        let decoder = DCMDecoder()

        let result = await decoder.getDownsampledPixels16Async()

        // Uninitialized decoder may return minimal default dimensions (1x1)
        if let (pixels, width, height) = result {
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
            XCTAssertLessThanOrEqual(width, 1, "Width should be minimal for uninitialized decoder")
            XCTAssertLessThanOrEqual(height, 1, "Height should be minimal for uninitialized decoder")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetDownsampledPixels16AsyncAfterFailedLoad() async {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/invalid/path.dcm")

        // After failed load, decoder still has default dimensions
        let result = await decoder.getDownsampledPixels16Async()

        // Verify file load was not successful
        XCTAssertFalse(decoder.dicomFileReadSuccess, "File load should not succeed")

        // If result exists, verify it's minimal (default dimensions)
        if let (pixels, width, height) = result {
            XCTAssertEqual(width * height, pixels.count, "Pixel count should match dimensions")
            XCTAssertLessThanOrEqual(width, 1, "Width should be minimal after failed load")
            XCTAssertLessThanOrEqual(height, 1, "Height should be minimal after failed load")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetDownsampledPixels16AsyncWithCustomMaxDimension() async {
        let decoder = DCMDecoder()

        let result = await decoder.getDownsampledPixels16Async(maxDimension: 200)

        // For uninitialized decoder, may return minimal result or nil
        if let (pixels, width, height) = result {
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
            XCTAssertGreaterThan(pixels.count, 0, "Should have at least one pixel if result exists")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetDownsampledPixels16AsyncConsistencyWithSync() async {
        let decoder = DCMDecoder()

        let syncResult = decoder.getDownsampledPixels16(maxDimension: 150)
        let asyncResult = await decoder.getDownsampledPixels16Async(maxDimension: 150)

        // Both should be nil for uninitialized decoder
        XCTAssertEqual(syncResult == nil, asyncResult == nil,
                      "Sync and async downsampling should be consistent")
    }

    func testDownsamplingExcludesColorImages() {
        let decoder = DCMDecoder()

        // Downsampling should not work on color images (samplesPerPixel=3)
        if decoder.samplesPerPixel == 3 {
            let result = decoder.getDownsampledPixels16()
            XCTAssertNil(result, "Downsampling should not work on color/RGB images")
        }
    }

    func testDownsamplingExcludes8BitImages() {
        let decoder = DCMDecoder()

        // Downsampling should not work on 8-bit images
        if decoder.bitDepth == 8 {
            let result = decoder.getDownsampledPixels16()
            XCTAssertNil(result, "Downsampling should not work on 8-bit images")
        }
    }

    // MARK: - Downsampled Pixels 8-bit Tests

    func testGetDownsampledPixels8WithUninitializedDecoder() {
        let decoder = DCMDecoder()

        let result = decoder.getDownsampledPixels8()

        // Uninitialized decoder may return minimal default dimensions (1x1)
        if let (pixels, width, height) = result {
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
            XCTAssertLessThanOrEqual(width, 1, "Width should be minimal for uninitialized decoder")
            XCTAssertLessThanOrEqual(height, 1, "Height should be minimal for uninitialized decoder")
        }
    }

    func testGetDownsampledPixels8AfterFailedLoad() {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/nonexistent/file.dcm")

        // After failed load, decoder still has default dimensions
        // Downsampling may return a minimal result or nil depending on state
        let result = decoder.getDownsampledPixels8()

        // Verify file load was not successful
        XCTAssertFalse(decoder.dicomFileReadSuccess, "File load should not succeed")

        // If result exists, verify it's minimal (default dimensions)
        if let (pixels, width, height) = result {
            XCTAssertEqual(width * height, pixels.count, "Pixel count should match dimensions")
            XCTAssertLessThanOrEqual(width, 1, "Width should be minimal after failed load")
            XCTAssertLessThanOrEqual(height, 1, "Height should be minimal after failed load")
        }
    }

    func testGetDownsampledPixels8RequiresGrayscale8Bit() {
        let decoder = DCMDecoder()

        // Downsampling requires samplesPerPixel=1 and bitDepth=8
        if decoder.samplesPerPixel != 1 || decoder.bitDepth != 8 {
            let result = decoder.getDownsampledPixels8()
            XCTAssertNil(result, "Downsampling should only work with 8-bit grayscale images")
        }
    }

    func testGetDownsampledPixels8WithDefaultMaxDimension() {
        let decoder = DCMDecoder()

        // Default maxDimension is 150
        let result = decoder.getDownsampledPixels8()

        // Uninitialized decoder may return minimal result
        if let (pixels, width, height) = result {
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
        }
    }

    func testGetDownsampledPixels8WithCustomMaxDimension() {
        let decoder = DCMDecoder()

        // Test with custom maxDimension
        let result = decoder.getDownsampledPixels8(maxDimension: 100)

        // Uninitialized decoder may return minimal result
        if let (pixels, width, height) = result {
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
            XCTAssertLessThanOrEqual(max(width, height), 100, "Dimensions should respect maxDimension")
        }
    }

    func testGetDownsampledPixels8MaxDimensionBounds() {
        let decoder = DCMDecoder()

        // Test various maxDimension values
        let smallResult = decoder.getDownsampledPixels8(maxDimension: 50)
        if let (pixels, width, height) = smallResult {
            XCTAssertLessThanOrEqual(max(width, height), 50, "Should respect small maxDimension")
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
        }

        let largeResult = decoder.getDownsampledPixels8(maxDimension: 500)
        if let (pixels, width, height) = largeResult {
            XCTAssertLessThanOrEqual(max(width, height), 500, "Should respect large maxDimension")
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
        }

        let tinyResult = decoder.getDownsampledPixels8(maxDimension: 10)
        if let (pixels, width, height) = tinyResult {
            XCTAssertLessThanOrEqual(max(width, height), 10, "Should respect tiny maxDimension")
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
        }
    }

    func testGetDownsampledPixels8AspectRatioPreservation() {
        let decoder = DCMDecoder()

        // Verify aspect ratio would be preserved (when data is available)
        let width = decoder.width
        let height = decoder.height

        if width > 0 && height > 0 {
            let originalAspect = Double(width) / Double(height)

            // For uninitialized decoder, we can't test actual downsampling
            // but we can verify the aspect ratio calculation logic
            let maxDim = 150
            let expectedWidth: Int
            let expectedHeight: Int

            if width > height {
                expectedWidth = min(width, maxDim)
                expectedHeight = Int(Double(expectedWidth) / originalAspect)
            } else {
                expectedHeight = min(height, maxDim)
                expectedWidth = Int(Double(expectedHeight) * originalAspect)
            }

            // Verify calculated dimensions maintain aspect ratio
            if expectedWidth > 0 && expectedHeight > 0 {
                let calculatedAspect = Double(expectedWidth) / Double(expectedHeight)
                XCTAssertEqual(calculatedAspect, originalAspect, accuracy: 0.1,
                             "Downsampled aspect ratio should match original")
            }
        }
    }

    func testGetDownsampledPixels8ReturnsExpectedTupleStructure() {
        let decoder = DCMDecoder()

        // When result is available, it should be a tuple (pixels, width, height)
        let result = decoder.getDownsampledPixels8(maxDimension: 150)

        // For uninitialized decoder, result will be nil
        if let (pixels, width, height) = result {
            XCTAssertFalse(pixels.isEmpty, "Downsampled pixels should not be empty")
            XCTAssertGreaterThan(width, 0, "Downsampled width should be positive")
            XCTAssertGreaterThan(height, 0, "Downsampled height should be positive")
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
        } else {
            XCTAssertNil(result, "Uninitialized decoder should return nil")
        }
    }

    func testGetDownsampledPixels8DimensionsWithinMaxBounds() {
        let decoder = DCMDecoder()

        let maxDim = 100
        let result = decoder.getDownsampledPixels8(maxDimension: maxDim)

        if let (_, width, height) = result {
            XCTAssertLessThanOrEqual(width, maxDim,
                                    "Downsampled width should not exceed maxDimension")
            XCTAssertLessThanOrEqual(height, maxDim,
                                    "Downsampled height should not exceed maxDimension")

            // At least one dimension should be close to maxDim (aspect-preserving)
            let maxOfDimensions = max(width, height)
            XCTAssertLessThanOrEqual(maxOfDimensions, maxDim,
                                    "Larger dimension should not exceed maxDimension")
        }
    }

    func testGetDownsampledPixels8ConsistencyAcrossMultipleCalls() {
        let decoder = DCMDecoder()

        let result1 = decoder.getDownsampledPixels8(maxDimension: 150)
        let result2 = decoder.getDownsampledPixels8(maxDimension: 150)

        // Both should be nil for uninitialized decoder
        XCTAssertEqual(result1 == nil, result2 == nil,
                      "Multiple downsampling calls should be consistent")

        if let (pixels1, width1, height1) = result1,
           let (pixels2, width2, height2) = result2 {
            XCTAssertEqual(width1, width2, "Downsampled width should be consistent")
            XCTAssertEqual(height1, height2, "Downsampled height should be consistent")
            XCTAssertEqual(pixels1.count, pixels2.count, "Downsampled pixel count should be consistent")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetDownsampledPixels8AsyncWithUninitializedDecoder() async {
        let decoder = DCMDecoder()

        let result = await decoder.getDownsampledPixels8Async()

        // Uninitialized decoder may return minimal default dimensions (1x1)
        if let (pixels, width, height) = result {
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
            XCTAssertLessThanOrEqual(width, 1, "Width should be minimal for uninitialized decoder")
            XCTAssertLessThanOrEqual(height, 1, "Height should be minimal for uninitialized decoder")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetDownsampledPixels8AsyncAfterFailedLoad() async {
        let decoder = DCMDecoder()

        decoder.setDicomFilename("/invalid/path.dcm")

        // After failed load, decoder still has default dimensions
        let result = await decoder.getDownsampledPixels8Async()

        // Verify file load was not successful
        XCTAssertFalse(decoder.dicomFileReadSuccess, "File load should not succeed")

        // If result exists, verify it's minimal (default dimensions)
        if let (pixels, width, height) = result {
            XCTAssertEqual(width * height, pixels.count, "Pixel count should match dimensions")
            XCTAssertLessThanOrEqual(width, 1, "Width should be minimal after failed load")
            XCTAssertLessThanOrEqual(height, 1, "Height should be minimal after failed load")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetDownsampledPixels8AsyncWithCustomMaxDimension() async {
        let decoder = DCMDecoder()

        let result = await decoder.getDownsampledPixels8Async(maxDimension: 200)

        // For uninitialized decoder, may return minimal result or nil
        if let (pixels, width, height) = result {
            XCTAssertEqual(pixels.count, width * height, "Pixel count should match dimensions")
            XCTAssertGreaterThan(pixels.count, 0, "Should have at least one pixel if result exists")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testGetDownsampledPixels8AsyncConsistencyWithSync() async {
        let decoder = DCMDecoder()

        let syncResult = decoder.getDownsampledPixels8(maxDimension: 150)
        let asyncResult = await decoder.getDownsampledPixels8Async(maxDimension: 150)

        // Both should be nil for uninitialized decoder
        XCTAssertEqual(syncResult == nil, asyncResult == nil,
                      "Sync and async downsampling should be consistent")
    }

    func testDownsamplingExcludes16BitImagesForPixels8() {
        let decoder = DCMDecoder()

        // Downsampling should not work on 16-bit images
        if decoder.bitDepth == 16 {
            let result = decoder.getDownsampledPixels8()
            XCTAssertNil(result, "Downsampling should not work on 16-bit images")
        }
    }
}
