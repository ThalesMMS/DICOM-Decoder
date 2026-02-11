//
//  JPEGLosslessDecoder.swift
//
//  JPEG Lossless decompression for DICOM images.
//  This module implements decoding for JPEG Lossless transfer syntaxes
//  (1.2.840.10008.1.2.4.57 and 1.2.840.10008.1.2.4.70) using predictive
//  coding with Huffman entropy coding. Supports Process 14 with Selection
//  Value 1 (first-order prediction).
//
//  The decoder parses JPEG markers (SOI, SOF3, DHT, SOS, EOI), constructs
//  Huffman decoding tables, and reconstructs pixels using spatial prediction.
//
//  Usage:
//
//    let decoder = JPEGLosslessDecoder()
//    let result = try decoder.decode(data: jpegData)
//    // result.pixels contains reconstructed 16-bit pixel buffer
//

import Foundation

// MARK: - JPEG Marker Constants

/// JPEG marker codes used in JPEG Lossless bitstreams
private enum JPEGMarker: UInt8 {
    case soi = 0xD8   // Start of Image
    case eoi = 0xD9   // End of Image
    case sos = 0xDA   // Start of Scan
    case dht = 0xC4   // Define Huffman Table
    case sof3 = 0xC3  // Start of Frame - Lossless (Process 14)

    /// Marker prefix byte (all JPEG markers start with 0xFF)
    static let prefix: UInt8 = 0xFF

    /// Byte stuffing padding (0xFF 0x00 in compressed data represents single 0xFF)
    static let stuffingByte: UInt8 = 0x00
}

// MARK: - Data Structures

/// Start of Frame (SOF3) marker data for lossless JPEG
internal struct SOF3Info {
    /// Image width in pixels
    let width: Int
    /// Image height in pixels
    let height: Int
    /// Sample precision in bits (typically 8, 12, or 16)
    let precision: Int
    /// Number of image components (1 for grayscale, 3 for RGB)
    let numberOfComponents: Int
    /// Component specifications (ID, sampling factors, quantization table)
    let components: [ComponentSpec]
}

/// Image component specification from SOF3 marker
internal struct ComponentSpec {
    /// Component identifier (1 = Y/grayscale, 2 = Cb, 3 = Cr)
    let id: UInt8
    /// Horizontal sampling factor
    let horizontalSamplingFactor: UInt8
    /// Vertical sampling factor
    let verticalSamplingFactor: UInt8
    /// Quantization table selector (unused in lossless mode)
    let quantizationTableSelector: UInt8
}

/// Start of Scan (SOS) marker data
internal struct SOSInfo {
    /// Number of components in this scan
    let numberOfComponents: Int
    /// Component selectors with entropy table assignments
    let components: [ScanComponentSelector]
    /// Selection value (predictor ID): 0-7
    /// For Transfer Syntax 1.2.840.10008.1.2.4.70, this must be 1
    let selectionValue: Int
    /// Start of spectral selection (must be 0 for lossless)
    let startSpectral: Int
    /// End of spectral selection (must be 0 for lossless)
    let endSpectral: Int
    /// Successive approximation bit position high (must be 0)
    let successiveApproximationHigh: UInt8
    /// Successive approximation bit position low (must be 0)
    let successiveApproximationLow: UInt8
}

/// Component selector for scan with entropy coding table assignments
internal struct ScanComponentSelector {
    /// Component identifier
    let componentId: UInt8
    /// DC entropy coding table selector (0-3)
    let dcTableSelector: UInt8
    /// AC entropy coding table selector (0-3, unused in lossless)
    let acTableSelector: UInt8
}

/// Huffman table for entropy decoding
internal struct HuffmanTable {
    /// Table class: 0 = DC, 1 = AC (lossless uses DC tables)
    let tableClass: UInt8
    /// Table destination identifier (0-3)
    let tableId: UInt8
    /// Number of codes of length 1-16 bits (16 entries)
    let symbolCounts: [UInt8]
    /// Huffman symbol values ordered by code length
    let symbolValues: [UInt8]

    // Decoding tables (populated by buildDecodingTables)
    /// Minimum code value for each bit length [1...16]
    var minCode: [Int] = []
    /// Maximum code value for each bit length [1...16]
    var maxCode: [Int] = []
    /// Index into symbolValues for each bit length [1...16]
    var valPtr: [Int] = []
}

