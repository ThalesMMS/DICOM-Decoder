//
//  DCMPixelReader.swift
//
//  Pixel data extraction and decoding for DICOM files.
//  This module handles reading uncompressed pixel buffers for 8‑bit,
//  16‑bit, and 24‑bit RGB images, as well as decoding compressed
//  transfer syntaxes using ImageIO.  Supports signed/unsigned pixel
//  representation, MONOCHROME1/MONOCHROME2 photometric interpretation,
//  and memory-mapped optimization for large files.
//
//  Usage:
//
//    let result = DCMPixelReader.readPixels(
//        data: dicomData,
//        width: 512,
//        height: 512,
//        bitDepth: 16,
//        samplesPerPixel: 1,
//        offset: 1024,
//        pixelRepresentation: 0,
//        littleEndian: true,
//        photometricInterpretation: "MONOCHROME2"
//    )
//    if let pixels16 = result.pixels16 {
//        // process 16-bit grayscale pixels
//    }
//

import Foundation
import CoreGraphics
import ImageIO

/// Result structure for pixel reading operations.
/// Contains pixel buffers and metadata about the pixel data.
internal struct DCMPixelReadResult {
    /// 8-bit grayscale pixel buffer
    var pixels8: [UInt8]?
    /// 16-bit grayscale pixel buffer
    var pixels16: [UInt16]?
    /// 24-bit RGB pixel buffer (interleaved)
    var pixels24: [UInt8]?
    /// True if pixels use signed representation
    var signedImage: Bool
    /// Actual image width (may differ from header for compressed images)
    var width: Int
    /// Actual image height (may differ from header for compressed images)
    var height: Int
    /// Actual bit depth (may differ from header for compressed images)
    var bitDepth: Int
    /// Actual samples per pixel (may differ from header for compressed images)
    var samplesPerPixel: Int
}

/// Reader for DICOM pixel data.
/// Handles extraction of pixel buffers from both uncompressed and
/// compressed DICOM files.  Supports 8‑bit grayscale, 16‑bit grayscale,
/// and 24‑bit RGB images.  Automatically handles endianness, signed/
/// unsigned pixel representation, and photometric interpretation.
///
/// This class is designed to be used by DCMDecoder.  All methods are
/// static and take the necessary parameters explicitly.
internal final class DCMPixelReader {

    // MARK: - Private Constants

    /// Minimum signed 16-bit value used for normalizing signed pixels
    private static let min16: Int = Int(Int16.min)

    /// Maximum allowed image dimension (width or height) in pixels.
    /// Prevents memory bombs from malformed DICOM headers.
    private static let maxImageDimension: Int = 65536

    /// Maximum allowed size for pixel buffer allocation (2 GB).
    /// Protects against excessive memory use and integer overflow.
    private static let maxPixelBufferSize: Int64 = 2 * 1024 * 1024 * 1024

    // MARK: - Pixel Reading Methods

    /// Converts a two's complement encoded 16‑bit value into an
    /// unsigned 16‑bit representation.  This is used when
    /// ``pixelRepresentation`` equals one to map signed pixel values
    /// into the positive range expected by rendering code.  The
    /// algorithm subtracts the minimum short value to shift the
    /// range appropriately.
    ///
    /// - Parameters:
    ///   - b0: Low byte
    ///   - b1: High byte
    /// - Returns: Normalized unsigned 16-bit value
    private static func normaliseSigned16(bytes b0: UInt8, b1: UInt8) -> UInt16 {
        let combined = Int16(bitPattern: UInt16(b1) << 8 | UInt16(b0))
        // Shift negative values up by min16 to make them positive
        let shifted = Int(combined) - min16
        return UInt16(shifted)
    }

