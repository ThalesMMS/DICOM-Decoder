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
        let componentCount = sof3.numberOfComponents

        guard componentCount == 1 || componentCount == 3 else {
            throw DICOMError.invalidDICOMFormat(
                reason: "JPEG Lossless multi-component decode supports 1 (grayscale) or 3 (interleaved color) components; the frame declares \(componentCount)"
            )
        }
        guard sos.components.count == componentCount else {
            throw DICOMError.invalidDICOMFormat(
                reason: "JPEG Lossless multi-component decode requires a single interleaved scan over all \(componentCount) frame components; the scan selects \(sos.components.count)"
            )
        }
        if componentCount > 1 {
            for component in sof3.components where component.horizontalSamplingFactor != 1
                || component.verticalSamplingFactor != 1 {
                throw DICOMError.invalidDICOMFormat(
                    reason: "JPEG Lossless multi-component decode requires 1x1 sampling; component \(component.id) declares "
                        + "\(component.horizontalSamplingFactor)x\(component.verticalSamplingFactor)"
                )
            }
        }

        let pixelCount = width.multipliedReportingOverflow(by: height)
        guard !pixelCount.overflow, pixelCount.partialValue > 0 else {
            throw DICOMError.invalidDICOMFormat(reason: "JPEG Lossless image dimensions overflow: \(width)x\(height)")
        }

        let numPixels = pixelCount.partialValue
        let maxPixelCount = Int(DCMDecoder.maxPixelBufferSize / Int64(MemoryLayout<UInt16>.stride))
        guard numPixels <= maxPixelCount / componentCount else {
            throw DICOMError.invalidDICOMFormat(reason: "JPEG Lossless image pixel count \(numPixels * componentCount) exceeds maximum \(maxPixelCount)")
        }

        // Huffman table per scan component.
        var componentTables = [HuffmanTable]()
        for componentSelector in sos.components {
            let tableKey = 0 << 4 | Int(componentSelector.dcTableSelector)
            guard var huffmanTable = huffmanTables[tableKey] else {
                throw DICOMError.invalidDICOMFormat(reason: "Huffman table not found: class=0, id=\(componentSelector.dcTableSelector)")
            }
            if huffmanTable.minCode.isEmpty {
                buildHuffmanDecodingTables(table: &huffmanTable)
                huffmanTables[tableKey] = huffmanTable
            }
            componentTables.append(huffmanTable)
        }

        if restartInterval == 0 {
            guard !containsRestartMarker(data: data, startIndex: compressedDataStart, endIndex: data.count) else {
                throw DICOMError.invalidDICOMFormat(
                    reason: "JPEG Lossless restart markers (RSTn) appear in the entropy-coded data but no restart interval was defined (missing DRI marker)"
                )
            }
        }

        var bitstream = BitStreamReader(
            data: data,
            startIndex: compressedDataStart,
            endIndex: data.count
        )

        // One plane per component; interleaved scans decode one sample of
        // each component per MCU (1x1 sampling), in raster MCU order.
        var planes = [[UInt16]](
            repeating: [UInt16](repeating: 0, count: numPixels),
            count: componentCount
        )
        let pointTransform = Int(sos.successiveApproximationLow)
        var mcuIndex = 0
        var restartCount = 0
        var intervalStartMCU = 0

        for y in 0..<height {
            for x in 0..<width {
                if restartInterval > 0, mcuIndex > 0, mcuIndex % restartInterval == 0 {
                    let found = try bitstream.consumeRestartMarker()
                    let expected = restartCount % 8
                    guard found == expected else {
                        throw DICOMError.invalidDICOMFormat(
                            reason: "JPEG Lossless restart marker out of order at MCU \(mcuIndex): expected RST\(expected), found RST\(found)"
                        )
                    }
                    restartCount += 1
                    // T.81 H: prediction is reset at each restart interval as
                    // at the start of a scan.
                    intervalStartMCU = mcuIndex
                }

                for component in 0..<componentCount {
                    let predictor = intervalAwarePredictor(
                        plane: planes[component],
                        x: x,
                        y: y,
                        width: width,
                        precision: precision,
                        selectionValue: sos.selectionValue,
                        pointTransform: pointTransform,
                        intervalStartMCU: intervalStartMCU
                    )

                    let ssss = try decodeHuffmanSymbol(
                        bitstream: &bitstream,
                        table: componentTables[component]
                    )
                    let category = Int(ssss)
                    guard category <= precision else {
                        throw DICOMError.invalidDICOMFormat(reason: "Invalid SSSS value: \(category) exceeds sample precision \(precision)")
                    }

                    let difference = try decodeDifference(
                        ssss: category,
                        bitstream: &bitstream
                    )

                    planes[component][y * width + x] = reconstructPixel(
                        predictor: predictor,
                        difference: difference,
                        precision: precision
                    )
                }
                mcuIndex += 1
            }
        }

        if componentCount == 1 {
            return planes[0]
        }

        // Interleave component planes (R,G,B per pixel).
        var interleaved = [UInt16](repeating: 0, count: numPixels * componentCount)
        for pixel in 0..<numPixels {
            for component in 0..<componentCount {
                interleaved[pixel * componentCount + component] = planes[component][pixel]
            }
        }
        return interleaved
    }

    /// Predictor per ITU-T T.81 Annex H.1.2 with restart-interval resets:
    /// the interval's first sample uses the default `2^(P-Pt-1)`, the rest
    /// of the interval's first line uses Ra, later line starts use Rb, and
    /// interior samples use the scan's selection-value predictor.
    private func intervalAwarePredictor(
        plane: [UInt16],
        x: Int,
        y: Int,
        width: Int,
        precision: Int,
        selectionValue: Int,
        pointTransform: Int,
        intervalStartMCU: Int
    ) -> Int {
        // Selection value 0 encodes raw values as differences from zero.
        guard selectionValue != 0 else { return 0 }

        let intervalStartY = intervalStartMCU / width
        let intervalStartX = intervalStartMCU % width
        let initialPredictor = 1 << max(0, precision - pointTransform - 1)

        if y == intervalStartY {
            // First line of the scan/restart interval (T.81 H.1.2: the
            // one-dimensional Ra predictor is used for the first line).
            if x == intervalStartX {
                return initialPredictor
            }
            return Int(plane[y * width + (x - 1)])
        }
        if x == 0 {
            // Line starts use Rb (sample above).
            return Int(plane[(y - 1) * width])
        }

        let ra = Int(plane[y * width + (x - 1)])
        let rb = Int(plane[(y - 1) * width + x])
        let rc = Int(plane[(y - 1) * width + (x - 1)])
        switch selectionValue {
        case 1: return ra
        case 2: return rb
        case 3: return rc
        case 4: return ra + rb - rc
        case 5: return ra + ((rb - rc) >> 1)
        case 6: return rb + ((ra - rc) >> 1)
        case 7: return (ra + rb) / 2
        default: return ra
        }
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
