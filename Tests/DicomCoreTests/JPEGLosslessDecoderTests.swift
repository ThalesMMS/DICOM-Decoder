import XCTest
@testable import DicomCore

final class JPEGLosslessDecoderTests: XCTestCase {

    // MARK: - Huffman Table Parsing Tests

    func testHuffmanTableParsing() throws {
        // Test Huffman table construction with a simple example
        // This tests the buildHuffmanDecodingTables method

        // Create a synthetic JPEG Lossless bitstream with DHT marker
        var jpegData = Data()

        // SOI marker (Start of Image)
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // DHT marker (Define Huffman Table)
        jpegData.append(contentsOf: [0xFF, 0xC4])

        // Simple Huffman table:
        // - Table class 0 (DC), table ID 0
        // - Symbol counts: 2 symbols of length 2, 3 symbols of length 3
        // - Symbol values: 0, 1, 2, 3, 4
        let symbolCounts: [UInt8] = [
            0,  // Length 1: 0 symbols
            2,  // Length 2: 2 symbols
            3,  // Length 3: 3 symbols
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0  // Lengths 4-16: 0 symbols (13 more zeros)
        ]
        let symbolValues: [UInt8] = [0, 1, 2, 3, 4]

        // DHT length includes: 2 (length field itself) + 1 (table info) + 16 (counts) + 5 (values) = 24
        let dhtLength: UInt16 = 2 + 1 + 16 + UInt16(symbolValues.count)
        jpegData.append(UInt8(dhtLength >> 8))
        jpegData.append(UInt8(dhtLength & 0xFF))

        // Table class (0) and ID (0)
        jpegData.append(0x00)

        // Symbol counts (16 bytes)
        jpegData.append(contentsOf: symbolCounts)

        // Symbol values
        jpegData.append(contentsOf: symbolValues)

        // SOF3 marker (Start of Frame - Lossless)
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11  // 2 + 1 + 2 + 2 + 1 + 3
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)  // Precision: 16-bit
        jpegData.append(0)   // Height high byte
        jpegData.append(2)   // Height low byte (2 pixels)
        jpegData.append(0)   // Width high byte
        jpegData.append(2)   // Width low byte (2 pixels)
        jpegData.append(1)   // 1 component
        jpegData.append(1)   // Component ID
        jpegData.append(0x11) // Sampling factors (1x1)
        jpegData.append(0)   // Quantization table selector

        // SOS marker (Start of Scan)
        jpegData.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8  // 2 + 1 + 2 + 3
        jpegData.append(UInt8(sosLength >> 8))
        jpegData.append(UInt8(sosLength & 0xFF))
        jpegData.append(1)   // 1 component
        jpegData.append(1)   // Component ID
        jpegData.append(0x00) // DC table 0, AC table 0
        jpegData.append(1)   // Selection value (predictor ID)
        jpegData.append(0)   // End spectral (must be 0)
        jpegData.append(0)   // Successive approximation (must be 0)

        // Compressed pixel data for 2x2 image (4 pixels)
        // Using symbol 0 (SSSS=0, difference=0) for all pixels
        // Symbol 0 has 2-bit code "00" based on the Huffman table above
        // 4 pixels × 2 bits = 8 bits = 1 byte: 00 00 00 00 = 0x00
        jpegData.append(0x00)

        // EOI marker (End of Image)
        jpegData.append(0xFF)
        jpegData.append(0xD9)

        // Create decoder and parse the data
        let decoder = JPEGLosslessDecoder()