    /// Validates dimensions and computes pixel counts and byte sizes safely.
    /// Returns nil when dimensions are invalid or allocations would be unsafe.
    private static func computePixelMetrics(
        width: Int,
        height: Int,
        bytesPerPixel: Int64,
        context: String,
        logger: AnyLogger?
    ) -> (numPixels: Int, numBytes: Int)? {
        guard width > 0, height > 0 else {
            logger?.warning("Invalid image dimensions: width=\(width), height=\(height)")
            return nil
        }
        if width > maxImageDimension || height > maxImageDimension {
            logger?.warning("Image dimensions exceed maximum allowed: \(width)x\(height) (max \(maxImageDimension))")
            return nil
        }

        let width64 = Int64(width)
        let height64 = Int64(height)
        let (pixelCount64, pixelOverflow) = width64.multipliedReportingOverflow(by: height64)
        if pixelOverflow || pixelCount64 <= 0 {
            logger?.warning("Pixel count overflow for \(context): width=\(width), height=\(height)")
            return nil
        }
        if pixelCount64 > Int64(Int.max) {
            logger?.warning("Pixel count exceeds addressable range for \(context): \(pixelCount64)")
            return nil
        }

        let (byteCount64, byteOverflow) = pixelCount64.multipliedReportingOverflow(by: bytesPerPixel)
        if byteOverflow || byteCount64 <= 0 {
            logger?.warning("Pixel buffer size overflow for \(context): pixels=\(pixelCount64), bytesPerPixel=\(bytesPerPixel)")
            return nil
        }
        if byteCount64 > maxPixelBufferSize {
            logger?.warning("Pixel buffer size \(byteCount64) bytes exceeds maximum allowed \(maxPixelBufferSize) bytes for \(context)")
            return nil
        }
        if byteCount64 > Int64(Int.max) {
            logger?.warning("Pixel buffer size exceeds addressable range for \(context): \(byteCount64)")
            return nil
        }

        return (numPixels: Int(pixelCount64), numBytes: Int(byteCount64))
    }

    /// Reads uncompressed pixel data from the DICOM file.  This method
    /// allocates new buffers and supports 8‑bit grayscale, 16‑bit
    /// grayscale and 8‑bit 3‑channel RGB images.  Other values of
    /// ``samplesPerPixel`` or ``bitDepth`` result in empty buffers.
    ///
    /// - Parameters:
    ///   - data: Raw DICOM file data
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    ///   - bitDepth: Bits per sample (8 or 16)
    ///   - samplesPerPixel: Number of color channels (1 for grayscale, 3 for RGB)
    ///   - offset: Byte offset to pixel data
    ///   - pixelRepresentation: 0 for unsigned, 1 for two's complement signed
    ///   - littleEndian: True for little endian byte order
    ///   - photometricInterpretation: MONOCHROME1 or MONOCHROME2
    ///   - logger: Optional logger for performance metrics
    /// - Returns: Pixel read result with populated buffers
    internal static func readPixels(
        data: Data,
        width: Int,
        height: Int,
        bitDepth: Int,
        samplesPerPixel: Int,
        offset: Int,
        pixelRepresentation: Int,
        littleEndian: Bool,
        photometricInterpretation: String,
        logger: AnyLogger? = nil
    ) -> DCMPixelReadResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        var result = DCMPixelReadResult(
            pixels8: nil,
            pixels16: nil,
            pixels24: nil,
            signedImage: false,
            width: width,
            height: height,
            bitDepth: bitDepth,
            samplesPerPixel: samplesPerPixel
        )

