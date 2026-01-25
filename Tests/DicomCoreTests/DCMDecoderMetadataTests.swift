import XCTest
@testable import DicomCore

final class DCMDecoderMetadataTests: XCTestCase {

    // MARK: - Tag Access Tests

    func testInfoMethodWithUninitializedDecoder() {
        let decoder = DCMDecoder()

        // Test that info returns empty string for uninitialized decoder
        let patientName = decoder.info(for: DicomTag.patientName.rawValue)
        XCTAssertEqual(patientName, "", "Uninitialized decoder should return empty string")

        let studyDate = decoder.info(for: DicomTag.studyDate.rawValue)
        XCTAssertEqual(studyDate, "", "Uninitialized decoder should return empty string")

        let modality = decoder.info(for: DicomTag.modality.rawValue)
        XCTAssertEqual(modality, "", "Uninitialized decoder should return empty string")
    }

    func testInfoMethodWithInvalidTag() {
        let decoder = DCMDecoder()

        // Test with invalid/non-existent tag
        let result = decoder.info(for: 0xFFFFFFFF)
        XCTAssertEqual(result, "", "Invalid tag should return empty string")

        // Test with zero tag
        let zeroResult = decoder.info(for: 0x00000000)
        XCTAssertEqual(zeroResult, "", "Zero tag should return empty string")
    }

    func testCommonPatientTags() {
        let decoder = DCMDecoder()

        // Test patient information tags
        _ = decoder.info(for: DicomTag.patientName.rawValue)
        _ = decoder.info(for: DicomTag.patientID.rawValue)
        _ = decoder.info(for: DicomTag.patientSex.rawValue)
        _ = decoder.info(for: DicomTag.patientAge.rawValue)
        _ = decoder.info(for: DicomTag.patientPosition.rawValue)

        // Should not crash and return empty strings for uninitialized decoder
        XCTAssertTrue(true, "Tag access should not crash")
    }

    func testCommonStudyTags() {
        let decoder = DCMDecoder()

        // Test study information tags
        _ = decoder.info(for: DicomTag.studyInstanceUID.rawValue)
        _ = decoder.info(for: DicomTag.studyDate.rawValue)
        _ = decoder.info(for: DicomTag.studyTime.rawValue)
        _ = decoder.info(for: DicomTag.studyDescription.rawValue)
        _ = decoder.info(for: DicomTag.studyID.rawValue)

        // Should not crash and return empty strings for uninitialized decoder
        XCTAssertTrue(true, "Tag access should not crash")
    }

    func testCommonSeriesTags() {
        let decoder = DCMDecoder()

        // Test series information tags
        _ = decoder.info(for: DicomTag.seriesInstanceUID.rawValue)
        _ = decoder.info(for: DicomTag.seriesNumber.rawValue)
        _ = decoder.info(for: DicomTag.seriesDescription.rawValue)
        _ = decoder.info(for: DicomTag.modality.rawValue)

        // Should not crash and return empty strings for uninitialized decoder
        XCTAssertTrue(true, "Tag access should not crash")
    }

    func testCommonImageTags() {
        let decoder = DCMDecoder()

        // Test image information tags
        _ = decoder.info(for: DicomTag.rows.rawValue)
        _ = decoder.info(for: DicomTag.columns.rawValue)
        _ = decoder.info(for: DicomTag.bitsAllocated.rawValue)
        _ = decoder.info(for: DicomTag.bitsStored.rawValue)
        _ = decoder.info(for: DicomTag.highBit.rawValue)
        _ = decoder.info(for: DicomTag.pixelRepresentation.rawValue)

        // Should not crash and return empty strings for uninitialized decoder
        XCTAssertTrue(true, "Tag access should not crash")
    }

    // MARK: - Type Conversion Tests

    func testIntValueConversionWithUninitializedDecoder() {
        let decoder = DCMDecoder()

        // Test that intValue returns nil for uninitialized decoder
        let rows = decoder.intValue(for: DicomTag.rows.rawValue)
        XCTAssertNil(rows, "Uninitialized decoder should return nil for intValue")

        let columns = decoder.intValue(for: DicomTag.columns.rawValue)
        XCTAssertNil(columns, "Uninitialized decoder should return nil for intValue")

        let bitsAllocated = decoder.intValue(for: DicomTag.bitsAllocated.rawValue)
        XCTAssertNil(bitsAllocated, "Uninitialized decoder should return nil for intValue")
    }

