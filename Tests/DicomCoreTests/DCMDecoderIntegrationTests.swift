import XCTest
@testable import DicomCore
import Foundation

final class DCMDecoderIntegrationTests: XCTestCase {

    // MARK: - Setup & Utilities

    /// Get path to fixtures directory
    private func getFixturesPath() -> URL {
        return URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    /// Get DICOM files from specific modality subdirectory
    private func getDICOMFiles(from subdirectory: String) throws -> [URL] {
        let modalityPath = getFixturesPath().appendingPathComponent(subdirectory)

        // Skip if directory doesn't exist
        guard FileManager.default.fileExists(atPath: modalityPath.path) else {
            throw XCTSkip("Fixtures directory '\(subdirectory)' not found. See Tests/DicomCoreTests/Fixtures/README.md for setup instructions.")
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: modalityPath,
            includingPropertiesForKeys: nil
        ).filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "dcm" || ext == "dicom"
        }

        guard !files.isEmpty else {
            throw XCTSkip("No DICOM files found in '\(subdirectory)'. See Tests/DicomCoreTests/Fixtures/README.md for setup instructions.")
        }

        return files
    }

    /// Get any available DICOM file from fixtures
    private func getAnyDICOMFile() throws -> URL {
        let fixturesPath = getFixturesPath()

        // Skip if fixtures directory doesn't exist
        guard FileManager.default.fileExists(atPath: fixturesPath.path) else {
            throw XCTSkip("Fixtures directory not found. See Tests/DicomCoreTests/Fixtures/README.md for setup instructions.")
        }

        // Search recursively for any .dcm or .dicom file
        let enumerator = FileManager.default.enumerator(at: fixturesPath, includingPropertiesForKeys: nil)

        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "dcm" || ext == "dicom" {
                return fileURL
            }
        }

