import Foundation

extension JPEGLosslessDecoder {
    // MARK: - Pixel Decoding

    /// Decodes pixel data from compressed JPEG Lossless bitstream
    /// - Parameters:
    ///   - data: Complete JPEG bitstream
    ///   - sof3: Start of Frame information
    ///   - sos: Start of Scan information
    ///   - compressedDataStart: Byte offset where entropy-coded data begins
    /// - Returns: Decoded pixel buffer
    /// Decode JPEG Lossless entropy-coded image data into a linear buffer of reconstructed samples.
    /// - Parameters:
    ///   - data: Complete DICOM JPEG data blob containing the compressed entropy-coded segment.
    ///   - sof3: SOF3 (Start Of Frame) info providing image width, height, and sample precision.
    ///   - sos: SOS (Start Of Scan) info providing scan component selectors and selection value used for prediction.
    ///   - compressedDataStart: Byte offset into `data` where the entropy-coded segment begins.
    /// - Returns: A row-major (`width × height`) array of reconstructed samples as `UInt16`.
    /// - Throws: `DICOMError.invalidDICOMFormat` if required Huffman tables are missing or malformed, if an invalid Huffman code or out-of-range symbol index is encountered, or if an invalid `SSSS` value is decoded.
    func decodePixels(
        data: Data,
        sof3: SOF3Info,
        sos: SOSInfo,
        compressedDataStart: Int
    ) throws -> [UInt16] {
        let width = sof3.width
        let height = sof3.height
        let precision = sof3.precision

        guard sof3.numberOfComponents == 1, sos.components.count == 1 else {
            throw DICOMError.invalidDICOMFormat(reason: "JPEG Lossless multi-component images are unsupported")
        }

        let pixelCount = width.multipliedReportingOverflow(by: height)
        guard !pixelCount.overflow, pixelCount.partialValue > 0 else {
            throw DICOMError.invalidDICOMFormat(reason: "JPEG Lossless image dimensions overflow: \(width)x\(height)")
        }

        let numPixels = pixelCount.partialValue
        let maxPixelCount = Int(DCMDecoder.maxPixelBufferSize / Int64(MemoryLayout<UInt16>.stride))
        guard numPixels <= maxPixelCount else {
            throw DICOMError.invalidDICOMFormat(reason: "JPEG Lossless image pixel count \(numPixels) exceeds maximum \(maxPixelCount)")
        }

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

        guard !containsRestartMarker(data: data, startIndex: compressedDataStart, endIndex: data.count) else {
            throw DICOMError.invalidDICOMFormat(reason: "JPEG Lossless restart markers (RSTn) are unsupported")
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
                    precision: precision,
                    selectionValue: sos.selectionValue,
                    pointTransform: Int(sos.successiveApproximationLow),
                    isFirstSampleInScan: index == 0
                )

                // Decode Huffman symbol (SSSS - number of difference bits)
                let ssss = try decodeHuffmanSymbol(
                    bitstream: &bitstream,
                    table: huffmanTable
                )
                let category = Int(ssss)
                guard category <= precision else {
                    throw DICOMError.invalidDICOMFormat(reason: "Invalid SSSS value: \(category) exceeds sample precision \(precision)")
                }

                // Decode difference value
                let difference = try decodeDifference(
                    ssss: category,
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

    /// BitStreamReader.fillBuffer leaves byteIndex positioned at markers so callers
    /// can consume them. Restart intervals are not implemented, so reject RSTn
    /// markers before the entropy loop can stop on one without resetting state.
    private func containsRestartMarker(data: Data, startIndex: Int, endIndex: Int) -> Bool {
        var index = startIndex
        while index + 1 < endIndex {
            guard data[index] == JPEGMarker.prefix else {
                index += 1
                continue
            }

            var markerIndex = index + 1
            while markerIndex < endIndex && data[markerIndex] == JPEGMarker.prefix {
                markerIndex += 1
            }

            guard markerIndex < endIndex else { return false }

            let marker = data[markerIndex]
            if marker == JPEGMarker.stuffingByte {
                index = markerIndex + 1
                continue
            }

            if JPEGMarker.isRestart(marker) {
                return true
            }

            index = markerIndex + 1
        }

        return false
    }

    /// Decodes a Huffman symbol from the bitstream
    /// - Parameters:
    ///   - bitstream: Bitstream reader
    ///   - table: Huffman table to use for decoding
    /// - Returns: Decoded symbol value (SSSS)
    /// Decode a Huffman-coded symbol from the bitstream using the provided Huffman table.
    /// - Parameters:
    ///   - bitstream: A bit-level reader positioned at the next Huffman code; advances as bits are consumed.
    ///   - table: A prepared Huffman decoding table containing `minCode`, `maxCode`, `valPtr`, and `symbolValues`.
    /// - Returns: The decoded symbol value as a `UInt8`.
    /// - Throws: `DICOMError.invalidDICOMFormat` if an invalid Huffman code is encountered or the computed symbol index is out of range.
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
    /// Decodes a signed prediction difference from the bitstream using JPEG magnitude encoding.
    /// - Parameters:
    ///   - ssss: Number of magnitude bits (SSSS) from the Huffman-decoded symbol; must be between 0 and 16.
    ///   - bitstream: Bit reader positioned after the Huffman symbol; this function consumes additional magnitude bits except for the lossless-only `SSSS == 16` code.
    /// - Returns: The decoded signed difference as an `Int` (positive or negative).
    /// - Throws: `DICOMError.invalidDICOMFormat` if `ssss` is greater than 16; also propagates errors thrown by `bitstream.readBit()`.
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

        // JPEG lossless extends DC categories with SSSS=16 for the most-negative
        // 16-bit difference value. No extra bits follow this code.
        if ssss == 16 {
            return -32768
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
    /// Reconstructs a single sample by applying a signed difference to a predictor and enforcing JPEG modulo wraparound.
    /// - Parameters:
    ///   - predictor: The predicted sample value (may be outside final range before wraparound).
    ///   - difference: The signed difference to add to the predictor.
    ///   - precision: Bit precision of the sample (P); used to compute the modulo range 2^P.
    /// - Returns: The reconstructed sample value wrapped into the range 0..(2^precision - 1) as a `UInt16`.
    private func reconstructPixel(
        predictor: Int,
        difference: Int,
        precision: Int
    ) -> UInt16 {
        let modulo = 1 << precision  // 2^P (e.g., 65536 for 16-bit)
        let mask = modulo - 1
        let pixel = predictor + difference

        // Handle modulo wraparound (JPEG spec requirement).
        return UInt16(pixel & mask)
    }

}