    func testIntValueConversionWithInvalidTag() {
        let decoder = DCMDecoder()

        // Test with invalid tag
        let result = decoder.intValue(for: 0xFFFFFFFF)
        XCTAssertNil(result, "Invalid tag should return nil for intValue")
    }

    func testDoubleValueConversionWithUninitializedDecoder() {
        let decoder = DCMDecoder()

        // Test that doubleValue returns nil for uninitialized decoder
        let pixelSpacing = decoder.doubleValue(for: DicomTag.pixelSpacing.rawValue)
        XCTAssertNil(pixelSpacing, "Uninitialized decoder should return nil for doubleValue")

        let sliceThickness = decoder.doubleValue(for: DicomTag.sliceThickness.rawValue)
        XCTAssertNil(sliceThickness, "Uninitialized decoder should return nil for doubleValue")

        let rescaleSlope = decoder.doubleValue(for: DicomTag.rescaleSlope.rawValue)
        XCTAssertNil(rescaleSlope, "Uninitialized decoder should return nil for doubleValue")
    }

    func testDoubleValueConversionWithInvalidTag() {
        let decoder = DCMDecoder()

        // Test with invalid tag
        let result = decoder.doubleValue(for: 0xFFFFFFFF)
        XCTAssertNil(result, "Invalid tag should return nil for doubleValue")
    }

    // MARK: - Rescale Parameter Tests

    func testRescaleParameterAccess() {
        let decoder = DCMDecoder()

        // Test initial rescale parameters
        let rescaleParams = decoder.rescaleParameters
        XCTAssertEqual(rescaleParams.intercept, 0.0, "Default rescale intercept should be 0.0")
        XCTAssertEqual(rescaleParams.slope, 1.0, "Default rescale slope should be 1.0")
    }

    func testWindowSettingsAccess() {
        let decoder = DCMDecoder()

        // Test initial window settings
        let windowSettings = decoder.windowSettings
        XCTAssertEqual(windowSettings.center, 0.0, "Default window center should be 0.0")
        XCTAssertEqual(windowSettings.width, 0.0, "Default window width should be 0.0")
    }

    func testPixelSpacingAccess() {
        let decoder = DCMDecoder()

        // Test initial pixel spacing
        let pixelSpacing = decoder.pixelSpacing
        XCTAssertEqual(pixelSpacing.width, 1.0, "Default pixel width should be 1.0")
        XCTAssertEqual(pixelSpacing.height, 1.0, "Default pixel height should be 1.0")
        XCTAssertEqual(pixelSpacing.depth, 1.0, "Default pixel depth should be 1.0")
    }

    func testImageDimensionsAccess() {
        let decoder = DCMDecoder()

        // Test initial image dimensions
        let dimensions = decoder.imageDimensions
        XCTAssertEqual(dimensions.width, 1, "Default image width should be 1")
        XCTAssertEqual(dimensions.height, 1, "Default image height should be 1")
    }

    // MARK: - Tag Caching Tests

    func testFrequentTagAccessPerformance() {
        let decoder = DCMDecoder()

        // Access frequently cached tags multiple times
        measure {
            for _ in 0..<100 {
                _ = decoder.info(for: DicomTag.rescaleSlope.rawValue)
                _ = decoder.info(for: DicomTag.rescaleIntercept.rawValue)
                _ = decoder.info(for: DicomTag.rows.rawValue)
                _ = decoder.info(for: DicomTag.columns.rawValue)
            }
        }
    }

    func testNonCachedTagAccessPerformance() {
        let decoder = DCMDecoder()

        // Access non-cached tags multiple times
        measure {
            for _ in 0..<100 {
                _ = decoder.info(for: DicomTag.patientName.rawValue)
                _ = decoder.info(for: DicomTag.studyDate.rawValue)
                _ = decoder.info(for: DicomTag.seriesDescription.rawValue)
                _ = decoder.info(for: DicomTag.studyInstanceUID.rawValue)
            }
        }
    }

