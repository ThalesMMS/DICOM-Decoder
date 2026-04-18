import Foundation

/// Create a minimal, self-contained JPEG byte stream representing a lossless (SOF3) image using the supplied dimensions and encoding parameters.
/// - Parameters:
///   - width: Image width in pixels; must be > 0 and ≤ UInt16.max.
///   - height: Image height in pixels; must be > 0 and ≤ UInt16.max.
///   - precision: Sample precision (bits per sample); must be within 0...UInt8.max. Default is 16.
///   - predictionMode: Lossless prediction mode value; must be within 0...7. Default is 1.
/// - Returns: A `Data` buffer containing a minimal JPEG stream (SOI, DHT, SOF3, SOS, compressed payload of zero bytes, EOI) sized for the given image dimensions.
func makeMinimalJPEGLosslessData(
    width: Int,
    height: Int,
    precision: Int = 16,
    predictionMode: Int = 1
) -> Data {
    precondition(width > 0 && width <= Int(UInt16.max))
    precondition(height > 0 && height <= Int(UInt16.max))
    precondition((0...Int(UInt8.max)).contains(precision))
    precondition((0...7).contains(predictionMode))

    var jpegData = Data()

    jpegData.append(contentsOf: [0xFF, 0xD8])

    let symbolCounts: [UInt8] = [1] + Array(repeating: 0, count: 15)
    let symbolValues: [UInt8] = [0]

    jpegData.append(contentsOf: [0xFF, 0xC4])
    jpegData.appendUInt16(2 + 1 + 16 + UInt16(symbolValues.count))
    jpegData.append(0x00)
    jpegData.append(contentsOf: symbolCounts)
    jpegData.append(contentsOf: symbolValues)

    jpegData.append(contentsOf: [0xFF, 0xC3])
    jpegData.appendUInt16(11)
    jpegData.append(UInt8(precision))
    jpegData.appendUInt16(UInt16(height))
    jpegData.appendUInt16(UInt16(width))
    jpegData.append(1)
    jpegData.append(1)
    jpegData.append(0x11)
    jpegData.append(0)

    jpegData.append(contentsOf: [0xFF, 0xDA])
    jpegData.appendUInt16(8)
    jpegData.append(1)
    jpegData.append(1)
    jpegData.append(0x00)
    jpegData.append(UInt8(predictionMode))
    jpegData.append(0)
    jpegData.append(0)

    let pixelCount = width * height
    let compressedByteCount = max(1, (pixelCount + 7) / 8)
    jpegData.append(contentsOf: [UInt8](repeating: 0x00, count: compressedByteCount))

    jpegData.append(contentsOf: [0xFF, 0xD9])

    return jpegData
}

private extension Data {
    /// Appends a 16-bit unsigned integer to the data in big-endian (most-significant byte first) order.
    /// - Parameter value: The `UInt16` value to append as two bytes, most significant byte first.
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }
}
