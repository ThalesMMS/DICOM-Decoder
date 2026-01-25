import XCTest
@testable import DicomCore

final class DCMDecoderConcurrencyTests: XCTestCase {

    // MARK: - Concurrent Instance Tests

    func testMultipleDecoderInstancesConcurrent() {
        // Test that multiple decoder instances can be created and used concurrently
        let expectation = XCTestExpectation(description: "Multiple decoders created concurrently")
        let iterations = 10
        var completedCount = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let countLock = NSLock()

        for i in 0..<iterations {
            queue.async {
                // Create a decoder instance in this thread
                let decoder = DCMDecoder()

                // Verify initial state is consistent
                XCTAssertFalse(decoder.isValid(), "New decoder \(i) should not be valid")
                XCTAssertFalse(decoder.dicomFileReadSuccess, "New decoder \(i) should not have read success")

                // Test basic operations
                let status = decoder.getValidationStatus()
                XCTAssertFalse(status.isValid, "Decoder \(i) validation should fail initially")

                // Increment completed count safely
                countLock.lock()
                completedCount += 1
                if completedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(completedCount, iterations, "All decoder instances should complete")
    }

    func testConcurrentDecoderPropertyAccess() {
        // Test that multiple threads can safely access decoder properties
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent property access")
        let iterations = 20
        var completedCount = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let countLock = NSLock()

        for _ in 0..<iterations {
            queue.async {
                // Access various properties concurrently
                _ = decoder.isValid()
                _ = decoder.dicomFileReadSuccess
                _ = decoder.width
                _ = decoder.height
                _ = decoder.imageDimensions
                _ = decoder.pixelSpacing
                _ = decoder.windowSettings
                _ = decoder.rescaleParameters
                _ = decoder.isGrayscale
                _ = decoder.isColorImage

                // Increment completed count safely
                countLock.lock()
                completedCount += 1
                if completedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(completedCount, iterations, "All property access operations should complete")
    }

    func testConcurrentValidationStatusChecks() {
        // Test that validation status can be checked from multiple threads safely
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent validation checks")
        let iterations = 15
        var completedCount = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let countLock = NSLock()

        for i in 0..<iterations {
            queue.async {
                // Check validation status
                let status = decoder.getValidationStatus()
                XCTAssertFalse(status.isValid, "Thread \(i): validation should fail for unloaded decoder")
                XCTAssertFalse(status.hasPixels, "Thread \(i): should have no pixels")

                // Check convenience methods
                XCTAssertFalse(decoder.isValid(), "Thread \(i): decoder should not be valid")

                // Increment completed count safely
                countLock.lock()
                completedCount += 1
                if completedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(completedCount, iterations, "All validation checks should complete")
    }

    func testConcurrentMetadataAccess() {
        // Test that metadata access is thread-safe
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent metadata access")
        let iterations = 20
        var completedCount = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let countLock = NSLock()

        // Common DICOM tags to query
        let tags = [
            0x00100010, // Patient Name
            0x00100020, // Patient ID
            0x00080060, // Modality
            0x00280010, // Rows
            0x00280011, // Columns
            0x0020000D, // Study Instance UID
        ]

        for _ in 0..<iterations {
            queue.async {
                // Access metadata concurrently
                for tag in tags {
                    _ = decoder.info(for: tag)
                    _ = decoder.intValue(for: tag)
                    _ = decoder.doubleValue(for: tag)
                }

                // Access grouped metadata
                _ = decoder.getPatientInfo()
                _ = decoder.getStudyInfo()
                _ = decoder.getSeriesInfo()

                // Increment completed count safely
                countLock.lock()
                completedCount += 1
                if completedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(completedCount, iterations, "All metadata access operations should complete")
    }

    func testConcurrentPixelDataAccess() {
        // Test that pixel data access is thread-safe (even when no pixels are loaded)
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent pixel access")
        let iterations = 15
        var completedCount = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let countLock = NSLock()

        for i in 0..<iterations {
            queue.async {
                // Attempt to access pixels concurrently
                let pixels8 = decoder.getPixels8()
                let pixels16 = decoder.getPixels16()

                // Should be nil since no file is loaded
                XCTAssertNil(pixels8, "Thread \(i): pixels8 should be nil")
                XCTAssertNil(pixels16, "Thread \(i): pixels16 should be nil")

                // Increment completed count safely
                countLock.lock()
                completedCount += 1
                if completedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(completedCount, iterations, "All pixel access operations should complete")
    }

    func testConcurrentPixelAndMetadataAccess() {
        // Test that a single decoder instance can handle concurrent pixel and metadata access
        // This is the most realistic scenario - threads reading both pixel data and metadata
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent pixel and metadata access")
        let iterations = 30
        var completedCount = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let countLock = NSLock()

        for i in 0..<iterations {
            queue.async {
                // Mix pixel access with metadata access
                switch i % 6 {
                case 0:
                    // Pixel access - 8-bit
                    let pixels8 = decoder.getPixels8()
                    XCTAssertNil(pixels8, "Thread \(i): pixels8 should be nil")
                    _ = decoder.width
                    _ = decoder.height

                case 1:
                    // Pixel access - 16-bit
                    let pixels16 = decoder.getPixels16()
                    XCTAssertNil(pixels16, "Thread \(i): pixels16 should be nil")
                    _ = decoder.info(for: 0x00280010) // Rows
                    _ = decoder.info(for: 0x00280011) // Columns

                case 2:
                    // Pixel access - 24-bit color
                    let pixels24 = decoder.getPixels24()
                    XCTAssertNil(pixels24, "Thread \(i): pixels24 should be nil")
                    _ = decoder.isColorImage
                    _ = decoder.isGrayscale

                case 3:
                    // Downsampled pixel access (may return default values even when no file loaded)
                    _ = decoder.getDownsampledPixels16(maxDimension: 150)
                    _ = decoder.pixelSpacing
                    _ = decoder.imageDimensions

                case 4:
                    // Multiple pixel format checks
                    _ = decoder.getPixels8()
                    _ = decoder.getPixels16()
                    _ = decoder.windowSettings
                    _ = decoder.rescaleParameters

                case 5:
                    // Mixed metadata and validation
                    _ = decoder.getValidationStatus()
                    _ = decoder.getPatientInfo()
                    let pixels = decoder.getPixels16()
                    XCTAssertNil(pixels, "Thread \(i): pixels16 should be nil")
                    _ = decoder.getStudyInfo()

                default:
                    break
                }

                // Increment completed count safely
                countLock.lock()
                completedCount += 1
                if completedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: 10.0)
        XCTAssertEqual(completedCount, iterations, "All concurrent pixel and metadata access operations should complete")
    }

    // MARK: - Mixed Operations Tests

    func testConcurrentMixedOperations() {
        // Test a realistic scenario with mixed read operations
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent mixed operations")
        let iterations = 25
        var completedCount = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let countLock = NSLock()

        for i in 0..<iterations {
            queue.async {
                // Perform various operations concurrently
                switch i % 5 {
                case 0:
                    _ = decoder.isValid()
                    _ = decoder.getValidationStatus()
                case 1:
                    _ = decoder.width
                    _ = decoder.height
                    _ = decoder.imageDimensions
                case 2:
                    _ = decoder.info(for: 0x00100010)
                    _ = decoder.getPatientInfo()
                case 3:
                    _ = decoder.getPixels16()
                    _ = decoder.getPixels8()
                case 4:
                    _ = decoder.windowSettings
                    _ = decoder.rescaleParameters
                    _ = decoder.pixelSpacing
                default:
                    break
                }

                // Increment completed count safely
                countLock.lock()
                completedCount += 1
                if completedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(completedCount, iterations, "All mixed operations should complete")
    }

    // MARK: - Stress Tests

    func testHighConcurrencyStress() {
        // Stress test with high concurrency
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "High concurrency stress test")
        let iterations = 50
        var completedCount = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let countLock = NSLock()

        for _ in 0..<iterations {
            queue.async {
                // Rapid-fire property access
                for _ in 0..<10 {
                    _ = decoder.isValid()
                    _ = decoder.width
                    _ = decoder.info(for: 0x00280010)
                }

                // Increment completed count safely
                countLock.lock()
                completedCount += 1
                if completedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: 10.0)
        XCTAssertEqual(completedCount, iterations, "All stress test operations should complete")
    }

    func testMultipleDecodersWithMixedAccess() {
        // Test multiple decoders being accessed concurrently
        let decoderCount = 5
        let decoders = (0..<decoderCount).map { _ in DCMDecoder() }
        let expectation = XCTestExpectation(description: "Multiple decoders with mixed access")
        let iterations = 30
        var completedCount = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let countLock = NSLock()

        for i in 0..<iterations {
            queue.async {
                // Access a random decoder
                let decoder = decoders[i % decoderCount]

                // Perform operations
                _ = decoder.isValid()
                _ = decoder.width
                _ = decoder.height
                _ = decoder.getValidationStatus()
                _ = decoder.info(for: 0x00100010)

                // Increment completed count safely
                countLock.lock()
                completedCount += 1
                if completedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(completedCount, iterations, "All operations across multiple decoders should complete")
    }

    func testMultipleConcurrentOperationsStress() {
        // Comprehensive stress test with multiple concurrent operations
        // This test simulates a realistic high-load scenario with many threads
        // performing different operations simultaneously
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Multiple concurrent operations stress test")
        #if targetEnvironment(simulator)
        let iterations = 50
        let timeout: TimeInterval = 60.0
        #else
        let iterations = 100
        let timeout: TimeInterval = 15.0
        #endif
        var completedCount = 0
        let countLock = NSLock()

        // Use multiple queues to simulate different priority operations
        let highPriorityQueue = DispatchQueue.global(qos: .userInteractive)
        let normalPriorityQueue = DispatchQueue.global(qos: .userInitiated)
        #if targetEnvironment(simulator)
        let backgroundQueue = DispatchQueue.global(qos: .utility)
        #else
        let backgroundQueue = DispatchQueue.global(qos: .background)
        #endif

        // DICOM tags for stress testing metadata access
        let commonTags = [
            0x00100010, // Patient Name
            0x00100020, // Patient ID
            0x00080060, // Modality
            0x00280010, // Rows
            0x00280011, // Columns
            0x0020000D, // Study Instance UID
            0x0020000E, // Series Instance UID
            0x00080020, // Study Date
        ]

        for i in 0..<iterations {
            // Distribute operations across different queues
            let selectedQueue: DispatchQueue
            switch i % 3 {
            case 0:
                selectedQueue = highPriorityQueue
            case 1:
                selectedQueue = normalPriorityQueue
            default:
                selectedQueue = backgroundQueue
            }

            selectedQueue.async {
                // Perform a comprehensive set of operations based on iteration
                switch i % 10 {
                case 0:
                    // Validation operations
                    _ = decoder.isValid()
                    let status = decoder.getValidationStatus()
                    _ = status.isValid
                    _ = status.width
                    _ = status.height
                    _ = status.hasPixels
                    _ = status.isCompressed
                    _ = decoder.dicomFileReadSuccess

                case 1:
                    // Dimension and geometry properties
                    _ = decoder.width
                    _ = decoder.height
                    _ = decoder.imageDimensions
                    _ = decoder.pixelSpacing
                    _ = decoder.isMultiFrame

                case 2:
                    // Window and rescale parameters
                    _ = decoder.windowSettings
                    _ = decoder.rescaleParameters
                    _ = decoder.isGrayscale
                    _ = decoder.isColorImage

                case 3:
                    // Patient metadata access
                    _ = decoder.getPatientInfo()
                    _ = decoder.info(for: 0x00100010) // Patient Name
                    _ = decoder.info(for: 0x00100020) // Patient ID
                    _ = decoder.info(for: 0x00100030) // Patient Birth Date

                case 4:
                    // Study metadata access
                    _ = decoder.getStudyInfo()
                    _ = decoder.info(for: 0x0020000D) // Study Instance UID
                    _ = decoder.info(for: 0x00080020) // Study Date
                    _ = decoder.info(for: 0x00080030) // Study Time

                case 5:
                    // Series metadata access
                    _ = decoder.getSeriesInfo()
                    _ = decoder.info(for: 0x0020000E) // Series Instance UID
                    _ = decoder.info(for: 0x00080060) // Modality
                    _ = decoder.info(for: 0x00200011) // Series Number

                case 6:
                    // Multiple tag queries
                    for tag in commonTags {
                        _ = decoder.info(for: tag)
                    }

                case 7:
                    // Pixel data access - 8-bit and 16-bit
                    _ = decoder.getPixels8()
                    _ = decoder.getPixels16()
                    _ = decoder.width
                    _ = decoder.height

                case 8:
                    // Color and downsampled pixel access
                    _ = decoder.getPixels24()
                    _ = decoder.getDownsampledPixels16(maxDimension: 150)
                    _ = decoder.isColorImage
                    _ = decoder.isGrayscale

                case 9:
                    // Mixed operations - validation, properties, and metadata
                    _ = decoder.getValidationStatus()
                    _ = decoder.imageDimensions
                    _ = decoder.windowSettings
                    _ = decoder.getPatientInfo()
                    for tag in commonTags.prefix(4) {
                        _ = decoder.info(for: tag)
                        _ = decoder.intValue(for: tag)
                        _ = decoder.doubleValue(for: tag)
                    }

                default:
                    break
                }

                // Increment completed count safely
                countLock.lock()
                completedCount += 1
                if completedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(completedCount, iterations, "All stress test operations should complete")

        // Verify decoder is still in consistent state after stress test
        XCTAssertFalse(decoder.isValid(), "Decoder should still be invalid after stress test")
        let finalStatus = decoder.getValidationStatus()
        XCTAssertFalse(finalStatus.isValid, "Validation status should be consistent")
    }

    // MARK: - Async API Tests

    @available(iOS 13.0, macOS 12.0, *)
    func testConcurrentAsyncPixelAccess() async {
        // Test that async pixel access is thread-safe
        let decoder = DCMDecoder()

        // Launch multiple async tasks
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let pixels16 = await decoder.getPixels16Async()
                    let pixels8 = await decoder.getPixels8Async()

                    // Should be nil since no file is loaded
                    return pixels16 == nil && pixels8 == nil
                }
            }

            // Verify all tasks completed successfully
            var successCount = 0
            for await result in group {
                if result {
                    successCount += 1
                }
            }

            XCTAssertEqual(successCount, 10, "All async pixel access tasks should succeed")
        }
    }

    // MARK: - Performance Tests

    func testConcurrencyPerformance() {
        // Measure performance of concurrent access
        let decoder = DCMDecoder()

        measure {
            let expectation = XCTestExpectation(description: "Performance test")
            let iterations = 100
            var completedCount = 0
            let queue = DispatchQueue.global(qos: .userInitiated)
            let countLock = NSLock()

            for _ in 0..<iterations {
                queue.async {
                    _ = decoder.isValid()
                    _ = decoder.width
                    _ = decoder.info(for: 0x00100010)

                    countLock.lock()
                    completedCount += 1
                    if completedCount == iterations {
                        expectation.fulfill()
                    }
                    countLock.unlock()
                }
            }

            self.wait(for: [expectation], timeout: 5.0)
        }
    }
}