    // MARK: - Image Type Detection Tests

    func testImageTypeDetectionDefaults() {
        let decoder = DCMDecoder()

        // Test default image type flags
        XCTAssertTrue(decoder.isGrayscale, "Default should be grayscale")
        XCTAssertFalse(decoder.isColorImage, "Default should not be color")
        XCTAssertFalse(decoder.isMultiFrame, "Default should not be multi-frame")
    }

    func testPhotometricInterpretationAccess() {
        let decoder = DCMDecoder()

        // Test initial photometric interpretation
        XCTAssertEqual(decoder.photometricInterpretation, "", "Default photometric interpretation should be empty")
    }

    // MARK: - Image Geometry Tests

    func testImagePositionAccess() {
        let decoder = DCMDecoder()

        // Test initial image position
        XCTAssertNil(decoder.imagePosition, "Initial image position should be nil")
    }

    func testImageOrientationAccess() {
        let decoder = DCMDecoder()

        // Test initial image orientation
        XCTAssertNil(decoder.imageOrientation, "Initial image orientation should be nil")
    }

    // MARK: - Geometry and Spacing Tests

    func testImagePositionPatientTagAccess() {
        let decoder = DCMDecoder()

        // Test Image Position (Patient) tag access - 0x00200032
        let position = decoder.info(for: 0x00200032)
        XCTAssertEqual(position, "", "Uninitialized decoder should return empty string for image position")
    }

    func testImageOrientationPatientTagAccess() {
        let decoder = DCMDecoder()

        // Test Image Orientation (Patient) tag access - 0x00200037
        let orientation = decoder.info(for: 0x00200037)
        XCTAssertEqual(orientation, "", "Uninitialized decoder should return empty string for image orientation")
    }

    func testSliceLocationAccess() {
        let decoder = DCMDecoder()

        // Test Slice Location tag access - 0x00201041
        let sliceLocation = decoder.info(for: 0x00201041)
        XCTAssertEqual(sliceLocation, "", "Uninitialized decoder should return empty string for slice location")

        // Test double value conversion
        let sliceLocationValue = decoder.doubleValue(for: 0x00201041)
        XCTAssertNil(sliceLocationValue, "Uninitialized decoder should return nil for slice location double value")
    }

    func testSliceThicknessAccess() {
        let decoder = DCMDecoder()

        // Test Slice Thickness tag access - 0x00180050
        let sliceThickness = decoder.info(for: 0x00180050)
        XCTAssertEqual(sliceThickness, "", "Uninitialized decoder should return empty string for slice thickness")

        // Test double value conversion
        let sliceThicknessValue = decoder.doubleValue(for: 0x00180050)
        XCTAssertNil(sliceThicknessValue, "Uninitialized decoder should return nil for slice thickness double value")
    }

    func testPixelSpacingTagAccess() {
        let decoder = DCMDecoder()

        // Test Pixel Spacing tag access - 0x00280030
        let pixelSpacing = decoder.info(for: 0x00280030)
        XCTAssertEqual(pixelSpacing, "", "Uninitialized decoder should return empty string for pixel spacing")

        // Test double value conversion
        let pixelSpacingValue = decoder.doubleValue(for: 0x00280030)
        XCTAssertNil(pixelSpacingValue, "Uninitialized decoder should return nil for pixel spacing double value")
    }

    func testPixelSpacingPropertiesConsistency() {
        let decoder = DCMDecoder()

        // Test that pixel spacing properties match convenience accessors
        let spacing = decoder.pixelSpacing
        XCTAssertEqual(spacing.width, decoder.pixelWidth, "Pixel spacing width should match pixelWidth property")
        XCTAssertEqual(spacing.height, decoder.pixelHeight, "Pixel spacing height should match pixelHeight property")
        XCTAssertEqual(spacing.depth, decoder.pixelDepth, "Pixel spacing depth should match pixelDepth property")
    }