/// Result of JPEG Lossless decoding operation
internal struct JPEGLosslessDecodeResult {
    /// Decoded pixel buffer (16-bit grayscale)
    let pixels: [UInt16]
    /// Image width in pixels
    let width: Int
    /// Image height in pixels
    let height: Int
    /// Bit depth (8, 12, or 16)
    let bitDepth: Int
}

// MARK: - JPEG Lossless Decoder

/// Decoder for JPEG Lossless compressed DICOM pixel data.
/// Implements JPEG Lossless (Process 14) with first-order prediction
/// as specified in ITU-T T.81 and DICOM PS3.5 Section 8.2.4.
///
/// This decoder handles:
/// - JPEG marker parsing (SOI, SOF3, DHT, SOS, EOI)
/// - Huffman table construction and symbol decoding
/// - Predictive coding with Selection Value 1 (left neighbor predictor)
/// - Bit-level stream parsing with byte stuffing removal
///
/// Supports DICOM Transfer Syntaxes:
/// - 1.2.840.10008.1.2.4.57: JPEG Lossless, Non-Hierarchical (Process 14)
/// - 1.2.840.10008.1.2.4.70: JPEG Lossless, First-Order Prediction (Process 14, SV1)
internal final class JPEGLosslessDecoder {

    // MARK: - Properties

    /// Parsed SOF3 (Start of Frame) information
    private var sof3Info: SOF3Info?

    /// Parsed SOS (Start of Scan) information
    private var sosInfo: SOSInfo?

    /// Huffman tables indexed by (tableClass << 4) | tableId
    private var huffmanTables: [Int: HuffmanTable] = [:]

    /// Byte offset where compressed entropy-coded data begins (after SOS header)
    private var compressedDataStart: Int = 0

    /// Logger for diagnostics and performance tracking
    private let logger: LoggerProtocol?

    // MARK: - Initialization

    /// Creates a new JPEG Lossless decoder
    /// - Parameter logger: Optional logger for diagnostics
    internal init(logger: LoggerProtocol? = nil) {
        self.logger = logger
    }

    // MARK: - Public Decoding Interface

    /// Decodes JPEG Lossless compressed pixel data
    /// - Parameter data: Raw JPEG Lossless bitstream starting with SOI marker
    /// - Returns: Decoded pixel buffer with metadata
    /// - Throws: DICOMError if parsing or decoding fails
    internal func decode(data: Data) throws -> JPEGLosslessDecodeResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Reset state
        sof3Info = nil
        sosInfo = nil
        huffmanTables.removeAll()
        compressedDataStart = 0

        // Parse JPEG markers
        try parseMarkers(data: data)

        // Validate required markers were found
        guard let sof3 = sof3Info else {
            throw DICOMError.invalidDICOMFormat(reason: "Missing SOF3 (Start of Frame) marker in JPEG Lossless stream")
        }
        guard let sos = sosInfo else {
            throw DICOMError.invalidDICOMFormat(reason: "Missing SOS (Start of Scan) marker in JPEG Lossless stream")
        }

        // Validate frame parameters
        try validateFrameParameters(sof3: sof3, sos: sos)

        // Decode pixels
        let pixels = try decodePixels(
            data: data,
            sof3: sof3,
            sos: sos,
            compressedDataStart: compressedDataStart
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger?.info("JPEG Lossless decode completed in \(String(format: "%.3f", elapsed))s")

        return JPEGLosslessDecodeResult(
            pixels: pixels,
            width: sof3.width,
            height: sof3.height,
            bitDepth: sof3.precision
        )
    }

    // MARK: - Marker Parsing

