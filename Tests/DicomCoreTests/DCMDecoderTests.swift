import XCTest
@testable import DicomCore

final class DCMDecoderTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDecoderInitialization() {
        let decoder = DCMDecoder()

        // Test initial state
        XCTAssertFalse(decoder.dicomFileReadSuccess, "New decoder should not have read success")
        XCTAssertFalse(decoder.dicomFound, "New decoder should not have DICM marker found")
        XCTAssertFalse(decoder.compressedImage, "New decoder should not be compressed")
        XCTAssertFalse(decoder.signedImage, "New decoder should not be signed")

        // Test initial dimensions
        XCTAssertEqual(decoder.width, 1, "Default width should be 1")
        XCTAssertEqual(decoder.height, 1, "Default height should be 1")
        XCTAssertEqual(decoder.bitDepth, 16, "Default bit depth should be 16")

        // Test initial samples and frames
        XCTAssertEqual(decoder.samplesPerPixel, 1, "Default samples per pixel should be 1")
        XCTAssertEqual(decoder.nImages, 1, "Default number of images should be 1")

        // Test initial pixel spacing
        XCTAssertEqual(decoder.pixelWidth, 1.0, "Default pixel width should be 1.0")
        XCTAssertEqual(decoder.pixelHeight, 1.0, "Default pixel height should be 1.0")
        XCTAssertEqual(decoder.pixelDepth, 1.0, "Default pixel depth should be 1.0")

        // Test initial window settings
        XCTAssertEqual(decoder.windowCenter, 0.0, "Default window center should be 0.0")
        XCTAssertEqual(decoder.windowWidth, 0.0, "Default window width should be 0.0")

