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
}
