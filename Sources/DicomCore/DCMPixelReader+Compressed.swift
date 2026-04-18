//
//  DCMPixelReader+Compressed.swift
//
//  Compressed pixel decoding helpers for DCMPixelReader.
//

import Foundation
import CoreGraphics
import ImageIO

extension DCMPixelReader {

    /// Decode compressed image bytes starting at `offset` and produce a `DCMPixelReadResult`.
    /// 
    /// Detects JPEG Lossless streams and decodes them into 16-bit pixel data; for other formats it uses ImageIO/Core Graphics to decode into either 8-bit grayscale (`pixels8`) or packed 24-bit RGB (`pixels24`). Returns `nil` when the data cannot be parsed, decoded, or rendered into a pixel buffer (for example: invalid image source, failed decode, or inability to create/get CGContext data).
    /// - Parameters:
    ///   - data: The full data buffer containing the compressed image bytes.
    ///   - offset: The byte index within `data` where the compressed image begins.
    ///   - pixelRepresentation: DICOM Pixel Representation value (`1` for signed pixel data).
    ///   - logger: An optional logger for warning messages when decoding fails.
    /// - Returns: A `DCMPixelReadResult` populated with decoded pixels and image metadata, or `nil` if decoding failed.
    internal static func decodeCompressedPixelData(
        data: Data,
        offset: Int,
        pixelRepresentation: Int = 0,
        logger: LoggerProtocol? = nil
    ) -> DCMPixelReadResult? {
        guard offset > 0, offset <= data.count else {
            logger?.warning("Invalid compressed pixel data offset: \(offset) (data count: \(data.count))")
            return nil
        }

        let compressedData = data.subdata(in: offset..<data.count)
        let signedImage = pixelRepresentation == 1

        if compressedData.count >= 2,
           compressedData[0] == 0xFF,
           compressedData[1] == 0xD8,
           isJPEGLossless(data: compressedData) {
            let decoder = JPEGLosslessDecoder()
            do {
                let losslessResult = try decoder.decode(data: compressedData)
                return DCMPixelReadResult(
                    pixels8: nil,
                    pixels16: losslessResult.pixels,
                    pixels24: nil,
                    signedImage: signedImage,
                    width: losslessResult.width,
                    height: losslessResult.height,
                    bitDepth: losslessResult.bitDepth,
                    samplesPerPixel: 1
                )
            } catch {
                logger?.warning("JPEG Lossless decoding failed: \(error)")
                return nil
            }
        }

        guard let source = CGImageSourceCreateWithData(compressedData as CFData, nil) else {
            logger?.warning("Failed to create image source from compressed data")
            return nil
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            logger?.warning("Failed to decode image from source")
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bitDepth = cgImage.bitsPerComponent
        let samples = max(1, cgImage.bitsPerPixel / cgImage.bitsPerComponent)
        let samplesPerPixel = samples >= 3 ? 3 : 1
        guard bitDepth <= 8 else {
            logger?.warning("ImageIO fallback does not support >8-bit compressed output. Found \(bitDepth)-bit components")
            return nil
        }

        var result = DCMPixelReadResult(
            pixels8: nil,
            pixels16: nil,
            pixels24: nil,
            signedImage: signedImage,
            width: width,
            height: height,
            bitDepth: bitDepth,
            samplesPerPixel: samplesPerPixel
        )

        if samplesPerPixel == 1 {
            let colorSpace = CGColorSpaceCreateDeviceGray()
            let bytesPerRow = width
            guard let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                logger?.warning("Failed to create grayscale context")
                return nil
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let dataPtr = ctx.data else {
                logger?.warning("Failed to get context data pointer")
                return nil
            }
            let buffer = dataPtr.assumingMemoryBound(to: UInt8.self)
            result.pixels8 = [UInt8](UnsafeBufferPointer(start: buffer, count: width * height))
        } else {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let bytesPerRow = width * bytesPerPixel
            let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            guard let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
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
            var output = [UInt8](repeating: 0, count: count * 3)
            for i in 0..<count {
                let srcIndex = i * 4
                let dstIndex = i * 3
                output[dstIndex] = rawBuffer[srcIndex]
                output[dstIndex + 1] = rawBuffer[srcIndex + 1]
                output[dstIndex + 2] = rawBuffer[srcIndex + 2]
            }
            result.pixels24 = output
        }

        return result
    }

    /// Detects whether JPEG data uses the Lossless (SOF3) encoding.
    /// 
    /// Scans JPEG markers starting at byte index 2 and returns `true` if a Start Of Frame 3 (marker `0xC3`) is encountered before the Start Of Scan marker (`0xDA`); returns `false` if the scan ends or `0xDA` is reached first.
    /// - Returns: `true` if the JPEG stream contains a lossless SOF3 (`0xC3`) marker before SOS (`0xDA`), `false` otherwise.
    private static func isJPEGLossless(data: Data) -> Bool {
        var index = 2

        while index + 1 < data.count {
            if data[index] != 0xFF {
                index += 1
                continue
            }

            let markerCode = data[index + 1]
            if markerCode == 0xC3 {
                return true
            }
            if markerCode == 0xDA {
                return false
            }

            if markerCode == 0xD8 || markerCode == 0xD9 {
                index += 2
            } else if index + 3 < data.count {
                let length = Int(data[index + 2]) << 8 | Int(data[index + 3])
                index += 2 + length
            } else {
                break
            }
        }

        return false
    }
}