        // Test initial photometric interpretation
        XCTAssertEqual(decoder.photometricInterpretation, "", "Default photometric interpretation should be empty")
    }

    func testDecoderInitialPixelBuffers() {
        let decoder = DCMDecoder()

        // Test that pixel buffers are initially nil
        XCTAssertNil(decoder.getPixels8(), "Initial pixels8 should be nil")
        XCTAssertNil(decoder.getPixels16(), "Initial pixels16 should be nil")
        XCTAssertNil(decoder.getPixels24(), "Initial pixels24 should be nil")
    }

    func testDecoderInitialValidationState() {
        let decoder = DCMDecoder()

        // Test isValid returns false initially
        XCTAssertFalse(decoder.isValid(), "New decoder should not be valid")

        // Test getValidationStatus
        let status = decoder.getValidationStatus()
        XCTAssertFalse(status.isValid, "Initial validation status should be false")
        XCTAssertEqual(status.width, 1, "Initial status width should be 1")
        XCTAssertEqual(status.height, 1, "Initial status height should be 1")
        XCTAssertFalse(status.hasPixels, "Initial status should have no pixels")
        XCTAssertFalse(status.isCompressed, "Initial status should not be compressed")
    }

    // MARK: - Throwing Initializer Tests

    /// Get path to fixtures directory
    private func getFixturesPath() -> URL {
        return URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
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

    func testThrowingInitializerWithURLAndValidFile() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()

        // Test that initializer succeeds with valid file
        let decoder = try DCMDecoder(contentsOf: fileURL)

        // Verify decoder loaded successfully
        XCTAssertTrue(decoder.dicomFileReadSuccess, "Decoder should have read success with valid file")
        XCTAssertTrue(decoder.dicomFound, "Decoder should have found DICM marker")

        // Verify decoder has valid dimensions
        XCTAssertGreaterThan(decoder.width, 0, "Width should be greater than 0")
        XCTAssertGreaterThan(decoder.height, 0, "Height should be greater than 0")

        // Verify decoder is valid
        XCTAssertTrue(decoder.isValid(), "Decoder should be valid after loading")

        // Verify validation status
        let status = decoder.getValidationStatus()
        XCTAssertTrue(status.isValid, "Validation status should be true")
        XCTAssertGreaterThan(status.width, 0, "Status width should be greater than 0")
        XCTAssertGreaterThan(status.height, 0, "Status height should be greater than 0")
    }

    func testThrowingInitializerWithPathAndValidFile() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()
        let filePath = fileURL.path

        // Test that initializer succeeds with valid file path
        let decoder = try DCMDecoder(contentsOfFile: filePath)

        // Verify decoder loaded successfully
        XCTAssertTrue(decoder.dicomFileReadSuccess, "Decoder should have read success with valid file")
        XCTAssertTrue(decoder.dicomFound, "Decoder should have found DICM marker")

        // Verify decoder has valid dimensions
        XCTAssertGreaterThan(decoder.width, 0, "Width should be greater than 0")
        XCTAssertGreaterThan(decoder.height, 0, "Height should be greater than 0")

        // Verify decoder is valid
        XCTAssertTrue(decoder.isValid(), "Decoder should be valid after loading")

        // Verify validation status
        let status = decoder.getValidationStatus()
        XCTAssertTrue(status.isValid, "Validation status should be true")
        XCTAssertGreaterThan(status.width, 0, "Status width should be greater than 0")
        XCTAssertGreaterThan(status.height, 0, "Status height should be greater than 0")
    }

    func testThrowingInitializerLoadsMetadata() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()

        // Test that initializer loads metadata
        let decoder = try DCMDecoder(contentsOf: fileURL)

        // Verify some basic metadata is accessible
        // We can't test specific values since we don't know which test file was loaded,
        // but we can verify the decoder can retrieve tag information
        XCTAssertNotNil(decoder.getAllTags(), "Should be able to get all tags")

        // Verify dimensions are accessible through convenience properties
        let dimensions = decoder.imageDimensions
        XCTAssertEqual(dimensions.width, decoder.width, "imageDimensions should match width")
        XCTAssertEqual(dimensions.height, decoder.height, "imageDimensions should match height")

        // Verify pixel spacing is accessible
        let spacing = decoder.pixelSpacing
        XCTAssertGreaterThan(spacing.width, 0, "Pixel spacing width should be positive")
        XCTAssertGreaterThan(spacing.height, 0, "Pixel spacing height should be positive")
    }

    func testThrowingInitializerEquivalentToSetDicomFilename() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()
        let filePath = fileURL.path

        // Load with throwing initializer
        let decoder1 = try DCMDecoder(contentsOf: fileURL)

        // Load with traditional method
        let decoder2 = DCMDecoder()
        decoder2.setDicomFilename(filePath)

        // Verify both methods produce equivalent results
        XCTAssertEqual(decoder1.width, decoder2.width, "Both decoders should have same width")
        XCTAssertEqual(decoder1.height, decoder2.height, "Both decoders should have same height")
        XCTAssertEqual(decoder1.bitDepth, decoder2.bitDepth, "Both decoders should have same bit depth")
        XCTAssertEqual(decoder1.samplesPerPixel, decoder2.samplesPerPixel, "Both decoders should have same samples per pixel")
        XCTAssertEqual(decoder1.dicomFileReadSuccess, decoder2.dicomFileReadSuccess, "Both decoders should have same read success")
        XCTAssertEqual(decoder1.dicomFound, decoder2.dicomFound, "Both decoders should have same DICM marker status")
    }

    // MARK: - Throwing Initializer Error Tests

    func testThrowingInitializerWithURLThrowsForNonExistentFile() {
        // Create URL for non-existent file
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/file.dcm")

        // Test that initializer throws fileNotFound error
        XCTAssertThrowsError(try DCMDecoder(contentsOf: nonExistentURL)) { error in
            guard let dicomError = error as? DICOMError else {
                XCTFail("Error should be of type DICOMError")
                return
            }

            // Verify it's the correct error type
            if case .fileNotFound(let path) = dicomError {
                XCTAssertTrue(path.contains("nonexistent"), "Error should reference the non-existent path")
            } else {
                XCTFail("Error should be .fileNotFound, got \(dicomError)")
            }
        }
    }

    func testThrowingInitializerWithPathThrowsForNonExistentFile() {
        // Test that initializer throws fileNotFound error for non-existent file
        XCTAssertThrowsError(try DCMDecoder(contentsOfFile: "/nonexistent/file.dcm")) { error in
            guard let dicomError = error as? DICOMError else {
                XCTFail("Error should be of type DICOMError")
                return
            }

            // Verify it's the correct error type
            if case .fileNotFound(let path) = dicomError {
                XCTAssertTrue(path.contains("nonexistent"), "Error should reference the non-existent path")
            } else {
                XCTFail("Error should be .fileNotFound, got \(dicomError)")
            }
        }
    }

    func testThrowingInitializerWithPathThrowsForEmptyPath() {
        // Test that initializer throws error for empty path
        XCTAssertThrowsError(try DCMDecoder(contentsOfFile: "")) { error in
            guard let dicomError = error as? DICOMError else {
                XCTFail("Error should be of type DICOMError")
                return
            }

            // Should be fileNotFound or invalidFileFormat
            switch dicomError {
            case .fileNotFound:
                break // Valid error for empty path
            case .invalidFileFormat:
                break // Also valid for empty path
            default:
                XCTFail("Error should be .fileNotFound or .invalidFileFormat, got \(dicomError)")
            }
        }
    }

    func testThrowingInitializerWithURLThrowsForInvalidDICOMFile() throws {
        // Create a temporary file that is not a valid DICOM file
        let tempDir = FileManager.default.temporaryDirectory
        let invalidFileURL = tempDir.appendingPathComponent("invalid_dicom_\(UUID().uuidString).dcm")

        // Write some non-DICOM data to the file
        let invalidData = "This is not a DICOM file".data(using: .utf8)!
        try invalidData.write(to: invalidFileURL)

        // Ensure cleanup
        defer {
            try? FileManager.default.removeItem(at: invalidFileURL)
        }

        // Test that initializer throws error for invalid DICOM file
        XCTAssertThrowsError(try DCMDecoder(contentsOf: invalidFileURL)) { error in
            guard let dicomError = error as? DICOMError else {
                XCTFail("Error should be of type DICOMError")
                return
            }

            // Should be invalidDICOMFormat or similar
            switch dicomError {
            case .invalidDICOMFormat:
                break // Expected error
            case .invalidFileFormat:
                break // Also acceptable
            case .fileCorrupted:
                break // Also acceptable
            default:
                XCTFail("Error should be .invalidDICOMFormat, .invalidFileFormat, or .fileCorrupted, got \(dicomError)")
            }
        }
    }

    func testThrowingInitializerWithPathThrowsForInvalidDICOMFile() throws {
        // Create a temporary file that is not a valid DICOM file
        let tempDir = FileManager.default.temporaryDirectory
        let invalidFileURL = tempDir.appendingPathComponent("invalid_dicom_\(UUID().uuidString).dcm")

        // Write some non-DICOM data to the file
        let invalidData = "This is not a DICOM file".data(using: .utf8)!
        try invalidData.write(to: invalidFileURL)

        // Ensure cleanup
        defer {
            try? FileManager.default.removeItem(at: invalidFileURL)
        }

        // Test that initializer throws error for invalid DICOM file
        XCTAssertThrowsError(try DCMDecoder(contentsOfFile: invalidFileURL.path)) { error in
            guard let dicomError = error as? DICOMError else {
                XCTFail("Error should be of type DICOMError")
                return
            }

            // Should be invalidDICOMFormat or similar
            switch dicomError {
            case .invalidDICOMFormat:
                break // Expected error
            case .invalidFileFormat:
                break // Also acceptable
            case .fileCorrupted:
                break // Also acceptable
            default:
                XCTFail("Error should be .invalidDICOMFormat, .invalidFileFormat, or .fileCorrupted, got \(dicomError)")
            }
        }
    }

    func testThrowingInitializerWithURLThrowsForDirectory() {
        // Test that initializer throws error when given a directory path
        let directoryURL = FileManager.default.temporaryDirectory

        XCTAssertThrowsError(try DCMDecoder(contentsOf: directoryURL)) { error in
            guard let dicomError = error as? DICOMError else {
                XCTFail("Error should be of type DICOMError")
                return
            }

            // Should throw some kind of error for directory
            // Could be fileReadError, invalidFileFormat, etc.
            XCTAssertNotNil(dicomError.errorDescription, "Error should have a description")
        }
    }

    func testThrowingInitializerErrorMessagesAreDescriptive() {
        // Test that error messages contain useful information
        do {
            _ = try DCMDecoder(contentsOfFile: "/nonexistent/test.dcm")
            XCTFail("Should have thrown an error")
        } catch let error as DICOMError {
            let errorMessage = error.errorDescription ?? ""
            XCTAssertFalse(errorMessage.isEmpty, "Error should have a description")
            XCTAssertTrue(errorMessage.contains("test.dcm") || errorMessage.contains("nonexistent"),
                         "Error message should mention the file path")

            // Verify recovery suggestion exists
            XCTAssertNotNil(error.recoverySuggestion, "Error should have recovery suggestion")
        } catch {
            XCTFail("Error should be of type DICOMError")
        }
    }

    func testThrowingInitializerDoesNotLeavePartialState() {
        // Verify that a failed throwing initializer doesn't leave a partially initialized object
        // This is guaranteed by Swift's error handling - the object is never returned if init throws

        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/file.dcm")

        do {
            _ = try DCMDecoder(contentsOf: nonExistentURL)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected - no decoder instance should exist
            // If we got here, the throwing init worked correctly
            XCTAssertTrue(true, "Throwing initializer correctly prevented object creation")
        }
    }

    // MARK: - Async Throwing Initializer Tests

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerWithURLAndValidFile() async throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()

        // Test that async initializer succeeds with valid file
        let decoder = try await DCMDecoder(contentsOf: fileURL)

        // Verify decoder loaded successfully
        XCTAssertTrue(decoder.dicomFileReadSuccess, "Decoder should have read success with valid file")
        XCTAssertTrue(decoder.dicomFound, "Decoder should have found DICM marker")

        // Verify decoder has valid dimensions
        XCTAssertGreaterThan(decoder.width, 0, "Width should be greater than 0")
        XCTAssertGreaterThan(decoder.height, 0, "Height should be greater than 0")

        // Verify decoder is valid
        XCTAssertTrue(decoder.isValid(), "Decoder should be valid after loading")

        // Verify validation status
        let status = decoder.getValidationStatus()
        XCTAssertTrue(status.isValid, "Validation status should be true")
        XCTAssertGreaterThan(status.width, 0, "Status width should be greater than 0")
        XCTAssertGreaterThan(status.height, 0, "Status height should be greater than 0")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerWithPathAndValidFile() async throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()
        let filePath = fileURL.path

        // Test that async initializer succeeds with valid file path
        let decoder = try await DCMDecoder(contentsOfFile: filePath)

        // Verify decoder loaded successfully
        XCTAssertTrue(decoder.dicomFileReadSuccess, "Decoder should have read success with valid file")
        XCTAssertTrue(decoder.dicomFound, "Decoder should have found DICM marker")

        // Verify decoder has valid dimensions
        XCTAssertGreaterThan(decoder.width, 0, "Width should be greater than 0")
        XCTAssertGreaterThan(decoder.height, 0, "Height should be greater than 0")

        // Verify decoder is valid
        XCTAssertTrue(decoder.isValid(), "Decoder should be valid after loading")

        // Verify validation status
        let status = decoder.getValidationStatus()
        XCTAssertTrue(status.isValid, "Validation status should be true")
        XCTAssertGreaterThan(status.width, 0, "Status width should be greater than 0")
        XCTAssertGreaterThan(status.height, 0, "Status height should be greater than 0")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerLoadsMetadata() async throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()

        // Test that async initializer loads metadata
        let decoder = try await DCMDecoder(contentsOf: fileURL)

        // Verify some basic metadata is accessible
        // We can't test specific values since we don't know which test file was loaded,
        // but we can verify the decoder can retrieve tag information
        XCTAssertNotNil(decoder.getAllTags(), "Should be able to get all tags")

        // Verify dimensions are accessible through convenience properties
        let dimensions = decoder.imageDimensions
        XCTAssertEqual(dimensions.width, decoder.width, "imageDimensions should match width")
        XCTAssertEqual(dimensions.height, decoder.height, "imageDimensions should match height")

        // Verify pixel spacing is accessible
        let spacing = decoder.pixelSpacing
        XCTAssertGreaterThan(spacing.width, 0, "Pixel spacing width should be positive")
        XCTAssertGreaterThan(spacing.height, 0, "Pixel spacing height should be positive")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerEquivalentToSyncVersion() async throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()
        let filePath = fileURL.path

        // Load with async throwing initializer
        let decoder1 = try await DCMDecoder(contentsOf: fileURL)

        // Load with sync throwing initializer (need await in async context)
        let decoder2 = try await DCMDecoder(contentsOfFile: filePath)

        // Verify both methods produce equivalent results
        XCTAssertEqual(decoder1.width, decoder2.width, "Both decoders should have same width")
        XCTAssertEqual(decoder1.height, decoder2.height, "Both decoders should have same height")
        XCTAssertEqual(decoder1.bitDepth, decoder2.bitDepth, "Both decoders should have same bit depth")
        XCTAssertEqual(decoder1.samplesPerPixel, decoder2.samplesPerPixel, "Both decoders should have same samples per pixel")
        XCTAssertEqual(decoder1.dicomFileReadSuccess, decoder2.dicomFileReadSuccess, "Both decoders should have same read success")
        XCTAssertEqual(decoder1.dicomFound, decoder2.dicomFound, "Both decoders should have same DICM marker status")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerEquivalentToLoadDICOMFileAsync() async throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()
        let filePath = fileURL.path

        // Load with async throwing initializer
        let decoder1 = try await DCMDecoder(contentsOf: fileURL)

        // Load with loadDICOMFileAsync method
        let decoder2 = DCMDecoder()
        let success = await decoder2.loadDICOMFileAsync(filePath)
        XCTAssertTrue(success, "loadDICOMFileAsync should succeed")

        // Verify both methods produce equivalent results
        XCTAssertEqual(decoder1.width, decoder2.width, "Both decoders should have same width")
        XCTAssertEqual(decoder1.height, decoder2.height, "Both decoders should have same height")
        XCTAssertEqual(decoder1.bitDepth, decoder2.bitDepth, "Both decoders should have same bit depth")
        XCTAssertEqual(decoder1.samplesPerPixel, decoder2.samplesPerPixel, "Both decoders should have same samples per pixel")
        XCTAssertEqual(decoder1.dicomFileReadSuccess, decoder2.dicomFileReadSuccess, "Both decoders should have same read success")
        XCTAssertEqual(decoder1.dicomFound, decoder2.dicomFound, "Both decoders should have same DICM marker status")
    }

    // MARK: - Async Throwing Initializer Error Tests

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerWithURLThrowsForNonExistentFile() async {
        // Create URL for non-existent file
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/file.dcm")

        // Test that async initializer throws fileNotFound error
        do {
            _ = try await DCMDecoder(contentsOf: nonExistentURL)
            XCTFail("Should have thrown an error")
        } catch let error as DICOMError {
            // Verify it's the correct error type
            if case .fileNotFound(let path) = error {
                XCTAssertTrue(path.contains("nonexistent"), "Error should reference the non-existent path")
            } else {
                XCTFail("Error should be .fileNotFound, got \(error)")
            }
        } catch {
            XCTFail("Error should be of type DICOMError")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerWithPathThrowsForNonExistentFile() async {
        // Test that async initializer throws fileNotFound error for non-existent file
        do {
            _ = try await DCMDecoder(contentsOfFile: "/nonexistent/file.dcm")
            XCTFail("Should have thrown an error")
        } catch let error as DICOMError {
            // Verify it's the correct error type
            if case .fileNotFound(let path) = error {
                XCTAssertTrue(path.contains("nonexistent"), "Error should reference the non-existent path")
            } else {
                XCTFail("Error should be .fileNotFound, got \(error)")
            }
        } catch {
            XCTFail("Error should be of type DICOMError")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerWithPathThrowsForEmptyPath() async {
        // Test that async initializer throws error for empty path
        do {
            _ = try await DCMDecoder(contentsOfFile: "")
            XCTFail("Should have thrown an error")
        } catch let error as DICOMError {
            // Should be fileNotFound or invalidFileFormat
            switch error {
            case .fileNotFound:
                break // Valid error for empty path
            case .invalidFileFormat:
                break // Also valid for empty path
            default:
                XCTFail("Error should be .fileNotFound or .invalidFileFormat, got \(error)")
            }
        } catch {
            XCTFail("Error should be of type DICOMError")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerWithURLThrowsForInvalidDICOMFile() async throws {
        // Create a temporary file that is not a valid DICOM file
        let tempDir = FileManager.default.temporaryDirectory
        let invalidFileURL = tempDir.appendingPathComponent("invalid_dicom_async_\(UUID().uuidString).dcm")

        // Write some non-DICOM data to the file
        let invalidData = "This is not a DICOM file".data(using: .utf8)!
        try invalidData.write(to: invalidFileURL)

        // Ensure cleanup
        defer {
            try? FileManager.default.removeItem(at: invalidFileURL)
        }

        // Test that async initializer throws error for invalid DICOM file
        do {
            _ = try await DCMDecoder(contentsOf: invalidFileURL)
            XCTFail("Should have thrown an error")
        } catch let error as DICOMError {
            // Should be invalidDICOMFormat or similar
            switch error {
            case .invalidDICOMFormat:
                break // Expected error
            case .invalidFileFormat:
                break // Also acceptable
            case .fileCorrupted:
                break // Also acceptable
            default:
                XCTFail("Error should be .invalidDICOMFormat, .invalidFileFormat, or .fileCorrupted, got \(error)")
            }
        } catch {
            XCTFail("Error should be of type DICOMError")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerWithPathThrowsForInvalidDICOMFile() async throws {
        // Create a temporary file that is not a valid DICOM file
        let tempDir = FileManager.default.temporaryDirectory
        let invalidFileURL = tempDir.appendingPathComponent("invalid_dicom_async_path_\(UUID().uuidString).dcm")

        // Write some non-DICOM data to the file
        let invalidData = "This is not a DICOM file".data(using: .utf8)!
        try invalidData.write(to: invalidFileURL)

        // Ensure cleanup
        defer {
            try? FileManager.default.removeItem(at: invalidFileURL)
        }

        // Test that async initializer throws error for invalid DICOM file
        do {
            _ = try await DCMDecoder(contentsOfFile: invalidFileURL.path)
            XCTFail("Should have thrown an error")
        } catch let error as DICOMError {
            // Should be invalidDICOMFormat or similar
            switch error {
            case .invalidDICOMFormat:
                break // Expected error
            case .invalidFileFormat:
                break // Also acceptable
            case .fileCorrupted:
                break // Also acceptable
            default:
                XCTFail("Error should be .invalidDICOMFormat, .invalidFileFormat, or .fileCorrupted, got \(error)")
            }
        } catch {
            XCTFail("Error should be of type DICOMError")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerWithURLThrowsForDirectory() async {
        // Test that async initializer throws error when given a directory path
        let directoryURL = FileManager.default.temporaryDirectory

        do {
            _ = try await DCMDecoder(contentsOf: directoryURL)
            XCTFail("Should have thrown an error")
        } catch let error as DICOMError {
            // Should throw some kind of error for directory
            // Could be fileReadError, invalidFileFormat, etc.
            XCTAssertNotNil(error.errorDescription, "Error should have a description")
        } catch {
            XCTFail("Error should be of type DICOMError")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerErrorMessagesAreDescriptive() async {
        // Test that async initializer error messages contain useful information
        do {
            _ = try await DCMDecoder(contentsOfFile: "/nonexistent/test.dcm")
            XCTFail("Should have thrown an error")
        } catch let error as DICOMError {
            let errorMessage = error.errorDescription ?? ""
            XCTAssertFalse(errorMessage.isEmpty, "Error should have a description")
            XCTAssertTrue(errorMessage.contains("test.dcm") || errorMessage.contains("nonexistent"),
                         "Error message should mention the file path")

            // Verify recovery suggestion exists
            XCTAssertNotNil(error.recoverySuggestion, "Error should have recovery suggestion")
        } catch {
            XCTFail("Error should be of type DICOMError")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerDoesNotLeavePartialState() async {
        // Verify that a failed async throwing initializer doesn't leave a partially initialized object
        // This is guaranteed by Swift's error handling - the object is never returned if init throws

        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/file.dcm")

        do {
            _ = try await DCMDecoder(contentsOf: nonExistentURL)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected - no decoder instance should exist
            // If we got here, the async throwing init worked correctly
            XCTAssertTrue(true, "Async throwing initializer correctly prevented object creation")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerConcurrentCalls() async throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()

        // Test concurrent async initializer calls with the same file
        async let decoder1 = try DCMDecoder(contentsOf: fileURL)
        async let decoder2 = try DCMDecoder(contentsOf: fileURL)
        async let decoder3 = try DCMDecoder(contentsOf: fileURL)

        let decoders = try await [decoder1, decoder2, decoder3]

        // All decoders should have loaded successfully and have same properties
        for decoder in decoders {
            XCTAssertTrue(decoder.dicomFileReadSuccess, "Decoder should have read success")
            XCTAssertTrue(decoder.dicomFound, "Decoder should have found DICM marker")
            XCTAssertTrue(decoder.isValid(), "Decoder should be valid")
        }

        // Verify all decoders have same dimensions
        let firstDecoder = decoders[0]
        for decoder in decoders.dropFirst() {
            XCTAssertEqual(decoder.width, firstDecoder.width, "All decoders should have same width")
            XCTAssertEqual(decoder.height, firstDecoder.height, "All decoders should have same height")
            XCTAssertEqual(decoder.bitDepth, firstDecoder.bitDepth, "All decoders should have same bit depth")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerConcurrentCallsWithErrors() async {
        // Test concurrent async initializer calls with non-existent files
        async let result1 = try? DCMDecoder(contentsOfFile: "/nonexistent/file1.dcm")
        async let result2 = try? DCMDecoder(contentsOfFile: "/nonexistent/file2.dcm")
        async let result3 = try? DCMDecoder(contentsOfFile: "/nonexistent/file3.dcm")

        let results = await [result1, result2, result3]

        // All should be nil (failed to initialize)
        for result in results {
            XCTAssertNil(result, "Decoder should be nil for non-existent file")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncThrowingInitializerPreservesErrorInformation() async {
        // Test that async initializer preserves detailed error information
        let nonExistentPath = "/nonexistent/deeply/nested/path/file.dcm"

        do {
            _ = try await DCMDecoder(contentsOfFile: nonExistentPath)
            XCTFail("Should have thrown an error")
        } catch let error as DICOMError {
            // Verify error preserves path information
            let errorDescription = error.errorDescription ?? ""
            let failureReason = error.failureReason ?? ""
            let recoverySuggestion = error.recoverySuggestion ?? ""

            // At least one of these should contain path information
            let containsPath = errorDescription.contains("file.dcm") ||
                              failureReason.contains("file.dcm") ||
                              recoverySuggestion.contains("exist")

            XCTAssertTrue(containsPath, "Error should preserve path information in description, reason, or suggestion")
        } catch {
            XCTFail("Error should be of type DICOMError")
        }
    }

    // MARK: - Validation Tests

    func testValidateDICOMFileWithNonExistentFile() {
        let decoder = DCMDecoder()
        let result = decoder.validateDICOMFile("/nonexistent/file.dcm")

        XCTAssertFalse(result.isValid, "Validation should fail for nonexistent file")
        XCTAssertFalse(result.issues.isEmpty, "Should have validation issues")
        XCTAssertTrue(result.issues.contains("File does not exist"), "Should report file does not exist")
    }

    func testValidateDICOMFileWithEmptyPath() {
        let decoder = DCMDecoder()
        let result = decoder.validateDICOMFile("")

        XCTAssertFalse(result.isValid, "Validation should fail for empty path")
        XCTAssertFalse(result.issues.isEmpty, "Should have validation issues")
    }

    func testIsValidWithUninitializedDecoder() {
        let decoder = DCMDecoder()

        XCTAssertFalse(decoder.isValid(), "Uninitialized decoder should not be valid")
    }

    func testGetValidationStatusDetails() {
        let decoder = DCMDecoder()
        let status = decoder.getValidationStatus()

        // Verify all status fields are present
        XCTAssertNotNil(status.isValid, "Status should have isValid field")
        XCTAssertNotNil(status.width, "Status should have width field")
        XCTAssertNotNil(status.height, "Status should have height field")
        XCTAssertNotNil(status.hasPixels, "Status should have hasPixels field")
        XCTAssertNotNil(status.isCompressed, "Status should have isCompressed field")

        // Verify initial values
        XCTAssertFalse(status.isValid, "Initial status should be invalid")
        XCTAssertFalse(status.hasPixels, "Initial status should have no pixels")
        XCTAssertFalse(status.isCompressed, "Initial status should not be compressed")
    }

    // MARK: - Convenience Property Tests

    func testImageDimensionsProperty() {
        let decoder = DCMDecoder()
        let dimensions = decoder.imageDimensions

        XCTAssertEqual(dimensions.width, decoder.width, "imageDimensions.width should match width")
        XCTAssertEqual(dimensions.height, decoder.height, "imageDimensions.height should match height")
        XCTAssertEqual(dimensions.width, 1, "Initial dimensions width should be 1")
        XCTAssertEqual(dimensions.height, 1, "Initial dimensions height should be 1")
    }

    func testPixelSpacingProperty() {
        let decoder = DCMDecoder()
        let spacing = decoder.pixelSpacing

        XCTAssertEqual(spacing.width, decoder.pixelWidth, "pixelSpacing.width should match pixelWidth")
        XCTAssertEqual(spacing.height, decoder.pixelHeight, "pixelSpacing.height should match pixelHeight")
        XCTAssertEqual(spacing.depth, decoder.pixelDepth, "pixelSpacing.depth should match pixelDepth")

        XCTAssertEqual(spacing.width, 1.0, "Initial spacing width should be 1.0")
        XCTAssertEqual(spacing.height, 1.0, "Initial spacing height should be 1.0")
        XCTAssertEqual(spacing.depth, 1.0, "Initial spacing depth should be 1.0")
    }

    func testWindowSettingsProperty() {
        let decoder = DCMDecoder()
        let settings = decoder.windowSettings

        XCTAssertEqual(settings.center, decoder.windowCenter, "windowSettings.center should match windowCenter")
        XCTAssertEqual(settings.width, decoder.windowWidth, "windowSettings.width should match windowWidth")

        XCTAssertEqual(settings.center, 0.0, "Initial window center should be 0.0")
        XCTAssertEqual(settings.width, 0.0, "Initial window width should be 0.0")
    }

    func testRescaleParametersProperty() {
        let decoder = DCMDecoder()
        let parameters = decoder.rescaleParameters

        XCTAssertEqual(parameters.intercept, 0.0, "Initial rescale intercept should be 0.0")
        XCTAssertEqual(parameters.slope, 1.0, "Initial rescale slope should be 1.0")
    }

    func testApplyRescaleMethod() {
        let decoder = DCMDecoder()

        // Test with default slope (1.0) and intercept (0.0)
        let value1 = decoder.applyRescale(to: 100.0)
        XCTAssertEqual(value1, 100.0, accuracy: 0.01, "Should apply default rescale correctly")

        let value2 = decoder.applyRescale(to: 0.0)
        XCTAssertEqual(value2, 0.0, accuracy: 0.01, "Should handle zero value")

        let value3 = decoder.applyRescale(to: -50.0)
        XCTAssertEqual(value3, -50.0, accuracy: 0.01, "Should handle negative value")
    }

    // MARK: - V2 API Tests (Type-Safe Structs)

    func testPixelSpacingV2Property() {
        let decoder = DCMDecoder()
        let spacingV2 = decoder.pixelSpacingV2

        // Verify V2 API returns PixelSpacing struct with correct values
        XCTAssertEqual(spacingV2.x, decoder.pixelWidth, "pixelSpacingV2.x should match pixelWidth")
        XCTAssertEqual(spacingV2.y, decoder.pixelHeight, "pixelSpacingV2.y should match pixelHeight")
        XCTAssertEqual(spacingV2.z, decoder.pixelDepth, "pixelSpacingV2.z should match pixelDepth")

        // Verify default values
        XCTAssertEqual(spacingV2.x, 1.0, "Initial spacing x should be 1.0")
        XCTAssertEqual(spacingV2.y, 1.0, "Initial spacing y should be 1.0")
        XCTAssertEqual(spacingV2.z, 1.0, "Initial spacing z should be 1.0")

        // Verify V2 API returns equivalent values to old tuple-based API
        let spacingOld = decoder.pixelSpacing
        XCTAssertEqual(spacingV2.x, spacingOld.width, "V2 API should match old API width")
        XCTAssertEqual(spacingV2.y, spacingOld.height, "V2 API should match old API height")
        XCTAssertEqual(spacingV2.z, spacingOld.depth, "V2 API should match old API depth")
    }

    func testWindowSettingsV2Property() {
        let decoder = DCMDecoder()
        let settingsV2 = decoder.windowSettingsV2

        // Verify V2 API returns WindowSettings struct with correct values
        XCTAssertEqual(settingsV2.center, decoder.windowCenter, "windowSettingsV2.center should match windowCenter")
        XCTAssertEqual(settingsV2.width, decoder.windowWidth, "windowSettingsV2.width should match windowWidth")

        // Verify default values
        XCTAssertEqual(settingsV2.center, 0.0, "Initial window center should be 0.0")
        XCTAssertEqual(settingsV2.width, 0.0, "Initial window width should be 0.0")

        // Verify V2 API returns equivalent values to old tuple-based API
        let settingsOld = decoder.windowSettings
        XCTAssertEqual(settingsV2.center, settingsOld.center, "V2 API should match old API center")
        XCTAssertEqual(settingsV2.width, settingsOld.width, "V2 API should match old API width")
    }

    func testRescaleParametersV2Property() {
        let decoder = DCMDecoder()
        let parametersV2 = decoder.rescaleParametersV2

        // Verify default values
        XCTAssertEqual(parametersV2.intercept, 0.0, "Initial rescale intercept should be 0.0")
        XCTAssertEqual(parametersV2.slope, 1.0, "Initial rescale slope should be 1.0")

        // Verify V2 API returns equivalent values to old tuple-based API
        let parametersOld = decoder.rescaleParameters
        XCTAssertEqual(parametersV2.intercept, parametersOld.intercept, "V2 API should match old API intercept")
        XCTAssertEqual(parametersV2.slope, parametersOld.slope, "V2 API should match old API slope")

        // Verify isIdentity property
        XCTAssertTrue(parametersV2.isIdentity, "Default parameters should be identity transformation")
    }

    func testPixelSpacingV2WithLoadedFile() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()
        let decoder = try DCMDecoder(contentsOf: fileURL)

        let spacingV2 = decoder.pixelSpacingV2
        let spacingOld = decoder.pixelSpacing

        // Verify V2 API matches old API with real file data
        XCTAssertEqual(spacingV2.x, spacingOld.width, "V2 API should match old API with loaded file")
        XCTAssertEqual(spacingV2.y, spacingOld.height, "V2 API should match old API with loaded file")
        XCTAssertEqual(spacingV2.z, spacingOld.depth, "V2 API should match old API with loaded file")

        // Verify spacing values match decoder properties
        XCTAssertEqual(spacingV2.x, decoder.pixelWidth, "V2 x should match pixelWidth")
        XCTAssertEqual(spacingV2.y, decoder.pixelHeight, "V2 y should match pixelHeight")
        XCTAssertEqual(spacingV2.z, decoder.pixelDepth, "V2 z should match pixelDepth")
    }

    func testWindowSettingsV2WithLoadedFile() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()
        let decoder = try DCMDecoder(contentsOf: fileURL)

        let settingsV2 = decoder.windowSettingsV2
        let settingsOld = decoder.windowSettings

        // Verify V2 API matches old API with real file data
        XCTAssertEqual(settingsV2.center, settingsOld.center, "V2 API should match old API with loaded file")
        XCTAssertEqual(settingsV2.width, settingsOld.width, "V2 API should match old API with loaded file")

        // Verify settings values match decoder properties
        XCTAssertEqual(settingsV2.center, decoder.windowCenter, "V2 center should match windowCenter")
        XCTAssertEqual(settingsV2.width, decoder.windowWidth, "V2 width should match windowWidth")
    }

    func testRescaleParametersV2WithLoadedFile() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()
        let decoder = try DCMDecoder(contentsOf: fileURL)

        let parametersV2 = decoder.rescaleParametersV2
        let parametersOld = decoder.rescaleParameters

        // Verify V2 API matches old API with real file data
        XCTAssertEqual(parametersV2.intercept, parametersOld.intercept, "V2 API should match old API with loaded file")
        XCTAssertEqual(parametersV2.slope, parametersOld.slope, "V2 API should match old API with loaded file")

        // Verify apply() method produces same result as decoder's applyRescale
        let testValue = 100.0
        let v2Result = parametersV2.apply(to: testValue)
        let decoderResult = decoder.applyRescale(to: testValue)
        XCTAssertEqual(v2Result, decoderResult, accuracy: 0.01, "V2 apply() should match decoder applyRescale()")
    }

    func testCalculateOptimalWindowV2() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()
        let decoder = try DCMDecoder(contentsOf: fileURL)

        // Test V2 API
        guard let settingsV2 = decoder.calculateOptimalWindowV2() else {
            throw XCTSkip("File has no pixel data for optimal window calculation")
        }

        // Test old API
        guard let settingsOld = decoder.calculateOptimalWindow() else {
            XCTFail("Old API returned nil but V2 API returned non-nil")
            return
        }

        // Verify V2 API returns equivalent values to old tuple-based API
        XCTAssertEqual(settingsV2.center, settingsOld.center, accuracy: 0.01, "V2 API should match old API center")
        XCTAssertEqual(settingsV2.width, settingsOld.width, accuracy: 0.01, "V2 API should match old API width")

        // Verify returned settings are valid
        XCTAssertTrue(settingsV2.isValid, "Calculated settings should be valid")
        XCTAssertGreaterThan(settingsV2.width, 0, "Calculated window width should be positive")
    }

    func testCalculateOptimalWindowV2WithNoPixelData() {
        // Create empty decoder with no pixel data
        let decoder = DCMDecoder()

        // Both V2 and old API should return nil for empty decoder
        let settingsV2 = decoder.calculateOptimalWindowV2()
        let settingsOld = decoder.calculateOptimalWindow()

        XCTAssertNil(settingsV2, "V2 API should return nil when no pixel data")
        XCTAssertNil(settingsOld, "Old API should return nil when no pixel data")
    }

    func testV2APIStructTypeSafety() {
        let decoder = DCMDecoder()

        // Verify V2 APIs return the correct struct types
        let spacing: PixelSpacing = decoder.pixelSpacingV2
        let settings: WindowSettings = decoder.windowSettingsV2
        let parameters: RescaleParameters = decoder.rescaleParametersV2

        // Verify struct conformances through usage
        _ = spacing.isValid
        _ = settings.isValid
        _ = parameters.isIdentity

        // This test primarily verifies compile-time type safety
        XCTAssertNotNil(spacing, "Should compile with PixelSpacing type")
        XCTAssertNotNil(settings, "Should compile with WindowSettings type")
        XCTAssertNotNil(parameters, "Should compile with RescaleParameters type")
    }

    func testV2APIStructCodableConformance() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()
        let decoder = try DCMDecoder(contentsOf: fileURL)

        // Get V2 structs
        let spacing = decoder.pixelSpacingV2
        let settings = decoder.windowSettingsV2
        let parameters = decoder.rescaleParametersV2

        // Verify all structs can be encoded/decoded via JSON
        let encoder = JSONEncoder()
        let jsonDecoder = JSONDecoder()

        // Test PixelSpacing Codable
        let spacingData = try encoder.encode(spacing)
        let spacingDecoded = try jsonDecoder.decode(PixelSpacing.self, from: spacingData)
        XCTAssertEqual(spacing, spacingDecoded, "PixelSpacing should encode/decode correctly")

        // Test WindowSettings Codable
        let settingsData = try encoder.encode(settings)
        let settingsDecoded = try jsonDecoder.decode(WindowSettings.self, from: settingsData)
        XCTAssertEqual(settings, settingsDecoded, "WindowSettings should encode/decode correctly")

        // Test RescaleParameters Codable
        let parametersData = try encoder.encode(parameters)
        let parametersDecoded = try jsonDecoder.decode(RescaleParameters.self, from: parametersData)
        XCTAssertEqual(parameters, parametersDecoded, "RescaleParameters should encode/decode correctly")
    }

    // MARK: - Image Type Detection Tests

    func testIsGrayscaleProperty() {
        let decoder = DCMDecoder()

        // Default should be grayscale (samplesPerPixel = 1)
        XCTAssertTrue(decoder.isGrayscale, "Default should be grayscale")
    }

    func testIsColorImageProperty() {
        let decoder = DCMDecoder()

        // Default should not be color (samplesPerPixel = 1, not 3)
        XCTAssertFalse(decoder.isColorImage, "Default should not be color")
    }

    func testIsMultiFrameProperty() {
        let decoder = DCMDecoder()

        // Default should not be multi-frame (nImages = 1)
        XCTAssertFalse(decoder.isMultiFrame, "Default should not be multi-frame")
    }

    func testPixelRepresentationProperties() {
        let decoder = DCMDecoder()

        // Test initial pixel representation
        XCTAssertEqual(decoder.pixelRepresentationTagValue, 0, "Default pixel representation should be 0 (unsigned)")
        XCTAssertFalse(decoder.isSignedPixelRepresentation, "Default should not be signed")
    }

    // MARK: - Info Dictionary Tests

    func testInfoMethodWithEmptyDecoder() {
        let decoder = DCMDecoder()

        // Test info method with uninitialized decoder
        let patientName = decoder.info(for: 0x00100010)
        XCTAssertEqual(patientName, "", "Info should return empty string for uninitialized decoder")

        let modality = decoder.info(for: 0x00080060)
        XCTAssertEqual(modality, "", "Info should return empty string for uninitialized decoder")
    }

    func testIntValueMethodWithEmptyDecoder() {
        let decoder = DCMDecoder()

        // Test intValue method with uninitialized decoder
        let rows = decoder.intValue(for: 0x00280010)
        XCTAssertNil(rows, "intValue should return nil for uninitialized decoder")

        let columns = decoder.intValue(for: 0x00280011)
        XCTAssertNil(columns, "intValue should return nil for uninitialized decoder")
    }

    func testDoubleValueMethodWithEmptyDecoder() {
        let decoder = DCMDecoder()

        // Test doubleValue method with uninitialized decoder
        let pixelSpacing = decoder.doubleValue(for: 0x00280030)
        XCTAssertNil(pixelSpacing, "doubleValue should return nil for uninitialized decoder")

        let sliceThickness = decoder.doubleValue(for: 0x00180050)
        XCTAssertNil(sliceThickness, "doubleValue should return nil for uninitialized decoder")
    }

    func testGetAllTagsWithEmptyDecoder() {
        let decoder = DCMDecoder()

        // Test getAllTags with uninitialized decoder
        let tags = decoder.getAllTags()
        XCTAssertTrue(tags.isEmpty, "getAllTags should return empty dictionary for uninitialized decoder")
    }

    func testGetPatientInfoWithEmptyDecoder() {
        let decoder = DCMDecoder()

        // Test getPatientInfo with uninitialized decoder
        let patientInfo = decoder.getPatientInfo()
        XCTAssertNotNil(patientInfo, "getPatientInfo should return dictionary")
        XCTAssertEqual(patientInfo["Name"], "", "Patient name should be empty")
        XCTAssertEqual(patientInfo["ID"], "", "Patient ID should be empty")
        XCTAssertEqual(patientInfo["Sex"], "", "Patient sex should be empty")
        XCTAssertEqual(patientInfo["Age"], "", "Patient age should be empty")
    }

    func testGetStudyInfoWithEmptyDecoder() {
        let decoder = DCMDecoder()

        // Test getStudyInfo with uninitialized decoder
        let studyInfo = decoder.getStudyInfo()
        XCTAssertNotNil(studyInfo, "getStudyInfo should return dictionary")
        XCTAssertEqual(studyInfo["StudyInstanceUID"], "", "Study Instance UID should be empty")
        XCTAssertEqual(studyInfo["StudyID"], "", "Study ID should be empty")
        XCTAssertEqual(studyInfo["StudyDate"], "", "Study date should be empty")
        XCTAssertEqual(studyInfo["StudyTime"], "", "Study time should be empty")
        XCTAssertEqual(studyInfo["StudyDescription"], "", "Study description should be empty")
        XCTAssertEqual(studyInfo["ReferringPhysician"], "", "Referring physician should be empty")
    }

    func testGetSeriesInfoWithEmptyDecoder() {
        let decoder = DCMDecoder()

        // Test getSeriesInfo with uninitialized decoder
        let seriesInfo = decoder.getSeriesInfo()
        XCTAssertNotNil(seriesInfo, "getSeriesInfo should return dictionary")
        XCTAssertEqual(seriesInfo["SeriesInstanceUID"], "", "Series Instance UID should be empty")
        XCTAssertEqual(seriesInfo["SeriesNumber"], "", "Series number should be empty")
        XCTAssertEqual(seriesInfo["SeriesDate"], "", "Series date should be empty")
        XCTAssertEqual(seriesInfo["SeriesTime"], "", "Series time should be empty")
        XCTAssertEqual(seriesInfo["SeriesDescription"], "", "Series description should be empty")
        XCTAssertEqual(seriesInfo["Modality"], "", "Modality should be empty")
    }

    // MARK: - Metadata Extraction Tests

    func testCommonDICOMTagsExtraction() {
        let decoder = DCMDecoder()

        // Test common DICOM tags return empty strings when decoder is uninitialized
        // Patient Information Tags
        XCTAssertEqual(decoder.info(for: 0x00100010), "", "Patient Name should return empty string")
        XCTAssertEqual(decoder.info(for: 0x00100020), "", "Patient ID should return empty string")
        XCTAssertEqual(decoder.info(for: 0x00100030), "", "Patient Birth Date should return empty string")
        XCTAssertEqual(decoder.info(for: 0x00100040), "", "Patient Sex should return empty string")

        // Study Information Tags
        XCTAssertEqual(decoder.info(for: 0x0020000D), "", "Study Instance UID should return empty string")
        XCTAssertEqual(decoder.info(for: 0x00080020), "", "Study Date should return empty string")
        XCTAssertEqual(decoder.info(for: 0x00080030), "", "Study Time should return empty string")
        XCTAssertEqual(decoder.info(for: 0x00081030), "", "Study Description should return empty string")

        // Image Information Tags
        XCTAssertNil(decoder.intValue(for: 0x00280010), "Rows should return nil")
        XCTAssertNil(decoder.intValue(for: 0x00280011), "Columns should return nil")
        XCTAssertEqual(decoder.info(for: 0x00080060), "", "Modality should return empty string")
    }

    func testPatientInformationTagsExtraction() {
        let decoder = DCMDecoder()

        // Test patient information tags
        let patientName = decoder.info(for: 0x00100010)
        XCTAssertEqual(patientName, "", "Patient Name should be empty for uninitialized decoder")

        let patientID = decoder.info(for: 0x00100020)
        XCTAssertEqual(patientID, "", "Patient ID should be empty for uninitialized decoder")

        let patientBirthDate = decoder.info(for: 0x00100030)
        XCTAssertEqual(patientBirthDate, "", "Patient Birth Date should be empty for uninitialized decoder")

        let patientSex = decoder.info(for: 0x00100040)
        XCTAssertEqual(patientSex, "", "Patient Sex should be empty for uninitialized decoder")

        let patientAge = decoder.info(for: 0x00101010)
        XCTAssertEqual(patientAge, "", "Patient Age should be empty for uninitialized decoder")

        let patientWeight = decoder.info(for: 0x00101030)
        XCTAssertEqual(patientWeight, "", "Patient Weight should be empty for uninitialized decoder")
    }

    func testStudyInformationTagsExtraction() {
        let decoder = DCMDecoder()

        // Test study information tags
        let studyInstanceUID = decoder.info(for: 0x0020000D)
        XCTAssertEqual(studyInstanceUID, "", "Study Instance UID should be empty for uninitialized decoder")

        let studyID = decoder.info(for: 0x00200010)
        XCTAssertEqual(studyID, "", "Study ID should be empty for uninitialized decoder")

        let studyDate = decoder.info(for: 0x00080020)
        XCTAssertEqual(studyDate, "", "Study Date should be empty for uninitialized decoder")

        let studyTime = decoder.info(for: 0x00080030)
        XCTAssertEqual(studyTime, "", "Study Time should be empty for uninitialized decoder")

        let studyDescription = decoder.info(for: 0x00081030)
        XCTAssertEqual(studyDescription, "", "Study Description should be empty for uninitialized decoder")

        let referringPhysician = decoder.info(for: 0x00080090)
        XCTAssertEqual(referringPhysician, "", "Referring Physician should be empty for uninitialized decoder")

        let accessionNumber = decoder.info(for: 0x00080050)
        XCTAssertEqual(accessionNumber, "", "Accession Number should be empty for uninitialized decoder")
    }

    func testSeriesInformationTagsExtraction() {
        let decoder = DCMDecoder()

        // Test series information tags
        let seriesInstanceUID = decoder.info(for: 0x0020000E)
        XCTAssertEqual(seriesInstanceUID, "", "Series Instance UID should be empty for uninitialized decoder")

        let seriesNumber = decoder.info(for: 0x00200011)
        XCTAssertEqual(seriesNumber, "", "Series Number should be empty for uninitialized decoder")

        let seriesDate = decoder.info(for: 0x00080021)
        XCTAssertEqual(seriesDate, "", "Series Date should be empty for uninitialized decoder")

        let seriesTime = decoder.info(for: 0x00080031)
        XCTAssertEqual(seriesTime, "", "Series Time should be empty for uninitialized decoder")

        let seriesDescription = decoder.info(for: 0x0008103E)
        XCTAssertEqual(seriesDescription, "", "Series Description should be empty for uninitialized decoder")

        let modality = decoder.info(for: 0x00080060)
        XCTAssertEqual(modality, "", "Modality should be empty for uninitialized decoder")

        let bodyPartExamined = decoder.info(for: 0x00180015)
        XCTAssertEqual(bodyPartExamined, "", "Body Part Examined should be empty for uninitialized decoder")
    }

    func testImageInformationTagsExtraction() {
        let decoder = DCMDecoder()

        // Test image dimension tags
        let rows = decoder.intValue(for: 0x00280010)
        XCTAssertNil(rows, "Rows should return nil for uninitialized decoder")

        let columns = decoder.intValue(for: 0x00280011)
        XCTAssertNil(columns, "Columns should return nil for uninitialized decoder")

        let bitsAllocated = decoder.intValue(for: 0x00280100)
        XCTAssertNil(bitsAllocated, "Bits Allocated should return nil for uninitialized decoder")

        let bitsStored = decoder.intValue(for: 0x00280101)
        XCTAssertNil(bitsStored, "Bits Stored should return nil for uninitialized decoder")

        let highBit = decoder.intValue(for: 0x00280102)
        XCTAssertNil(highBit, "High Bit should return nil for uninitialized decoder")

        let samplesPerPixel = decoder.intValue(for: 0x00280002)
        XCTAssertNil(samplesPerPixel, "Samples Per Pixel should return nil for uninitialized decoder")

        let photometricInterpretation = decoder.info(for: 0x00280004)
        XCTAssertEqual(photometricInterpretation, "", "Photometric Interpretation should be empty for uninitialized decoder")

        let pixelRepresentation = decoder.intValue(for: 0x00280103)
        XCTAssertNil(pixelRepresentation, "Pixel Representation should return nil for uninitialized decoder")
    }

    func testImagePositionOrientationTagsExtraction() {
        let decoder = DCMDecoder()

        // Test image position and orientation tags
        let imagePositionPatient = decoder.info(for: 0x00200032)
        XCTAssertEqual(imagePositionPatient, "", "Image Position (Patient) should be empty for uninitialized decoder")

        let imageOrientationPatient = decoder.info(for: 0x00200037)
        XCTAssertEqual(imageOrientationPatient, "", "Image Orientation (Patient) should be empty for uninitialized decoder")

        let sliceLocation = decoder.doubleValue(for: 0x00201041)
        XCTAssertNil(sliceLocation, "Slice Location should return nil for uninitialized decoder")

        let sliceThickness = decoder.doubleValue(for: 0x00180050)
        XCTAssertNil(sliceThickness, "Slice Thickness should return nil for uninitialized decoder")

        let pixelSpacing = decoder.doubleValue(for: 0x00280030)
        XCTAssertNil(pixelSpacing, "Pixel Spacing should return nil for uninitialized decoder")
    }

    func testWindowingTagsExtraction() {
        let decoder = DCMDecoder()

        // Test windowing tags
        let windowCenter = decoder.doubleValue(for: 0x00281050)
        XCTAssertNil(windowCenter, "Window Center should return nil for uninitialized decoder")

        let windowWidth = decoder.doubleValue(for: 0x00281051)
        XCTAssertNil(windowWidth, "Window Width should return nil for uninitialized decoder")

        let rescaleIntercept = decoder.doubleValue(for: 0x00281052)
        XCTAssertNil(rescaleIntercept, "Rescale Intercept should return nil for uninitialized decoder")

        let rescaleSlope = decoder.doubleValue(for: 0x00281053)
        XCTAssertNil(rescaleSlope, "Rescale Slope should return nil for uninitialized decoder")

        let rescaleType = decoder.info(for: 0x00281054)
        XCTAssertEqual(rescaleType, "", "Rescale Type should be empty for uninitialized decoder")
    }

    func testModalitySpecificTagsExtraction() {
        let decoder = DCMDecoder()

        // Test CT-specific tags
        let kvp = decoder.doubleValue(for: 0x00180060)
        XCTAssertNil(kvp, "KVP should return nil for uninitialized decoder")

        let exposureTime = decoder.doubleValue(for: 0x00181150)
        XCTAssertNil(exposureTime, "Exposure Time should return nil for uninitialized decoder")

        let xRayTubeCurrent = decoder.doubleValue(for: 0x00181151)
        XCTAssertNil(xRayTubeCurrent, "X-Ray Tube Current should return nil for uninitialized decoder")

        // Test MR-specific tags
        let repetitionTime = decoder.doubleValue(for: 0x00180080)
        XCTAssertNil(repetitionTime, "Repetition Time should return nil for uninitialized decoder")

        let echoTime = decoder.doubleValue(for: 0x00180081)
        XCTAssertNil(echoTime, "Echo Time should return nil for uninitialized decoder")

        let magneticFieldStrength = decoder.doubleValue(for: 0x00180087)
        XCTAssertNil(magneticFieldStrength, "Magnetic Field Strength should return nil for uninitialized decoder")

        let imagingFrequency = decoder.doubleValue(for: 0x00180084)
        XCTAssertNil(imagingFrequency, "Imaging Frequency should return nil for uninitialized decoder")
    }

    func testEquipmentInformationTagsExtraction() {
        let decoder = DCMDecoder()

        // Test equipment information tags
        let manufacturer = decoder.info(for: 0x00080070)
        XCTAssertEqual(manufacturer, "", "Manufacturer should be empty for uninitialized decoder")

        let manufacturerModelName = decoder.info(for: 0x00081090)
        XCTAssertEqual(manufacturerModelName, "", "Manufacturer Model Name should be empty for uninitialized decoder")

        let stationName = decoder.info(for: 0x00081010)
        XCTAssertEqual(stationName, "", "Station Name should be empty for uninitialized decoder")

        let institutionName = decoder.info(for: 0x00080080)
        XCTAssertEqual(institutionName, "", "Institution Name should be empty for uninitialized decoder")

        let softwareVersions = decoder.info(for: 0x00181020)
        XCTAssertEqual(softwareVersions, "", "Software Versions should be empty for uninitialized decoder")
    }

    func testInstanceInformationTagsExtraction() {
        let decoder = DCMDecoder()

        // Test instance information tags
        let sopInstanceUID = decoder.info(for: 0x00080018)
        XCTAssertEqual(sopInstanceUID, "", "SOP Instance UID should be empty for uninitialized decoder")

        let sopClassUID = decoder.info(for: 0x00080016)
        XCTAssertEqual(sopClassUID, "", "SOP Class UID should be empty for uninitialized decoder")

        let instanceNumber = decoder.info(for: 0x00200013)
        XCTAssertEqual(instanceNumber, "", "Instance Number should be empty for uninitialized decoder")

        let contentDate = decoder.info(for: 0x00080023)
        XCTAssertEqual(contentDate, "", "Content Date should be empty for uninitialized decoder")

        let contentTime = decoder.info(for: 0x00080033)
        XCTAssertEqual(contentTime, "", "Content Time should be empty for uninitialized decoder")

        let acquisitionDate = decoder.info(for: 0x00080022)
        XCTAssertEqual(acquisitionDate, "", "Acquisition Date should be empty for uninitialized decoder")

        let acquisitionTime = decoder.info(for: 0x00080032)
        XCTAssertEqual(acquisitionTime, "", "Acquisition Time should be empty for uninitialized decoder")
    }

    func testTagDataTypeValidation() {
        let decoder = DCMDecoder()

        // Test that info() returns strings
        let patientName = decoder.info(for: 0x00100010)
        XCTAssertTrue(patientName.isEmpty, "info() should return empty string for uninitialized decoder")

        // Test that intValue() returns Int? (nil for uninitialized)
        let rows = decoder.intValue(for: 0x00280010)
        XCTAssertNil(rows, "intValue() should return nil for uninitialized decoder")

        // Test that doubleValue() returns Double? (nil for uninitialized)
        let pixelSpacing = decoder.doubleValue(for: 0x00280030)
        XCTAssertNil(pixelSpacing, "doubleValue() should return nil for uninitialized decoder")
    }

    func testMissingTagHandling() {
        let decoder = DCMDecoder()

        // Test with arbitrary/non-standard tag IDs
        let nonExistentTag1 = decoder.info(for: 0xFFFFFFFF)
        XCTAssertEqual(nonExistentTag1, "", "Non-existent tag should return empty string")

        let nonExistentTag2 = decoder.info(for: 0x00000000)
        XCTAssertEqual(nonExistentTag2, "", "Zero tag should return empty string")

        let nonExistentIntValue = decoder.intValue(for: 0xFFFFFFFF)
        XCTAssertNil(nonExistentIntValue, "Non-existent tag should return nil for intValue")

        let nonExistentDoubleValue = decoder.doubleValue(for: 0xFFFFFFFF)
        XCTAssertNil(nonExistentDoubleValue, "Non-existent tag should return nil for doubleValue")
    }

    func testMetadataExtractionConsistency() {
        let decoder = DCMDecoder()

        // Test that multiple calls to the same tag return consistent results
        let patientName1 = decoder.info(for: 0x00100010)
        let patientName2 = decoder.info(for: 0x00100010)
        XCTAssertEqual(patientName1, patientName2, "Multiple calls should return consistent results")

        let rows1 = decoder.intValue(for: 0x00280010)
        let rows2 = decoder.intValue(for: 0x00280010)
        XCTAssertEqual(rows1, rows2, "Multiple intValue calls should return consistent results")

        let pixelSpacing1 = decoder.doubleValue(for: 0x00280030)
        let pixelSpacing2 = decoder.doubleValue(for: 0x00280030)
        XCTAssertEqual(pixelSpacing1, pixelSpacing2, "Multiple doubleValue calls should return consistent results")
    }

    func testGetAllTagsReturnsValidDictionary() {
        let decoder = DCMDecoder()

        // Test getAllTags returns a valid dictionary
        let allTags = decoder.getAllTags()
        XCTAssertNotNil(allTags, "getAllTags should return a non-nil dictionary")
        XCTAssertTrue(allTags.isEmpty, "getAllTags should be empty for uninitialized decoder")
    }

    func testPatientInfoDictionaryStructure() {
        let decoder = DCMDecoder()

        // Test getPatientInfo returns expected keys
        let patientInfo = decoder.getPatientInfo()
        XCTAssertNotNil(patientInfo["Name"], "Patient info should have Name key")
        XCTAssertNotNil(patientInfo["ID"], "Patient info should have ID key")
        XCTAssertNotNil(patientInfo["Sex"], "Patient info should have Sex key")
        XCTAssertNotNil(patientInfo["Age"], "Patient info should have Age key")

        // All values should be strings (dictionary values are typed as String)
    }

    func testStudyInfoDictionaryStructure() {
        let decoder = DCMDecoder()

        // Test getStudyInfo returns expected keys
        let studyInfo = decoder.getStudyInfo()
        XCTAssertNotNil(studyInfo["StudyInstanceUID"], "Study info should have StudyInstanceUID key")
        XCTAssertNotNil(studyInfo["StudyID"], "Study info should have StudyID key")
        XCTAssertNotNil(studyInfo["StudyDate"], "Study info should have StudyDate key")
        XCTAssertNotNil(studyInfo["StudyTime"], "Study info should have StudyTime key")
        XCTAssertNotNil(studyInfo["StudyDescription"], "Study info should have StudyDescription key")
        XCTAssertNotNil(studyInfo["ReferringPhysician"], "Study info should have ReferringPhysician key")

        // All values should be strings (dictionary values are typed as String)
    }

    func testSeriesInfoDictionaryStructure() {
        let decoder = DCMDecoder()

        // Test getSeriesInfo returns expected keys
        let seriesInfo = decoder.getSeriesInfo()
        XCTAssertNotNil(seriesInfo["SeriesInstanceUID"], "Series info should have SeriesInstanceUID key")
        XCTAssertNotNil(seriesInfo["SeriesNumber"], "Series info should have SeriesNumber key")
        XCTAssertNotNil(seriesInfo["SeriesDate"], "Series info should have SeriesDate key")
        XCTAssertNotNil(seriesInfo["SeriesTime"], "Series info should have SeriesTime key")
        XCTAssertNotNil(seriesInfo["SeriesDescription"], "Series info should have SeriesDescription key")
        XCTAssertNotNil(seriesInfo["Modality"], "Series info should have Modality key")

        // All values should be strings (dictionary values are typed as String)
    }

    // MARK: - DicomTag Enum Tests

    func testDicomTagEnumUsage() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()

        // Load the file using throwing initializer
        let decoder = try DCMDecoder(contentsOf: fileURL)

        // Test info(for: DicomTag) method
        let patientName = decoder.info(for: .patientName)
        XCTAssertNotNil(patientName, "Should be able to retrieve patient name using DicomTag enum")
        // Patient name may be empty in some test files, so we just verify it returns a string

        // Test intValue(for: DicomTag) method
        let rows = decoder.intValue(for: .rows)
        XCTAssertNotNil(rows, "Should be able to retrieve rows using DicomTag enum")
        if let rowsValue = rows {
            XCTAssertGreaterThan(rowsValue, 0, "Rows value should be greater than 0")
            XCTAssertEqual(rowsValue, decoder.height, "Rows value should match decoder.height")
        }

        let columns = decoder.intValue(for: .columns)
        XCTAssertNotNil(columns, "Should be able to retrieve columns using DicomTag enum")
        if let columnsValue = columns {
            XCTAssertGreaterThan(columnsValue, 0, "Columns value should be greater than 0")
            XCTAssertEqual(columnsValue, decoder.width, "Columns value should match decoder.width")
        }

        // Test doubleValue(for: DicomTag) method
        // Note: windowCenter may not be present in all DICOM files, so we test with pixelWidth instead
        let pixelSpacingStr = decoder.info(for: .pixelSpacing)
        if !pixelSpacingStr.isEmpty {
            // Pixel spacing is typically stored as "row\\column" string
            // We can verify the method works even if we don't validate the exact value
            let spacing = decoder.doubleValue(for: .pixelSpacing)
            // The doubleValue method may not parse multi-value strings correctly,
            // so we just verify it returns a value or nil without crashing
            _ = spacing
        }

        // Test rescale slope and intercept if available
        let rescaleSlope = decoder.doubleValue(for: .rescaleSlope)
        let rescaleIntercept = decoder.doubleValue(for: .rescaleIntercept)
        // These may be nil in some files, just verify the methods don't crash
        _ = rescaleSlope
        _ = rescaleIntercept
    }

    func testDicomTagVsRawValueEquivalence() throws {
        // Get a valid DICOM file from fixtures
        let fileURL = try getAnyDICOMFile()

        // Load the file using throwing initializer
        let decoder = try DCMDecoder(contentsOf: fileURL)

        // Test that DicomTag enum and raw hex values return identical results

        // Test info(for:) equivalence
        let patientNameEnum = decoder.info(for: .patientName)
        let patientNameHex = decoder.info(for: 0x00100010)
        XCTAssertEqual(patientNameEnum, patientNameHex,
                       "info(for: .patientName) should equal info(for: 0x00100010)")

        let modalityEnum = decoder.info(for: .modality)
        let modalityHex = decoder.info(for: 0x00080060)
        XCTAssertEqual(modalityEnum, modalityHex,
                       "info(for: .modality) should equal info(for: 0x00080060)")

        // Test intValue(for:) equivalence
        let rowsEnum = decoder.intValue(for: .rows)
        let rowsHex = decoder.intValue(for: 0x00280010)
        XCTAssertEqual(rowsEnum, rowsHex,
                       "intValue(for: .rows) should equal intValue(for: 0x00280010)")

        let columnsEnum = decoder.intValue(for: .columns)
        let columnsHex = decoder.intValue(for: 0x00280011)
        XCTAssertEqual(columnsEnum, columnsHex,
                       "intValue(for: .columns) should equal intValue(for: 0x00280011)")

        let bitsAllocatedEnum = decoder.intValue(for: .bitsAllocated)
        let bitsAllocatedHex = decoder.intValue(for: 0x00280100)
        XCTAssertEqual(bitsAllocatedEnum, bitsAllocatedHex,
                       "intValue(for: .bitsAllocated) should equal intValue(for: 0x00280100)")

        // Test doubleValue(for:) equivalence
        let rescaleSlopeEnum = decoder.doubleValue(for: .rescaleSlope)
        let rescaleSlopeHex = decoder.doubleValue(for: 0x00281053)
        XCTAssertEqual(rescaleSlopeEnum, rescaleSlopeHex,
                       "doubleValue(for: .rescaleSlope) should equal doubleValue(for: 0x00281053)")

        let rescaleInterceptEnum = decoder.doubleValue(for: .rescaleIntercept)
        let rescaleInterceptHex = decoder.doubleValue(for: 0x00281052)
        XCTAssertEqual(rescaleInterceptEnum, rescaleInterceptHex,
                       "doubleValue(for: .rescaleIntercept) should equal doubleValue(for: 0x00281052)")

        let windowCenterEnum = decoder.doubleValue(for: .windowCenter)
        let windowCenterHex = decoder.doubleValue(for: 0x00281050)
        XCTAssertEqual(windowCenterEnum, windowCenterHex,
                       "doubleValue(for: .windowCenter) should equal doubleValue(for: 0x00281050)")

        let windowWidthEnum = decoder.doubleValue(for: .windowWidth)
        let windowWidthHex = decoder.doubleValue(for: 0x00281051)
        XCTAssertEqual(windowWidthEnum, windowWidthHex,
                       "doubleValue(for: .windowWidth) should equal doubleValue(for: 0x00281051)")
    }

    // MARK: - File Loading Tests

    func testSetDicomFilenameWithEmptyPath() {
        let decoder = DCMDecoder()

        // Test with empty filename
        decoder.setDicomFilename("")

        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with empty filename")
        XCTAssertFalse(decoder.isValid(), "Should not be valid with empty filename")
    }

    func testSetDicomFilenameWithNonExistentFile() {
        let decoder = DCMDecoder()

        // Test with nonexistent file
        decoder.setDicomFilename("/nonexistent/file.dcm")

        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with nonexistent file")
        XCTAssertFalse(decoder.isValid(), "Should not be valid with nonexistent file")
    }

    func testSetDicomFilenameWithInvalidPath() {
        let decoder = DCMDecoder()

        // Test with various invalid paths
        decoder.setDicomFilename("/invalid/path/to/file.dcm")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with invalid path")

        decoder.setDicomFilename("relative/path/file.dcm")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with relative invalid path")

        decoder.setDicomFilename("/")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with root directory")
    }

    func testSetDicomFilenameStateReset() {
        let decoder = DCMDecoder()

        // First attempt with nonexistent file
        decoder.setDicomFilename("/nonexistent/file1.dcm")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "First load should fail")

        // Second attempt should also fail and not retain previous state
        decoder.setDicomFilename("/nonexistent/file2.dcm")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Second load should also fail")
        XCTAssertFalse(decoder.isValid(), "Decoder should remain invalid")
    }

    func testSetDicomFilenameThreadSafety() {
        let decoder = DCMDecoder()
        let expectation = self.expectation(description: "Thread-safe file loading")
        expectation.expectedFulfillmentCount = 5

        // Test concurrent file loading attempts
        for i in 0..<5 {
            DispatchQueue.global().async {
                decoder.setDicomFilename("/nonexistent/file\(i).dcm")
                _ = decoder.isValid()
                _ = decoder.dicomFileReadSuccess
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0, handler: nil)
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testLoadDICOMFileAsyncWithEmptyPath() async {
        let decoder = DCMDecoder()

        // Test async loading with empty path
        let success = await decoder.loadDICOMFileAsync("")

        XCTAssertFalse(success, "Async load should fail with empty path")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not have read success")
        XCTAssertFalse(decoder.isValid(), "Should not be valid")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testLoadDICOMFileAsyncWithNonExistentFile() async {
        let decoder = DCMDecoder()

        // Test async loading with nonexistent file
        let success = await decoder.loadDICOMFileAsync("/nonexistent/file.dcm")

        XCTAssertFalse(success, "Async load should fail with nonexistent file")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not have read success")
        XCTAssertFalse(decoder.isValid(), "Should not be valid")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testLoadDICOMFileAsyncMultipleCalls() async {
        let decoder = DCMDecoder()

        // Test multiple async loading attempts
        let success1 = await decoder.loadDICOMFileAsync("/nonexistent/file1.dcm")
        XCTAssertFalse(success1, "First async load should fail")

        let success2 = await decoder.loadDICOMFileAsync("/nonexistent/file2.dcm")
        XCTAssertFalse(success2, "Second async load should fail")

        XCTAssertFalse(decoder.isValid(), "Decoder should remain invalid after multiple failed loads")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testLoadDICOMFileAsyncConcurrentCalls() async {
        let decoder = DCMDecoder()

        // Test concurrent async loading
        async let result1 = decoder.loadDICOMFileAsync("/nonexistent/file1.dcm")
        async let result2 = decoder.loadDICOMFileAsync("/nonexistent/file2.dcm")
        async let result3 = decoder.loadDICOMFileAsync("/nonexistent/file3.dcm")

        let results = await [result1, result2, result3]

        // All should fail
        XCTAssertTrue(results.allSatisfy { !$0 }, "All concurrent loads should fail")
        XCTAssertFalse(decoder.isValid(), "Decoder should remain invalid")
    }

    func testFileLoadingPreservesDecoderState() {
        let decoder = DCMDecoder()

        // Get initial state
        let initialWidth = decoder.width
        let initialHeight = decoder.height
        let initialBitDepth = decoder.bitDepth

        // Attempt to load nonexistent file
        decoder.setDicomFilename("/nonexistent/file.dcm")

        // State should be preserved or reset to defaults
        XCTAssertEqual(decoder.width, initialWidth, "Width should remain unchanged")
        XCTAssertEqual(decoder.height, initialHeight, "Height should remain unchanged")
        XCTAssertEqual(decoder.bitDepth, initialBitDepth, "Bit depth should remain unchanged")
    }

    func testValidationBeforeLoading() {
        let decoder = DCMDecoder()

        // Validate before loading
        let validation1 = decoder.validateDICOMFile("/nonexistent/file.dcm")
        XCTAssertFalse(validation1.isValid, "Validation should fail for nonexistent file")
        XCTAssertFalse(validation1.issues.isEmpty, "Should have validation issues")

        // Validation with empty path
        let validation2 = decoder.validateDICOMFile("")
        XCTAssertFalse(validation2.isValid, "Validation should fail for empty path")

        // Decoder should still be in initial state
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Validation should not trigger file loading")
        XCTAssertFalse(decoder.isValid(), "Decoder should remain invalid")
    }

    func testValidationIssuesContent() {
        let decoder = DCMDecoder()

        // Validate nonexistent file and check issues
        let validation = decoder.validateDICOMFile("/nonexistent/file.dcm")

        XCTAssertFalse(validation.isValid, "Validation should fail")
        XCTAssertGreaterThan(validation.issues.count, 0, "Should have at least one issue")

        // Check that issues contain meaningful messages
        let issuesString = validation.issues.joined(separator: " ")
        XCTAssertFalse(issuesString.isEmpty, "Issues should not be empty")
    }

    func testFileLoadingWithDirectoryPath() {
        let decoder = DCMDecoder()

        // Test loading a directory instead of file
        decoder.setDicomFilename("/tmp")

        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with directory path")
        XCTAssertFalse(decoder.isValid(), "Should not be valid with directory path")
    }

    func testFileLoadingWithSymbolicPaths() {
        let decoder = DCMDecoder()

        // Test with various symbolic paths
        decoder.setDicomFilename("~/nonexistent/file.dcm")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with tilde path")

        decoder.setDicomFilename("./nonexistent/file.dcm")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with relative path")

        decoder.setDicomFilename("../nonexistent/file.dcm")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Should not succeed with parent relative path")
    }

    func testLoadingStateAfterFailure() {
        let decoder = DCMDecoder()

        // Load invalid file
        decoder.setDicomFilename("/nonexistent/file.dcm")

        // Check all state flags
        XCTAssertFalse(decoder.dicomFileReadSuccess, "Read success should be false")
        XCTAssertFalse(decoder.dicomFound, "DICM marker should not be found")
        XCTAssertFalse(decoder.isValid(), "Should not be valid")

        // Check validation status
        let status = decoder.getValidationStatus()
        XCTAssertFalse(status.isValid, "Validation status should be invalid")
        XCTAssertFalse(status.hasPixels, "Should not have pixels")

        // Check pixel buffers are still nil
        XCTAssertNil(decoder.getPixels8(), "pixels8 should be nil")
        XCTAssertNil(decoder.getPixels16(), "pixels16 should be nil")
        XCTAssertNil(decoder.getPixels24(), "pixels24 should be nil")
    }

    // MARK: - Quality Methods Tests

    func testCalculateOptimalWindowWithNoData() {
        let decoder = DCMDecoder()

        // Test calculateOptimalWindow with no pixel data
        let optimal = decoder.calculateOptimalWindow()
        XCTAssertNil(optimal, "calculateOptimalWindow should return nil with no pixel data")
    }

    func testGetQualityMetricsWithNoData() {
        let decoder = DCMDecoder()

        // Test getQualityMetrics with no pixel data
        let metrics = decoder.getQualityMetrics()
        XCTAssertNil(metrics, "getQualityMetrics should return nil with no pixel data")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentAccess() {
        let decoder = DCMDecoder()
        let expectation = self.expectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent reads
        for _ in 0..<10 {
            DispatchQueue.global().async {
                _ = decoder.isValid()
                _ = decoder.width
                _ = decoder.height
                _ = decoder.getValidationStatus()
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testConcurrentInfoAccess() {
        let decoder = DCMDecoder()
        let expectation = self.expectation(description: "Concurrent info access")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent info method calls
        for _ in 0..<10 {
            DispatchQueue.global().async {
                _ = decoder.info(for: 0x00100010)
                _ = decoder.intValue(for: 0x00280010)
                _ = decoder.doubleValue(for: 0x00280030)
                _ = decoder.getPatientInfo()
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0, handler: nil)
    }
}