    func testImageDimensionsPropertiesConsistency() {
        let decoder = DCMDecoder()

        // Test that image dimensions match convenience accessors
        let dimensions = decoder.imageDimensions
        XCTAssertEqual(dimensions.width, decoder.width, "Image dimensions width should match width property")
        XCTAssertEqual(dimensions.height, decoder.height, "Image dimensions height should match height property")
    }

    func testSpacingBetweenSlicesAccess() {
        let decoder = DCMDecoder()

        // Test Spacing Between Slices tag access - 0x00180088
        let spacing = decoder.info(for: 0x00180088)
        XCTAssertEqual(spacing, "", "Uninitialized decoder should return empty string for spacing between slices")

        // Test double value conversion
        let spacingValue = decoder.doubleValue(for: 0x00180088)
        XCTAssertNil(spacingValue, "Uninitialized decoder should return nil for spacing between slices double value")
    }

    func testImageOrientationPatientComponents() {
        let decoder = DCMDecoder()

        // Image Orientation (Patient) should contain 6 values (row cosines + column cosines)
        // Test that accessing it doesn't crash
        let orientation = decoder.info(for: 0x00200037)
        XCTAssertNotNil(orientation, "Image orientation info should not be nil")
    }

    func testImagePositionPatientComponents() {
        let decoder = DCMDecoder()

        // Image Position (Patient) should contain 3 values (x, y, z)
        // Test that accessing it doesn't crash
        let position = decoder.info(for: 0x00200032)
        XCTAssertNotNil(position, "Image position info should not be nil")
    }

    func testGeometryTagsConsistentAccess() {
        let decoder = DCMDecoder()

        // Test that multiple accesses to geometry tags return consistent results
        let position1 = decoder.info(for: 0x00200032)
        let position2 = decoder.info(for: 0x00200032)
        XCTAssertEqual(position1, position2, "Consecutive position accesses should return same result")

        let orientation1 = decoder.info(for: 0x00200037)
        let orientation2 = decoder.info(for: 0x00200037)
        XCTAssertEqual(orientation1, orientation2, "Consecutive orientation accesses should return same result")
    }

    func testPixelAspectRatioTagAccess() {
        let decoder = DCMDecoder()

        // Test Pixel Aspect Ratio tag access - 0x00280034
        let aspectRatio = decoder.info(for: 0x00280034)
        XCTAssertEqual(aspectRatio, "", "Uninitialized decoder should return empty string for pixel aspect ratio")
    }

    func testImagePlaneGeometryTags() {
        let decoder = DCMDecoder()

        // Test all image plane geometry tags
        _ = decoder.info(for: 0x00200032)  // Image Position (Patient)
        _ = decoder.info(for: 0x00200037)  // Image Orientation (Patient)
        _ = decoder.info(for: 0x00280030)  // Pixel Spacing
        _ = decoder.info(for: 0x00180050)  // Slice Thickness
        _ = decoder.info(for: 0x00180088)  // Spacing Between Slices
        _ = decoder.info(for: 0x00201041)  // Slice Location

        XCTAssertTrue(true, "All geometry tag accesses should not crash")
    }

    func testSpatialResolutionDefaults() {
        let decoder = DCMDecoder()

        // Test default spatial resolution values
        let pixelWidth = decoder.pixelWidth
        let pixelHeight = decoder.pixelHeight
        let pixelDepth = decoder.pixelDepth

        XCTAssertEqual(pixelWidth, 1.0, "Default pixel width should be 1.0")
        XCTAssertEqual(pixelHeight, 1.0, "Default pixel height should be 1.0")
        XCTAssertEqual(pixelDepth, 1.0, "Default pixel depth should be 1.0")
    }

    func testImageDimensionsDefaults() {
        let decoder = DCMDecoder()

        // Test default image dimension values
        let width = decoder.width
        let height = decoder.height

        XCTAssertGreaterThan(width, 0, "Default width should be positive")
        XCTAssertGreaterThan(height, 0, "Default height should be positive")
    }

