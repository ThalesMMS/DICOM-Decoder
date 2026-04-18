import XCTest
@testable import DicomCore

final class DCMDecoderPixelThreadSafetyTests: XCTestCase {

    // MARK: - Thread Safety Tests for Pixel Access

    func testConcurrentPixelAccess() throws {
        let decoder = try DCMDecoder(contentsOf: getCTSyntheticFixtureURL())
        let expectedPixels16 = try XCTUnwrap(decoder.getPixels16())
        let expectation = self.expectation(description: "Concurrent pixel access")
        expectation.expectedFulfillmentCount = 10
        let resultsQueue = DispatchQueue(label: "pixel.results.queue")
        var pixels16Results: [[UInt16]?] = []
        var pixels8Results: [[UInt8]?] = []
        var pixels24Results: [[UInt8]?] = []

        // Test concurrent pixel buffer access
        for _ in 0..<10 {
            DispatchQueue.global().async {
                let pixels8 = decoder.getPixels8()
                let pixels16 = decoder.getPixels16()
                let pixels24 = decoder.getPixels24()
                resultsQueue.sync {
                    pixels8Results.append(pixels8)
                    pixels16Results.append(pixels16)
                    pixels24Results.append(pixels24)
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0, handler: nil)
        XCTAssertEqual(pixels16Results.count, 10)
        XCTAssertTrue(pixels16Results.allSatisfy { $0 == expectedPixels16 }, "All concurrent pixels16 accesses should return the same buffer")
        XCTAssertTrue(pixels8Results.allSatisfy { $0 == nil }, "CT fixture should not expose 8-bit pixels")
        XCTAssertTrue(pixels24Results.allSatisfy { $0 == nil }, "CT fixture should not expose RGB pixels")
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
        let expectation = self.expectation(description: "Concurrent load and pixel access")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent file loading attempts
        for i in 0..<10 {
            DispatchQueue.global().async {
                let decoder = try? DCMDecoder(contentsOfFile: "/nonexistent/file\(i).dcm")
                XCTAssertNil(decoder, "Decoder should be nil for nonexistent file")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0, handler: nil)
    }
}