    /// Parses all JPEG markers from the bitstream
    /// Extracts SOF3, DHT, and SOS marker data
    /// - Parameter data: JPEG bitstream
    /// - Throws: DICOMError if markers are invalid or missing
    private func parseMarkers(data: Data) throws {
        var index = 0
        let endIndex = data.count

        // Expect SOI (Start of Image) marker at beginning
        guard index + 2 <= endIndex,
              data[index] == JPEGMarker.prefix,
              data[index + 1] == JPEGMarker.soi.rawValue else {
            throw DICOMError.invalidDICOMFormat(reason: "JPEG Lossless stream must start with SOI marker (0xFFD8)")
        }
        index += 2

        // Parse markers until SOS (Start of Scan)
        while index < endIndex {
            // Find next marker (0xFF followed by non-zero byte)
            guard index + 1 < endIndex else {
                throw DICOMError.invalidDICOMFormat(reason: "Unexpected end of data while parsing JPEG markers")
            }

            // Verify marker prefix
            guard data[index] == JPEGMarker.prefix else {
                throw DICOMError.invalidDICOMFormat(reason: "Expected marker prefix 0xFF at offset \(index), found 0x\(String(data[index], radix: 16))")
            }

            let markerType = data[index + 1]
            index += 2

            // Handle marker based on type
            if markerType == JPEGMarker.soi.rawValue {
                // SOI has no payload, already handled
                continue
            } else if markerType == JPEGMarker.eoi.rawValue {
                // EOI has no payload, marks end of image
                break
            } else if markerType == JPEGMarker.stuffingByte {
                // 0xFF 0x00 is byte stuffing in compressed data, should not appear here
                throw DICOMError.invalidDICOMFormat(reason: "Unexpected byte stuffing (0xFF 0x00) in marker section")
            }

            // All other markers have length field (2 bytes, big-endian, includes itself)
            guard index + 2 <= endIndex else {
                throw DICOMError.invalidDICOMFormat(reason: "Marker 0xFF\(String(markerType, radix: 16)) missing length field")
            }

            let length = Int(data[index]) << 8 | Int(data[index + 1])
            guard length >= 2 else {
                throw DICOMError.invalidDICOMFormat(reason: "Invalid marker length \(length) at offset \(index)")
            }

            let payloadLength = length - 2
            let payloadStart = index + 2
            let payloadEnd = payloadStart + payloadLength

            guard payloadEnd <= endIndex else {
                throw DICOMError.invalidDICOMFormat(reason: "Marker 0xFF\(String(markerType, radix: 16)) payload extends beyond data (needs \(payloadLength) bytes, \(endIndex - payloadStart) available)")
            }

            // Parse marker payload
            switch markerType {
            case JPEGMarker.sof3.rawValue:
                sof3Info = try parseSOF3(data: data, offset: payloadStart, length: payloadLength)

            case JPEGMarker.dht.rawValue:
                try parseDHT(data: data, offset: payloadStart, length: payloadLength)

            case JPEGMarker.sos.rawValue:
                sosInfo = try parseSOS(data: data, offset: payloadStart, length: payloadLength)
                // Compressed data starts immediately after SOS header
                compressedDataStart = payloadEnd
                // Stop marker parsing, rest is entropy-coded data
                return

            default:
                // Unknown marker, skip payload
                logger?.debug("Skipping unknown JPEG marker 0xFF\(String(markerType, radix: 16)) with \(payloadLength) bytes")
            }

            index = payloadEnd
        }
    }

    /// Parses Start of Frame (SOF3) marker for lossless JPEG
    /// - Parameters:
    ///   - data: JPEG data
    ///   - offset: Start of SOF3 payload
    ///   - length: Length of SOF3 payload
    /// - Returns: Parsed SOF3 information
    /// - Throws: DICOMError if SOF3 is malformed
    private func parseSOF3(data: Data, offset: Int, length: Int) throws -> SOF3Info {
        guard length >= 6 else {
            throw DICOMError.invalidDICOMFormat(reason: "SOF3 payload too short (\(length) bytes)")
        }

        let precision = Int(data[offset])
        let height = Int(data[offset + 1]) << 8 | Int(data[offset + 2])
        let width = Int(data[offset + 3]) << 8 | Int(data[offset + 4])
        let numberOfComponents = Int(data[offset + 5])

        // Validate dimensions
        guard width > 0, height > 0 else {
            throw DICOMError.invalidDICOMFormat(reason: "Invalid SOF3 dimensions: \(width)×\(height)")
        }

        // Validate precision
        guard precision == 8 || precision == 12 || precision == 16 else {
            throw DICOMError.invalidDICOMFormat(reason: "Unsupported SOF3 precision: \(precision) bits (expected 8, 12, or 16)")
        }

        // Parse component specifications
        let componentDataLength = numberOfComponents * 3
        guard length >= 6 + componentDataLength else {
            throw DICOMError.invalidDICOMFormat(reason: "SOF3 payload too short for \(numberOfComponents) components")
        }

        var components: [ComponentSpec] = []
        var pos = offset + 6

        for _ in 0..<numberOfComponents {
            let id = data[pos]
            let samplingFactors = data[pos + 1]
            let qtableSelector = data[pos + 2]

            let hSampling = (samplingFactors >> 4) & 0x0F
            let vSampling = samplingFactors & 0x0F

            components.append(ComponentSpec(
                id: id,
                horizontalSamplingFactor: hSampling,
                verticalSamplingFactor: vSampling,
                quantizationTableSelector: qtableSelector
            ))

            pos += 3
        }

        logger?.debug("SOF3: \(width)×\(height), \(precision)-bit, \(numberOfComponents) component(s)")

        return SOF3Info(
            width: width,
            height: height,
            precision: precision,
            numberOfComponents: numberOfComponents,
            components: components
        )
    }