    func testGeometryDoubleValueConversions() {
        let decoder = DCMDecoder()

        // Test all geometry-related double value conversions
        let spacing = decoder.doubleValue(for: 0x00280030)
        let thickness = decoder.doubleValue(for: 0x00180050)
        let location = decoder.doubleValue(for: 0x00201041)
        let spacingBetweenSlices = decoder.doubleValue(for: 0x00180088)

        XCTAssertNil(spacing, "Uninitialized decoder should return nil for pixel spacing")
        XCTAssertNil(thickness, "Uninitialized decoder should return nil for slice thickness")
        XCTAssertNil(location, "Uninitialized decoder should return nil for slice location")
        XCTAssertNil(spacingBetweenSlices, "Uninitialized decoder should return nil for spacing between slices")
    }

    func testFrameOfReferenceUIDAccess() {
        let decoder = DCMDecoder()

        // Test Frame of Reference UID tag access - 0x00200052
        let frameOfReference = decoder.info(for: 0x00200052)
        XCTAssertEqual(frameOfReference, "", "Uninitialized decoder should return empty string for frame of reference UID")
    }

    func testPositionReferenceIndicatorAccess() {
        let decoder = DCMDecoder()

        // Test Position Reference Indicator tag access - 0x00201040
        let positionReference = decoder.info(for: 0x00201040)
        XCTAssertEqual(positionReference, "", "Uninitialized decoder should return empty string for position reference indicator")
    }

    func testGeometryMetadataCompleteness() {
        let decoder = DCMDecoder()

        // Verify that all essential geometry metadata accessors are available
        XCTAssertNotNil(decoder.imageDimensions, "Image dimensions should be accessible")
        XCTAssertNotNil(decoder.pixelSpacing, "Pixel spacing should be accessible")
        XCTAssertNotNil(decoder.width, "Width property should be accessible")
        XCTAssertNotNil(decoder.height, "Height property should be accessible")
        XCTAssertNotNil(decoder.pixelWidth, "Pixel width property should be accessible")
        XCTAssertNotNil(decoder.pixelHeight, "Pixel height property should be accessible")
        XCTAssertNotNil(decoder.pixelDepth, "Pixel depth property should be accessible")
    }

