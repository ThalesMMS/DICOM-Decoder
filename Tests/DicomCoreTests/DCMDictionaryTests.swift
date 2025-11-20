import XCTest
@testable import DicomCore

final class DCMDictionaryTests: XCTestCase {

    // MARK: - Dictionary Loading Tests

    func testDictionaryLoadsFromBundle() {
        let modalityDescription = DCMDictionary.description(forKey: "00080060")
        XCTAssertNotNil(modalityDescription, "Expected DICOM tag 00080060 to exist in the dictionary")
    }

    func testCommonDICOMTags() {
        // Patient Information Tags
        XCTAssertNotNil(DCMDictionary.description(forKey: "00100010"), "Patient Name should exist")
        XCTAssertNotNil(DCMDictionary.description(forKey: "00100020"), "Patient ID should exist")

        // Study Information Tags
        XCTAssertNotNil(DCMDictionary.description(forKey: "0020000D"), "Study Instance UID should exist")
        XCTAssertNotNil(DCMDictionary.description(forKey: "00080020"), "Study Date should exist")

        // Image Information Tags
        XCTAssertNotNil(DCMDictionary.description(forKey: "00280010"), "Rows should exist")
        XCTAssertNotNil(DCMDictionary.description(forKey: "00280011"), "Columns should exist")
    }

    // MARK: - Decoder Validation Tests

    func testDecoderValidation() {
        let decoder = DCMDecoder()

        // Test initial state
        XCTAssertFalse(decoder.isValid(), "New decoder should not be valid")
        XCTAssertFalse(decoder.dicomFileReadSuccess, "New decoder should not have read success")

        // Test validation status
        let status = decoder.getValidationStatus()
        XCTAssertFalse(status.isValid, "Initial validation should fail")
        XCTAssertFalse(status.hasPixels, "Should have no pixels initially")
    }

    func testDecoderConvenienceMethods() {
        let decoder = DCMDecoder()

        // Test convenience getters
        XCTAssertEqual(decoder.imageDimensions.width, decoder.width)
        XCTAssertEqual(decoder.imageDimensions.height, decoder.height)

        XCTAssertEqual(decoder.pixelSpacing.width, decoder.pixelWidth)
        XCTAssertEqual(decoder.pixelSpacing.height, decoder.pixelHeight)
        XCTAssertEqual(decoder.pixelSpacing.depth, decoder.pixelDepth)

        XCTAssertEqual(decoder.windowSettings.center, decoder.windowCenter)
        XCTAssertEqual(decoder.windowSettings.width, decoder.windowWidth)

        XCTAssertEqual(decoder.rescaleParameters.intercept, 0.0)
        XCTAssertEqual(decoder.rescaleParameters.slope, 1.0)
    }

    func testDecoderImageTypeDetection() {
        let decoder = DCMDecoder()

        // Grayscale should be default
        XCTAssertTrue(decoder.isGrayscale, "Default should be grayscale")
        XCTAssertFalse(decoder.isColorImage, "Default should not be color")
        XCTAssertFalse(decoder.isMultiFrame, "Default should not be multi-frame")
    }

    // MARK: - Windowing Processor Tests

    func testWindowingPresets() {
        // Test all presets have valid values
        for preset in DCMWindowingProcessor.allPresets {
            let values = DCMWindowingProcessor.getPresetValues(preset: preset)
            XCTAssertGreaterThan(values.width, 0, "\(preset.displayName) should have positive width")
        }
    }

    func testCTPresets() {
        let ctPresets = DCMWindowingProcessor.ctPresets
        XCTAssertTrue(ctPresets.contains(.lung), "CT presets should include lung")
        XCTAssertTrue(ctPresets.contains(.bone), "CT presets should include bone")
        XCTAssertTrue(ctPresets.contains(.brain), "CT presets should include brain")
    }

    func testPresetSuggestions() {
        // Test CT modality suggestions
        let ctSuggestions = DCMWindowingProcessor.suggestPresets(for: "CT", bodyPart: "CHEST")
        XCTAssertTrue(ctSuggestions.contains(.lung), "CT chest should suggest lung preset")

        let brainSuggestions = DCMWindowingProcessor.suggestPresets(for: "CT", bodyPart: "BRAIN")
        XCTAssertTrue(brainSuggestions.contains(.brain), "CT brain should suggest brain preset")

        // Test other modalities
        let mgSuggestions = DCMWindowingProcessor.suggestPresets(for: "MG")
        XCTAssertTrue(mgSuggestions.contains(.mammography), "MG should suggest mammography preset")

        let petSuggestions = DCMWindowingProcessor.suggestPresets(for: "PT")
        XCTAssertTrue(petSuggestions.contains(.petScan), "PT should suggest PET scan preset")
    }