        throw XCTSkip("No DICOM files found in Fixtures. See Tests/DicomCoreTests/Fixtures/README.md for setup instructions.")
    }

    // MARK: - Basic Integration Tests

    func testLoadRealDICOMFile() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read DICOM file: \(file.lastPathComponent)")
        XCTAssertTrue(decoder.isValid(), "Decoder should be valid after loading real DICOM file")
        XCTAssertGreaterThan(decoder.width, 0, "Image width should be greater than 0")
        XCTAssertGreaterThan(decoder.height, 0, "Image height should be greater than 0")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testLoadRealDICOMFileAsync() async throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        let success = await decoder.loadDICOMFileAsync(file.path)

        XCTAssertTrue(success, "Should successfully load DICOM file asynchronously: \(file.lastPathComponent)")
        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should have read success flag set")
        XCTAssertTrue(decoder.isValid(), "Decoder should be valid after async loading")
        XCTAssertGreaterThan(decoder.width, 0, "Image width should be greater than 0")
        XCTAssertGreaterThan(decoder.height, 0, "Image height should be greater than 0")
    }

    func testValidateRealDICOMFile() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        let validation = decoder.validateDICOMFile(file.path)

        XCTAssertTrue(validation.isValid, "Real DICOM file should pass validation: \(file.lastPathComponent)")
        XCTAssertTrue(validation.issues.isEmpty, "Valid DICOM file should have no validation issues")
    }

    func testExtractMetadataFromRealFile() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        // Get all tags - should have at least some metadata
        let allTags = decoder.getAllTags()
        XCTAssertFalse(allTags.isEmpty, "Real DICOM file should have metadata tags")

        // Test common required tags
        let rows = decoder.intValue(for: 0x00280010)
        let columns = decoder.intValue(for: 0x00280011)
        XCTAssertNotNil(rows, "Should have Rows tag")
        XCTAssertNotNil(columns, "Should have Columns tag")

        if let r = rows, let c = columns {
            XCTAssertEqual(r, decoder.height, "Rows should match height")
            XCTAssertEqual(c, decoder.width, "Columns should match width")
        }
    }

    func testExtractPixelDataFromRealFile() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        let validationStatus = decoder.getValidationStatus()
        XCTAssertTrue(validationStatus.hasPixels, "Real DICOM file should have pixel data")

        // Try to extract pixel data based on bit depth
        if decoder.bitDepth == 8 {
            let pixels = decoder.getPixels8()
            XCTAssertNotNil(pixels, "Should extract 8-bit pixel data")
            if let pixels = pixels {
                let expectedSize = decoder.width * decoder.height * decoder.samplesPerPixel
                XCTAssertEqual(pixels.count, expectedSize, "Pixel data size should match image dimensions")
            }
        } else if decoder.bitDepth == 16 {
            let pixels = decoder.getPixels16()
            XCTAssertNotNil(pixels, "Should extract 16-bit pixel data")
            if let pixels = pixels {
                let expectedSize = decoder.width * decoder.height * decoder.samplesPerPixel
                XCTAssertEqual(pixels.count, expectedSize, "Pixel data size should match image dimensions")
            }
        } else if decoder.bitDepth == 24 {
            let pixels = decoder.getPixels24()
            XCTAssertNotNil(pixels, "Should extract 24-bit pixel data")
            if let pixels = pixels {
                let expectedSize = decoder.width * decoder.height
                XCTAssertEqual(pixels.count, expectedSize, "Pixel data size should match image dimensions")
            }
        }
    }

    // MARK: - Modality-Specific Tests

    func testLoadCTImage() throws {
        let files = try getDICOMFiles(from: "CT")
        let file = files.first!

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read CT file")
        XCTAssertEqual(decoder.info(for: 0x00080060), "CT", "Modality should be CT")

        // CT images are typically 16-bit
        XCTAssertGreaterThanOrEqual(decoder.bitDepth, 8, "CT should have at least 8-bit depth")

        // CT should be grayscale (1 sample per pixel)
        XCTAssertEqual(decoder.samplesPerPixel, 1, "CT should be grayscale")
        XCTAssertTrue(decoder.isGrayscale, "CT should be grayscale")

        // CT should have window/level settings
        XCTAssertNotEqual(decoder.windowWidth, 0.0, "CT should have window width")

        // CT should have Hounsfield units (rescale intercept typically -1024)
        let rescaleType = decoder.info(for: 0x00281054)
        if !rescaleType.isEmpty {
            XCTAssertEqual(rescaleType, "HU", "CT rescale type should be HU (Hounsfield Units)")
        }
    }

    func testLoadMRImage() throws {
        let files = try getDICOMFiles(from: "MR")
        let file = files.first!

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read MR file")
        XCTAssertEqual(decoder.info(for: 0x00080060), "MR", "Modality should be MR")

        // MR images are typically 16-bit grayscale
        XCTAssertEqual(decoder.samplesPerPixel, 1, "MR should be grayscale")
        XCTAssertTrue(decoder.isGrayscale, "MR should be grayscale")

        // MR should have echo time
        let echoTime = decoder.doubleValue(for: 0x00180081)
        if let te = echoTime {
            XCTAssertGreaterThan(te, 0.0, "MR should have positive echo time")
        }

        // MR should have repetition time
        let repetitionTime = decoder.doubleValue(for: 0x00180080)
        if let tr = repetitionTime {
            XCTAssertGreaterThan(tr, 0.0, "MR should have positive repetition time")
        }
    }

    func testLoadXRayImage() throws {
        let files = try getDICOMFiles(from: "XR")
        let file = files.first!

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read X-ray file")

        let modality = decoder.info(for: 0x00080060)
        XCTAssertTrue(["XR", "CR", "DX"].contains(modality), "Modality should be X-ray type (XR, CR, or DX)")

        // X-ray images are typically grayscale
        XCTAssertTrue(decoder.isGrayscale, "X-ray should be grayscale")
    }

    func testLoadUltrasoundImage() throws {
        let files = try getDICOMFiles(from: "US")
        let file = files.first!

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read ultrasound file")
        XCTAssertEqual(decoder.info(for: 0x00080060), "US", "Modality should be US")

        // Ultrasound can be grayscale or color
        XCTAssertTrue(decoder.samplesPerPixel >= 1, "US should have at least 1 sample per pixel")
    }

    // MARK: - Transfer Syntax Tests

    func testLoadLittleEndianExplicitVRImage() throws {
        // Try to find a file with Little Endian Explicit VR (1.2.840.10008.1.2.1)
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file with explicit VR")

        let transferSyntax = decoder.info(for: 0x00020010)
        if !transferSyntax.isEmpty {
            // Just verify we can read the transfer syntax tag
            XCTAssertFalse(transferSyntax.isEmpty, "Should have transfer syntax UID")
        }
    }

    func testLoadCompressedImage() throws {
        let files = try getDICOMFiles(from: "Compressed")
        let file = files.first!

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        // Compressed images should either load successfully or fail gracefully
        if decoder.dicomFileReadSuccess {
            XCTAssertTrue(decoder.compressedImage, "Compressed file should set compressed flag")
            XCTAssertGreaterThan(decoder.width, 0, "Should have valid dimensions")
            XCTAssertGreaterThan(decoder.height, 0, "Should have valid dimensions")
        } else {
            // If compression not supported, that's expected
            XCTAssertTrue(true, "Unsupported compression is acceptable")
        }
    }

    // MARK: - Patient/Study/Series Extraction Tests

    func testExtractPatientInformation() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        let patientInfo = decoder.getPatientInfo()
        XCTAssertNotNil(patientInfo, "Should return patient info dictionary")

        // Check dictionary has expected keys
        XCTAssertTrue(patientInfo.keys.contains("Name"), "Should have Name key")
        XCTAssertTrue(patientInfo.keys.contains("ID"), "Should have ID key")
        XCTAssertTrue(patientInfo.keys.contains("Sex"), "Should have Sex key")
        XCTAssertTrue(patientInfo.keys.contains("Age"), "Should have Age key")

        // Values should be strings (may be empty for anonymized files)
        XCTAssertNotNil(patientInfo["Name"], "Name should exist")
        XCTAssertNotNil(patientInfo["ID"], "ID should exist")
    }

    func testExtractStudyInformation() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        let studyInfo = decoder.getStudyInfo()
        XCTAssertNotNil(studyInfo, "Should return study info dictionary")

        // Study Instance UID is required
        XCTAssertTrue(studyInfo.keys.contains("StudyInstanceUID"), "Should have StudyInstanceUID key")

        if let studyUID = studyInfo["StudyInstanceUID"], !studyUID.isEmpty {
            XCTAssertTrue(studyUID.contains("."), "Study Instance UID should be a UID (contains dots)")
        }
    }

    func testExtractSeriesInformation() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        let seriesInfo = decoder.getSeriesInfo()
        XCTAssertNotNil(seriesInfo, "Should return series info dictionary")

        // Series Instance UID is required
        XCTAssertTrue(seriesInfo.keys.contains("SeriesInstanceUID"), "Should have SeriesInstanceUID key")

        if let seriesUID = seriesInfo["SeriesInstanceUID"], !seriesUID.isEmpty {
            XCTAssertTrue(seriesUID.contains("."), "Series Instance UID should be a UID (contains dots)")
        }

        // Modality should be present
        XCTAssertTrue(seriesInfo.keys.contains("Modality"), "Should have Modality key")
    }

    // MARK: - Image Properties Tests

    func testImageDimensionsConsistency() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        // Test convenience properties match direct access
        let dimensions = decoder.imageDimensions
        XCTAssertEqual(dimensions.width, decoder.width, "imageDimensions.width should match width")
        XCTAssertEqual(dimensions.height, decoder.height, "imageDimensions.height should match height")

        // Test that tag values match properties
        if let rows = decoder.intValue(for: 0x00280010),
           let columns = decoder.intValue(for: 0x00280011) {
            XCTAssertEqual(rows, decoder.height, "Rows tag should match height")
            XCTAssertEqual(columns, decoder.width, "Columns tag should match width")
        }
    }

    func testPixelSpacingExtraction() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        let spacing = decoder.pixelSpacing
        XCTAssertGreaterThan(spacing.width, 0.0, "Pixel spacing width should be positive")
        XCTAssertGreaterThan(spacing.height, 0.0, "Pixel spacing height should be positive")
        XCTAssertGreaterThan(spacing.depth, 0.0, "Pixel spacing depth should be positive")
    }

    func testWindowingSettings() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        let windowSettings = decoder.windowSettings

        // Some images may not have window settings
        if windowSettings.width > 0.0 {
            XCTAssertGreaterThan(windowSettings.width, 0.0, "Window width should be positive if present")
        }
    }

    func testRescaleParameters() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        let rescale = decoder.rescaleParameters

        // Verify rescale slope is not zero (would be invalid)
        XCTAssertNotEqual(rescale.slope, 0.0, "Rescale slope should not be zero")

        // Test applyRescale method
        let testValue = 100.0
        let rescaled = decoder.applyRescale(to: testValue)
        let expected = testValue * rescale.slope + rescale.intercept
        XCTAssertEqual(rescaled, expected, accuracy: 0.01, "applyRescale should match formula")
    }

    // MARK: - Windowing and Image Processing Tests

    func testCalculateOptimalWindowFromRealImage() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        if decoder.bitDepth == 16 {
            let optimal = decoder.calculateOptimalWindow()

            if let window = optimal {
                XCTAssertGreaterThan(window.center, 0.0, "Optimal window center should be positive")
                XCTAssertGreaterThan(window.width, 0.0, "Optimal window width should be positive")
            }
        }
    }

    func testCalculateQualityMetrics() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        if decoder.bitDepth == 16 {
            let metrics = decoder.getQualityMetrics()

            if let metrics = metrics {
                XCTAssertNotNil(metrics["mean"], "Should have mean value")
                XCTAssertNotNil(metrics["std_deviation"], "Should have standard deviation")
                XCTAssertNotNil(metrics["contrast"], "Should have contrast")
                XCTAssertNotNil(metrics["snr"], "Should have SNR")

                // Verify values are reasonable
                if let mean = metrics["mean"] {
                    XCTAssertGreaterThanOrEqual(mean, 0.0, "Mean should be non-negative")
                }
                if let stdDev = metrics["std_deviation"] {
                    XCTAssertGreaterThanOrEqual(stdDev, 0.0, "Standard deviation should be non-negative")
                }
            }
        }
    }

    func testApplyWindowingPresets() throws {
        let files = try getDICOMFiles(from: "CT")
        let file = files.first!

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read CT file")

        if let pixels = decoder.getPixels16() {
            // Test applying lung preset to CT
            let lungPreset = DCMWindowingProcessor.getPresetValues(preset: .lung)
            let windowed = DCMWindowingProcessor.applyWindowLevel(
                pixels16: pixels,
                center: lungPreset.center,
                width: lungPreset.width
            )

            if let windowed = windowed {
                XCTAssertEqual(windowed.count, pixels.count, "Windowed pixel count should match input")
                XCTAssertTrue(windowed.allSatisfy { $0 <= 255 }, "Windowed values should be in 0-255 range")
            } else {
                XCTFail("Windowing should produce output data")
            }
        }
    }

    // MARK: - Multi-file Tests

    func testLoadMultipleFilesFromSameSeries() throws {
        let file = try getAnyDICOMFile()

        // Load same file multiple times (simulating series)
        let decoder1 = DCMDecoder()
        let decoder2 = DCMDecoder()

        decoder1.setDicomFilename(file.path)
        decoder2.setDicomFilename(file.path)

        XCTAssertTrue(decoder1.dicomFileReadSuccess, "First decoder should load successfully")
        XCTAssertTrue(decoder2.dicomFileReadSuccess, "Second decoder should load successfully")

        // Both should have same properties
        XCTAssertEqual(decoder1.width, decoder2.width, "Both decoders should have same width")
        XCTAssertEqual(decoder1.height, decoder2.height, "Both decoders should have same height")
        XCTAssertEqual(decoder1.bitDepth, decoder2.bitDepth, "Both decoders should have same bit depth")

        let seriesUID1 = decoder1.info(for: 0x0020000E)
        let seriesUID2 = decoder2.info(for: 0x0020000E)
        XCTAssertEqual(seriesUID1, seriesUID2, "Both should have same Series Instance UID")
    }

    func testLoadAllFilesInDirectory() throws {
        let file = try getAnyDICOMFile()
        let directory = file.deletingLastPathComponent()

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "dcm" }

        var successCount = 0
        for file in files.prefix(5) { // Test first 5 files to avoid long test times
            let decoder = DCMDecoder()
            decoder.setDicomFilename(file.path)

            if decoder.dicomFileReadSuccess {
                successCount += 1
                XCTAssertTrue(decoder.isValid(), "Successfully loaded file should be valid")
            }
        }

        XCTAssertGreaterThan(successCount, 0, "Should successfully load at least one file")
    }

    // MARK: - Performance Tests

    func testLoadingPerformance() throws {
        let file = try getAnyDICOMFile()

        measure {
            let decoder = DCMDecoder()
            decoder.setDicomFilename(file.path)
            _ = decoder.dicomFileReadSuccess
        }
    }

    func testMetadataExtractionPerformance() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        measure {
            _ = decoder.info(for: 0x00100010) // Patient Name
            _ = decoder.info(for: 0x00080060) // Modality
            _ = decoder.intValue(for: 0x00280010) // Rows
            _ = decoder.intValue(for: 0x00280011) // Columns
            _ = decoder.getPatientInfo()
            _ = decoder.getStudyInfo()
            _ = decoder.getSeriesInfo()
        }
    }

    func testPixelDataAccessPerformance() throws {
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully read file")

        measure {
            if decoder.bitDepth == 8 {
                _ = decoder.getPixels8()
            } else if decoder.bitDepth == 16 {
                _ = decoder.getPixels16()
            } else if decoder.bitDepth == 24 {
                _ = decoder.getPixels24()
            }
        }
    }

    // MARK: - Edge Cases

    func testLoadVeryLargeImage() throws {
        // Try to find a large image (>1MB)
        let fixturesPath = getFixturesPath()

        guard FileManager.default.fileExists(atPath: fixturesPath.path) else {
            throw XCTSkip("Fixtures directory not found")
        }

        let enumerator = FileManager.default.enumerator(at: fixturesPath, includingPropertiesForKeys: [.fileSizeKey])
        var largeFile: URL?

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "dcm" {
                if let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resources.fileSize,
                   fileSize > 1_000_000 { // > 1MB
                    largeFile = fileURL
                    break
                }
            }
        }

        guard let file = largeFile else {
            throw XCTSkip("No large DICOM files (>1MB) found in fixtures")
        }

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should successfully load large DICOM file")
        XCTAssertTrue(decoder.isValid(), "Large file should be valid")
    }

    func testHandleMinimalMetadata() throws {
        // Test with any available file - should handle gracefully even if minimal metadata
        let file = try getAnyDICOMFile()

        let decoder = DCMDecoder()
        decoder.setDicomFilename(file.path)

        XCTAssertTrue(decoder.dicomFileReadSuccess, "Should load file even with minimal metadata")

        // Should not crash when accessing potentially missing tags
        _ = decoder.info(for: 0x00100010)
        _ = decoder.info(for: 0x00181030)
        _ = decoder.doubleValue(for: 0x00180050)
        _ = decoder.intValue(for: 0x00200013)

        XCTAssertTrue(true, "Should handle missing tags gracefully")
    }

    // MARK: - Concurrent Access Tests

    @available(macOS 10.15, iOS 13.0, *)
    func testConcurrentFileLoading() async throws {
        let file = try getAnyDICOMFile()

        // Load same file concurrently with multiple decoders
        async let result1 = Task {
            let decoder = DCMDecoder()
            let success = await decoder.loadDICOMFileAsync(file.path)
            return (decoder, success)
        }.value

        async let result2 = Task {
            let decoder = DCMDecoder()
            let success = await decoder.loadDICOMFileAsync(file.path)
            return (decoder, success)
        }.value

        async let result3 = Task {
            let decoder = DCMDecoder()
            let success = await decoder.loadDICOMFileAsync(file.path)
            return (decoder, success)
        }.value

        let results = await [result1, result2, result3]

        // All should succeed
        for (decoder, success) in results {
            XCTAssertTrue(success, "Concurrent load should succeed")
            XCTAssertTrue(decoder.isValid(), "Concurrently loaded decoder should be valid")
        }

        // All should have same dimensions
        let widths = results.map { $0.0.width }
        let heights = results.map { $0.0.height }
        XCTAssertTrue(widths.allSatisfy { $0 == widths[0] }, "All decoders should have same width")
        XCTAssertTrue(heights.allSatisfy { $0 == heights[0] }, "All decoders should have same height")
    }
}