        // Grayscale 8‑bit
        if samplesPerPixel == 1 && bitDepth == 8 {
            guard let metrics = computePixelMetrics(
                width: width,
                height: height,
                bytesPerPixel: 1,
                context: "8-bit grayscale",
                logger: logger
            ) else {
                return result
            }
            let numPixels = metrics.numPixels
            guard offset > 0, offset <= data.count, numPixels <= data.count - offset else {
                logger?.warning("Invalid offset or insufficient data. offset=\(offset), needed=\(numPixels), available=\(max(0, data.count - offset))")
                return result
            }
            result.pixels8 = Array(data[offset..<offset + numPixels])

            // Handle MONOCHROME1 (white is zero) - common for X-rays
            if photometricInterpretation == "MONOCHROME1" {
                if var p8 = result.pixels8 {
                    for i in 0..<numPixels {
                        p8[i] = 255 - p8[i]
                    }
                    result.pixels8 = p8
                }
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger?.debug("[PERF] readPixels (8-bit): \(String(format: "%.2f", elapsed))ms | size: \(width)x\(height)")
            return result
        }

        // Grayscale 16‑bit
        if samplesPerPixel == 1 && bitDepth == 16 {
            guard let metrics = computePixelMetrics(
                width: width,
                height: height,
                bytesPerPixel: 2,
                context: "16-bit grayscale",
                logger: logger
            ) else {
                return result
            }
            let numPixels = metrics.numPixels
            let numBytes = metrics.numBytes

            guard offset > 0, offset <= data.count, numBytes <= data.count - offset else {
                logger?.warning("Invalid offset or insufficient data. offset=\(offset), needed=\(numBytes), available=\(data.count - offset)")
                return result
            }

            // OPTIMIZATION: Use withUnsafeBytes for much faster pixel reading
            result.pixels16 = Array(repeating: 0, count: numPixels)
            guard var pixels = result.pixels16 else { return result }

            data.withUnsafeBytes { dataBytes in
                let basePtr = dataBytes.baseAddress!.advanced(by: offset)

                if pixelRepresentation == 0 {
                    // Unsigned pixels - most common for CR/DX
                    if littleEndian {
                        // Little endian (most common)
                        // Check if the pointer is aligned for UInt16 access
                        if offset % 2 == 0 {
                            // Aligned - can use fast path
                            basePtr.withMemoryRebound(to: UInt16.self, capacity: numPixels) { uint16Ptr in
                                if photometricInterpretation == "MONOCHROME1" {
                                    // Invert for MONOCHROME1 (white is zero)
                                    for i in 0..<numPixels {
                                        pixels[i] = 65535 - uint16Ptr[i]
                                    }
                                } else {
                                    // Direct copy for MONOCHROME2
                                    pixels.withUnsafeMutableBufferPointer { pixelBuffer in
                                        _ = memcpy(pixelBuffer.baseAddress!, uint16Ptr, numBytes)
                                    }
                                }
                            }
                        } else {
                            // Unaligned - use byte-by-byte reading
                            let uint8Ptr = basePtr.assumingMemoryBound(to: UInt8.self)
                            for i in 0..<numPixels {
                                let byteIndex = i * 2
                                let b0 = uint8Ptr[byteIndex]
                                let b1 = uint8Ptr[byteIndex + 1]
                                var value = UInt16(b0) | (UInt16(b1) << 8)  // Little endian
                                if photometricInterpretation == "MONOCHROME1" {
                                    value = 65535 - value
                                }
                                pixels[i] = value
                            }
                        }
                    } else {
                        // Big endian (rare)
                        let uint8Ptr = basePtr.assumingMemoryBound(to: UInt8.self)
                        for i in 0..<numPixels {
                            let byteIndex = i * 2
                            let b0 = uint8Ptr[byteIndex]
                            let b1 = uint8Ptr[byteIndex + 1]
                            var value = UInt16(b0) << 8 | UInt16(b1)
                            if photometricInterpretation == "MONOCHROME1" {
                                value = 65535 - value
                            }
                            pixels[i] = value
                        }
                    }
                    result.signedImage = false
                } else {
                    // Signed pixels (less common)
                    result.signedImage = true
                    let uint8Ptr = basePtr.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<numPixels {
                        let byteIndex = i * 2
                        let b0 = uint8Ptr[byteIndex]
                        let b1 = uint8Ptr[byteIndex + 1]
                        var value = normaliseSigned16(bytes: b0, b1: b1)
                        if photometricInterpretation == "MONOCHROME1" {
                            value = UInt16(32768) - (value - UInt16(32768))
                        }
                        pixels[i] = value
                    }
                }
            }

            result.pixels16 = pixels

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger?.debug("[PERF] readPixels (16-bit): \(String(format: "%.2f", elapsed))ms | size: \(width)x\(height)")
            return result
        }

        // Colour 8‑bit RGB
        if samplesPerPixel == 3 && bitDepth == 8 {
            result.signedImage = false
            guard let metrics = computePixelMetrics(
                width: width,
                height: height,
                bytesPerPixel: 3,
                context: "24-bit RGB",
                logger: logger
            ) else {
                return result
            }
            let numBytes = metrics.numBytes
            guard offset > 0, offset <= data.count, numBytes <= data.count - offset else {
                logger?.warning("Invalid offset or insufficient data. offset=\(offset), needed=\(numBytes), available=\(max(0, data.count - offset))")
                return result
            }
            result.pixels24 = Array(data[offset..<offset + numBytes])

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger?.debug("[PERF] readPixels (24-bit RGB): \(String(format: "%.2f", elapsed))ms | size: \(width)x\(height)")
            return result
        }

        // Fallback: leave buffers nil
        return result
    }