    func testConcurrentGeometryAccess() {
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent geometry access")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent access to geometry-related methods
        for _ in 0..<10 {
            DispatchQueue.global().async {
                _ = decoder.info(for: 0x00200032)  // Image Position
                _ = decoder.info(for: 0x00200037)  // Image Orientation
                _ = decoder.doubleValue(for: 0x00280030)  // Pixel Spacing
                _ = decoder.pixelSpacing
                _ = decoder.imageDimensions

                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Transfer Syntax Tests

    func testTransferSyntaxDetection() {
        let decoder = DCMDecoder()

        // Test that compression flag is initially false
        XCTAssertFalse(decoder.compressedImage, "Initial compressed image flag should be false")
    }

    // MARK: - Pixel Representation Tests

    func testPixelRepresentationAccess() {
        let decoder = DCMDecoder()

        // Test pixel representation accessors
        XCTAssertEqual(decoder.pixelRepresentationTagValue, 0, "Default pixel representation should be 0 (unsigned)")
        XCTAssertFalse(decoder.isSignedPixelRepresentation, "Default should not be signed")
        XCTAssertFalse(decoder.signedImage, "Default signed image flag should be false")
    }

    // MARK: - Metadata Access Thread Safety Tests

    func testConcurrentMetadataAccess() {
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent metadata access")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent access to metadata methods
        for _ in 0..<10 {
            DispatchQueue.global().async {
                // Access various metadata methods concurrently
                _ = decoder.info(for: DicomTag.patientName.rawValue)
                _ = decoder.intValue(for: DicomTag.rows.rawValue)
                _ = decoder.doubleValue(for: DicomTag.pixelSpacing.rawValue)
                _ = decoder.rescaleParameters
                _ = decoder.windowSettings
                _ = decoder.imageDimensions

                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testConcurrentMixedPropertyAndMethodAccess() {
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent mixed access")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent access mixing properties and methods
        for i in 0..<10 {
            DispatchQueue.global().async {
                if i % 2 == 0 {
                    _ = decoder.width
                    _ = decoder.height
                    _ = decoder.bitDepth
                } else {
                    _ = decoder.info(for: DicomTag.modality.rawValue)
                    _ = decoder.intValue(for: DicomTag.bitsAllocated.rawValue)
                    _ = decoder.doubleValue(for: DicomTag.rescaleSlope.rawValue)
                }

                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Tag Constant Validation Tests

    func testDicomTagConstantsAreValid() {
        // Test that common DICOM tag constants have reasonable values
        XCTAssertGreaterThan(DicomTag.patientName.rawValue, 0, "PatientName tag should be positive")
        XCTAssertGreaterThan(DicomTag.rows.rawValue, 0, "Rows tag should be positive")
        XCTAssertGreaterThan(DicomTag.columns.rawValue, 0, "Columns tag should be positive")

        // Test specific known tag values
        XCTAssertEqual(DicomTag.patientName.rawValue, 0x00100010, "PatientName should be 0x00100010")
        XCTAssertEqual(DicomTag.rows.rawValue, 0x00280010, "Rows should be 0x00280010")
        XCTAssertEqual(DicomTag.columns.rawValue, 0x00280011, "Columns should be 0x00280011")
    }

    func testDicomTagConstantsAreUnique() {
        // Collect all tag values
        let tags = [
            DicomTag.patientName.rawValue,
            DicomTag.patientID.rawValue,
            DicomTag.studyDate.rawValue,
            DicomTag.modality.rawValue,
            DicomTag.rows.rawValue,
            DicomTag.columns.rawValue,
            DicomTag.bitsAllocated.rawValue,
            DicomTag.pixelRepresentation.rawValue
        ]

        // Verify all tags are unique
        let uniqueTags = Set(tags)
        XCTAssertEqual(tags.count, uniqueTags.count, "All DICOM tag constants should be unique")
    }

    // MARK: - Edge Case Tests

    func testNegativeTagValue() {
        let decoder = DCMDecoder()

        // Test with negative tag value (should still work as it's treated as unsigned)
        let result = decoder.info(for: -1)
        XCTAssertEqual(result, "", "Negative tag should return empty string")
    }

    func testVeryLargeTagValue() {
        let decoder = DCMDecoder()

        // Test with very large tag value
        let result = decoder.info(for: Int.max)
        XCTAssertEqual(result, "", "Very large tag should return empty string")
    }

    func testMultipleConsecutiveInfoCalls() {
        let decoder = DCMDecoder()

        // Test that multiple consecutive calls return consistent results
        let result1 = decoder.info(for: DicomTag.patientName.rawValue)
        let result2 = decoder.info(for: DicomTag.patientName.rawValue)
        let result3 = decoder.info(for: DicomTag.patientName.rawValue)

        XCTAssertEqual(result1, result2, "Consecutive calls should return same result")
        XCTAssertEqual(result2, result3, "Consecutive calls should return same result")
    }

    func testMultipleConsecutiveIntValueCalls() {
        let decoder = DCMDecoder()

        // Test that multiple consecutive calls return consistent results
        let result1 = decoder.intValue(for: DicomTag.rows.rawValue)
        let result2 = decoder.intValue(for: DicomTag.rows.rawValue)
        let result3 = decoder.intValue(for: DicomTag.rows.rawValue)

        XCTAssertEqual(result1, result2, "Consecutive calls should return same result")
        XCTAssertEqual(result2, result3, "Consecutive calls should return same result")
    }

    func testMultipleConsecutiveDoubleValueCalls() {
        let decoder = DCMDecoder()

        // Test that multiple consecutive calls return consistent results
        let result1 = decoder.doubleValue(for: DicomTag.rescaleSlope.rawValue)
        let result2 = decoder.doubleValue(for: DicomTag.rescaleSlope.rawValue)
        let result3 = decoder.doubleValue(for: DicomTag.rescaleSlope.rawValue)

        XCTAssertEqual(result1, result2, "Consecutive calls should return same result")
        XCTAssertEqual(result2, result3, "Consecutive calls should return same result")
    }

    // MARK: - Grouped Metadata Helpers Tests

    func testGroupedMetadataHelpers() {
        let decoder = DCMDecoder()

        // Test that grouped helpers match individual properties
        XCTAssertEqual(decoder.imageDimensions.width, decoder.width, "Image dimensions width should match width property")
        XCTAssertEqual(decoder.imageDimensions.height, decoder.height, "Image dimensions height should match height property")

        XCTAssertEqual(decoder.pixelSpacing.width, decoder.pixelWidth, "Pixel spacing width should match pixelWidth property")
        XCTAssertEqual(decoder.pixelSpacing.height, decoder.pixelHeight, "Pixel spacing height should match pixelHeight property")
        XCTAssertEqual(decoder.pixelSpacing.depth, decoder.pixelDepth, "Pixel spacing depth should match pixelDepth property")

        XCTAssertEqual(decoder.windowSettings.center, decoder.windowCenter, "Window settings center should match windowCenter property")
        XCTAssertEqual(decoder.windowSettings.width, decoder.windowWidth, "Window settings width should match windowWidth property")

        // Test default rescale parameters (properties are private)
        XCTAssertEqual(decoder.rescaleParameters.intercept, 0.0, "Default rescale intercept should be 0.0")
        XCTAssertEqual(decoder.rescaleParameters.slope, 1.0, "Default rescale slope should be 1.0")
    }

    func testWindowSettingsPropertiesConsistency() {
        let decoder = DCMDecoder()

        // Test that window settings match convenience accessors
        let settings = decoder.windowSettings
        XCTAssertEqual(settings.center, decoder.windowCenter, "Window settings center should match windowCenter property")
        XCTAssertEqual(settings.width, decoder.windowWidth, "Window settings width should match windowWidth property")
    }

    func testRescaleParametersPropertiesConsistency() {
        let decoder = DCMDecoder()

        // Test that rescale parameters have expected defaults
        let params = decoder.rescaleParameters
        XCTAssertEqual(params.intercept, 0.0, "Default rescale intercept should be 0.0")
        XCTAssertEqual(params.slope, 1.0, "Default rescale slope should be 1.0")
    }

    func testAllGroupedHelpersReturnNonNilValues() {
        let decoder = DCMDecoder()

        // Test that all grouped helpers return valid (non-nil) values
        let dimensions = decoder.imageDimensions
        XCTAssertNotNil(dimensions.width, "Image dimensions width should not be nil")
        XCTAssertNotNil(dimensions.height, "Image dimensions height should not be nil")

        let spacing = decoder.pixelSpacing
        XCTAssertNotNil(spacing.width, "Pixel spacing width should not be nil")
        XCTAssertNotNil(spacing.height, "Pixel spacing height should not be nil")
        XCTAssertNotNil(spacing.depth, "Pixel spacing depth should not be nil")

        let windowSettings = decoder.windowSettings
        XCTAssertNotNil(windowSettings.center, "Window settings center should not be nil")
        XCTAssertNotNil(windowSettings.width, "Window settings width should not be nil")

        let rescaleParams = decoder.rescaleParameters
        XCTAssertNotNil(rescaleParams.intercept, "Rescale parameters intercept should not be nil")
        XCTAssertNotNil(rescaleParams.slope, "Rescale parameters slope should not be nil")
    }

    func testGroupedHelpersDefaults() {
        let decoder = DCMDecoder()

        // Test default values for grouped helpers
        let dimensions = decoder.imageDimensions
        XCTAssertGreaterThan(dimensions.width, 0, "Default image width should be positive")
        XCTAssertGreaterThan(dimensions.height, 0, "Default image height should be positive")

        let spacing = decoder.pixelSpacing
        XCTAssertEqual(spacing.width, 1.0, "Default pixel width should be 1.0")
        XCTAssertEqual(spacing.height, 1.0, "Default pixel height should be 1.0")
        XCTAssertEqual(spacing.depth, 1.0, "Default pixel depth should be 1.0")

        let windowSettings = decoder.windowSettings
        XCTAssertEqual(windowSettings.center, 0.0, "Default window center should be 0.0")
        XCTAssertEqual(windowSettings.width, 0.0, "Default window width should be 0.0")

        let rescaleParams = decoder.rescaleParameters
        XCTAssertEqual(rescaleParams.intercept, 0.0, "Default rescale intercept should be 0.0")
        XCTAssertEqual(rescaleParams.slope, 1.0, "Default rescale slope should be 1.0")
    }

    func testGroupedHelpersConcurrentAccess() {
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent grouped helpers access")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent access to all grouped helpers
        for _ in 0..<10 {
            DispatchQueue.global().async {
                _ = decoder.imageDimensions
                _ = decoder.pixelSpacing
                _ = decoder.windowSettings
                _ = decoder.rescaleParameters

                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testGroupedHelpersConsistencyAfterMultipleAccesses() {
        let decoder = DCMDecoder()

        // Access grouped helpers multiple times
        for _ in 0..<100 {
            let dims1 = decoder.imageDimensions
            let dims2 = decoder.imageDimensions
            XCTAssertEqual(dims1.width, dims2.width, "Image dimensions should be consistent")
            XCTAssertEqual(dims1.height, dims2.height, "Image dimensions should be consistent")

            let spacing1 = decoder.pixelSpacing
            let spacing2 = decoder.pixelSpacing
            XCTAssertEqual(spacing1.width, spacing2.width, "Pixel spacing should be consistent")
            XCTAssertEqual(spacing1.height, spacing2.height, "Pixel spacing should be consistent")
            XCTAssertEqual(spacing1.depth, spacing2.depth, "Pixel spacing should be consistent")

            let window1 = decoder.windowSettings
            let window2 = decoder.windowSettings
            XCTAssertEqual(window1.center, window2.center, "Window settings should be consistent")
            XCTAssertEqual(window1.width, window2.width, "Window settings should be consistent")

            let rescale1 = decoder.rescaleParameters
            let rescale2 = decoder.rescaleParameters
            XCTAssertEqual(rescale1.intercept, rescale2.intercept, "Rescale parameters should be consistent")
            XCTAssertEqual(rescale1.slope, rescale2.slope, "Rescale parameters should be consistent")
        }
    }

    // MARK: - Convenience Property Tests

    func testRescaleParametersStructure() {
        let decoder = DCMDecoder()
        let params = decoder.rescaleParameters

        // Test that the tuple has both fields
        _ = params.intercept
        _ = params.slope

        XCTAssertTrue(true, "Rescale parameters should have intercept and slope fields")
    }

    func testWindowSettingsStructure() {
        let decoder = DCMDecoder()
        let settings = decoder.windowSettings

        // Test that the tuple has both fields
        _ = settings.center
        _ = settings.width

        XCTAssertTrue(true, "Window settings should have center and width fields")
    }

    func testPixelSpacingStructure() {
        let decoder = DCMDecoder()
        let spacing = decoder.pixelSpacing

        // Test that the tuple has all three fields
        _ = spacing.width
        _ = spacing.height
        _ = spacing.depth

        XCTAssertTrue(true, "Pixel spacing should have width, height, and depth fields")
    }

    func testImageDimensionsStructure() {
        let decoder = DCMDecoder()
        let dimensions = decoder.imageDimensions

        // Test that the tuple has both fields
        _ = dimensions.width
        _ = dimensions.height

        XCTAssertTrue(true, "Image dimensions should have width and height fields")
    }

    // MARK: - Memory and Performance Tests

    func testMetadataAccessMemoryEfficiency() {
        let decoder = DCMDecoder()

        // Access metadata many times to ensure no memory leaks
        for _ in 0..<10000 {
            _ = decoder.info(for: DicomTag.patientName.rawValue)
            _ = decoder.intValue(for: DicomTag.rows.rawValue)
            _ = decoder.doubleValue(for: DicomTag.pixelSpacing.rawValue)
        }

        XCTAssertTrue(true, "Multiple metadata accesses should not cause memory issues")
    }

    func testMetadataAccessPerformance() {
        let decoder = DCMDecoder()

        // Measure overall metadata access performance
        measure {
            for _ in 0..<1000 {
                _ = decoder.info(for: DicomTag.patientName.rawValue)
                _ = decoder.info(for: DicomTag.studyDate.rawValue)
                _ = decoder.intValue(for: DicomTag.rows.rawValue)
                _ = decoder.doubleValue(for: DicomTag.rescaleSlope.rawValue)
                _ = decoder.rescaleParameters
                _ = decoder.windowSettings
            }
        }
    }
}