    /// Parses Define Huffman Table (DHT) marker
    /// May contain multiple Huffman table definitions
    /// - Parameters:
    ///   - data: JPEG data
    ///   - offset: Start of DHT payload
    ///   - length: Length of DHT payload
    /// - Throws: DICOMError if DHT is malformed
    private func parseDHT(data: Data, offset: Int, length: Int) throws {
        var pos = offset
        let endPos = offset + length

        // DHT marker can contain multiple table definitions
        while pos < endPos {
            guard pos + 17 <= endPos else {
                throw DICOMError.invalidDICOMFormat(reason: "DHT payload truncated at offset \(pos)")
            }

            // Table class and ID packed in single byte
            let tableInfo = data[pos]
            let tableClass = (tableInfo >> 4) & 0x0F  // High nibble: 0=DC, 1=AC
            let tableId = tableInfo & 0x0F            // Low nibble: 0-3
            pos += 1

            // Read symbol counts for each bit length (1-16)
            var symbolCounts: [UInt8] = []
            var totalSymbols = 0
            for _ in 0..<16 {
                let count = data[pos]
                symbolCounts.append(count)
                totalSymbols += Int(count)
                pos += 1
            }

            // Validate symbol count
            guard totalSymbols <= 256 else {
                throw DICOMError.invalidDICOMFormat(reason: "DHT table has too many symbols: \(totalSymbols) (max 256)")
            }

            // Read symbol values
            guard pos + totalSymbols <= endPos else {
                throw DICOMError.invalidDICOMFormat(reason: "DHT symbol values extend beyond payload")
            }

            var symbolValues: [UInt8] = []
            for _ in 0..<totalSymbols {
                symbolValues.append(data[pos])
                pos += 1
            }

            // Store Huffman table and build decoding tables
            let tableKey = Int(tableClass) << 4 | Int(tableId)
            var table = HuffmanTable(
                tableClass: tableClass,
                tableId: tableId,
                symbolCounts: symbolCounts,
                symbolValues: symbolValues
            )

            // Build Huffman decoding tables (minCode, maxCode, valPtr arrays)
            buildHuffmanDecodingTables(table: &table)

            huffmanTables[tableKey] = table

            logger?.debug("DHT: class=\(tableClass), id=\(tableId), symbols=\(totalSymbols)")
        }
    }