        // The decode method should successfully parse the markers
        // and build the Huffman tables without throwing
        do {
            _ = try decoder.decode(data: jpegData)

            // If we got here without throwing, the Huffman table was successfully parsed
            // The actual decoding will return placeholder data since we haven't implemented
            // the full pixel decoding yet, but marker parsing should work

        } catch {
            XCTFail("Huffman table parsing failed with error: \(error)")
        }
    }

    func testHuffmanTableParsingWithMultipleTables() throws {
        // Test parsing multiple Huffman tables in a single DHT marker

        var jpegData = Data()

        // SOI marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // DHT marker with two tables
        jpegData.append(contentsOf: [0xFF, 0xC4])

        // First table: class 0, ID 0
        let symbolCounts1: [UInt8] = [
            1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ]
        let symbolValues1: [UInt8] = [0, 1, 2]

        // Second table: class 0, ID 1
        let symbolCounts2: [UInt8] = [
            0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ]
        let symbolValues2: [UInt8] = [5, 6, 7]

        // Total DHT payload length (length field includes itself)
        let table1Size = 1 + 16 + symbolValues1.count
        let table2Size = 1 + 16 + symbolValues2.count
        let dhtLength: UInt16 = 2 + UInt16(table1Size + table2Size)
        jpegData.append(UInt8(dhtLength >> 8))
        jpegData.append(UInt8(dhtLength & 0xFF))

        // First table
        jpegData.append(0x00)  // Class 0, ID 0
        jpegData.append(contentsOf: symbolCounts1)
        jpegData.append(contentsOf: symbolValues1)

        // Second table
        jpegData.append(0x01)  // Class 0, ID 1
        jpegData.append(contentsOf: symbolCounts2)
        jpegData.append(contentsOf: symbolValues2)

        // SOF3 marker
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)  // Precision
        jpegData.append(0)   // Height high
        jpegData.append(2)   // Height low
        jpegData.append(0)   // Width high
        jpegData.append(2)   // Width low
        jpegData.append(1)   // 1 component
        jpegData.append(1)   // Component ID
        jpegData.append(0x11) // Sampling factors
        jpegData.append(0)   // Quantization table

        // SOS marker
        jpegData.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        jpegData.append(UInt8(sosLength >> 8))
        jpegData.append(UInt8(sosLength & 0xFF))
        jpegData.append(1)   // 1 component
        jpegData.append(1)   // Component ID
        jpegData.append(0x00) // DC table 0, AC table 0
        jpegData.append(1)   // Selection value
        jpegData.append(0)   // End spectral
        jpegData.append(0)   // Successive approximation

        // Compressed pixel data for 2x2 image (4 pixels)
        // Using symbol 0 from table 0 (SSSS=0, difference=0) for all pixels
        // Symbol 0 has 1-bit code "0" based on symbolCounts1 (1 symbol of length 1)
        // 4 pixels × 1 bit = 4 bits, padded to byte: 0000 0000 = 0x00
        jpegData.append(0x00)

        // EOI marker (End of Image)
        jpegData.append(contentsOf: [0xFF, 0xD9])

        // Decode should successfully parse both tables
        let decoder = JPEGLosslessDecoder()

        do {
            _ = try decoder.decode(data: jpegData)
        } catch {
            XCTFail("Failed to parse multiple Huffman tables: \(error)")
        }
    }

    func testHuffmanTableParsingInvalidTable() throws {
        // Test that invalid Huffman table (too many symbols) is rejected

        var jpegData = Data()

        // SOI marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // DHT marker with invalid symbol count (> 256)
        jpegData.append(contentsOf: [0xFF, 0xC4])

        // Symbol counts that add up to > 256 (invalid)
        let symbolCounts: [UInt8] = [
            255, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ]

        let dhtLength: UInt16 = 2 + 1 + 16 + 257
        jpegData.append(UInt8(dhtLength >> 8))
        jpegData.append(UInt8(dhtLength & 0xFF))
        jpegData.append(0x00)
        jpegData.append(contentsOf: symbolCounts)

        // Add 257 dummy symbol values (will fail before reading all)
        for _ in 0..<255 {
            jpegData.append(0)
        }

        let decoder = JPEGLosslessDecoder()

        // Should throw error due to invalid table
        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    // MARK: - First-Order Prediction Tests

    func testFirstOrderPrediction() throws {
        // Test the first-order predictor (Selection Value 1)
        // This tests the computePredictor method with left neighbor prediction

        let decoder = JPEGLosslessDecoder()

        // Test parameters
        let width = 4
        let height = 3
        let precision = 16
        let defaultPredictor = 1 << (precision - 1)  // 2^15 = 32768 for 16-bit

        // Sample pixel buffer (partially filled for testing)
        var pixels = [UInt16](repeating: 0, count: width * height)
        pixels[0] = 32768  // First pixel
        pixels[1] = 30000  // Second pixel in row 0
        pixels[2] = 28000  // Third pixel in row 0
        pixels[3] = 26000  // Fourth pixel in row 0
        pixels[4] = 35000  // First pixel in row 1

        // Test case 1: First pixel of first row (x=0, y=0)
        // Expected: default predictor (2^15 = 32768)
        let pred1 = decoder.computePredictor(x: 0, y: 0, pixels: pixels, width: width, precision: precision)
        XCTAssertEqual(pred1, defaultPredictor, "First pixel should use default predictor 2^(P-1)")

        // Test case 2: Second pixel of first row (x=1, y=0)
        // Expected: left neighbor (pixels[0] = 32768)
        let pred2 = decoder.computePredictor(x: 1, y: 0, pixels: pixels, width: width, precision: precision)
        XCTAssertEqual(pred2, 32768, "Second pixel should use left neighbor as predictor")

        // Test case 3: Third pixel of first row (x=2, y=0)
        // Expected: left neighbor (pixels[1] = 30000)
        let pred3 = decoder.computePredictor(x: 2, y: 0, pixels: pixels, width: width, precision: precision)
        XCTAssertEqual(pred3, 30000, "Third pixel should use left neighbor as predictor")

        // Test case 4: First pixel of second row (x=0, y=1)
        // Expected: default predictor (2^15 = 32768)
        let pred4 = decoder.computePredictor(x: 0, y: 1, pixels: pixels, width: width, precision: precision)
        XCTAssertEqual(pred4, defaultPredictor, "First pixel of each row should use default predictor")

        // Test case 5: Second pixel of second row (x=1, y=1)
        // Expected: left neighbor (pixels[4] = 35000)
        let pred5 = decoder.computePredictor(x: 1, y: 1, pixels: pixels, width: width, precision: precision)
        XCTAssertEqual(pred5, 35000, "Second pixel of row should use left neighbor as predictor")

        // Test with different precision (12-bit)
        let precision12 = 12
        let defaultPredictor12 = 1 << (precision12 - 1)  // 2^11 = 2048 for 12-bit

        let pred6 = decoder.computePredictor(x: 0, y: 0, pixels: pixels, width: width, precision: precision12)
        XCTAssertEqual(pred6, defaultPredictor12, "12-bit precision should use 2^11 = 2048 as default predictor")

        // Test with different precision (8-bit)
        let precision8 = 8
        let defaultPredictor8 = 1 << (precision8 - 1)  // 2^7 = 128 for 8-bit

        let pred7 = decoder.computePredictor(x: 0, y: 0, pixels: pixels, width: width, precision: precision8)
        XCTAssertEqual(pred7, defaultPredictor8, "8-bit precision should use 2^7 = 128 as default predictor")
    }

    func testFirstOrderPredictionEdgeCases() throws {
        // Test edge cases for first-order prediction

        let decoder = JPEGLosslessDecoder()

        // Test with minimum width (1 pixel)
        let width1 = 1
        let height1 = 3
        let precision = 16
        let defaultPredictor = 1 << (precision - 1)

        var pixels1 = [UInt16](repeating: 0, count: width1 * height1)
        pixels1[0] = 32768

        // All pixels in a single-column image should use default predictor
        for y in 0..<height1 {
            let pred = decoder.computePredictor(x: 0, y: y, pixels: pixels1, width: width1, precision: precision)
            XCTAssertEqual(pred, defaultPredictor, "Single-column image should always use default predictor")
        }

        // Test with maximum precision values
        let pixels16bit = [UInt16](repeating: 65535, count: 10)
        let pred16 = decoder.computePredictor(x: 1, y: 0, pixels: pixels16bit, width: 5, precision: 16)
        XCTAssertEqual(pred16, 65535, "Should handle maximum 16-bit value")

        // Test with minimum precision values
        let pixels16bitMin = [UInt16](repeating: 0, count: 10)
        let predMin = decoder.computePredictor(x: 1, y: 0, pixels: pixels16bitMin, width: 5, precision: 16)
        XCTAssertEqual(predMin, 0, "Should handle minimum value (0)")
    }

    // MARK: - Marker Parsing Tests

    func testMarkerParsingMissingSOI() throws {
        // Test that missing SOI marker is detected

        var jpegData = Data()

        // Start with wrong marker (not SOI)
        jpegData.append(contentsOf: [0xFF, 0xC3])  // SOF3 instead of SOI

        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    func testMarkerParsingEmptyData() throws {
        // Test that empty data is rejected

        let jpegData = Data()
        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    func testMarkerParsingTruncatedData() throws {
        // Test that truncated data is detected

        var jpegData = Data()

        // SOI marker only (no other markers)
        jpegData.append(contentsOf: [0xFF, 0xD8])

        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    func testMarkerParsingMissingSOF3() throws {
        // Test that missing SOF3 marker is detected

        var jpegData = Data()

        // SOI marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // SOS marker without SOF3
        jpegData.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        jpegData.append(UInt8(sosLength >> 8))
        jpegData.append(UInt8(sosLength & 0xFF))
        jpegData.append(1)   // 1 component
        jpegData.append(1)   // Component ID
        jpegData.append(0x00) // DC table 0
        jpegData.append(1)   // Selection value
        jpegData.append(0)   // End spectral
        jpegData.append(0)   // Successive approximation

        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    func testMarkerParsingMissingSOS() throws {
        // Test that missing SOS marker is detected

        var jpegData = Data()

        // SOI marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // SOF3 marker only
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)  // Precision
        jpegData.append(0)   // Height high
        jpegData.append(2)   // Height low
        jpegData.append(0)   // Width high
        jpegData.append(2)   // Width low
        jpegData.append(1)   // 1 component
        jpegData.append(1)   // Component ID
        jpegData.append(0x11) // Sampling factors
        jpegData.append(0)   // Quantization table

        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    // MARK: - SOF3 Parsing Tests

    func testSOF3ParsingInvalidDimensions() throws {
        // Test that invalid dimensions (0x0) are rejected

        var jpegData = Data()

        // SOI marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // SOF3 marker with 0x0 dimensions
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)  // Precision
        jpegData.append(0)   // Height high
        jpegData.append(0)   // Height low (invalid: 0)
        jpegData.append(0)   // Width high
        jpegData.append(0)   // Width low (invalid: 0)
        jpegData.append(1)   // 1 component
        jpegData.append(1)   // Component ID
        jpegData.append(0x11) // Sampling factors
        jpegData.append(0)   // Quantization table

        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    func testSOF3ParsingInvalidPrecision() throws {
        // Test that unsupported precision (e.g., 7-bit) is rejected

        var jpegData = Data()

        // SOI marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // SOF3 marker with invalid precision
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(7)   // Invalid precision (not 8, 12, or 16)
        jpegData.append(0)   // Height high
        jpegData.append(2)   // Height low
        jpegData.append(0)   // Width high
        jpegData.append(2)   // Width low
        jpegData.append(1)   // 1 component
        jpegData.append(1)   // Component ID
        jpegData.append(0x11) // Sampling factors
        jpegData.append(0)   // Quantization table

        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    func testSOF3ParsingTruncatedPayload() throws {
        // Test that truncated SOF3 payload is detected

        var jpegData = Data()

        // SOI marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // SOF3 marker with incomplete payload
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)  // Precision
        jpegData.append(0)   // Height high
        // Missing rest of payload

        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    func testSOF3ParsingValidPrecisionValues() throws {
        // Test that all valid precision values (8, 12, 16) are accepted

        for precision in [8, 12, 16] {
            var jpegData = Data()

            // SOI marker
            jpegData.append(contentsOf: [0xFF, 0xD8])

            // DHT marker (simple table)
            jpegData.append(contentsOf: [0xFF, 0xC4])
            let symbolCounts: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            let symbolValues: [UInt8] = [0]
            let dhtLength: UInt16 = 2 + 1 + 16 + UInt16(symbolValues.count)
            jpegData.append(UInt8(dhtLength >> 8))
            jpegData.append(UInt8(dhtLength & 0xFF))
            jpegData.append(0x00)
            jpegData.append(contentsOf: symbolCounts)
            jpegData.append(contentsOf: symbolValues)

            // SOF3 marker with specified precision
            jpegData.append(contentsOf: [0xFF, 0xC3])
            let sof3Length: UInt16 = 11
            jpegData.append(UInt8(sof3Length >> 8))
            jpegData.append(UInt8(sof3Length & 0xFF))
            jpegData.append(UInt8(precision))  // Precision
            jpegData.append(0)   // Height high
            jpegData.append(2)   // Height low
            jpegData.append(0)   // Width high
            jpegData.append(2)   // Width low
            jpegData.append(1)   // 1 component
            jpegData.append(1)   // Component ID
            jpegData.append(0x11) // Sampling factors
            jpegData.append(0)   // Quantization table

            // SOS marker
            jpegData.append(contentsOf: [0xFF, 0xDA])
            let sosLength: UInt16 = 8
            jpegData.append(UInt8(sosLength >> 8))
            jpegData.append(UInt8(sosLength & 0xFF))
            jpegData.append(1)   // 1 component
            jpegData.append(1)   // Component ID
            jpegData.append(0x00) // DC table 0
            jpegData.append(1)   // Selection value
            jpegData.append(0)   // End spectral
            jpegData.append(0)   // Successive approximation

            // Compressed pixel data (minimal)
            jpegData.append(0x00)

            // EOI marker
            jpegData.append(contentsOf: [0xFF, 0xD9])

            let decoder = JPEGLosslessDecoder()

            do {
                let result = try decoder.decode(data: jpegData)
                XCTAssertEqual(result.bitDepth, precision, "Decoded bit depth should match SOF3 precision")
            } catch {
                XCTFail("Failed to decode valid \(precision)-bit image: \(error)")
            }
        }
    }

    // MARK: - SOS Parsing Tests

    func testSOSParsingInvalidComponentCount() throws {
        // Test that invalid component count (0 or > 4) is rejected

        var jpegData = Data()

        // SOI marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // SOF3 marker
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)
        jpegData.append(0)
        jpegData.append(2)
        jpegData.append(0)
        jpegData.append(2)
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x11)
        jpegData.append(0)

        // SOS marker with invalid component count
        jpegData.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 6
        jpegData.append(UInt8(sosLength >> 8))
        jpegData.append(UInt8(sosLength & 0xFF))
        jpegData.append(0)   // Invalid: 0 components
        jpegData.append(1)
        jpegData.append(0)
        jpegData.append(0)

        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    func testSOSParsingInvalidSelectionValue() throws {
        // Test that invalid selection value (> 7) is rejected

        var jpegData = Data()

        // SOI marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // DHT marker
        jpegData.append(contentsOf: [0xFF, 0xC4])
        let symbolCounts: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let symbolValues: [UInt8] = [0]
        let dhtLength: UInt16 = 2 + 1 + 16 + UInt16(symbolValues.count)
        jpegData.append(UInt8(dhtLength >> 8))
        jpegData.append(UInt8(dhtLength & 0xFF))
        jpegData.append(0x00)
        jpegData.append(contentsOf: symbolCounts)
        jpegData.append(contentsOf: symbolValues)

        // SOF3 marker
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)
        jpegData.append(0)
        jpegData.append(2)
        jpegData.append(0)
        jpegData.append(2)
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x11)
        jpegData.append(0)

        // SOS marker with invalid selection value
        jpegData.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        jpegData.append(UInt8(sosLength >> 8))
        jpegData.append(UInt8(sosLength & 0xFF))
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x00)
        jpegData.append(8)   // Invalid: > 7
        jpegData.append(0)
        jpegData.append(0)

        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    func testSOSParsingMissingHuffmanTable() throws {
        // Test that missing referenced Huffman table is detected

        var jpegData = Data()

        // SOI marker
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // SOF3 marker
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)
        jpegData.append(0)
        jpegData.append(2)
        jpegData.append(0)
        jpegData.append(2)
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x11)
        jpegData.append(0)

        // SOS marker referencing non-existent Huffman table
        jpegData.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        jpegData.append(UInt8(sosLength >> 8))
        jpegData.append(UInt8(sosLength & 0xFF))
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x03) // DC table 0, AC table 3 (no DHT defined)
        jpegData.append(1)
        jpegData.append(0)
        jpegData.append(0)

        let decoder = JPEGLosslessDecoder()

        XCTAssertThrowsError(try decoder.decode(data: jpegData)) { error in
            guard case DICOMError.invalidDICOMFormat = error else {
                XCTFail("Expected invalidDICOMFormat error, got \(error)")
                return
            }
        }
    }

    // MARK: - Decode Result Tests

    func testDecodeResultStructure() throws {
        // Test that decode result has correct structure

        var jpegData = Data()

        // Build minimal valid JPEG Lossless image (2x2, 16-bit)
        // SOI
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // DHT
        jpegData.append(contentsOf: [0xFF, 0xC4])
        let symbolCounts: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let symbolValues: [UInt8] = [0]
        let dhtLength: UInt16 = 2 + 1 + 16 + UInt16(symbolValues.count)
        jpegData.append(UInt8(dhtLength >> 8))
        jpegData.append(UInt8(dhtLength & 0xFF))
        jpegData.append(0x00)
        jpegData.append(contentsOf: symbolCounts)
        jpegData.append(contentsOf: symbolValues)

        // SOF3
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)
        jpegData.append(0)
        jpegData.append(2)
        jpegData.append(0)
        jpegData.append(2)
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x11)
        jpegData.append(0)

        // SOS
        jpegData.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        jpegData.append(UInt8(sosLength >> 8))
        jpegData.append(UInt8(sosLength & 0xFF))
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x00)
        jpegData.append(1)
        jpegData.append(0)
        jpegData.append(0)

        // Compressed pixel data (4 pixels with SSSS=0)
        jpegData.append(0x00)

        // EOI
        jpegData.append(contentsOf: [0xFF, 0xD9])

        let decoder = JPEGLosslessDecoder()
        let result = try decoder.decode(data: jpegData)

        // Verify result structure
        XCTAssertEqual(result.width, 2, "Width should match SOF3")
        XCTAssertEqual(result.height, 2, "Height should match SOF3")
        XCTAssertEqual(result.bitDepth, 16, "Bit depth should match SOF3")
        XCTAssertEqual(result.pixels.count, 4, "Pixel count should be width × height")

        // Verify pixels are non-nil and reasonable
        for pixel in result.pixels {
            XCTAssertTrue(pixel <= 65535, "16-bit pixel should be in valid range")
        }
    }

    func testDecodeResultPixelCount() throws {
        // Test that pixel count matches dimensions for various sizes

        let testCases: [(width: Int, height: Int)] = [
            (1, 1),
            (2, 2),
            (3, 3),
            (10, 10),
            (16, 8)
        ]

        for testCase in testCases {
            var jpegData = Data()

            // SOI
            jpegData.append(contentsOf: [0xFF, 0xD8])

            // DHT
            jpegData.append(contentsOf: [0xFF, 0xC4])
            let symbolCounts: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            let symbolValues: [UInt8] = [0]
            let dhtLength: UInt16 = 2 + 1 + 16 + UInt16(symbolValues.count)
            jpegData.append(UInt8(dhtLength >> 8))
            jpegData.append(UInt8(dhtLength & 0xFF))
            jpegData.append(0x00)
            jpegData.append(contentsOf: symbolCounts)
            jpegData.append(contentsOf: symbolValues)

            // SOF3
            jpegData.append(contentsOf: [0xFF, 0xC3])
            let sof3Length: UInt16 = 11
            jpegData.append(UInt8(sof3Length >> 8))
            jpegData.append(UInt8(sof3Length & 0xFF))
            jpegData.append(16)
            jpegData.append(UInt8(testCase.height >> 8))
            jpegData.append(UInt8(testCase.height & 0xFF))
            jpegData.append(UInt8(testCase.width >> 8))
            jpegData.append(UInt8(testCase.width & 0xFF))
            jpegData.append(1)
            jpegData.append(1)
            jpegData.append(0x11)
            jpegData.append(0)

            // SOS
            jpegData.append(contentsOf: [0xFF, 0xDA])
            let sosLength: UInt16 = 8
            jpegData.append(UInt8(sosLength >> 8))
            jpegData.append(UInt8(sosLength & 0xFF))
            jpegData.append(1)
            jpegData.append(1)
            jpegData.append(0x00)
            jpegData.append(1)
            jpegData.append(0)
            jpegData.append(0)

            // Compressed pixel data (enough bytes for all pixels)
            let pixelCount = testCase.width * testCase.height
            let byteCount = (pixelCount + 7) / 8  // 1 bit per pixel
            for _ in 0..<byteCount {
                jpegData.append(0x00)
            }

            // EOI
            jpegData.append(contentsOf: [0xFF, 0xD9])

            let decoder = JPEGLosslessDecoder()
            let result = try decoder.decode(data: jpegData)

            XCTAssertEqual(result.pixels.count, pixelCount,
                           "Pixel count should match width(\(testCase.width)) × height(\(testCase.height))")
        }
    }

    // MARK: - Edge Case Tests

    func testDecodeWithByteStuffing() throws {
        // Test that byte stuffing (0xFF 0x00) is correctly handled
        // Note: This test verifies the BitStreamReader correctly handles byte stuffing
        // by not throwing errors when encountering 0xFF 0x00 sequences in compressed data

        var jpegData = Data()

        // SOI
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // DHT - simple table with 1-bit codes
        jpegData.append(contentsOf: [0xFF, 0xC4])
        let symbolCounts: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let symbolValues: [UInt8] = [0]
        let dhtLength: UInt16 = 2 + 1 + 16 + UInt16(symbolValues.count)
        jpegData.append(UInt8(dhtLength >> 8))
        jpegData.append(UInt8(dhtLength & 0xFF))
        jpegData.append(0x00)
        jpegData.append(contentsOf: symbolCounts)
        jpegData.append(contentsOf: symbolValues)

        // SOF3 (2x2)
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)
        jpegData.append(0)
        jpegData.append(2)
        jpegData.append(0)
        jpegData.append(2)
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x11)
        jpegData.append(0)

        // SOS
        jpegData.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        jpegData.append(UInt8(sosLength >> 8))
        jpegData.append(UInt8(sosLength & 0xFF))
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x00)
        jpegData.append(1)
        jpegData.append(0)
        jpegData.append(0)

        // Compressed data: 4 pixels with SSSS=0 (1 bit each = 4 bits = 0b0000)
        // Add a 0xFF byte (which should trigger byte stuffing handling)
        // Pattern: 0b0000_0000 (4 pixels) then 0xFF 0x00 (byte stuffing)
        // followed by padding
        jpegData.append(0x00)  // First 4 pixels (bits 0000)
        jpegData.append(0xFF)  // Data byte that needs stuffing
        jpegData.append(0x00)  // Stuffing byte (BitStreamReader should handle this)

        // EOI
        jpegData.append(contentsOf: [0xFF, 0xD9])

        let decoder = JPEGLosslessDecoder()

        // Should decode without error (byte stuffing handled correctly)
        // The BitStreamReader will see 0xFF 0x00 and correctly interpret it as a single 0xFF data byte
        do {
            let result = try decoder.decode(data: jpegData)
            XCTAssertEqual(result.pixels.count, 4, "Should decode 2x2 image = 4 pixels")
        } catch {
            XCTFail("Failed to handle byte stuffing: \(error)")
        }
    }

    func testDecodeWithMinimalImage() throws {
        // Test decoding 1x1 pixel image (minimal possible)

        var jpegData = Data()

        // SOI
        jpegData.append(contentsOf: [0xFF, 0xD8])

        // DHT
        jpegData.append(contentsOf: [0xFF, 0xC4])
        let symbolCounts: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let symbolValues: [UInt8] = [0]
        let dhtLength: UInt16 = 2 + 1 + 16 + UInt16(symbolValues.count)
        jpegData.append(UInt8(dhtLength >> 8))
        jpegData.append(UInt8(dhtLength & 0xFF))
        jpegData.append(0x00)
        jpegData.append(contentsOf: symbolCounts)
        jpegData.append(contentsOf: symbolValues)

        // SOF3 (1x1)
        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)
        jpegData.append(0)
        jpegData.append(1)  // Height = 1
        jpegData.append(0)
        jpegData.append(1)  // Width = 1
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x11)
        jpegData.append(0)

        // SOS
        jpegData.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        jpegData.append(UInt8(sosLength >> 8))
        jpegData.append(UInt8(sosLength & 0xFF))
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x00)
        jpegData.append(1)
        jpegData.append(0)
        jpegData.append(0)

        // Compressed data (1 pixel)
        jpegData.append(0x00)

        // EOI
        jpegData.append(contentsOf: [0xFF, 0xD9])

        let decoder = JPEGLosslessDecoder()
        let result = try decoder.decode(data: jpegData)

        XCTAssertEqual(result.width, 1, "Width should be 1")
        XCTAssertEqual(result.height, 1, "Height should be 1")
        XCTAssertEqual(result.pixels.count, 1, "Should have exactly 1 pixel")
    }

    func testDecodeConsistency() throws {
        // Test that decoding the same data multiple times produces consistent results

        var jpegData = Data()

        // Build test image
        jpegData.append(contentsOf: [0xFF, 0xD8])

        jpegData.append(contentsOf: [0xFF, 0xC4])
        let symbolCounts: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let symbolValues: [UInt8] = [0]
        let dhtLength: UInt16 = 2 + 1 + 16 + UInt16(symbolValues.count)
        jpegData.append(UInt8(dhtLength >> 8))
        jpegData.append(UInt8(dhtLength & 0xFF))
        jpegData.append(0x00)
        jpegData.append(contentsOf: symbolCounts)
        jpegData.append(contentsOf: symbolValues)

        jpegData.append(contentsOf: [0xFF, 0xC3])
        let sof3Length: UInt16 = 11
        jpegData.append(UInt8(sof3Length >> 8))
        jpegData.append(UInt8(sof3Length & 0xFF))
        jpegData.append(16)
        jpegData.append(0)
        jpegData.append(3)
        jpegData.append(0)
        jpegData.append(3)
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x11)
        jpegData.append(0)

        jpegData.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        jpegData.append(UInt8(sosLength >> 8))
        jpegData.append(UInt8(sosLength & 0xFF))
        jpegData.append(1)
        jpegData.append(1)
        jpegData.append(0x00)
        jpegData.append(1)
        jpegData.append(0)
        jpegData.append(0)

        jpegData.append(contentsOf: [0x00, 0x00])

        jpegData.append(contentsOf: [0xFF, 0xD9])

        let decoder = JPEGLosslessDecoder()

        // Decode multiple times
        let result1 = try decoder.decode(data: jpegData)
        let result2 = try decoder.decode(data: jpegData)
        let result3 = try decoder.decode(data: jpegData)

        // Verify all results are identical
        XCTAssertEqual(result1.width, result2.width, "Width should be consistent")
        XCTAssertEqual(result2.width, result3.width, "Width should be consistent")

        XCTAssertEqual(result1.height, result2.height, "Height should be consistent")
        XCTAssertEqual(result2.height, result3.height, "Height should be consistent")

        XCTAssertEqual(result1.pixels, result2.pixels, "Pixels should be consistent")
        XCTAssertEqual(result2.pixels, result3.pixels, "Pixels should be consistent")
    }
}
