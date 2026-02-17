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
import Accelerate
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

    /// Vectorized conversion of signed 16‑bit pixels to unsigned
    /// representation using Accelerate vDSP operations.  This
    /// function reads signed Int16 values from raw bytes and shifts
    /// them into the unsigned UInt16 range by subtracting Int16.min
    /// (i.e., adding 32768).  The conversion is performed using SIMD
    /// operations for optimal performance.
    ///
    /// - Parameters:
    ///   - sourcePtr: Pointer to raw byte data containing signed 16‑bit pixels
    ///   - outputBuffer: Destination buffer for normalized UInt16 pixels
    ///   - count: Number of pixels to convert
    ///   - littleEndian: True if source data is little endian
    private static func normaliseSigned16Vectorized(
        sourcePtr: UnsafeRawPointer,
        outputBuffer: inout [UInt16],
        count: Int,
        littleEndian: Bool
    ) {
        // Acquire temporary buffers from pool
        var signedPixels = BufferPool.shared.acquire(type: [Int16].self, count: count)
        var floatPixels = BufferPool.shared.acquire(type: [Float].self, count: count)

        // Ensure buffers are released back to pool when done
        defer {
            BufferPool.shared.release(signedPixels)
            BufferPool.shared.release(floatPixels)
        }

        // Copy raw bytes into Int16 buffer with appropriate endianness
        // Note: Buffer may be larger than count due to bucketing, so use only first count elements
        signedPixels.withUnsafeMutableBytes { signedBytes in
            let signedPtr = signedBytes.baseAddress!
            _ = memcpy(signedPtr, sourcePtr, count * 2)

            // Handle big endian byte swapping if needed
            if !littleEndian {
                let int16Ptr = signedPtr.assumingMemoryBound(to: Int16.self)
                for i in 0..<count {
                    int16Ptr[i] = Int16(bigEndian: int16Ptr[i])
                }
            }
        }

        // Convert signed Int16 to Float for vDSP processing
        signedPixels.withUnsafeBufferPointer { signedBuffer in
            vDSP_vflt16(signedBuffer.baseAddress!, 1, &floatPixels, 1, vDSP_Length(count))
        }

        // Add offset to shift signed range [-32768, 32767] to unsigned [0, 65535]
        var offset: Float = 32768.0
        vDSP_vsadd(floatPixels, 1, &offset, &floatPixels, 1, vDSP_Length(count))

        // Clamp to valid range [0, 65535] to handle any edge cases
        var lowerBound: Float = 0.0
        var upperBound: Float = 65535.0
        vDSP_vclip(floatPixels, 1, &lowerBound, &upperBound, &floatPixels, 1, vDSP_Length(count))

        // Convert back to UInt16
        floatPixels.withUnsafeBufferPointer { floatBuffer in
            outputBuffer.withUnsafeMutableBufferPointer { uint16Buffer in
                vDSP_vfixu16(floatBuffer.baseAddress!, 1, uint16Buffer.baseAddress!, 1, vDSP_Length(count))
            }
        }
    }

    /// Vectorized inversion of 16‑bit pixels for MONOCHROME1 photometric
    /// interpretation using Accelerate vDSP operations.  This function
    /// performs the operation: output[i] = 65535 - input[i] using SIMD
    /// operations for optimal performance on large pixel buffers.
    ///
    /// - Parameters:
    ///   - buffer: Buffer of UInt16 pixels to invert in-place
    ///   - count: Number of pixels to invert
    private static func invertMonochrome1Vectorized(
        buffer: inout [UInt16],
        count: Int
    ) {
        // Acquire temporary buffer from pool
        var floatPixels = BufferPool.shared.acquire(type: [Float].self, count: count)

        // Ensure buffer is released back to pool when done
        defer {
            BufferPool.shared.release(floatPixels)
        }

        // Convert UInt16 to Float for vDSP processing
        buffer.withUnsafeBufferPointer { uint16Buffer in
            vDSP_vfltu16(uint16Buffer.baseAddress!, 1, &floatPixels, 1, vDSP_Length(count))
        }

        // Negate values: -input
        vDSP_vneg(floatPixels, 1, &floatPixels, 1, vDSP_Length(count))

        // Add 65535: 65535 + (-input) = 65535 - input
        var offset: Float = 65535.0
        vDSP_vsadd(floatPixels, 1, &offset, &floatPixels, 1, vDSP_Length(count))

        // Clamp to valid range [0, 65535] to handle any edge cases
        var lowerBound: Float = 0.0
        var upperBound: Float = 65535.0
        vDSP_vclip(floatPixels, 1, &lowerBound, &upperBound, &floatPixels, 1, vDSP_Length(count))

        // Convert back to UInt16
        floatPixels.withUnsafeBufferPointer { floatBuffer in
            buffer.withUnsafeMutableBufferPointer { uint16Buffer in
                vDSP_vfixu16(floatBuffer.baseAddress!, 1, uint16Buffer.baseAddress!, 1, vDSP_Length(count))
            }
        }
    }

    /// Vectorized inversion of signed 16‑bit pixels for MONOCHROME1
    /// photometric interpretation using Accelerate vDSP operations.
    /// This function performs the operation:
    /// output[i] = 32768 - (input[i] - 32768) = 65536 - input[i]
    /// which inverts pixel values around the midpoint 32768 for
    /// normalized signed pixels.
    ///
    /// - Parameters:
    ///   - buffer: Buffer of UInt16 pixels to invert in-place
    ///   - count: Number of pixels to invert
    private static func invertMonochrome1SignedVectorized(
        buffer: inout [UInt16],
        count: Int
    ) {
        // Convert UInt16 to Float for vDSP processing
        var floatPixels = [Float](repeating: 0, count: count)
        buffer.withUnsafeBufferPointer { uint16Buffer in
            vDSP_vfltu16(uint16Buffer.baseAddress!, 1, &floatPixels, 1, vDSP_Length(count))
        }

        // Negate values: -input
        vDSP_vneg(floatPixels, 1, &floatPixels, 1, vDSP_Length(count))

        // Add 65536: 65536 + (-input) = 65536 - input
        var offset: Float = 65536.0
        vDSP_vsadd(floatPixels, 1, &offset, &floatPixels, 1, vDSP_Length(count))

        // Clamp to valid range [0, 65535] to handle wrapping
        var lowerBound: Float = 0.0
        var upperBound: Float = 65535.0
        vDSP_vclip(floatPixels, 1, &lowerBound, &upperBound, &floatPixels, 1, vDSP_Length(count))

        // Convert back to UInt16
        floatPixels.withUnsafeBufferPointer { floatBuffer in
            buffer.withUnsafeMutableBufferPointer { uint16Buffer in
                vDSP_vfixu16(floatBuffer.baseAddress!, 1, uint16Buffer.baseAddress!, 1, vDSP_Length(count))
            }
        }
    }

    /// Validates dimensions and computes pixel counts and byte sizes safely.
    /// Returns nil when dimensions are invalid or allocations would be unsafe.
    private static func computePixelMetrics(
        width: Int,
        height: Int,
        bytesPerPixel: Int64,
        context: String,
        logger: LoggerProtocol?
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
    /// Reads pixel data from a DICOM data buffer and produces a DCMPixelReadResult containing decoded pixel arrays and metadata.
    /// - Parameters:
    ///   - data: Source data containing pixel bytes.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - bitDepth: Bits per sample (e.g., 8 or 16).
    ///   - samplesPerPixel: Number of samples per pixel (1 for grayscale, 3 for RGB).
    ///   - offset: Byte offset within `data` where the pixel codestream begins.
    ///   - pixelRepresentation: Pixel value representation: `0` = unsigned, `1` = two's-complement signed.
    ///   - littleEndian: `true` if pixel bytes are in little-endian order, `false` for big-endian.
    ///   - photometricInterpretation: Photometric interpretation string (e.g., "MONOCHROME1" or "MONOCHROME2"); when "MONOCHROME1" grayscale samples are inverted.
    /// - Returns: A DCMPixelReadResult with one of these populated depending on format:
    ///            - `pixels8` for 8-bit grayscale,
    ///            - `pixels16` for 16-bit grayscale (with `signedImage` set when pixelRepresentation == 1),
    ///            - `pixels24` for 24-bit RGB (3 bytes per pixel).
    ///          If the input combination is unsupported or validation fails, the result contains nil buffers and the provided metadata.
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
        logger: LoggerProtocol? = nil
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

            // OPTIMIZATION: Use buffer pool to reduce allocation overhead
            // For very large images (>2048×2048), allocate directly since pool buckets max out
            var pixels: [UInt16]
            var pooledBuffer: [UInt16]? = nil
            if numPixels <= 4194304 { // xlarge bucket size
                pooledBuffer = BufferPool.shared.acquire(type: [UInt16].self, count: numPixels)
                pixels = pooledBuffer!
            } else {
                pixels = Array(repeating: 0, count: numPixels)
            }
            defer {
                // Release pooled buffer back to pool if used
                if let buffer = pooledBuffer {
                    BufferPool.shared.release(buffer)
                }
            }

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
                                // Direct copy for aligned data
                                pixels.withUnsafeMutableBufferPointer { pixelBuffer in
                                    _ = memcpy(pixelBuffer.baseAddress!, uint16Ptr, numBytes)
                                }

                                // Handle MONOCHROME1 inversion if needed using vectorized operations
                                if photometricInterpretation == "MONOCHROME1" {
                                    invertMonochrome1Vectorized(buffer: &pixels, count: numPixels)
                                }
                            }
                        } else {
                            // Unaligned - use optimized vectorized copy
                            // Even though source is unaligned, memcpy handles this efficiently
                            // and the destination buffer is always aligned
                            pixels.withUnsafeMutableBufferPointer { pixelBuffer in
                                _ = memcpy(pixelBuffer.baseAddress!, basePtr, numBytes)
                            }

                            // Handle MONOCHROME1 inversion if needed using vectorized operations
                            if photometricInterpretation == "MONOCHROME1" {
                                invertMonochrome1Vectorized(buffer: &pixels, count: numPixels)
                            }
                        }
                    } else {
                        // Big endian (rare) - use optimized vectorized byte swapping
                        pixels.withUnsafeMutableBufferPointer { pixelBuffer in
                            // First copy data to output buffer (vectorized by system)
                            _ = memcpy(pixelBuffer.baseAddress!, basePtr, numBytes)

                            // Perform in-place byte swapping
                            // Swift's byteSwapped is optimized to use hardware instructions
                            let pixelPtr = pixelBuffer.baseAddress!
                            for i in 0..<numPixels {
                                pixelPtr[i] = pixelPtr[i].byteSwapped
                            }
                        }

                        // Handle MONOCHROME1 inversion if needed using vectorized operations
                        if photometricInterpretation == "MONOCHROME1" {
                            invertMonochrome1Vectorized(buffer: &pixels, count: numPixels)
                        }
                    }
                    result.signedImage = false
                } else {
                    // Signed pixels (less common) - use vectorized conversion
                    result.signedImage = true

                    // Use vectorized normalization for signed pixels
                    normaliseSigned16Vectorized(
                        sourcePtr: basePtr,
                        outputBuffer: &pixels,
                        count: numPixels,
                        littleEndian: littleEndian
                    )

                    // Handle MONOCHROME1 inversion if needed using vectorized operations
                    if photometricInterpretation == "MONOCHROME1" {
                        invertMonochrome1SignedVectorized(buffer: &pixels, count: numPixels)
                    }
                }
            }

            // Copy pixels to result (slice if using pooled buffer to get exact size)
            if let _ = pooledBuffer {
                result.pixels16 = Array(pixels[0..<min(numPixels, pixels.count)])
            } else {
                result.pixels16 = pixels
            }

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

    // MARK: - Range-Based Pixel Reading Methods

    /// Reads a range of 16-bit grayscale pixels from uncompressed DICOM data.
    /// This method enables streaming access by reading only the requested
    /// pixel range instead of the entire image buffer.
    ///
    /// - Parameters:
    ///   - data: Raw DICOM file data
    ///   - range: Range of pixel indices to read (e.g., 0..<100 for first 100 pixels)
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    ///   - offset: Byte offset to start of pixel data in file
    ///   - pixelRepresentation: 0 for unsigned, 1 for two's complement signed
    ///   - littleEndian: True for little endian byte order
    ///   - photometricInterpretation: MONOCHROME1 or MONOCHROME2
    ///   - logger: Optional logger for performance metrics
    /// Reads a contiguous range of 16-bit grayscale pixels from DICOM pixel data.
    /// - Parameters:
    ///   - data: The raw pixel data buffer.
    ///   - range: The pixel index range (0-based) to read from the image (inclusive lower bound, exclusive upper bound).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - offset: Byte offset in `data` where pixel data starts.
    ///   - pixelRepresentation: 0 for unsigned pixel samples, 1 for signed pixel samples; used to determine interpretation and normalization.
    ///   - littleEndian: `true` if stored pixel pairs are little-endian, `false` for big-endian.
    ///   - photometricInterpretation: Photometric interpretation string (e.g., `"MONOCHROME1"` or `"MONOCHROME2"`); affects value inversion for `MONOCHROME1`.
    ///   - logger: Optional logger for warnings and performance debug messages (may be omitted).
    /// - Returns: A `DCMPixelReadResult` whose `pixels16` contains the requested 16-bit pixel values and whose metadata (width, height, bitDepth=16, samplesPerPixel=1, `signedImage`) reflects the read; returns `nil` if dimensions, range, or data bounds are invalid.
    internal static func readPixels16(
        data: Data,
        range: Range<Int>,
        width: Int,
        height: Int,
        offset: Int,
        pixelRepresentation: Int,
        littleEndian: Bool,
        photometricInterpretation: String,
        logger: LoggerProtocol? = nil
    ) -> DCMPixelReadResult? {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard computePixelMetrics(
            width: width,
            height: height,
            bytesPerPixel: 2,
            context: "16-bit grayscale (range)",
            logger: logger
        ) != nil else {
            return nil
        }

        let width64 = Int64(width)
        let height64 = Int64(height)
        let (totalPixels64, totalOverflow) = width64.multipliedReportingOverflow(by: height64)
        guard !totalOverflow && totalPixels64 > 0 else {
            logger?.warning("Pixel count overflow for range: width=\(width), height=\(height)")
            return nil
        }
        guard totalPixels64 <= Int64(Int.max) else {
            logger?.warning("Pixel count exceeds addressable range for range: \(totalPixels64)")
            return nil
        }

        // Validate range
        let lower64 = Int64(range.lowerBound)
        let upper64 = Int64(range.upperBound)
        guard lower64 >= 0, upper64 <= totalPixels64 else {
            logger?.warning("Range out of bounds: \(range) (total pixels: \(totalPixels64))")
            return nil
        }
        guard upper64 > lower64 else {
            logger?.warning("Empty range requested")
            return nil
        }

        let rangeCount64 = upper64 - lower64
        guard rangeCount64 <= Int64(Int.max) else {
            logger?.warning("Range size exceeds addressable range: \(range)")
            return nil
        }

        let bytesPerPixel64: Int64 = 2
        let (rangeBytes64, rangeBytesOverflow) = rangeCount64.multipliedReportingOverflow(by: bytesPerPixel64)
        let (pixelOffset64, pixelOffsetOverflow) = lower64.multipliedReportingOverflow(by: bytesPerPixel64)
        let (rangeByteOffset64, offsetOverflow) = Int64(offset).addingReportingOverflow(pixelOffset64)
        guard !rangeBytesOverflow && !pixelOffsetOverflow && !offsetOverflow else {
            logger?.warning("Byte offset overflow for range: \(range)")
            return nil
        }
        guard rangeBytes64 <= Int64(Int.max), rangeByteOffset64 <= Int64(Int.max) else {
            logger?.warning("Byte offset exceeds addressable range for range: \(range)")
            return nil
        }

        // Validate data availability
        let dataCount64 = Int64(data.count)
        guard rangeByteOffset64 >= 0,
              rangeByteOffset64 <= dataCount64,
              rangeBytes64 <= dataCount64 - rangeByteOffset64 else {
            let available = max(Int64(0), dataCount64 - rangeByteOffset64)
            logger?.warning("Invalid range offset or insufficient data. offset=\(rangeByteOffset64), needed=\(rangeBytes64), available=\(available)")
            return nil
        }

        let rangeCount = Int(rangeCount64)
        let rangeBytes = Int(rangeBytes64)
        let rangeByteOffset = Int(rangeByteOffset64)

        var result = DCMPixelReadResult(
            pixels8: nil,
            pixels16: nil,
            pixels24: nil,
            signedImage: pixelRepresentation == 1,
            width: width,
            height: height,
            bitDepth: 16,
            samplesPerPixel: 1
        )

        // Acquire buffer from pool for requested range
        // For very large ranges (>2048×2048), allocate directly
        var pixels: [UInt16]
        var pooledBuffer: [UInt16]? = nil
        if rangeCount <= 4194304 { // xlarge bucket size
            pooledBuffer = BufferPool.shared.acquire(type: [UInt16].self, count: rangeCount)
            pixels = pooledBuffer!
        } else {
            pixels = Array(repeating: 0, count: rangeCount)
        }
        defer {
            if let buffer = pooledBuffer {
                BufferPool.shared.release(buffer)
            }
        }

        data.withUnsafeBytes { dataBytes in
            let basePtr = dataBytes.baseAddress!.advanced(by: rangeByteOffset)

            if pixelRepresentation == 0 {
                // Unsigned pixels - most common for CR/DX
                if littleEndian {
                    // Little endian (most common)
                    if rangeByteOffset % 2 == 0 {
                        // Aligned - can use fast path
                        basePtr.withMemoryRebound(to: UInt16.self, capacity: rangeCount) { uint16Ptr in
                            // Direct copy for aligned data
                            pixels.withUnsafeMutableBufferPointer { pixelBuffer in
                                _ = memcpy(pixelBuffer.baseAddress!, uint16Ptr, rangeBytes)
                            }

                            // Handle MONOCHROME1 inversion if needed using vectorized operations
                            if photometricInterpretation == "MONOCHROME1" {
                                invertMonochrome1Vectorized(buffer: &pixels, count: rangeCount)
                            }
                        }
                    } else {
                        // Unaligned - use optimized vectorized copy
                        // Even though source is unaligned, memcpy handles this efficiently
                        // and the destination buffer is always aligned
                        pixels.withUnsafeMutableBufferPointer { pixelBuffer in
                            _ = memcpy(pixelBuffer.baseAddress!, basePtr, rangeBytes)
                        }

                        // Handle MONOCHROME1 inversion if needed using vectorized operations
                        if photometricInterpretation == "MONOCHROME1" {
                            invertMonochrome1Vectorized(buffer: &pixels, count: rangeCount)
                        }
                    }
                } else {
                    // Big endian (rare) - use optimized vectorized byte swapping
                    pixels.withUnsafeMutableBufferPointer { pixelBuffer in
                        // First copy data to output buffer (vectorized by system)
                        _ = memcpy(pixelBuffer.baseAddress!, basePtr, rangeBytes)

                        // Perform in-place byte swapping
                        // Swift's byteSwapped is optimized to use hardware instructions
                        let pixelPtr = pixelBuffer.baseAddress!
                        for i in 0..<rangeCount {
                            pixelPtr[i] = pixelPtr[i].byteSwapped
                        }
                    }

                    // Handle MONOCHROME1 inversion if needed using vectorized operations
                    if photometricInterpretation == "MONOCHROME1" {
                        invertMonochrome1Vectorized(buffer: &pixels, count: rangeCount)
                    }
                }
            } else {
                // Signed pixels (less common) - use vectorized conversion
                normaliseSigned16Vectorized(
                    sourcePtr: basePtr,
                    outputBuffer: &pixels,
                    count: rangeCount,
                    littleEndian: littleEndian
                )

                // Handle MONOCHROME1 inversion if needed using vectorized operations
                if photometricInterpretation == "MONOCHROME1" {
                    invertMonochrome1SignedVectorized(buffer: &pixels, count: rangeCount)
                }
            }
        }

        // Copy pixels to result (slice if using pooled buffer to get exact size)
        if let _ = pooledBuffer {
            result.pixels16 = Array(pixels[0..<min(rangeCount, pixels.count)])
        } else {
            result.pixels16 = pixels
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        logger?.debug("[PERF] readPixels16 (range): \(String(format: "%.2f", elapsed))ms | range: \(range.lowerBound)..<\(range.upperBound) | size: \(width)x\(height)")
        return result
    }

    /// Reads a range of 8-bit grayscale pixels from uncompressed DICOM data.
    /// This method enables streaming access by reading only the requested
    /// pixel range instead of the entire image buffer.
    ///
    /// - Parameters:
    ///   - data: Raw DICOM file data
    ///   - range: Range of pixel indices to read (e.g., 0..<100 for first 100 pixels)
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    ///   - offset: Byte offset to start of pixel data in file
    ///   - photometricInterpretation: MONOCHROME1 or MONOCHROME2
    ///   - logger: Optional logger for performance metrics
    /// Reads a contiguous range of 8-bit grayscale pixels for a single-frame image and returns them as a DCMPixelReadResult.
    /// 
    /// The returned result contains the requested pixels in `pixels8`. If `photometricInterpretation` equals `"MONOCHROME1"`,
    /// pixel values are inverted (255 - value). The function validates image dimensions, range bounds, and data availability and
    /// returns `nil` if any validation fails.
    ///
    /// - Parameters:
    ///   - data: The source Data containing pixel bytes (frame codestream) starting at `offset`.
    ///   - range: The half-open range of pixel indices to read (0-based, upperBound exclusive).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - offset: Byte offset into `data` that corresponds to the first pixel of the frame.
    ///   - photometricInterpretation: Photometric interpretation string; supports `"MONOCHROME1"` (inverted) and other values (copied as-is).
    /// - Returns: A `DCMPixelReadResult` with `pixels8` populated with the requested bytes, or `nil` if validation or bounds checks fail.
    internal static func readPixels8(
        data: Data,
        range: Range<Int>,
        width: Int,
        height: Int,
        offset: Int,
        photometricInterpretation: String,
        logger: LoggerProtocol? = nil
    ) -> DCMPixelReadResult? {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard computePixelMetrics(
            width: width,
            height: height,
            bytesPerPixel: 1,
            context: "8-bit grayscale (range)",
            logger: logger
        ) != nil else {
            return nil
        }

        let width64 = Int64(width)
        let height64 = Int64(height)
        let (totalPixels64, totalOverflow) = width64.multipliedReportingOverflow(by: height64)
        guard !totalOverflow && totalPixels64 > 0 else {
            logger?.warning("Pixel count overflow for range: width=\(width), height=\(height)")
            return nil
        }
        guard totalPixels64 <= Int64(Int.max) else {
            logger?.warning("Pixel count exceeds addressable range for range: \(totalPixels64)")
            return nil
        }

        // Validate range
        let lower64 = Int64(range.lowerBound)
        let upper64 = Int64(range.upperBound)
        guard lower64 >= 0, upper64 <= totalPixels64 else {
            logger?.warning("Range out of bounds: \(range) (total pixels: \(totalPixels64))")
            return nil
        }
        guard upper64 > lower64 else {
            logger?.warning("Empty range requested")
            return nil
        }

        let rangeCount64 = upper64 - lower64
        guard rangeCount64 <= Int64(Int.max) else {
            logger?.warning("Range size exceeds addressable range: \(range)")
            return nil
        }

        let bytesPerPixel64: Int64 = 1
        let (rangeBytes64, rangeBytesOverflow) = rangeCount64.multipliedReportingOverflow(by: bytesPerPixel64)
        let (pixelOffset64, pixelOffsetOverflow) = lower64.multipliedReportingOverflow(by: bytesPerPixel64)
        let (rangeByteOffset64, offsetOverflow) = Int64(offset).addingReportingOverflow(pixelOffset64)
        guard !rangeBytesOverflow && !pixelOffsetOverflow && !offsetOverflow else {
            logger?.warning("Byte offset overflow for range: \(range)")
            return nil
        }
        guard rangeBytes64 <= Int64(Int.max), rangeByteOffset64 <= Int64(Int.max) else {
            logger?.warning("Byte offset exceeds addressable range for range: \(range)")
            return nil
        }

        // Validate data availability
        let dataCount64 = Int64(data.count)
        guard rangeByteOffset64 >= 0,
              rangeByteOffset64 <= dataCount64,
              rangeBytes64 <= dataCount64 - rangeByteOffset64 else {
            let available = max(Int64(0), dataCount64 - rangeByteOffset64)
            logger?.warning("Invalid range offset or insufficient data. offset=\(rangeByteOffset64), needed=\(rangeBytes64), available=\(available)")
            return nil
        }

        let rangeCount = Int(rangeCount64)
        let rangeBytes = Int(rangeBytes64)
        let rangeByteOffset = Int(rangeByteOffset64)

        var result = DCMPixelReadResult(
            pixels8: nil,
            pixels16: nil,
            pixels24: nil,
            signedImage: false,
            width: width,
            height: height,
            bitDepth: 8,
            samplesPerPixel: 1
        )

        // Acquire buffer from pool for requested range
        // For very large ranges (>2048×2048), allocate directly
        var pixels: [UInt8]
        var pooledBuffer: [UInt8]? = nil
        if rangeCount <= 4194304 { // xlarge bucket size
            pooledBuffer = BufferPool.shared.acquire(type: [UInt8].self, count: rangeCount)
            pixels = pooledBuffer!
        } else {
            pixels = Array(repeating: 0, count: rangeCount)
        }
        defer {
            if let buffer = pooledBuffer {
                BufferPool.shared.release(buffer)
            }
        }

        // Use withUnsafeBytes for efficient memory-mapped access
        data.withUnsafeBytes { dataBytes in
            let basePtr = dataBytes.baseAddress!.advanced(by: rangeByteOffset)
            let uint8Ptr = basePtr.assumingMemoryBound(to: UInt8.self)

            if photometricInterpretation == "MONOCHROME1" {
                // Invert for MONOCHROME1 (white is zero) - common for X-rays
                for i in 0..<rangeCount {
                    pixels[i] = 255 - uint8Ptr[i]
                }
            } else {
                // Direct copy for MONOCHROME2
                pixels.withUnsafeMutableBufferPointer { pixelBuffer in
                    _ = memcpy(pixelBuffer.baseAddress!, uint8Ptr, rangeBytes)
                }
            }
        }

        // Copy pixels to result (slice if using pooled buffer to get exact size)
        if let _ = pooledBuffer {
            result.pixels8 = Array(pixels[0..<min(rangeCount, pixels.count)])
        } else {
            result.pixels8 = pixels
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        logger?.debug("[PERF] readPixels8 (range): \(String(format: "%.2f", elapsed))ms | range: \(range.lowerBound)..<\(range.upperBound) | size: \(width)x\(height)")
        return result
    }

    /// Reads a range of 24-bit RGB pixels from uncompressed DICOM data.
    /// This method enables streaming access by reading only the requested
    /// pixel range instead of the entire image buffer.
    ///
    /// - Parameters:
    ///   - data: Raw DICOM file data
    ///   - range: Range of pixel indices to read (e.g., 0..<100 for first 100 pixels)
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    ///   - offset: Byte offset to start of pixel data in file
    ///   - logger: Optional logger for performance metrics
    /// Reads a contiguous range of 24-bit RGB pixels from raw image data.
    /// - Parameters:
    ///   - data: Source byte buffer containing interleaved RGB pixel data.
    ///   - range: 0-based range of pixel indices to read (each pixel is three bytes).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - offset: Byte offset within `data` where the image pixel data begins.
    ///   - logger: Optional logger for warnings and performance diagnostics (may be nil).
    /// - Returns: A `DCMPixelReadResult` whose `pixels24` contains `3 * range.count` bytes (RGB triples) for the requested range, or `nil` if dimensions are invalid, the range is out of bounds, or there is insufficient data.
    internal static func readPixels24(
        data: Data,
        range: Range<Int>,
        width: Int,
        height: Int,
        offset: Int,
        logger: LoggerProtocol? = nil
    ) -> DCMPixelReadResult? {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard computePixelMetrics(
            width: width,
            height: height,
            bytesPerPixel: 3,
            context: "24-bit RGB (range)",
            logger: logger
        ) != nil else {
            return nil
        }

        let width64 = Int64(width)
        let height64 = Int64(height)
        let (totalPixels64, totalOverflow) = width64.multipliedReportingOverflow(by: height64)
        guard !totalOverflow && totalPixels64 > 0 else {
            logger?.warning("Pixel count overflow for range: width=\(width), height=\(height)")
            return nil
        }
        guard totalPixels64 <= Int64(Int.max) else {
            logger?.warning("Pixel count exceeds addressable range for range: \(totalPixels64)")
            return nil
        }

        // Validate range
        let lower64 = Int64(range.lowerBound)
        let upper64 = Int64(range.upperBound)
        guard lower64 >= 0, upper64 <= totalPixels64 else {
            logger?.warning("Range out of bounds: \(range) (total pixels: \(totalPixels64))")
            return nil
        }
        guard upper64 > lower64 else {
            logger?.warning("Empty range requested")
            return nil
        }

        let rangeCount64 = upper64 - lower64
        guard rangeCount64 <= Int64(Int.max) else {
            logger?.warning("Range size exceeds addressable range: \(range)")
            return nil
        }

        let bytesPerPixel64: Int64 = 3
        let (rangeBytes64, rangeBytesOverflow) = rangeCount64.multipliedReportingOverflow(by: bytesPerPixel64)
        let (pixelOffset64, pixelOffsetOverflow) = lower64.multipliedReportingOverflow(by: bytesPerPixel64)
        let (rangeByteOffset64, offsetOverflow) = Int64(offset).addingReportingOverflow(pixelOffset64)
        guard !rangeBytesOverflow && !pixelOffsetOverflow && !offsetOverflow else {
            logger?.warning("Byte offset overflow for range: \(range)")
            return nil
        }
        guard rangeBytes64 <= Int64(Int.max), rangeByteOffset64 <= Int64(Int.max) else {
            logger?.warning("Byte offset exceeds addressable range for range: \(range)")
            return nil
        }

        // Validate data availability
        let dataCount64 = Int64(data.count)
        guard rangeByteOffset64 >= 0,
              rangeByteOffset64 <= dataCount64,
              rangeBytes64 <= dataCount64 - rangeByteOffset64 else {
            let available = max(Int64(0), dataCount64 - rangeByteOffset64)
            logger?.warning("Invalid range offset or insufficient data. offset=\(rangeByteOffset64), needed=\(rangeBytes64), available=\(available)")
            return nil
        }

        let rangeBytes = Int(rangeBytes64)
        let rangeByteOffset = Int(rangeByteOffset64)

        var result = DCMPixelReadResult(
            pixels8: nil,
            pixels16: nil,
            pixels24: nil,
            signedImage: false,
            width: width,
            height: height,
            bitDepth: 8,
            samplesPerPixel: 3
        )

        // Acquire buffer from pool for requested range
        // For very large ranges (>2048×2048×3), allocate directly
        var pixels: [UInt8]
        var pooledBuffer: [UInt8]? = nil
        if rangeBytes <= 12582912 { // xlarge bucket size * 3 for RGB
            pooledBuffer = BufferPool.shared.acquire(type: [UInt8].self, count: rangeBytes)
            pixels = pooledBuffer!
        } else {
            pixels = Array(repeating: 0, count: rangeBytes)
        }
        defer {
            if let buffer = pooledBuffer {
                BufferPool.shared.release(buffer)
            }
        }

        // Use withUnsafeBytes for efficient memory-mapped access
        data.withUnsafeBytes { dataBytes in
            let basePtr = dataBytes.baseAddress!.advanced(by: rangeByteOffset)
            let uint8Ptr = basePtr.assumingMemoryBound(to: UInt8.self)

            // Direct copy of RGB bytes
            pixels.withUnsafeMutableBufferPointer { pixelBuffer in
                _ = memcpy(pixelBuffer.baseAddress!, uint8Ptr, rangeBytes)
            }
        }

        // Copy pixels to result (slice if using pooled buffer to get exact size)
        if let _ = pooledBuffer {
            result.pixels24 = Array(pixels[0..<min(rangeBytes, pixels.count)])
        } else {
            result.pixels24 = pixels
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        logger?.debug("[PERF] readPixels24 (range): \(String(format: "%.2f", elapsed))ms | range: \(range.lowerBound)..<\(range.upperBound) | size: \(width)x\(height)")
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
        logger: LoggerProtocol? = nil
    ) -> DCMPixelReadResult? {
        // Extract the encapsulated pixel data from the offset to
        // the end of the file.  Some DICOM files encapsulate each
        // frame into separate items; for simplicity we treat the
        // entire remaining data as one JPEG/JP2 codestream.  For
        // robust handling you would need to parse the Basic Offset
        // Table and items (see PS3.5).  This implementation is
        // designed to handle single–frame images.
        let compressedData = data.subdata(in: offset..<data.count)

        // Check if this is JPEG Lossless format (SOF3 marker 0xFFC3)
        // JPEG files start with SOI marker 0xFFD8
        if compressedData.count >= 2,
           compressedData[0] == 0xFF,
           compressedData[1] == 0xD8 {
            // This is a JPEG file, check for JPEG Lossless (SOF3) marker
            if isJPEGLossless(data: compressedData) {
                // JPEG Lossless detected - use dedicated decoder
                let decoder = JPEGLosslessDecoder()
                do {
                    let losslessResult = try decoder.decode(data: compressedData)

                    // Convert JPEGLosslessDecodeResult to DCMPixelReadResult
                    let result = DCMPixelReadResult(
                        pixels8: nil,
                        pixels16: losslessResult.pixels,
                        pixels24: nil,
                        signedImage: false,
                        width: losslessResult.width,
                        height: losslessResult.height,
                        bitDepth: losslessResult.bitDepth,
                        samplesPerPixel: 1
                    )
                    return result
                } catch {
                    logger?.warning("JPEG Lossless decoding failed: \(error)")
                    return nil
                }
            }
        }

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

    /// Detects if the compressed data is JPEG Lossless format by scanning for the SOF3 marker (0xFFC3).
    /// JPEG Lossless uses a different decoding algorithm than standard JPEG and must be handled separately.
    ///
    /// - Parameter data: Compressed JPEG data starting with SOI marker (0xFFD8)
    /// - Returns: True if SOF3 marker is found, indicating JPEG Lossless format
    private static func isJPEGLossless(data: Data) -> Bool {
        var index = 2  // Skip SOI marker (0xFFD8)

        while index + 1 < data.count {
            // Find next marker (all JPEG markers start with 0xFF)
            if data[index] != 0xFF {
                index += 1
                continue
            }

            let markerCode = data[index + 1]

            // Check for SOF3 marker (0xC3) - indicates JPEG Lossless (Process 14)
            if markerCode == 0xC3 {
                return true
            }

            // Check for SOS marker (0xDA) - if we reach this without SOF3, it's not lossless
            if markerCode == 0xDA {
                return false
            }

            // Skip over marker segment
            if markerCode == 0xD8 || markerCode == 0xD9 {
                // SOI/EOI markers have no length field
                index += 2
            } else if index + 3 < data.count {
                // Read segment length (big endian, includes length field itself)
                let length = Int(data[index + 2]) << 8 | Int(data[index + 3])
                index += 2 + length
            } else {
                // Not enough data for length field
                break
            }
        }

        return false
    }
}