    /// Parses Start of Scan (SOS) marker
    /// - Parameters:
    ///   - data: JPEG data
    ///   - offset: Start of SOS payload
    ///   - length: Length of SOS payload
    /// - Returns: Parsed SOS information
    /// - Throws: DICOMError if SOS is malformed
    private func parseSOS(data: Data, offset: Int, length: Int) throws -> SOSInfo {
        guard length >= 4 else {
            throw DICOMError.invalidDICOMFormat(reason: "SOS payload too short (\(length) bytes)")
        }

        let numberOfComponents = Int(data[offset])

        // Validate component count
        guard numberOfComponents > 0, numberOfComponents <= 4 else {
            throw DICOMError.invalidDICOMFormat(reason: "Invalid SOS component count: \(numberOfComponents)")
        }

        // Each component has 2 bytes (ID + entropy table selectors)
        let componentDataLength = numberOfComponents * 2
        guard length >= 1 + componentDataLength + 3 else {
            throw DICOMError.invalidDICOMFormat(reason: "SOS payload too short for \(numberOfComponents) components")
        }

        // Parse component selectors
        var components: [ScanComponentSelector] = []
        var pos = offset + 1

        for _ in 0..<numberOfComponents {
            let componentId = data[pos]
            let entropySelectors = data[pos + 1]

            let dcTable = (entropySelectors >> 4) & 0x0F
            let acTable = entropySelectors & 0x0F

            components.append(ScanComponentSelector(
                componentId: componentId,
                dcTableSelector: dcTable,
                acTableSelector: acTable
            ))

            pos += 2
        }

        // Parse scan parameters
        let startSpectral = Int(data[pos])        // Ss: Selection value (predictor ID)
        let endSpectral = Int(data[pos + 1])      // Se: Must be 0 for lossless
        let successiveApprox = data[pos + 2]      // Ah (high nibble), Al (low nibble)

        let approxHigh = (successiveApprox >> 4) & 0x0F
        let approxLow = successiveApprox & 0x0F

        logger?.debug("SOS: components=\(numberOfComponents), selectionValue=\(startSpectral)")

        return SOSInfo(
            numberOfComponents: numberOfComponents,
            components: components,
            selectionValue: startSpectral,
            startSpectral: startSpectral,
            endSpectral: endSpectral,
            successiveApproximationHigh: approxHigh,
            successiveApproximationLow: approxLow
        )
    }

    // MARK: - Validation

    /// Validates parsed frame parameters against JPEG Lossless requirements
    /// - Parameters:
    ///   - sof3: Start of Frame information
    ///   - sos: Start of Scan information
    /// - Throws: DICOMError if validation fails
    private func validateFrameParameters(sof3: SOF3Info, sos: SOSInfo) throws {
        // Validate component count matches
        guard sof3.numberOfComponents == sos.numberOfComponents else {
            throw DICOMError.invalidDICOMFormat(reason: "Component count mismatch: SOF3=\(sof3.numberOfComponents), SOS=\(sos.numberOfComponents)")
        }

        // Validate lossless mode parameters
        guard sos.endSpectral == 0 else {
            throw DICOMError.invalidDICOMFormat(reason: "SOS Se (end spectral) must be 0 for lossless mode, found \(sos.endSpectral)")
        }

        guard sos.successiveApproximationHigh == 0, sos.successiveApproximationLow == 0 else {
            throw DICOMError.invalidDICOMFormat(reason: "SOS Ah/Al (successive approximation) must be 0 for lossless mode")
        }

        // Validate selection value (predictor ID)
        guard sos.selectionValue >= 0, sos.selectionValue <= 7 else {
            throw DICOMError.invalidDICOMFormat(reason: "Invalid SOS selection value (predictor): \(sos.selectionValue) (must be 0-7)")
        }

        // For DICOM Transfer Syntax 1.2.840.10008.1.2.4.70, selection value must be 1
        // (this is informational, we support other selection values too)
        if sos.selectionValue != 1 {
            logger?.debug("Selection value \(sos.selectionValue) detected (DICOM TS 1.2.840.10008.1.2.4.70 requires 1)")
        }

        // Verify referenced Huffman tables exist
        for component in sos.components {
            let dcTableKey = 0 << 4 | Int(component.dcTableSelector)
            guard huffmanTables[dcTableKey] != nil else {
                throw DICOMError.invalidDICOMFormat(reason: "SOS references undefined Huffman table: class=0, id=\(component.dcTableSelector)")
            }
        }

        // DICOM typically uses single-component (grayscale) for lossless
        if sof3.numberOfComponents > 1 {
            logger?.debug("Multi-component image detected (\(sof3.numberOfComponents) components)")
        }
    }

    // MARK: - Pixel Decoding

