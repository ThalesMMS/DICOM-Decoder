import XCTest
@testable import DicomCore

// MARK: - DCMWindowingProcessor Batch Tests

final class DCMWindowingProcessorBatchTests: XCTestCase {

    // MARK: - batchApplyWindowLevel Tests

    func testBatchApplyWindowLevelBasic() throws {
        let pixels1: [UInt16] = [0, 1000, 2000, 3000, 4000]
        let pixels2: [UInt16] = [500, 1500, 2500, 3500, 4500]

        let results = try DCMWindowingProcessor.batchApplyWindowLevel(
            imagePixels: [pixels1, pixels2],
            centers: [2000.0, 2500.0],
            widths: [4000.0, 4000.0]
        )

        XCTAssertEqual(results.count, 2, "Should return results for each input image")
        XCTAssertNotNil(results[0], "First image result should not be nil")
        XCTAssertNotNil(results[1], "Second image result should not be nil")
    }

    func testBatchApplyWindowLevelEmptyInput() throws {
        let results = try DCMWindowingProcessor.batchApplyWindowLevel(
            imagePixels: [],
            centers: [],
            widths: []
        )
        XCTAssertTrue(results.isEmpty, "Empty input should return empty results")
    }

    func testBatchApplyWindowLevelMismatchedArraysThrows() {
        let pixels: [UInt16] = [0, 1000, 2000]
        // 1 image, 2 centers, 2 widths - mismatched
        XCTAssertThrowsError(try DCMWindowingProcessor.batchApplyWindowLevel(
            imagePixels: [pixels],
            centers: [1000.0, 2000.0],
            widths: [2000.0, 3000.0]
        )) { error in
            XCTAssertEqual(error as? WindowingBatchError,
                           .mismatchedInputCounts(imagePixels: 1, centers: 2, widths: 2))
        }
    }

    func testBatchApplyWindowLevelMismatchedCentersWidthsThrows() {
        let pixels: [UInt16] = [0, 1000, 2000]
        // 1 image, 1 center, 2 widths - mismatched
        XCTAssertThrowsError(try DCMWindowingProcessor.batchApplyWindowLevel(
            imagePixels: [pixels],
            centers: [1000.0],
            widths: [2000.0, 3000.0]
        )) { error in
            XCTAssertEqual(error as? WindowingBatchError,
                           .mismatchedInputCounts(imagePixels: 1, centers: 1, widths: 2))
        }
    }

    func testBatchApplyWindowLevelResultSizesMatchInput() throws {
        let pixels1: [UInt16] = Array(repeating: 1000, count: 100)
        let pixels2: [UInt16] = Array(repeating: 2000, count: 200)

        let results = try DCMWindowingProcessor.batchApplyWindowLevel(
            imagePixels: [pixels1, pixels2],
            centers: [1000.0, 2000.0],
            widths: [2000.0, 2000.0]
        )

        XCTAssertEqual(results.count, 2, "Should have 2 results")
        XCTAssertEqual(results[0]?.count, 100, "First result should have 100 bytes")
        XCTAssertEqual(results[1]?.count, 200, "Second result should have 200 bytes")
    }

    func testBatchApplyWindowLevelSingleImage() throws {
        let pixels: [UInt16] = [0, 500, 1000, 1500, 2000]

        let results = try DCMWindowingProcessor.batchApplyWindowLevel(
            imagePixels: [pixels],
            centers: [1000.0],
            widths: [2000.0]
        )

        XCTAssertEqual(results.count, 1, "Single image should return single result")
        XCTAssertNotNil(results[0], "Result should not be nil")
        XCTAssertEqual(results[0]?.count, pixels.count, "Result size should match input size")
    }

    // MARK: - batchCalculateOptimalWindowLevelV2 Tests

    func testBatchCalculateOptimalWindowLevelBasic() {
        let pixels1: [UInt16] = [100, 500, 1000, 1500, 2000]
        let pixels2: [UInt16] = [200, 800, 1600, 2400, 3200]

        let results = DCMWindowingProcessor.batchCalculateOptimalWindowLevelV2(
            imagePixels: [pixels1, pixels2]
        )

        XCTAssertEqual(results.count, 2, "Should return one result per input image")
    }

    func testBatchCalculateOptimalWindowLevelEmptyInput() {
        let results = DCMWindowingProcessor.batchCalculateOptimalWindowLevelV2(imagePixels: [])
        XCTAssertTrue(results.isEmpty, "Empty input should return empty results")
    }

    func testBatchCalculateOptimalWindowLevelResultsHavePositiveWidth() {
        let pixels1: [UInt16] = [100, 500, 1000, 1500, 2000, 2500, 3000]
        let pixels2: [UInt16] = [50, 400, 800, 1200]

        let results = DCMWindowingProcessor.batchCalculateOptimalWindowLevelV2(
            imagePixels: [pixels1, pixels2]
        )

        for (i, settings) in results.enumerated() {
            XCTAssertGreaterThan(settings.width, 0, "Image \(i) should have positive window width")
        }
    }

    func testBatchCalculateOptimalWindowLevelSingleImage() {
        let pixels: [UInt16] = [1000, 2000, 3000, 4000, 5000]
        let results = DCMWindowingProcessor.batchCalculateOptimalWindowLevelV2(imagePixels: [pixels])
        XCTAssertEqual(results.count, 1, "Should return exactly one result for single image")
    }

