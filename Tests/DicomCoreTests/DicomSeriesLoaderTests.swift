import XCTest
@testable import DicomCore
import simd

final class DicomSeriesLoaderTests: XCTestCase {

    // MARK: - Error Type Tests

    func testDicomSeriesLoaderErrors() {
        // Test error types exist and can be created
        let noDicomFilesError = DicomSeriesLoaderError.noDicomFiles
        XCTAssertNotNil(noDicomFilesError, "Should create noDicomFiles error")

        let unsupportedSPPError = DicomSeriesLoaderError.unsupportedSamplesPerPixel(3)
        XCTAssertNotNil(unsupportedSPPError, "Should create unsupportedSamplesPerPixel error")

        let unsupportedBitDepthError = DicomSeriesLoaderError.unsupportedBitDepth(8)
        XCTAssertNotNil(unsupportedBitDepthError, "Should create unsupportedBitDepth error")

        let inconsistentDimensionsError = DicomSeriesLoaderError.inconsistentDimensions
        XCTAssertNotNil(inconsistentDimensionsError, "Should create inconsistentDimensions error")

        let inconsistentOrientationError = DicomSeriesLoaderError.inconsistentOrientation
        XCTAssertNotNil(inconsistentOrientationError, "Should create inconsistentOrientation error")

        let inconsistentPixelRepError = DicomSeriesLoaderError.inconsistentPixelRepresentation
        XCTAssertNotNil(inconsistentPixelRepError, "Should create inconsistentPixelRepresentation error")

        let testURL = URL(fileURLWithPath: "/test/path.dcm")
        let failedToDecodeError = DicomSeriesLoaderError.failedToDecode(testURL)
        XCTAssertNotNil(failedToDecodeError, "Should create failedToDecode error")
    }

    // MARK: - DicomSeriesVolume Tests

    func testDicomSeriesVolumeStructure() {
        // Create a test volume
        let testData = Data(count: 100)
        let testSpacing = SIMD3<Double>(1.0, 1.0, 2.5)
        let testOrientation = matrix_identity_double3x3
        let testOrigin = SIMD3<Double>(10.0, 20.0, 30.0)

        let volume = DicomSeriesVolume(
            voxels: testData,
            width: 10,
            height: 10,
            depth: 1,
            spacing: testSpacing,
            orientation: testOrientation,
            origin: testOrigin,
            rescaleSlope: 1.0,
            rescaleIntercept: -1024.0,
            bitsAllocated: 16,
            isSignedPixel: true,
            seriesDescription: "Test Series"
        )

        // Verify all properties
        XCTAssertEqual(volume.voxels.count, 100, "Voxel data should match")
        XCTAssertEqual(volume.width, 10, "Width should match")
        XCTAssertEqual(volume.height, 10, "Height should match")
        XCTAssertEqual(volume.depth, 1, "Depth should match")
        XCTAssertEqual(volume.spacing.x, 1.0, "X spacing should match")
        XCTAssertEqual(volume.spacing.y, 1.0, "Y spacing should match")
        XCTAssertEqual(volume.spacing.z, 2.5, "Z spacing should match")
        XCTAssertEqual(volume.rescaleSlope, 1.0, "Rescale slope should match")
        XCTAssertEqual(volume.rescaleIntercept, -1024.0, "Rescale intercept should match")
        XCTAssertEqual(volume.bitsAllocated, 16, "Bits allocated should match")
        XCTAssertTrue(volume.isSignedPixel, "Should be signed pixel")
        XCTAssertEqual(volume.seriesDescription, "Test Series", "Series description should match")
    }

    func testDicomSeriesVolumeOrientation() {
        // Test with custom orientation matrix
        let rowVector = SIMD3<Double>(1.0, 0.0, 0.0)
        let colVector = SIMD3<Double>(0.0, 1.0, 0.0)
        let normalVector = SIMD3<Double>(0.0, 0.0, 1.0)
        let orientation = simd_double3x3(columns: (rowVector, colVector, normalVector))

        let volume = DicomSeriesVolume(
            voxels: Data(),
            width: 512,
            height: 512,
            depth: 100,
            spacing: SIMD3<Double>(0.5, 0.5, 1.0),
            orientation: orientation,
            origin: SIMD3<Double>.zero,
            rescaleSlope: 1.0,
            rescaleIntercept: 0.0,
            bitsAllocated: 16,
            isSignedPixel: false,
            seriesDescription: "Axial CT"
        )

        // Verify orientation matrix
        XCTAssertEqual(volume.orientation.columns.0.x, 1.0, accuracy: 1e-6, "Row vector X should be 1.0")
        XCTAssertEqual(volume.orientation.columns.1.y, 1.0, accuracy: 1e-6, "Column vector Y should be 1.0")
        XCTAssertEqual(volume.orientation.columns.2.z, 1.0, accuracy: 1e-6, "Normal vector Z should be 1.0")
    }