    /// Decodes pixel data from compressed JPEG Lossless bitstream
    /// - Parameters:
    ///   - data: Complete JPEG bitstream
    ///   - sof3: Start of Frame information
    ///   - sos: Start of Scan information
    ///   - compressedDataStart: Byte offset where entropy-coded data begins
    /// - Returns: Decoded pixel buffer
    /// - Throws: DICOMError if decoding fails
    private func decodePixels(
        data: Data,
        sof3: SOF3Info,
        sos: SOSInfo,
        compressedDataStart: Int
    ) throws -> [UInt16] {
        let width = sof3.width
        let height = sof3.height
        let precision = sof3.precision
        let numPixels = width * height

        // Allocate pixel buffer
        var pixels = [UInt16](repeating: 0, count: numPixels)

        // Get Huffman table for decoding
        let componentSelector = sos.components[0]
        let tableKey = 0 << 4 | Int(componentSelector.dcTableSelector)
        guard var huffmanTable = huffmanTables[tableKey] else {
            throw DICOMError.invalidDICOMFormat(reason: "Huffman table not found: class=0, id=\(componentSelector.dcTableSelector)")
        }

        // Build decoding tables if not already built
        if huffmanTable.minCode.isEmpty {
            buildHuffmanDecodingTables(table: &huffmanTable)
            huffmanTables[tableKey] = huffmanTable
        }

        // Create bitstream reader
        var bitstream = BitStreamReader(
            data: data,
            startIndex: compressedDataStart,
            endIndex: data.count
        )

        // Decode pixels in raster scan order (row by row, left to right)
        var index = 0
        for y in 0..<height {
            for x in 0..<width {
                // Compute predictor for this pixel
                let predictor = computePredictor(
                    x: x,
                    y: y,
                    pixels: pixels,
                    width: width,
                    precision: precision
                )

                // Decode Huffman symbol (SSSS - number of difference bits)
                let ssss = try decodeHuffmanSymbol(
                    bitstream: &bitstream,
                    table: huffmanTable
                )

                // Decode difference value
                let difference = try decodeDifference(
                    ssss: Int(ssss),
                    bitstream: &bitstream
                )

                // Reconstruct pixel value
                pixels[index] = reconstructPixel(
                    predictor: predictor,
                    difference: difference,
                    precision: precision
                )

                index += 1
            }
        }

        return pixels
    }

    /// Decodes a Huffman symbol from the bitstream
    /// - Parameters:
    ///   - bitstream: Bitstream reader
    ///   - table: Huffman table to use for decoding
    /// - Returns: Decoded symbol value (SSSS)
    /// - Throws: DICOMError if decoding fails
    private func decodeHuffmanSymbol(
        bitstream: inout BitStreamReader,
        table: HuffmanTable
    ) throws -> UInt8 {
        // Decode Huffman code using table lookup algorithm (JPEG spec Annex F.2.2.3)
        var code = 0
        for length in 1...16 {
            // Read one bit and append to code
            let bit = try bitstream.readBit()
            code = (code << 1) | bit

            // Check if code is in range for this length
            if table.minCode[length] >= 0 && code <= table.maxCode[length] {
                // Found valid code - look up symbol value
                let symbolIndex = table.valPtr[length] + (code - table.minCode[length])
                guard symbolIndex >= 0 && symbolIndex < table.symbolValues.count else {
                    throw DICOMError.invalidDICOMFormat(reason: "Huffman symbol index out of range: \(symbolIndex)")
                }
                return table.symbolValues[symbolIndex]
            }
        }

        throw DICOMError.invalidDICOMFormat(reason: "Invalid Huffman code encountered")
    }

    /// Decodes a signed difference value from the bitstream
    /// - Parameters:
    ///   - ssss: Number of bits in the difference value
    ///   - bitstream: Bitstream reader
    /// - Returns: Signed difference value
    /// - Throws: DICOMError if decoding fails
    private func decodeDifference(
        ssss: Int,
        bitstream: inout BitStreamReader
    ) throws -> Int {
        // SSSS = 0 means difference is 0 (no additional bits)
        guard ssss > 0 else {
            return 0
        }

        guard ssss <= 16 else {
            throw DICOMError.invalidDICOMFormat(reason: "Invalid SSSS value: \(ssss) (must be 0-16)")
        }

        // Read SSSS bits to get magnitude representation
        var bits = 0
        for _ in 0..<ssss {
            let bit = try bitstream.readBit()
            bits = (bits << 1) | bit
        }

        // Decode sign from MSB (JPEG magnitude encoding)
        // If MSB is 1, value is positive: bits
        // If MSB is 0, value is negative: bits - (2^ssss - 1)
        let halfRange = 1 << (ssss - 1)
        if bits >= halfRange {
            // Positive value
            return bits
        } else {
            // Negative value: compute using JPEG's magnitude encoding
            return bits - ((1 << ssss) - 1)
        }
    }