    /// Attempts to decode compressed pixel data using ImageIO.
    /// This function supports common DICOM transfer syntaxes
    /// including JPEG Baseline, JPEG Extended, JPEG‑LS and
    /// JPEG2000.  The compressed data is assumed to begin at
    /// ``offset`` and extend to the end of ``data``.  On
    /// success the pixel buffers are populated accordingly.
    ///
    /// - Parameters:
    ///   - data: Raw DICOM file data
    ///   - offset: Byte offset to compressed pixel data
    ///   - logger: Optional logger for debugging
    /// - Returns: Pixel read result with populated buffers, or nil on failure
    internal static func decodeCompressedPixelData(
        data: Data,
        offset: Int,
        logger: AnyLogger? = nil
    ) -> DCMPixelReadResult? {
        // Extract the encapsulated pixel data from the offset to
        // the end of the file.  Some DICOM files encapsulate each
        // frame into separate items; for simplicity we treat the
        // entire remaining data as one JPEG/JP2 codestream.  For
        // robust handling you would need to parse the Basic Offset
        // Table and items (see PS3.5).  This implementation is
        // designed to handle single–frame images.
        let compressedData = data.subdata(in: offset..<data.count)

        // Create an image source from the compressed data.  ImageIO
        // automatically detects JPEG, JPEG2000 and JPEG‑LS formats.
        guard let source = CGImageSourceCreateWithData(compressedData as CFData, nil) else {
            logger?.warning("Failed to create image source from compressed data")
            return nil
        }

        // Decode the first image in the source.
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            logger?.warning("Failed to decode image from source")
            return nil
        }

        // Retrieve dimensions
        let width = cgImage.width
        let height = cgImage.height
        let bitDepth = cgImage.bitsPerComponent

        // Determine number of colour samples.  bitsPerPixel may
        // include alpha; we compute based on bitsPerPixel and
        // bitsPerComponent.
        let samples = max(1, cgImage.bitsPerPixel / cgImage.bitsPerComponent)
        let samplesPerPixel = samples >= 3 ? 3 : 1

        var result = DCMPixelReadResult(
            pixels8: nil,
            pixels16: nil,
            pixels24: nil,
            signedImage: false,
            width: width,
            height: height,
            bitDepth: bitDepth,
            samplesPerPixel: samplesPerPixel
        )

        // Prepare a context to extract the pixel data.  For colour
        // images we render into a BGRA 32‑bit buffer; for grayscale
        // we render into an 8‑bit buffer.
        if samplesPerPixel == 1 {
            // Grayscale output
            let colorSpace = CGColorSpaceCreateDeviceGray()
            let bytesPerRow = width
            guard let ctx = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                logger?.warning("Failed to create grayscale context")
                return nil
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let dataPtr = ctx.data else {
                logger?.warning("Failed to get context data pointer")
                return nil
            }
            let buffer = dataPtr.assumingMemoryBound(to: UInt8.self)
            let count = width * height
            result.pixels8 = [UInt8](UnsafeBufferPointer(start: buffer, count: count))
        } else {
            // Colour output.  Render into BGRA and then strip alpha.
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let bytesPerRow = width * bytesPerPixel
            let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            guard let ctx = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
                logger?.warning("Failed to create RGB context")
                return nil
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let dataPtr = ctx.data else {
                logger?.warning("Failed to get context data pointer")
                return nil
            }
            let rawBuffer = dataPtr.assumingMemoryBound(to: UInt8.self)
            let count = width * height
            // Allocate pixel24 and fill with RGB triples (BGR in
            // little endian).  We omit the alpha channel.
            var output = [UInt8](repeating: 0, count: count * 3)
            for i in 0..<count {
                let srcIndex = i * 4
                let dstIndex = i * 3
                // CGImage in little endian stores bytes as BGRA
                let blue  = rawBuffer[srcIndex]
                let green = rawBuffer[srcIndex + 1]
                let red   = rawBuffer[srcIndex + 2]
                output[dstIndex]     = blue
                output[dstIndex + 1] = green
                output[dstIndex + 2] = red
            }
            result.pixels24 = output
        }

        return result
    }
}