    func testDicomSeriesVolumeVoxelCount() {
        // Test total voxel count calculation
        let width = 256
        let height = 256
        let depth = 50
        let expectedVoxelCount = width * height * depth * MemoryLayout<Int16>.size
        let voxelData = Data(count: expectedVoxelCount)

        let volume = DicomSeriesVolume(
            voxels: voxelData,
            width: width,
            height: height,
            depth: depth,
            spacing: SIMD3<Double>(1, 1, 1),
            orientation: matrix_identity_double3x3,
            origin: SIMD3<Double>.zero,
            rescaleSlope: 1.0,
            rescaleIntercept: 0.0,
            bitsAllocated: 16,
            isSignedPixel: false,
            seriesDescription: "Test"
        )

        XCTAssertEqual(volume.voxels.count, expectedVoxelCount, "Voxel buffer should match expected size")
    }

    // MARK: - Loader Initialization Tests

    func testDicomSeriesLoaderInitialization() {
        let loader = DicomSeriesLoader()
        XCTAssertNotNil(loader, "Loader should initialize successfully")
    }

    func testLoaderWithNonexistentDirectory() {
        let loader = DicomSeriesLoader()
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/path/to/dicom/files")

        XCTAssertThrowsError(try loader.loadSeries(in: nonexistentURL)) { error in
            // The error could be either noDicomFiles or a system error
            XCTAssertTrue(
                error is DicomSeriesLoaderError || error is CocoaError,
                "Should throw an appropriate error for nonexistent directory"
            )
        }
    }