    /// Reconstructs a pixel value from predictor and difference
    /// - Parameters:
    ///   - predictor: Predicted pixel value
    ///   - difference: Decoded difference value
    ///   - precision: Sample precision in bits
    /// - Returns: Reconstructed pixel value
    private func reconstructPixel(
        predictor: Int,
        difference: Int,
        precision: Int
    ) -> UInt16 {
        let modulo = 1 << precision  // 2^P (e.g., 65536 for 16-bit)
        var pixel = predictor + difference

        // Handle modulo wraparound (JPEG spec requirement)
        if pixel < 0 {
            pixel += modulo
        } else if pixel >= modulo {
            pixel -= modulo
        }

        return UInt16(pixel & 0xFFFF)
    }

    // MARK: - Prediction

    /// Computes the predictor value for a pixel using first-order prediction (Selection Value 1)
    /// - Parameters:
    ///   - x: Horizontal pixel position (0-indexed)
    ///   - y: Vertical pixel position (0-indexed)
    ///   - pixels: Decoded pixel buffer (values decoded so far)
    ///   - width: Image width in pixels
    ///   - precision: Sample precision in bits (8, 12, or 16)
    /// - Returns: Predicted pixel value
    internal func computePredictor(x: Int, y: Int, pixels: [UInt16], width: Int, precision: Int) -> Int {
        // Selection Value 1: First-order prediction using left neighbor (Ra)
        //
        // Predictor formula:
        // - First column (x=0): Predictor = 2^(P-1) where P is precision
        // - Other columns: Predictor = Ra (left neighbor)
        //
        // Reference: ITU-T T.81 Annex H, DICOM PS3.5 Section 8.2.4

        if x == 0 {
            // First pixel of each row: use default predictor 2^(P-1)
            // For 16-bit: 2^15 = 32768
            // For 12-bit: 2^11 = 2048
            // For 8-bit: 2^7 = 128
            return 1 << (precision - 1)
        } else {
            // Use left neighbor (Ra) as predictor
            let index = y * width + (x - 1)
            return Int(pixels[index])
        }
    }

    // MARK: - Huffman Table Construction

    /// Builds Huffman decoding tables from symbol counts and values
    /// Implements the algorithm from JPEG specification Annex F.2.2.3
    /// - Parameter table: Huffman table to populate with decoding arrays
    private func buildHuffmanDecodingTables(table: inout HuffmanTable) {
        // Initialize decoding tables (length 17: index 0 unused, 1-16 for bit lengths)
        var minCode = [Int](repeating: -1, count: 17)
        var maxCode = [Int](repeating: -1, count: 17)
        var valPtr = [Int](repeating: 0, count: 17)

        // Generate code sizes array (JPEG spec Figure F.15)
        var huffsize: [Int] = []
        for length in 1...16 {
            let count = table.symbolCounts[length - 1]
            for _ in 0..<count {
                huffsize.append(length)
            }
        }

        // Generate Huffman codes array (JPEG spec Figure F.16)
        var huffcode: [Int] = []
        if !huffsize.isEmpty {
            var code = 0
            var currentSize = huffsize[0]

            for size in huffsize {
                // If code length increases, shift code left
                if size > currentSize {
                    code <<= (size - currentSize)
                    currentSize = size
                }
                huffcode.append(code)
                code += 1
            }
        }

        // Build decoding tables (JPEG spec Figure F.17)
        // For each bit length, store minimum code, maximum code, and symbol value index
        var symbolIndex = 0
        for length in 1...16 {
            let symbolCount = Int(table.symbolCounts[length - 1])
            if symbolCount > 0 {
                valPtr[length] = symbolIndex
                minCode[length] = huffcode[symbolIndex]
                symbolIndex += symbolCount
                maxCode[length] = huffcode[symbolIndex - 1]
            }
        }

        // Store decoding tables in mutable copy
        table.minCode = minCode
        table.maxCode = maxCode
        table.valPtr = valPtr
    }
}