    func testBatchCalculateOptimalWindowLevelPreservesOrder() {
        // Verify results are returned in the same order as inputs
        let pixelsHigh: [UInt16] = [5000, 6000, 7000, 8000] // high intensity
        let pixelsLow: [UInt16] = [100, 200, 300, 400]      // low intensity

        let results = DCMWindowingProcessor.batchCalculateOptimalWindowLevelV2(
            imagePixels: [pixelsHigh, pixelsLow]
        )

        XCTAssertEqual(results.count, 2, "Should return 2 results")
        // High intensity image should have higher center than low intensity image
        XCTAssertGreaterThan(results[0].center, results[1].center,
                             "High intensity image should have higher center")
    }

    // MARK: - optimizedApplyWindowLevel Tests

    func testOptimizedApplyWindowLevelBasic() {
        let pixels: [UInt16] = [0, 1000, 2000, 3000, 4000]
        let result = DCMWindowingProcessor.optimizedApplyWindowLevel(
            pixels16: pixels, center: 2000.0, width: 4000.0)

        XCTAssertNotNil(result, "Should produce output for valid input")
        XCTAssertEqual(result?.count, pixels.count, "Output should have same count as input")
    }

    func testOptimizedApplyWindowLevelEmptyInput() {
        let result = DCMWindowingProcessor.optimizedApplyWindowLevel(
            pixels16: [], center: 2000.0, width: 4000.0)
        XCTAssertNil(result, "Empty input should return nil")
    }

    func testOptimizedApplyWindowLevelZeroWidthReturnsNil() {
        let pixels: [UInt16] = [0, 1000, 2000]
        let result = DCMWindowingProcessor.optimizedApplyWindowLevel(
            pixels16: pixels, center: 1000.0, width: 0.0)
        XCTAssertNil(result, "Zero width should return nil")
    }

    func testOptimizedApplyWindowLevelNegativeWidthReturnsNil() {
        let pixels: [UInt16] = [0, 1000, 2000]
        let result = DCMWindowingProcessor.optimizedApplyWindowLevel(
            pixels16: pixels, center: 1000.0, width: -100.0)
        XCTAssertNil(result, "Negative width should return nil")
    }

    func testOptimizedApplyWindowLevelOutputRange() {
        // Output should be clamped to 0-255
        let pixels: [UInt16] = [0, 500, 1000, 1500, 2000]
        let result = DCMWindowingProcessor.optimizedApplyWindowLevel(
            pixels16: pixels, center: 1000.0, width: 2000.0)

        XCTAssertNotNil(result)
        let bytes = [UInt8](result!)
        for byte in bytes {
            XCTAssertLessThanOrEqual(byte, 255, "Output should be <= 255")
            XCTAssertGreaterThanOrEqual(byte, 0, "Output should be >= 0")
        }
    }

    func testOptimizedApplyWindowLevelSequentialMode() {
        // Use useParallel=false (sequential mode)
        let pixels: [UInt16] = Array(0..<100).map { UInt16($0 * 10) }
        let result = DCMWindowingProcessor.optimizedApplyWindowLevel(
            pixels16: pixels, center: 500.0, width: 1000.0, useParallel: false)

        XCTAssertNotNil(result, "Sequential mode should produce output")
        XCTAssertEqual(result?.count, pixels.count, "Output size should match input")
    }

    func testOptimizedApplyWindowLevelParallelEqualsSequential() {
        // Large enough to trigger parallel processing (>10000 pixels)
        let pixelCount = 15000
        let pixels: [UInt16] = Array(0..<pixelCount).map { UInt16($0 % 4096) }
        let center = 2000.0
        let width = 4000.0

        let seqResult = DCMWindowingProcessor.optimizedApplyWindowLevel(
            pixels16: pixels, center: center, width: width, useParallel: false)
        let parResult = DCMWindowingProcessor.optimizedApplyWindowLevel(
            pixels16: pixels, center: center, width: width, useParallel: true)

        XCTAssertNotNil(seqResult, "Sequential result should not be nil")
        XCTAssertNotNil(parResult, "Parallel result should not be nil")
        XCTAssertEqual(seqResult?.count, parResult?.count, "Sequential and parallel results should have same count")

        // Verify results are equivalent (parallel processing should produce same values)
        let seqBytes = [UInt8](seqResult!)
        let parBytes = [UInt8](parResult!)
        XCTAssertEqual(seqBytes, parBytes, "Sequential and parallel results should be identical")
    }

    func testOptimizedApplyWindowLevelBoundaryMapping() {
        // Pixel at window minimum should map to 0, maximum should map to 255
        // center=1000, width=2000 → range [0, 2000]
        let pixels: [UInt16] = [0, 2000, 1000]
        let result = DCMWindowingProcessor.optimizedApplyWindowLevel(
            pixels16: pixels, center: 1000.0, width: 2000.0, useParallel: false)

        XCTAssertNotNil(result)
        let bytes = [UInt8](result!)
        XCTAssertEqual(bytes[0], 0, "Pixel at window minimum should map to 0")
        XCTAssertEqual(bytes[1], 255, "Pixel at window maximum should map to 255")
        // Center should map to approximately 127
        XCTAssertTrue(bytes[2] >= 125 && bytes[2] <= 130, "Center pixel should map to ~127, got \(bytes[2])")
    }
}
