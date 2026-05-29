import Foundation

internal enum DicomRLELosslessDecoder {
    static func decode(
        frame data: Data,
        width: Int,
        height: Int,
        bitsAllocated: Int,
        samplesPerPixel: Int,
        pixelRepresentation: Int,
        photometricInterpretation: String
    ) throws -> DCMPixelReadResult {
        guard let metrics = DCMPixelReader.computePixelMetrics(
            width: width,
            height: height,
            bytesPerPixel: Int64(max(1, samplesPerPixel) * max(1, (bitsAllocated + 7) / 8)),
            context: "RLE Lossless",
            logger: nil
        ) else {
            throw DICOMError.invalidPixelData(reason: "Invalid RLE image dimensions")
        }

        let bytesPerSample = max(1, (bitsAllocated + 7) / 8)
        guard bytesPerSample == 1 || bytesPerSample == 2 else {
            throw DICOMError.invalidPixelData(reason: "RLE supports only 8-bit and 16-bit samples in this decoder")
        }
        guard samplesPerPixel == 1 || (samplesPerPixel == 3 && bytesPerSample == 1) else {
            throw DICOMError.invalidPixelData(reason: "RLE supports grayscale samples or 8-bit RGB samples")
        }
        guard data.count >= 64 else {
            throw DICOMError.invalidPixelData(reason: "RLE frame is shorter than the 64-byte header")
        }

        let segmentCount = Int(readUInt32LE(data, offset: 0))
        let expectedSegments = samplesPerPixel * bytesPerSample
        guard segmentCount == expectedSegments, segmentCount > 0, segmentCount <= 15 else {
            throw DICOMError.invalidPixelData(reason: "RLE segment count \(segmentCount) does not match expected count \(expectedSegments)")
        }

        let offsets = (0..<segmentCount).map { index in
            Int(readUInt32LE(data, offset: 4 + index * 4))
        }
        for offset in offsets {
            guard offset >= 64, offset <= data.count else {
                throw DICOMError.invalidPixelData(reason: "RLE segment offset \(offset) is outside frame bounds")
            }
        }

        let pixelCount = metrics.numPixels
        let decodedSegments = try offsets.enumerated().map { index, offset in
            let end = index + 1 < offsets.count ? offsets[index + 1] : data.count
            guard end >= offset else {
                throw DICOMError.invalidPixelData(reason: "RLE segment offsets are not monotonic")
            }
            return try decodePackBitsSegment(data[offset..<end], expectedCount: pixelCount)
        }

        if samplesPerPixel == 1 && bytesPerSample == 1 {
            var pixels = decodedSegments[0]
            if pixelRepresentation == 1 {
                pixels = pixels.map { sample in
                    UInt8(Int(Int8(bitPattern: sample)) - Int(Int8.min))
                }
            }
            if photometricInterpretation == "MONOCHROME1" {
                pixels = pixels.map { 255 - $0 }
            }
            return DCMPixelReadResult(
                pixels8: pixels,
                pixels16: nil,
                pixels24: nil,
                signedImage: pixelRepresentation == 1,
                width: width,
                height: height,
                bitDepth: bitsAllocated,
                samplesPerPixel: samplesPerPixel
            )
        }

        if samplesPerPixel == 1 && bytesPerSample == 2 {
            var pixels = [UInt16](repeating: 0, count: pixelCount)
            for index in 0..<pixelCount {
                let high = UInt16(decodedSegments[0][index])
                let low = UInt16(decodedSegments[1][index])
                let sample = (high << 8) | low
                if pixelRepresentation == 1 {
                    pixels[index] = UInt16(Int(Int16(bitPattern: sample)) - Int(Int16.min))
                } else {
                    pixels[index] = sample
                }
            }
            if photometricInterpretation == "MONOCHROME1" {
                if pixelRepresentation == 1 {
                    DCMPixelReader.invertMonochrome1SignedVectorized(buffer: &pixels, count: pixelCount)
                } else {
                    DCMPixelReader.invertMonochrome1Vectorized(buffer: &pixels, count: pixelCount)
                }
            }
            return DCMPixelReadResult(
                pixels8: nil,
                pixels16: pixels,
                pixels24: nil,
                signedImage: pixelRepresentation == 1,
                width: width,
                height: height,
                bitDepth: bitsAllocated,
                samplesPerPixel: samplesPerPixel
            )
        }

        var rgb = [UInt8](repeating: 0, count: pixelCount * 3)
        for index in 0..<pixelCount {
            rgb[index * 3] = decodedSegments[0][index]
            rgb[index * 3 + 1] = decodedSegments[1][index]
            rgb[index * 3 + 2] = decodedSegments[2][index]
        }
        return DCMPixelReadResult(
            pixels8: nil,
            pixels16: nil,
            pixels24: rgb,
            signedImage: false,
            width: width,
            height: height,
            bitDepth: bitsAllocated,
            samplesPerPixel: samplesPerPixel
        )
    }

    private static func decodePackBitsSegment(_ segment: Data.SubSequence, expectedCount: Int) throws -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(expectedCount)
        var index = segment.startIndex

        while index < segment.endIndex && output.count < expectedCount {
            let control = Int(Int8(bitPattern: segment[index]))
            index = segment.index(after: index)

            if control >= 0 {
                let count = control + 1
                guard segment.distance(from: index, to: segment.endIndex) >= count else {
                    throw DICOMError.invalidPixelData(reason: "RLE literal run exceeds segment bounds")
                }
                guard output.count + count <= expectedCount else {
                    throw DICOMError.invalidPixelData(reason: "RLE literal run exceeds expected segment length")
                }
                output.append(contentsOf: segment[index..<segment.index(index, offsetBy: count)])
                index = segment.index(index, offsetBy: count)
            } else if control >= -127 {
                guard index < segment.endIndex else {
                    throw DICOMError.invalidPixelData(reason: "RLE replicated run is missing its value byte")
                }
                let count = 1 - control
                guard output.count + count <= expectedCount else {
                    throw DICOMError.invalidPixelData(reason: "RLE replicated run exceeds expected segment length")
                }
                output.append(contentsOf: repeatElement(segment[index], count: count))
                index = segment.index(after: index)
            }
        }

        guard output.count == expectedCount else {
            throw DICOMError.invalidPixelData(reason: "RLE segment decoded \(output.count) bytes; expected \(expectedCount)")
        }
        return output
    }

    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