// MARK: - Bit Stream Reader

/// Bitstream reader for JPEG Lossless entropy-coded data.
/// Handles bit-level access with automatic byte stuffing removal
/// (0xFF 0x00 → 0xFF) and marker detection (0xFF 0xXX where XX != 0x00).
///
/// The reader maintains a bit buffer for efficient bit extraction and
/// automatically handles JPEG byte stuffing according to ITU-T T.81.
internal struct BitStreamReader {
    /// Source data containing JPEG bitstream
    private let data: Data

    /// Current byte position in data
    private var byteIndex: Int

    /// End boundary (exclusive) for reading
    private let endIndex: Int

    /// Bit buffer (accumulates up to 32 bits)
    private var bitBuffer: UInt32 = 0

    /// Number of valid bits currently in buffer
    private var bitsAvailable: Int = 0

    /// Creates a bitstream reader for JPEG entropy-coded data
    /// - Parameters:
    ///   - data: Complete JPEG bitstream
    ///   - startIndex: Byte offset where entropy-coded data begins
    ///   - endIndex: Byte offset where entropy-coded data ends
    internal init(data: Data, startIndex: Int, endIndex: Int) {
        self.data = data
        self.byteIndex = startIndex
        self.endIndex = endIndex
    }

    /// Fills the bit buffer with up to 24 bits from the byte stream
    /// Handles byte stuffing removal (0xFF 0x00 → 0xFF) and marker detection
    /// - Throws: DICOMError if data is truncated or invalid
    private mutating func fillBuffer() throws {
        while bitsAvailable <= 24 && byteIndex < endIndex {
            let byte = data[byteIndex]
            byteIndex += 1

            // Handle byte stuffing
            if byte == JPEGMarker.prefix {
                // 0xFF byte encountered - check next byte
                if byteIndex < endIndex {
                    let nextByte = data[byteIndex]
                    if nextByte == JPEGMarker.stuffingByte {
                        // 0xFF 0x00: byte stuffing - skip 0x00, keep 0xFF
                        byteIndex += 1
                        bitBuffer = (bitBuffer << 8) | UInt32(byte)
                        bitsAvailable += 8
                    } else {
                        // 0xFF 0xXX: marker detected - stop reading
                        // Back up to marker for proper marker handling
                        byteIndex -= 1
                        return
                    }
                } else {
                    // 0xFF at end of data without following byte
                    throw DICOMError.invalidDICOMFormat(reason: "Truncated JPEG data: 0xFF at end of stream")
                }
            } else {
                // Normal byte - add to buffer
                bitBuffer = (bitBuffer << 8) | UInt32(byte)
                bitsAvailable += 8
            }
        }
    }

    /// Reads a single bit from the bitstream (MSB first)
    /// - Returns: Bit value (0 or 1)
    /// - Throws: DICOMError if insufficient data
    internal mutating func readBit() throws -> Int {
        // Refill buffer if empty
        if bitsAvailable == 0 {
            try fillBuffer()
        }

        guard bitsAvailable > 0 else {
            throw DICOMError.invalidDICOMFormat(reason: "Unexpected end of JPEG bitstream")
        }

        // Extract MSB from buffer
        bitsAvailable -= 1
        let bit = Int((bitBuffer >> bitsAvailable) & 1)
        return bit
    }

    /// Reads multiple bits from the bitstream (MSB first)
    /// - Parameter count: Number of bits to read (must be ≤ 16)
    /// - Returns: Bit sequence as integer
    /// - Throws: DICOMError if count is invalid or insufficient data
    internal mutating func readBits(_ count: Int) throws -> Int {
        guard count >= 0 && count <= 16 else {
            throw DICOMError.invalidDICOMFormat(reason: "Invalid bit count: \(count) (must be 0-16)")
        }

        guard count > 0 else {
            return 0
        }

        var result = 0
        for _ in 0..<count {
            let bit = try readBit()
            result = (result << 1) | bit
        }
        return result
    }
}