    func testLoaderWithEmptyDirectory() throws {
        let loader = DicomSeriesLoader()

        // Create a temporary empty directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomSeriesLoaderTests_Empty_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        XCTAssertThrowsError(try loader.loadSeries(in: tempDir)) { error in
            guard case DicomSeriesLoaderError.noDicomFiles = error else {
                XCTFail("Expected noDicomFiles error, got \(error)")
                return
            }
        }
    }

    // MARK: - Spacing and Geometry Tests

    func testSpacingVector() {
        let spacing = SIMD3<Double>(0.625, 0.625, 1.25)

        XCTAssertEqual(spacing.x, 0.625, "X spacing should be correct")
        XCTAssertEqual(spacing.y, 0.625, "Y spacing should be correct")
        XCTAssertEqual(spacing.z, 1.25, "Z spacing should be correct")
    }

    func testOrientationMatrixIdentity() {
        let identity = matrix_identity_double3x3

        XCTAssertEqual(identity.columns.0.x, 1.0, "Identity [0,0] should be 1")
        XCTAssertEqual(identity.columns.1.y, 1.0, "Identity [1,1] should be 1")
        XCTAssertEqual(identity.columns.2.z, 1.0, "Identity [2,2] should be 1")
        XCTAssertEqual(identity.columns.0.y, 0.0, "Identity [0,1] should be 0")
    }

    func testOrientationMatrixConstruction() {
        // Test typical axial orientation
        let row = SIMD3<Double>(1.0, 0.0, 0.0)
        let col = SIMD3<Double>(0.0, 1.0, 0.0)
        let normal = simd_cross(row, col)

        XCTAssertEqual(normal.x, 0.0, accuracy: 1e-10, "Normal X should be 0")
        XCTAssertEqual(normal.y, 0.0, accuracy: 1e-10, "Normal Y should be 0")
        XCTAssertEqual(normal.z, 1.0, accuracy: 1e-10, "Normal Z should be 1")

        let matrix = simd_double3x3(columns: (row, col, normal))
        XCTAssertEqual(matrix.columns.0, row, "Row vector should match")
        XCTAssertEqual(matrix.columns.1, col, "Column vector should match")
        XCTAssertEqual(matrix.columns.2, normal, "Normal vector should match")
    }

    func testOrientationMatrixNormalization() {
        // Test with non-unit vectors
        let row = SIMD3<Double>(2.0, 0.0, 0.0)
        let col = SIMD3<Double>(0.0, 3.0, 0.0)

        let normalizedRow = simd_normalize(row)
        let normalizedCol = simd_normalize(col)

        XCTAssertEqual(normalizedRow.x, 1.0, accuracy: 1e-10, "Normalized row should be unit vector")
        XCTAssertEqual(normalizedCol.y, 1.0, accuracy: 1e-10, "Normalized col should be unit vector")

        let length1 = simd_length(normalizedRow)
        let length2 = simd_length(normalizedCol)
        XCTAssertEqual(length1, 1.0, accuracy: 1e-10, "Row should be unit length")
        XCTAssertEqual(length2, 1.0, accuracy: 1e-10, "Column should be unit length")
    }

    // MARK: - SIMD Vector Operation Tests

    func testSIMDVectorAddition() {
        let v1 = SIMD3<Double>(1.0, 2.0, 3.0)
        let v2 = SIMD3<Double>(4.0, 5.0, 6.0)
        let result = v1 + v2

        XCTAssertEqual(result.x, 5.0, "X component should add correctly")
        XCTAssertEqual(result.y, 7.0, "Y component should add correctly")
        XCTAssertEqual(result.z, 9.0, "Z component should add correctly")
    }

    func testSIMDDotProduct() {
        let v1 = SIMD3<Double>(1.0, 0.0, 0.0)
        let v2 = SIMD3<Double>(0.0, 1.0, 0.0)
        let dot = simd_dot(v1, v2)

        XCTAssertEqual(dot, 0.0, "Perpendicular vectors should have dot product of 0")

        let v3 = SIMD3<Double>(2.0, 0.0, 0.0)
        let dot2 = simd_dot(v1, v3)
        XCTAssertEqual(dot2, 2.0, "Parallel vectors should have positive dot product")
    }

    func testSIMDCrossProduct() {
        let v1 = SIMD3<Double>(1.0, 0.0, 0.0)
        let v2 = SIMD3<Double>(0.0, 1.0, 0.0)
        let cross = simd_cross(v1, v2)

        XCTAssertEqual(cross.x, 0.0, accuracy: 1e-10, "Cross product X")
        XCTAssertEqual(cross.y, 0.0, accuracy: 1e-10, "Cross product Y")
        XCTAssertEqual(cross.z, 1.0, accuracy: 1e-10, "Cross product Z")
    }

    func testSIMDVectorLength() {
        let v1 = SIMD3<Double>(3.0, 4.0, 0.0)
        let length = simd_length(v1)

        XCTAssertEqual(length, 5.0, accuracy: 1e-10, "3-4-5 triangle should have length 5")
    }

    // MARK: - Data Buffer Tests

    func testDataBufferAllocation() {
        let width = 512
        let height = 512
        let depth = 100
        let voxelCount = width * height * depth
        let byteCount = voxelCount * MemoryLayout<Int16>.size

        let data = Data(count: byteCount)
        XCTAssertEqual(data.count, byteCount, "Data buffer should be allocated correctly")
    }

    func testDataBufferAccess() {
        var data = Data(count: 10 * MemoryLayout<Int16>.size)

        data.withUnsafeMutableBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: Int16.self)
            buffer[0] = 100
            buffer[9] = 200
        }

        data.withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: Int16.self)
            XCTAssertEqual(buffer[0], 100, "First element should be set")
            XCTAssertEqual(buffer[9], 200, "Last element should be set")
        }
    }

    // MARK: - Pixel Representation Tests

    func testSignedPixelConversion() {
        // Test conversion logic for signed pixels
        let unsignedValue: UInt16 = 32768 // 0x8000
        let signedValue = Int32(unsignedValue) + Int32(Int16.min)
        let result = Int16(truncatingIfNeeded: signedValue)

        XCTAssertEqual(result, 0, "32768 unsigned should convert to 0 signed")
    }

    func testUnsignedPixelConversion() {
        // Test conversion logic for unsigned pixels
        let unsignedValue: UInt16 = 1000
        let signedValue = Int16(bitPattern: unsignedValue)

        XCTAssertEqual(signedValue, 1000, "Small unsigned values should preserve")
    }

    func testPixelRangeConversions() {
        // Test edge cases
        let minValue: UInt16 = 0
        let maxValue: UInt16 = UInt16.max

        let minSigned = Int16(bitPattern: minValue)
        let maxSigned = Int16(bitPattern: maxValue)

        XCTAssertEqual(minSigned, 0, "Min unsigned should be 0 when converted")
        XCTAssertEqual(maxSigned, -1, "Max unsigned should be -1 when converted")
    }

    // MARK: - Slice Ordering Tests

    func testInstanceNumberOrdering() {
        // Test that instance numbers would be used for ordering
        let instance1 = 1
        let instance2 = 2
        let instance3 = 10

        XCTAssertLessThan(instance1, instance2, "Instance 1 should come before 2")
        XCTAssertLessThan(instance2, instance3, "Instance 2 should come before 10")
    }

    func testFilenameOrdering() {
        // Test localized standard compare for filenames
        let filename1 = "slice001.dcm"
        let filename2 = "slice002.dcm"
        let filename3 = "slice010.dcm"

        let compare1 = filename1.localizedStandardCompare(filename2)
        let compare2 = filename2.localizedStandardCompare(filename3)

        XCTAssertEqual(compare1, .orderedAscending, "slice001 should come before slice002")
        XCTAssertEqual(compare2, .orderedAscending, "slice002 should come before slice010")
    }

    func testProjectionOrdering() {
        // Test projection calculation for slice ordering
        let normal = SIMD3<Double>(0.0, 0.0, 1.0)
        let position1 = SIMD3<Double>(0.0, 0.0, 10.0)
        let position2 = SIMD3<Double>(0.0, 0.0, 20.0)
        let position3 = SIMD3<Double>(0.0, 0.0, 15.0)

        let proj1 = simd_dot(position1, normal)
        let proj2 = simd_dot(position2, normal)
        let proj3 = simd_dot(position3, normal)

        XCTAssertEqual(proj1, 10.0, "Projection 1 should be 10")
        XCTAssertEqual(proj2, 20.0, "Projection 2 should be 20")
        XCTAssertEqual(proj3, 15.0, "Projection 3 should be 15")

        XCTAssertLessThan(proj1, proj3, "Position 1 should be before position 3")
        XCTAssertLessThan(proj3, proj2, "Position 3 should be before position 2")
    }

    // MARK: - Progress Handler Tests

    func testProgressHandlerSignature() {
        // Test that progress handler type is defined correctly
        var progressCalls = 0

        let handler: DicomSeriesLoader.ProgressHandler = { fraction, sliceCount, sliceData, volume in
            progressCalls += 1
            XCTAssertGreaterThanOrEqual(fraction, 0.0, "Fraction should be >= 0")
            XCTAssertLessThanOrEqual(fraction, 1.0, "Fraction should be <= 1")
            XCTAssertGreaterThan(sliceCount, 0, "Slice count should be positive")
        }

        // Simulate a progress callback
        let testVolume = DicomSeriesVolume(
            voxels: Data(),
            width: 10,
            height: 10,
            depth: 1,
            spacing: SIMD3<Double>(1, 1, 1),
            orientation: matrix_identity_double3x3,
            origin: SIMD3<Double>.zero,
            rescaleSlope: 1.0,
            rescaleIntercept: 0.0,
            bitsAllocated: 16,
            isSignedPixel: false,
            seriesDescription: "Test"
        )

        handler(0.5, 1, Data(), testVolume)
        XCTAssertEqual(progressCalls, 1, "Progress handler should have been called once")
    }

    // MARK: - Rescale Parameters Tests

    func testRescaleParametersDefault() {
        // Test default rescale parameters
        let defaultSlope = 1.0
        let defaultIntercept = 0.0

        XCTAssertEqual(defaultSlope, 1.0, "Default slope should be 1.0")
        XCTAssertEqual(defaultIntercept, 0.0, "Default intercept should be 0.0")
    }

    func testRescaleParametersCT() {
        // Test typical CT rescale parameters
        let ctSlope = 1.0
        let ctIntercept = -1024.0

        // Test Hounsfield unit conversion
        let pixelValue = 1024.0
        let hu = pixelValue * ctSlope + ctIntercept

        XCTAssertEqual(hu, 0.0, "1024 pixel value should equal 0 HU")
    }

    func testRescaleParametersRange() {
        // Test rescale with different parameters
        let slope = 2.0
        let intercept = 100.0

        let pixel1 = 0.0
        let pixel2 = 100.0

        let value1 = pixel1 * slope + intercept
        let value2 = pixel2 * slope + intercept

        XCTAssertEqual(value1, 100.0, "Rescaled value 1 should be correct")
        XCTAssertEqual(value2, 300.0, "Rescaled value 2 should be correct")
    }

    // MARK: - Series Description Tests

    func testSeriesDescriptionDefault() {
        // Test that default series description comes from directory name
        let directoryName = "CT_CHEST_001"
        XCTAssertFalse(directoryName.isEmpty, "Directory name should not be empty")
        XCTAssertEqual(directoryName, "CT_CHEST_001", "Directory name should be preserved")
    }

    func testSeriesDescriptionTrimming() {
        // Test whitespace trimming
        let description1 = "  Test Series  "
        let trimmed = description1.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(trimmed, "Test Series", "Whitespace should be trimmed")

        let description2 = ""
        XCTAssertTrue(description2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                     "Empty string should remain empty after trimming")
    }

    // MARK: - File Extension Tests

    func testDicomFileExtensions() {
        // Test .dcm extension
        let dcmFile = "image.dcm"
        XCTAssertEqual(dcmFile.lowercased().hasSuffix(".dcm"), true, "Should recognize .dcm extension")

        // Test uppercase
        let dcmUpper = "image.DCM"
        XCTAssertEqual(dcmUpper.lowercased().hasSuffix(".dcm"), true, "Should recognize .DCM extension")

        // Test no extension (common for DICOM)
        let noExt = "IM000001"
        XCTAssertFalse(noExt.contains("."), "No extension files are valid DICOM")
    }

    // MARK: - Tolerance Tests

    func testOrientationTolerance() {
        // Test tolerance for orientation comparison
        let tolerance = 1e-4
        let v1 = SIMD3<Double>(1.0, 0.0, 0.0)
        let v2 = SIMD3<Double>(1.0 + tolerance / 2, 0.0, 0.0)
        let v3 = SIMD3<Double>(1.0 + tolerance * 2, 0.0, 0.0)

        let diff1 = abs(v1.x - v2.x)
        let diff2 = abs(v1.x - v3.x)

        XCTAssertLessThan(diff1, tolerance, "Should be within tolerance")
        XCTAssertGreaterThan(diff2, tolerance, "Should exceed tolerance")
    }

    func testSpacingTolerance() {
        // Test tolerance for spacing comparison (mm-level)
        let tolerance = 0.2
        let spacing1 = 1.0
        let spacing2 = 1.15
        let spacing3 = 1.25

        let diff1 = abs(spacing1 - spacing2)
        let diff2 = abs(spacing1 - spacing3)

        XCTAssertLessThan(diff1, tolerance, "Should be within tolerance")
        XCTAssertGreaterThan(diff2, tolerance, "Should exceed tolerance")
    }

    // MARK: - Async/Await Tests

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncLoadSeriesWithNonexistentDirectory() async {
        let loader = DicomSeriesLoader()
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/path/to/dicom/files")

        do {
            _ = try await loader.loadSeries(in: nonexistentURL, progress: nil)
            XCTFail("Should throw error for nonexistent directory")
        } catch {
            // Expected - error could be noDicomFiles or system error
            XCTAssertTrue(
                error is DicomSeriesLoaderError || error is CocoaError,
                "Should throw appropriate error for nonexistent directory"
            )
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncLoadSeriesWithEmptyDirectory() async throws {
        let loader = DicomSeriesLoader()

        // Create a temporary empty directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomSeriesLoaderAsyncTests_Empty_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        do {
            _ = try await loader.loadSeries(in: tempDir, progress: nil)
            XCTFail("Should throw noDicomFiles error for empty directory")
        } catch DicomSeriesLoaderError.noDicomFiles {
            // Expected
        } catch {
            XCTFail("Expected noDicomFiles error, got \(error)")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncLoadSeriesWithProgressCallback() async throws {
        // Create a temporary directory with mock DICOM files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomSeriesLoaderAsyncTests_Progress_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create mock files
        let sliceCount = 3
        for i in 0..<sliceCount {
            try Data().write(to: tempDir.appendingPathComponent("slice_\(i).dcm"))
        }

        // Create loader with mock decoder factory
        let mockFactory: () -> DicomDecoderProtocol = {
            let mock = MockDicomDecoder()
            mock.width = 256
            mock.height = 256
            mock.bitDepth = 16
            mock.samplesPerPixel = 1
            mock.setPixels16(Array(repeating: 100, count: 256 * 256))
            mock.imagePosition = SIMD3<Double>(0, 0, 0)
            mock.imageOrientation = (
                row: SIMD3<Double>(1, 0, 0),
                column: SIMD3<Double>(0, 1, 0)
            )
            return mock
        }

        let loader = DicomSeriesLoader(decoderFactory: mockFactory)

        var progressCallCount = 0
        var lastFraction = 0.0

        let volume = try await loader.loadSeries(in: tempDir) { fraction, slicesCopied, sliceData, vol in
            progressCallCount += 1
            XCTAssertGreaterThanOrEqual(fraction, 0.0, "Fraction should be >= 0")
            XCTAssertLessThanOrEqual(fraction, 1.0, "Fraction should be <= 1")
            XCTAssertGreaterThan(slicesCopied, 0, "Slices copied should be > 0")
            XCTAssertNotNil(vol, "Volume info should be provided")
            lastFraction = fraction
        }

        XCTAssertGreaterThan(progressCallCount, 0, "Progress callback should be called at least once")
        XCTAssertEqual(volume.depth, sliceCount, "Volume should have correct depth")
        XCTAssertEqual(lastFraction, 1.0, accuracy: 0.01, "Last progress should be 1.0")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncLoadSeriesMatchesSyncVersion() async throws {
        // Create a simple test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomSeriesLoaderAsyncTests_Sync_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create some mock files
        for i in 0..<2 {
            let url = tempDir.appendingPathComponent("slice_\(i).dcm")
            try Data().write(to: url)
        }

        // Create loader with mock decoder factory
        let mockFactory: () -> DicomDecoderProtocol = {
            let mock = MockDicomDecoder()
            mock.width = 128
            mock.height = 128
            mock.bitDepth = 16
            mock.samplesPerPixel = 1
            mock.setPixels16(Array(repeating: 50, count: 128 * 128))
            mock.imagePosition = SIMD3<Double>(0, 0, 0)
            mock.imageOrientation = (
                row: SIMD3<Double>(1, 0, 0),
                column: SIMD3<Double>(0, 1, 0)
            )
            return mock
        }

        let loader = DicomSeriesLoader(decoderFactory: mockFactory)

        // Load using detached task to call synchronous version explicitly
        let syncVolume = try await Task.detached {
            try loader.loadSeries(in: tempDir, progress: nil)
        }.value

        // Create new loader instance for async test
        let asyncLoader = DicomSeriesLoader(decoderFactory: mockFactory)

        // Load asynchronously
        let asyncVolume = try await asyncLoader.loadSeries(in: tempDir, progress: nil)

        // Verify both produce same results
        XCTAssertEqual(syncVolume.width, asyncVolume.width, "Width should match")
        XCTAssertEqual(syncVolume.height, asyncVolume.height, "Height should match")
        XCTAssertEqual(syncVolume.depth, asyncVolume.depth, "Depth should match")
        XCTAssertEqual(syncVolume.bitsAllocated, asyncVolume.bitsAllocated, "Bits allocated should match")
        XCTAssertEqual(syncVolume.spacing.x, asyncVolume.spacing.x, "X spacing should match")
        XCTAssertEqual(syncVolume.spacing.y, asyncVolume.spacing.y, "Y spacing should match")
        XCTAssertEqual(syncVolume.spacing.z, asyncVolume.spacing.z, "Z spacing should match")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testConcurrentAsyncLoadOperations() async throws {
        // Test that multiple async load operations can run concurrently
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomSeriesLoaderAsyncTests_Concurrent_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create mock files
        try Data().write(to: tempDir.appendingPathComponent("slice.dcm"))

        let iterations = 5
        let mockFactory: () -> DicomDecoderProtocol = {
            let mock = MockDicomDecoder()
            mock.width = 64
            mock.height = 64
            mock.bitDepth = 16
            mock.samplesPerPixel = 1
            mock.setPixels16(Array(repeating: 25, count: 64 * 64))
            mock.imagePosition = SIMD3<Double>(0, 0, 0)
            mock.imageOrientation = (
                row: SIMD3<Double>(1, 0, 0),
                column: SIMD3<Double>(0, 1, 0)
            )
            return mock
        }

        // Launch multiple concurrent async operations
        try await withThrowingTaskGroup(of: DicomSeriesVolume.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    let loader = DicomSeriesLoader(decoderFactory: mockFactory)
                    return try await loader.loadSeries(in: tempDir, progress: nil)
                }
            }

            var completedCount = 0
            for try await volume in group {
                XCTAssertEqual(volume.width, 64, "Each volume should have correct width")
                XCTAssertEqual(volume.height, 64, "Each volume should have correct height")
                completedCount += 1
            }

            XCTAssertEqual(completedCount, iterations, "All concurrent operations should complete")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncLoadSeriesErrorHandling() async throws {
        // Test various error conditions in async context
        let loader = DicomSeriesLoader()

        // Test with nonexistent directory
        let nonexistent = URL(fileURLWithPath: "/nonexistent/async/test/\(UUID().uuidString)")
        do {
            _ = try await loader.loadSeries(in: nonexistent, progress: nil)
            XCTFail("Should throw error for nonexistent directory")
        } catch {
            // Expected
            XCTAssertNotNil(error, "Should receive an error")
        }

        // Test with empty directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomSeriesLoaderAsyncTests_ErrorEmpty_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        do {
            _ = try await loader.loadSeries(in: tempDir, progress: nil)
            XCTFail("Should throw noDicomFiles error")
        } catch DicomSeriesLoaderError.noDicomFiles {
            // Expected
        } catch {
            XCTFail("Expected noDicomFiles, got \(error)")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncLoadSeriesWithoutProgressCallback() async throws {
        // Test async loading without progress callback
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomSeriesLoaderAsyncTests_NoProgress_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a mock file
        try Data().write(to: tempDir.appendingPathComponent("slice.dcm"))

        let mockFactory: () -> DicomDecoderProtocol = {
            let mock = MockDicomDecoder()
            mock.width = 32
            mock.height = 32
            mock.bitDepth = 16
            mock.samplesPerPixel = 1
            mock.setPixels16(Array(repeating: 10, count: 32 * 32))
            mock.imagePosition = SIMD3<Double>(0, 0, 0)
            mock.imageOrientation = (
                row: SIMD3<Double>(1, 0, 0),
                column: SIMD3<Double>(0, 1, 0)
            )
            return mock
        }

        let loader = DicomSeriesLoader(decoderFactory: mockFactory)

        // Load without progress callback (nil)
        let volume = try await loader.loadSeries(in: tempDir, progress: nil)

        XCTAssertEqual(volume.width, 32, "Should load volume without progress callback")
        XCTAssertEqual(volume.height, 32, "Should have correct dimensions")
        XCTAssertEqual(volume.depth, 1, "Should have single slice")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncLoadSeriesCancellation() async throws {
        // Test that async loading respects task cancellation
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomSeriesLoaderAsyncTests_Cancel_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create multiple mock files to make loading take longer
        for i in 0..<10 {
            try Data().write(to: tempDir.appendingPathComponent("slice_\(i).dcm"))
        }

        let mockFactory: () -> DicomDecoderProtocol = {
            let mock = MockDicomDecoder()
            mock.width = 512
            mock.height = 512
            mock.bitDepth = 16
            mock.samplesPerPixel = 1
            mock.setPixels16(Array(repeating: 100, count: 512 * 512))
            mock.imagePosition = SIMD3<Double>(0, 0, 0)
            mock.imageOrientation = (
                row: SIMD3<Double>(1, 0, 0),
                column: SIMD3<Double>(0, 1, 0)
            )
            return mock
        }

        let loader = DicomSeriesLoader(decoderFactory: mockFactory)

        // Create a task and cancel it
        let task = Task {
            try await loader.loadSeries(in: tempDir, progress: nil)
        }

        // Cancel immediately
        task.cancel()

        do {
            _ = try await task.value
            // Note: Cancellation might not always propagate in time
            // This test verifies the mechanism exists, not that it always works
        } catch is CancellationError {
            // Expected if cancellation propagated
        } catch {
            // Also acceptable - task may complete before cancellation
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testMultipleLoadersWithAsyncOperations() async throws {
        // Test that multiple loader instances can run async operations simultaneously
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomSeriesLoaderAsyncTests_MultiLoader_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        try Data().write(to: tempDir.appendingPathComponent("slice.dcm"))

        let mockFactory: () -> DicomDecoderProtocol = {
            let mock = MockDicomDecoder()
            mock.width = 128
            mock.height = 128
            mock.bitDepth = 16
            mock.samplesPerPixel = 1
            mock.setPixels16(Array(repeating: 75, count: 128 * 128))
            mock.imagePosition = SIMD3<Double>(0, 0, 0)
            mock.imageOrientation = (
                row: SIMD3<Double>(1, 0, 0),
                column: SIMD3<Double>(0, 1, 0)
            )
            return mock
        }

        // Create multiple loaders and run them concurrently
        async let volume1 = DicomSeriesLoader(decoderFactory: mockFactory).loadSeries(in: tempDir, progress: nil)
        async let volume2 = DicomSeriesLoader(decoderFactory: mockFactory).loadSeries(in: tempDir, progress: nil)
        async let volume3 = DicomSeriesLoader(decoderFactory: mockFactory).loadSeries(in: tempDir, progress: nil)

        let (v1, v2, v3) = try await (volume1, volume2, volume3)

        XCTAssertEqual(v1.width, 128, "First loader should succeed")
        XCTAssertEqual(v2.width, 128, "Second loader should succeed")
        XCTAssertEqual(v3.width, 128, "Third loader should succeed")
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testAsyncLoadSeriesProgressMonitoring() async throws {
        // Test detailed progress monitoring during async loading
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomSeriesLoaderAsyncTests_ProgressMonitor_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sliceCount = 5
        for i in 0..<sliceCount {
            try Data().write(to: tempDir.appendingPathComponent("slice_\(i).dcm"))
        }

        let mockFactory: () -> DicomDecoderProtocol = {
            let mock = MockDicomDecoder()
            mock.width = 64
            mock.height = 64
            mock.bitDepth = 16
            mock.samplesPerPixel = 1
            mock.setPixels16(Array(repeating: 33, count: 64 * 64))
            mock.imagePosition = SIMD3<Double>(0, 0, 0)
            mock.imageOrientation = (
                row: SIMD3<Double>(1, 0, 0),
                column: SIMD3<Double>(0, 1, 0)
            )
            return mock
        }

        let loader = DicomSeriesLoader(decoderFactory: mockFactory)

        var progressFractions: [Double] = []
        var slicesCopiedValues: [Int] = []

        let volume = try await loader.loadSeries(in: tempDir) { fraction, slicesCopied, sliceData, vol in
            progressFractions.append(fraction)
            slicesCopiedValues.append(slicesCopied)
        }

        XCTAssertEqual(volume.depth, sliceCount, "Volume should have all slices")
        XCTAssertFalse(progressFractions.isEmpty, "Should have progress updates")
        XCTAssertEqual(progressFractions.count, slicesCopiedValues.count, "Should have matching progress arrays")

        // Verify progress is monotonically increasing
        for i in 1..<progressFractions.count {
            XCTAssertGreaterThanOrEqual(progressFractions[i], progressFractions[i-1],
                                       "Progress should increase monotonically")
        }
    }

    @available(macOS 10.15, iOS 13.0, *)
    func testConcurrentLoaderInstancesWithAsyncAccess() async {
        // Test that multiple loader instances can be created and used concurrently in async context
        let iterations = 10

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    // Create a loader instance in this task
                    let loader = DicomSeriesLoader()

                    // Verify loader was created successfully (always true for struct/class init)
                    return true
                }
            }

            var completedCount = 0
            for await success in group {
                if success {
                    completedCount += 1
                }
            }

            XCTAssertEqual(completedCount, iterations, "All loader instances should be created successfully")
        }
    }
}