    func testPresetValuesByName() {
        // Test case-insensitive name lookup
        XCTAssertNotNil(DCMWindowingProcessor.getPresetValues(named: "lung"))
        XCTAssertNotNil(DCMWindowingProcessor.getPresetValues(named: "LUNG"))
        XCTAssertNotNil(DCMWindowingProcessor.getPresetValues(named: "Lung"))

        // Test multi-word names
        XCTAssertNotNil(DCMWindowingProcessor.getPresetValues(named: "soft tissue"))
        XCTAssertNotNil(DCMWindowingProcessor.getPresetValues(named: "softtissue"))

        // Test invalid name
        XCTAssertNil(DCMWindowingProcessor.getPresetValues(named: "invalid_preset"))
    }

    func testPresetNameRecognition() {
        let lungPreset = DCMWindowingProcessor.getPresetValues(preset: .lung)
        let recognizedName = DCMWindowingProcessor.getPresetName(
            center: lungPreset.center,
            width: lungPreset.width,
            tolerance: 10.0
        )
        XCTAssertEqual(recognizedName, "Lung", "Should recognize lung preset values")
    }

    func testHounsfieldConversion() {
        let slope = 1.0
        let intercept = -1024.0

        // Test pixel value to HU conversion
        let hu = DCMWindowingProcessor.pixelValueToHU(
            pixelValue: 1024.0,
            rescaleSlope: slope,
            rescaleIntercept: intercept
        )
        XCTAssertEqual(hu, 0.0, accuracy: 0.01, "1024 pixel value should equal 0 HU")

        // Test HU to pixel value conversion
        let pixelValue = DCMWindowingProcessor.huToPixelValue(
            hu: 0.0,
            rescaleSlope: slope,
            rescaleIntercept: intercept
        )
        XCTAssertEqual(pixelValue, 1024.0, accuracy: 0.01, "0 HU should equal 1024 pixel value")
    }

    func testQualityMetrics() {
        // Create sample pixel data
        let pixels: [UInt16] = Array(0..<1000).map { UInt16($0) }

        let metrics = DCMWindowingProcessor.calculateQualityMetrics(pixels16: pixels)

        XCTAssertNotNil(metrics["mean"], "Should have mean value")
        XCTAssertNotNil(metrics["std_deviation"], "Should have standard deviation")
        XCTAssertNotNil(metrics["min_value"], "Should have min value")
        XCTAssertNotNil(metrics["max_value"], "Should have max value")
        XCTAssertNotNil(metrics["contrast"], "Should have contrast value")
        XCTAssertNotNil(metrics["snr"], "Should have SNR value")
        XCTAssertNotNil(metrics["dynamic_range"], "Should have dynamic range")

        // Verify calculated values are reasonable
        XCTAssertGreaterThan(metrics["mean"]!, 0, "Mean should be positive")
        XCTAssertGreaterThan(metrics["std_deviation"]!, 0, "Std dev should be positive")
    }

    func testOptimalWindowCalculation() {
        // Create sample pixel data with known distribution
        let pixels: [UInt16] = Array(repeating: 100, count: 500) +
                               Array(repeating: 200, count: 500)

        let optimal = DCMWindowingProcessor.calculateOptimalWindowLevel(pixels16: pixels)

        XCTAssertGreaterThan(optimal.center, 0, "Center should be positive")
        XCTAssertGreaterThan(optimal.width, 0, "Width should be positive")
    }

    // MARK: - Error Handling Tests

    func testDICOMErrors() {
        let fileError = DICOMError.fileNotFound(path: "/test/path")
        XCTAssertNotNil(fileError.errorDescription, "Should have error description")
        XCTAssertNotNil(fileError.recoverySuggestion, "Should have recovery suggestion")

        XCTAssertEqual(fileError.category, .file, "Should be file category")
        XCTAssertEqual(fileError.severity, .warning, "File not found should be warning")

        let memoryError = DICOMError.memoryAllocationFailed(requestedSize: 1000000)
        XCTAssertEqual(memoryError.severity, .critical, "Memory error should be critical")
    }

    // MARK: - Performance Tests

    func testWindowingPerformance() {
        // Create large pixel array
        let pixels: [UInt16] = Array(repeating: 1000, count: 512 * 512)

        measure {
            _ = DCMWindowingProcessor.applyWindowLevel(
                pixels16: pixels,
                center: 40.0,
                width: 80.0
            )
        }
    }

    func testOptimizedWindowingPerformance() {
        let pixels: [UInt16] = Array(repeating: 1000, count: 512 * 512)

        measure {
            _ = DCMWindowingProcessor.optimizedApplyWindowLevel(
                pixels16: pixels,
                center: 40.0,
                width: 80.0,
                useParallel: true
            )
        }
    }
}
