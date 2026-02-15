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
                _ = decoder.width
                _ = decoder.height
                _ = decoder.imageDimensions
                _ = decoder.pixelSpacingV2
                _ = decoder.windowSettingsV2
                _ = decoder.rescaleParametersV2
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
                    _ = decoder.pixelSpacingV2
                    _ = decoder.imageDimensions

                case 4:
                    // Multiple pixel format checks
                    _ = decoder.getPixels8()
                    _ = decoder.getPixels16()
                    _ = decoder.windowSettingsV2
                    _ = decoder.rescaleParametersV2

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
                    _ = decoder.windowSettingsV2
                    _ = decoder.rescaleParametersV2
                    _ = decoder.pixelSpacingV2
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

                case 1:
                    // Dimension and geometry properties
                    _ = decoder.width
                    _ = decoder.height
                    _ = decoder.imageDimensions
                    _ = decoder.pixelSpacingV2
                    _ = decoder.isMultiFrame

                case 2:
                    // Window and rescale parameters
                    _ = decoder.windowSettingsV2
                    _ = decoder.rescaleParametersV2
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
                    _ = decoder.windowSettingsV2
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

    func testThreadSanitizerStressTest() {
        // ThreadSanitizer stress test with 50+ concurrent file loads
        // This test is specifically designed to detect data races and thread safety issues
        // when multiple threads simultaneously create decoder instances and load files
        let expectation = XCTestExpectation(description: "ThreadSanitizer stress test with concurrent file loads")
        let iterations = 55 // 50+ as required
        var completedCount = 0
        let countLock = NSLock()

        // Construct paths to test DICOM files using #file
        let fixturesPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")

        let testFiles = [
            fixturesPath.appendingPathComponent("CT/ct_synthetic.dcm").path,
            fixturesPath.appendingPathComponent("MR/mr_synthetic.dcm").path,
            fixturesPath.appendingPathComponent("US/us_synthetic.dcm").path,
            fixturesPath.appendingPathComponent("XR/xr_synthetic.dcm").path,
        ]

        // Use multiple queues with different priorities to maximize contention
        let queues = [
            DispatchQueue.global(qos: .userInteractive),
            DispatchQueue.global(qos: .userInitiated),
            DispatchQueue.global(qos: .default),
            DispatchQueue.global(qos: .utility),
        ]

        for i in 0..<iterations {
            let queue = queues[i % queues.count]
            let testFile = testFiles[i % testFiles.count]

            queue.async {
                // Create decoder and load file using throwing initializer (recommended pattern)
                do {
                    let decoder = try DCMDecoder(contentsOfFile: testFile)

                    // Perform comprehensive operations to stress test all code paths
                    XCTAssertTrue(decoder.isValid(), "Thread \(i): Decoder should be valid after loading")
                    XCTAssertTrue(decoder.dicomFileReadSuccess, "Thread \(i): File read should succeed")

                    // Access validation status
                    let status = decoder.getValidationStatus()
                    XCTAssertTrue(status.isValid, "Thread \(i): Validation status should be valid")
                    XCTAssertGreaterThan(status.width, 0, "Thread \(i): Width should be positive")
                    XCTAssertGreaterThan(status.height, 0, "Thread \(i): Height should be positive")

                    // Access dimension properties
                    XCTAssertGreaterThan(decoder.width, 0, "Thread \(i): Width should be positive")
                    XCTAssertGreaterThan(decoder.height, 0, "Thread \(i): Height should be positive")
                    _ = decoder.imageDimensions
                    _ = decoder.pixelSpacing

                    // Access metadata from multiple tag groups
                    _ = decoder.getPatientInfo()
                    _ = decoder.getStudyInfo()
                    _ = decoder.getSeriesInfo()
                    _ = decoder.info(for: 0x00080060) // Modality
                    _ = decoder.info(for: 0x00280010) // Rows
                    _ = decoder.info(for: 0x00280011) // Columns

                    // Access window and rescale parameters
                    _ = decoder.windowSettings
                    _ = decoder.windowSettingsV2
                    _ = decoder.rescaleParameters
                    _ = decoder.rescaleParametersV2

                    // Access pixel data (stress test the lazy loading mechanism)
                    // Note: Under high concurrency, pixel data may not always be immediately available
                    // The goal is to stress test for data races, not to strictly validate pixel data
                    if decoder.isGrayscale {
                        _ = decoder.getPixels16()
                        _ = decoder.getPixels8()
                    } else if decoder.isColorImage {
                        _ = decoder.getPixels24()
                    }

                    // Test downsampled pixel access (may return empty array if pixels not loaded)
                    _ = decoder.getDownsampledPixels16(maxDimension: 128)

                } catch {
                    XCTFail("Thread \(i): Failed to load file \(testFile): \(error)")
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

        // Allow enough time for all operations to complete
        wait(for: [expectation], timeout: 30.0)
        XCTAssertEqual(completedCount, iterations, "All \(iterations) concurrent file load operations should complete")
    }

    // MARK: - Async API Tests

    func testConcurrentAsyncPixelAccess() {
        // Test that pixel access is thread-safe from multiple concurrent tasks
        let decoder = DCMDecoder()
        let expectation = XCTestExpectation(description: "Concurrent pixel access")
        let iterations = 10
        var completedCount = 0
        var attemptedCount = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let countLock = NSLock()

        for _ in 0..<iterations {
            queue.async {
                // Use synchronous pixel methods (they are thread-safe)
                let pixels16 = decoder.getPixels16()
                let pixels8 = decoder.getPixels8()

                // Should be nil since no file is loaded
                let success = pixels16 == nil && pixels8 == nil

                countLock.lock()
                if success {
                    completedCount += 1
                }
                attemptedCount += 1
                if attemptedCount == iterations {
                    expectation.fulfill()
                }
                countLock.unlock()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(completedCount, iterations, "All concurrent pixel access tasks should succeed")
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

    // MARK: - Actor Isolation Tests

    @available(iOS 13.0, macOS 12.0, *)
    func testActorIsolation() async {
        // Test that decoder can be used inside an actor without warnings
        actor DecoderActor {
            private let decoder: DCMDecoder

            init() {
                self.decoder = DCMDecoder()
            }

            func validateDecoder() -> Bool {
                return decoder.isValid()
            }

            func getValidationStatus() -> (isValid: Bool, hasPixels: Bool) {
                let status = decoder.getValidationStatus()
                return (status.isValid, status.hasPixels)
            }

            func getDimensions() -> (width: Int, height: Int) {
                return (decoder.width, decoder.height)
            }

            func getPatientName() -> String {
                return decoder.info(for: 0x00100010)
            }

            func getPixelData() -> ([UInt16]?, [UInt8]?) {
                return (decoder.getPixels16(), decoder.getPixels8())
            }
        }

        // Create actor with decoder
        let decoderActor = DecoderActor()

        // Verify operations work through actor isolation
        let isValid = await decoderActor.validateDecoder()
        XCTAssertFalse(isValid, "Decoder should not be valid initially")

        let status = await decoderActor.getValidationStatus()
        XCTAssertFalse(status.isValid, "Validation status should be invalid")
        XCTAssertFalse(status.hasPixels, "Should have no pixels")

        let dimensions = await decoderActor.getDimensions()
        XCTAssertEqual(dimensions.width, 1, "Width should be 1 (default)")
        XCTAssertEqual(dimensions.height, 1, "Height should be 1 (default)")

        let patientName = await decoderActor.getPatientName()
        XCTAssertEqual(patientName, "", "Patient name should be empty")

        let pixels = await decoderActor.getPixelData()
        XCTAssertNil(pixels.0, "16-bit pixels should be nil")
        XCTAssertNil(pixels.1, "8-bit pixels should be nil")
    }

    @available(iOS 13.0, macOS 12.0, *)
    func testActorIsolationWithFileLoading() async {
        // Test that decoder can be loaded and used inside an actor
        actor DicomLoaderActor {
            private var decoder: DCMDecoder?

            func loadFile(_ path: String) throws {
                self.decoder = try DCMDecoder(contentsOfFile: path)
            }

            func getDecoderInfo() -> (isValid: Bool, width: Int, height: Int) {
                guard let decoder = decoder else {
                    return (false, 0, 0)
                }
                return (decoder.isValid(), decoder.width, decoder.height)
            }

            func getMetadata() -> (patientInfo: [String: String], modality: String) {
                guard let decoder = decoder else {
                    return ([:], "")
                }
                return (decoder.getPatientInfo(), decoder.info(for: 0x00080060))
            }
        }

        // Get test file path
        let fixturesPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let testFile = fixturesPath.appendingPathComponent("CT/ct_synthetic.dcm").path

        // Create actor and load file
        let loaderActor = DicomLoaderActor()

        do {
            try await loaderActor.loadFile(testFile)

            // Verify decoder loaded successfully
            let info = await loaderActor.getDecoderInfo()
            XCTAssertTrue(info.isValid, "Decoder should be valid after loading")
            XCTAssertGreaterThan(info.width, 0, "Width should be positive")
            XCTAssertGreaterThan(info.height, 0, "Height should be positive")

            // Verify metadata access through actor
            let metadata = await loaderActor.getMetadata()
            XCTAssertFalse(metadata.patientInfo.isEmpty, "Patient info should not be empty")
            XCTAssertFalse(metadata.modality.isEmpty, "Modality should not be empty")
        } catch {
            XCTFail("Failed to load file in actor: \(error)")
        }
    }

    @available(iOS 13.0, macOS 12.0, *)
    func testMultipleActorsWithDecoders() async {
        // Test that multiple actors can each have their own decoder instances
        actor DecoderActor {
            let id: Int
            private let decoder: DCMDecoder

            init(id: Int) {
                self.id = id
                self.decoder = DCMDecoder()
            }

            func performOperations() -> (id: Int, isValid: Bool, width: Int) {
                return (id, decoder.isValid(), decoder.width)
            }
        }

        // Create multiple actors
        let actorCount = 10
        let actors = (0..<actorCount).map { DecoderActor(id: $0) }

        // Execute operations on all actors concurrently
        await withTaskGroup(of: (Int, Bool, Int).self) { group in
            for actor in actors {
                group.addTask {
                    await actor.performOperations()
                }
            }

            var results: [(Int, Bool, Int)] = []
            for await result in group {
                results.append(result)
            }

            // Verify all actors completed successfully
            XCTAssertEqual(results.count, actorCount, "All actors should complete")
            for result in results {
                XCTAssertFalse(result.1, "Decoder in actor \(result.0) should not be valid")
                XCTAssertEqual(result.2, 1, "Width in actor \(result.0) should be 1 (default)")
            }
        }
    }

    @available(iOS 13.0, macOS 12.0, *)
    func testActorIsolationWithConcurrentAccess() async {
        // Test that an actor with a decoder can handle concurrent access from multiple tasks
        actor SharedDecoderActor {
            private let decoder: DCMDecoder
            private var accessCount = 0

            init() {
                self.decoder = DCMDecoder()
            }

            func checkValidation() -> (count: Int, isValid: Bool) {
                accessCount += 1
                return (accessCount, decoder.isValid())
            }

            func getDimensions() -> (count: Int, width: Int, height: Int) {
                accessCount += 1
                return (accessCount, decoder.width, decoder.height)
            }

            func getMetadata() -> (count: Int, patientName: String) {
                accessCount += 1
                return (accessCount, decoder.info(for: 0x00100010))
            }

            func getPixels() -> (count: Int, hasPixels: Bool) {
                accessCount += 1
                let pixels = decoder.getPixels16()
                return (accessCount, pixels != nil)
            }

            func getTotalAccessCount() -> Int {
                return accessCount
            }
        }

        // Create shared actor
        let sharedActor = SharedDecoderActor()

        // Launch multiple concurrent tasks accessing the actor
        await withTaskGroup(of: Void.self) { group in
            // Launch 20 tasks performing different operations
            for i in 0..<20 {
                group.addTask {
                    switch i % 4 {
                    case 0:
                        let result = await sharedActor.checkValidation()
                        XCTAssertGreaterThan(result.count, 0, "Access count should increase")
                        XCTAssertFalse(result.isValid, "Decoder should not be valid")
                    case 1:
                        let result = await sharedActor.getDimensions()
                        XCTAssertGreaterThan(result.count, 0, "Access count should increase")
                        XCTAssertEqual(result.width, 1, "Width should be 1 (default)")
                        XCTAssertEqual(result.height, 1, "Height should be 1 (default)")
                    case 2:
                        let result = await sharedActor.getMetadata()
                        XCTAssertGreaterThan(result.count, 0, "Access count should increase")
                        XCTAssertEqual(result.patientName, "", "Patient name should be empty")
                    case 3:
                        let result = await sharedActor.getPixels()
                        XCTAssertGreaterThan(result.count, 0, "Access count should increase")
                        XCTAssertFalse(result.hasPixels, "Should not have pixels")
                    default:
                        break
                    }
                }
            }

            // Wait for all tasks to complete
            await group.waitForAll()
        }

        // Verify total access count
        let totalCount = await sharedActor.getTotalAccessCount()
        XCTAssertEqual(totalCount, 20, "All 20 operations should complete")
    }

    @available(iOS 13.0, macOS 12.0, *)
    func testActorIsolationWithFileLoadingConcurrent() async {
        // Test multiple actors loading different files concurrently
        actor FileLoaderActor {
            let filePath: String
            private var decoder: DCMDecoder?

            init(filePath: String) {
                self.filePath = filePath
            }

            func loadAndValidate() async throws -> (path: String, isValid: Bool, width: Int, height: Int) {
                self.decoder = try await DCMDecoder(contentsOfFile: filePath)
                guard let decoder = decoder else {
                    throw DICOMError.fileNotFound(path: filePath)
                }
                return (filePath, decoder.isValid(), decoder.width, decoder.height)
            }
        }

        // Get test file paths
        let fixturesPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")

        let testFiles = [
            fixturesPath.appendingPathComponent("CT/ct_synthetic.dcm").path,
            fixturesPath.appendingPathComponent("MR/mr_synthetic.dcm").path,
            fixturesPath.appendingPathComponent("US/us_synthetic.dcm").path,
            fixturesPath.appendingPathComponent("XR/xr_synthetic.dcm").path,
        ]

        // Create actors for each file
        let actors = testFiles.map { FileLoaderActor(filePath: $0) }

        // Load files concurrently using actors
        await withTaskGroup(of: Result<(String, Bool, Int, Int), Error>.self) { group in
            for actor in actors {
                group.addTask {
                    do {
                        let result = try await actor.loadAndValidate()
                        return .success(result)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var successCount = 0
            for await result in group {
                switch result {
                case .success(let data):
                    XCTAssertTrue(data.1, "File should load successfully: \(data.0)")
                    XCTAssertGreaterThan(data.2, 0, "Width should be positive for \(data.0)")
                    XCTAssertGreaterThan(data.3, 0, "Height should be positive for \(data.0)")
                    successCount += 1
                case .failure(let error):
                    XCTFail("Failed to load file in actor: \(error)")
                }
            }

            XCTAssertEqual(successCount, testFiles.count, "All files should load successfully")
        }
    }
}
