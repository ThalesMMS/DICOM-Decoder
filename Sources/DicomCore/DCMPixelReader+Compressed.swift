//
//  DCMPixelReader+Compressed.swift
//
//  Compressed pixel decoding helpers for DCMPixelReader.
//

import Foundation
import CoreGraphics
import ImageIO

internal enum DicomCompressedPixelBackend: Equatable {
    case nativeJPEGLossless
    case nativeRLELossless
    case nativeJPEGLS
    case nativeJPEGExtended
    case imageIOJPEGBaseline
    case imageIOJPEGExtended
    case imageIOJPEG2000
    case openJPEG2000
    case openJPEGHTJ2K
    case legacyImageIO
    case unsupported
}

internal struct DicomCompressedPixelBackendDecision: Equatable {
    let backend: DicomCompressedPixelBackend
    let diagnostics: [String]
}

internal enum DicomCompressedPixelBackendResolver {
    static func resolve(
        transferSyntax: DicomTransferSyntax?,
        requestedBitDepth: Int?,
        samplesPerPixel: Int?,
        photometricInterpretation: String? = nil,
        bitsStored: Int? = nil
    ) -> DicomCompressedPixelBackendDecision {
        guard let transferSyntax else {
            return DicomCompressedPixelBackendDecision(backend: .legacyImageIO, diagnostics: [])
        }

        let componentContext = multiComponentContext(
            photometricInterpretation: photometricInterpretation,
            samplesPerPixel: samplesPerPixel
        )

        switch transferSyntax {
        case .rleLossless:
            return DicomCompressedPixelBackendDecision(backend: .nativeRLELossless, diagnostics: [])
        case .jpegLSLossless, .jpegLSNearLossless:
            if let samplesPerPixel, samplesPerPixel > 1, let requestedBitDepth, requestedBitDepth > 8 {
                return unsupported(
                    "JPEG-LS multi-component output above 8 bits per component is unsupported (\(componentContext))."
                )
            }
            return DicomCompressedPixelBackendDecision(backend: .nativeJPEGLS, diagnostics: [])
        case .jpegLossless, .jpegLosslessFirstOrder:
            if let samplesPerPixel, samplesPerPixel > 1 {
                let storedBits = bitsStored ?? requestedBitDepth
                let photometric = photometricInterpretation?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if samplesPerPixel == 3, photometric == "RGB", let storedBits, storedBits <= 8 {
                    // Interleaved 8-bit RGB is the unambiguous color shape:
                    // the decoded planes map directly onto the DICOM pixel
                    // model without a color-space conversion.
                    return DicomCompressedPixelBackendDecision(backend: .nativeJPEGLossless, diagnostics: [])
                }
                return unsupported(
                    "\(transferSyntax.registryEntry.name) (transfer syntax \(transferSyntax.rawValue)) multi-component"
                        + " decode supports 8-bit interleaved RGB only; \(storedBits.map { "\($0)-bit" } ?? "unknown-depth")"
                        + " output for \(componentContext) has no unambiguous mapping."
                )
            }
            return DicomCompressedPixelBackendDecision(backend: .nativeJPEGLossless, diagnostics: [])
        case .jpegBaseline:
            if let requestedBitDepth, requestedBitDepth > 8 {
                return unsupported(
                    "JPEG Baseline (Process 1) is limited to 8-bit output; refusing \(requestedBitDepth)-bit decode to avoid precision loss."
                )
            }
            return DicomCompressedPixelBackendDecision(backend: .imageIOJPEGBaseline, diagnostics: [])
        case .jpegExtended:
            // Sample precision comes from BitsStored: 12-bit JPEG Extended
            // files declare BitsAllocated=16 with BitsStored=12.
            guard let storedBits = bitsStored ?? requestedBitDepth else {
                return unsupported(
                    "JPEG Extended (Process 2 and 4) decode requires DICOM bit-depth metadata before selecting a backend."
                )
            }
            if storedBits > 12 {
                return unsupported(
                    "JPEG Extended (Process 2 and 4, transfer syntax \(transferSyntax.rawValue)) caps sample"
                        + " precision at 12 bits; \(storedBits)-bit output is not representable"
                        + " (\(componentContext))."
                )
            }
            if storedBits > 8 {
                if let samplesPerPixel, samplesPerPixel > 1 {
                    return unsupported(
                        "JPEG Extended (Process 2 and 4, transfer syntax \(transferSyntax.rawValue))"
                            + " \(storedBits)-bit decode supports single-component grayscale only;"
                            + " no precision-preserving backend exists for \(componentContext)."
                    )
                }
                return DicomCompressedPixelBackendDecision(backend: .nativeJPEGExtended, diagnostics: [])
            }
            return DicomCompressedPixelBackendDecision(backend: .imageIOJPEGExtended, diagnostics: [])
        case .jpeg2000Lossless, .jpeg2000:
            if let requestedBitDepth, requestedBitDepth > 16 {
                return unsupported(
                    "JPEG 2000 \(requestedBitDepth)-bit output exceeds the supported 16-bit grayscale backend path."
                )
            }
            if let samplesPerPixel, samplesPerPixel > 1, let requestedBitDepth, requestedBitDepth > 8 {
                return unsupported(
                    "JPEG 2000 color output above 8 bits per component has no precision-preserving backend path "
                        + "(\(componentContext))."
                )
            }
            if DicomJPEG2000Codec.isAvailable {
                return DicomCompressedPixelBackendDecision(backend: .openJPEG2000, diagnostics: [])
            }
            if let requestedBitDepth, requestedBitDepth > 8 {
                return unsupported(
                    "JPEG 2000 >8-bit output requires the OpenJPEG runtime library; refusing ImageIO fallback."
                )
            }
            return DicomCompressedPixelBackendDecision(backend: .imageIOJPEG2000, diagnostics: [])
        case .jpeg2000Part2MulticomponentLossless, .jpeg2000Part2Multicomponent:
            return unsupported(
                "\(transferSyntax.registryEntry.name) stores frames as a multi-component volume "
                    + "(\(componentContext)); use DicomJP3DVolumeDocument to decode the volume buffer."
            )
        case .jpipReferenced, .jpipReferencedDeflate:
            return unsupported(
                "\(transferSyntax.registryEntry.name) references remote pixel data; use DicomJPIPClient to stream progressive updates."
            )
        case .mpeg2MainProfileMainLevel,
             .mpeg2MainProfileMainLevelFragmentable,
             .mpeg2MainProfileHighLevel,
             .mpeg2MainProfileHighLevelFragmentable,
             .mpeg4AVCH264HighProfileLevel41,
             .mpeg4AVCH264HighProfileLevel41Fragmentable,
             .mpeg4AVCH264BDCompatibleHighProfileLevel41,
             .mpeg4AVCH264BDCompatibleHighProfileLevel41Fragmentable,
             .mpeg4AVCH264HighProfileLevel42For2DVideo,
             .mpeg4AVCH264HighProfileLevel42For2DVideoFragmentable,
             .mpeg4AVCH264HighProfileLevel42For3DVideo,
             .mpeg4AVCH264HighProfileLevel42For3DVideoFragmentable,
             .mpeg4AVCH264StereoHighProfileLevel42,
             .mpeg4AVCH264StereoHighProfileLevel42Fragmentable,
             .hevcH265MainProfileLevel51,
             .hevcH265Main10ProfileLevel51:
            return unsupported(
                "\(transferSyntax.registryEntry.name) stores an encoded video stream; use DicomVideo to forward it to a video player."
            )
        case .htj2kLossless, .htj2kLosslessRPCL, .htj2k:
            if let reason = DicomJPEG2000Codec.htj2kUnsupportedReason() {
                return unsupported(
                    "\(transferSyntax.registryEntry.name) (transfer syntax \(transferSyntax.rawValue)) \(reason)"
                        + " ImageIO JPEG 2000 fallback is not used for HTJ2K."
                )
            }
            // Same pipeline limits as classic JPEG 2000 output buffers.
            if let requestedBitDepth, requestedBitDepth > 16 {
                return unsupported(
                    "HTJ2K \(requestedBitDepth)-bit output exceeds the supported 16-bit grayscale backend path."
                )
            }
            if let samplesPerPixel, samplesPerPixel > 1, let requestedBitDepth, requestedBitDepth > 8 {
                return unsupported(
                    "HTJ2K color output above 8 bits per component has no precision-preserving backend path "
                        + "(\(componentContext))."
                )
            }
            return DicomCompressedPixelBackendDecision(backend: .openJPEGHTJ2K, diagnostics: [])
        case .implicitVRLittleEndian, .explicitVRLittleEndian, .deflatedExplicitVRLittleEndian, .explicitVRBigEndian:
            return unsupported("Transfer syntax \(transferSyntax.rawValue) is not compressed.")
        }
    }

    private static func unsupported(_ diagnostic: String) -> DicomCompressedPixelBackendDecision {
        DicomCompressedPixelBackendDecision(backend: .unsupported, diagnostics: [diagnostic])
    }

    private static func multiComponentContext(
        photometricInterpretation: String?,
        samplesPerPixel: Int?
    ) -> String {
        let photometric = photometricInterpretation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let photometricValue: String
        if let photometric, !photometric.isEmpty {
            photometricValue = photometric
        } else {
            photometricValue = "unknown"
        }
        let samplesValue = samplesPerPixel.map(String.init) ?? "unknown"
        return "Photometric Interpretation=\(photometricValue), Samples Per Pixel=\(samplesValue)"
    }
}

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
        transferSyntax: DicomTransferSyntax? = nil,
        width: Int? = nil,
        height: Int? = nil,
        bitDepth: Int? = nil,
        samplesPerPixel: Int? = nil,
        pixelRepresentation: Int = 0,
        photometricInterpretation: String = "MONOCHROME2",
        bitsStored: Int? = nil,
        logger: LoggerProtocol? = nil
    ) -> DCMPixelReadResult? {
        guard offset > 0, offset <= data.count else {
            logger?.warning("Invalid compressed pixel data offset: \(offset) (data count: \(data.count))")
            return nil
        }

        let compressedData = data.subdata(in: offset..<data.count)
        return decodeCompressedFrameData(
            data: compressedData,
            transferSyntax: transferSyntax,
            width: width,
            height: height,
            bitDepth: bitDepth,
            samplesPerPixel: samplesPerPixel,
            pixelRepresentation: pixelRepresentation,
            photometricInterpretation: photometricInterpretation,
            bitsStored: bitsStored,
            logger: logger
        )
    }

    internal static func decodeCompressedFrameData(
        data compressedData: Data,
        transferSyntax: DicomTransferSyntax? = nil,
        width: Int? = nil,
        height: Int? = nil,
        bitDepth: Int? = nil,
        samplesPerPixel: Int? = nil,
        pixelRepresentation: Int = 0,
        photometricInterpretation: String = "MONOCHROME2",
        bitsStored: Int? = nil,
        logger: LoggerProtocol? = nil
    ) -> DCMPixelReadResult? {
        let backendDecision = DicomCompressedPixelBackendResolver.resolve(
            transferSyntax: transferSyntax,
            requestedBitDepth: bitDepth,
            samplesPerPixel: samplesPerPixel,
            photometricInterpretation: photometricInterpretation,
            bitsStored: bitsStored
        )

        switch backendDecision.backend {
        case .nativeRLELossless:
            guard let width, let height, let bitDepth, let samplesPerPixel else {
                logger?.warning("RLE Lossless decode requires image dimensions, bit depth, and samples per pixel")
                return nil
            }
            do {
                return try DicomRLELosslessDecoder.decode(
                    frame: compressedData,
                    width: width,
                    height: height,
                    bitsAllocated: bitDepth,
                    samplesPerPixel: samplesPerPixel,
                    pixelRepresentation: pixelRepresentation,
                    photometricInterpretation: photometricInterpretation
                )
            } catch {
                logger?.warning("RLE Lossless decoding failed: \(error)")
                return nil
            }

        case .nativeJPEGLS:
            do {
                let decoded = try DicomJPEGLSCodec.decode(compressedData)
                return makeResult(
                    from: decoded,
                    pixelRepresentation: pixelRepresentation,
                    photometricInterpretation: photometricInterpretation
                )
            } catch {
                logger?.warning("JPEG-LS decoding failed: \(error)")
                return nil
            }

        case .nativeJPEGLossless:
            return decodeJPEGLosslessFrame(
                compressedData,
                pixelRepresentation: pixelRepresentation,
                photometricInterpretation: photometricInterpretation,
                logger: logger
            )

        case .nativeJPEGExtended:
            do {
                let frame = try JPEGExtendedDecoder.decode(compressedData)
                return makeGrayscaleResult(
                    pixels: frame.pixels,
                    width: frame.width,
                    height: frame.height,
                    bitDepth: frame.precision,
                    pixelRepresentation: pixelRepresentation,
                    photometricInterpretation: photometricInterpretation
                )
            } catch {
                logger?.warning("JPEG Extended native decoding failed: \(error)")
                return nil
            }

        case .imageIOJPEGBaseline, .imageIOJPEGExtended, .imageIOJPEG2000:
            return decodeImageIOFrame(
                compressedData,
                backend: backendDecision.backend,
                requestedBitDepth: bitDepth,
                pixelRepresentation: pixelRepresentation,
                photometricInterpretation: photometricInterpretation,
                logger: logger
            )

        case .openJPEG2000:
            do {
                let decoded = try DicomJPEG2000Codec.decode(compressedData)
                return makeResult(
                    bytes: decoded.bytes,
                    width: decoded.width,
                    height: decoded.height,
                    bitsPerSample: decoded.bitsPerSample,
                    componentCount: decoded.componentCount,
                    pixelRepresentation: pixelRepresentation,
                    photometricInterpretation: photometricInterpretation
                )
            } catch {
                logger?.warning("JPEG 2000 decoding failed: \(error)")
                return nil
            }

        case .openJPEGHTJ2K:
            do {
                let decoded = try DicomJPEG2000Codec.decode(compressedData)
                return makeResult(
                    bytes: decoded.bytes,
                    width: decoded.width,
                    height: decoded.height,
                    bitsPerSample: decoded.bitsPerSample,
                    componentCount: decoded.componentCount,
                    pixelRepresentation: pixelRepresentation,
                    photometricInterpretation: photometricInterpretation
                )
            } catch {
                logger?.warning("HTJ2K decoding failed: \(error)")
                return nil
            }

        case .legacyImageIO:
            if isJPEGLosslessFrame(compressedData) {
                return decodeJPEGLosslessFrame(
                    compressedData,
                    pixelRepresentation: pixelRepresentation,
                    photometricInterpretation: photometricInterpretation,
                    logger: logger
                )
            }
            return decodeImageIOFrame(
                compressedData,
                backend: .legacyImageIO,
                requestedBitDepth: bitDepth,
                pixelRepresentation: pixelRepresentation,
                photometricInterpretation: photometricInterpretation,
                logger: logger
            )

        case .unsupported:
            backendDecision.diagnostics.forEach { logger?.warning($0) }
            return nil
        }
    }

    private static func decodeJPEGLosslessFrame(
        _ compressedData: Data,
        pixelRepresentation: Int,
        photometricInterpretation: String,
        logger: LoggerProtocol?
    ) -> DCMPixelReadResult? {
        guard isJPEGLosslessFrame(compressedData) else {
            logger?.warning("JPEG Lossless transfer syntax requires a JPEG Lossless SOF3 frame")
            return nil
        }

        let decoder = JPEGLosslessDecoder()
        do {
            let losslessResult = try decoder.decode(data: compressedData)
            if losslessResult.componentCount == 3 {
                guard losslessResult.bitDepth <= 8 else {
                    logger?.warning(
                        "JPEG Lossless interleaved color decode supports 8 bits per component; "
                            + "the stream declares \(losslessResult.bitDepth) (Photometric Interpretation=\(photometricInterpretation))"
                    )
                    return nil
                }
                guard photometricInterpretation == "RGB" else {
                    logger?.warning(
                        "JPEG Lossless 3-component output is only unambiguous for Photometric Interpretation=RGB; "
                            + "got \(photometricInterpretation)"
                    )
                    return nil
                }
                return DCMPixelReadResult(
                    pixels8: nil,
                    pixels16: nil,
                    pixels24: losslessResult.pixels.map { UInt8(truncatingIfNeeded: $0) },
                    signedImage: false,
                    width: losslessResult.width,
                    height: losslessResult.height,
                    bitDepth: losslessResult.bitDepth,
                    samplesPerPixel: 3
                )
            }
            return makeGrayscaleResult(
                pixels: losslessResult.pixels,
                width: losslessResult.width,
                height: losslessResult.height,
                bitDepth: losslessResult.bitDepth,
                pixelRepresentation: pixelRepresentation,
                photometricInterpretation: photometricInterpretation
            )
        } catch {
            logger?.warning("JPEG Lossless decoding failed: \(error)")
            return nil
        }
    }

    private static func decodeImageIOFrame(
        _ compressedData: Data,
        backend: DicomCompressedPixelBackend,
        requestedBitDepth: Int?,
        pixelRepresentation: Int,
        photometricInterpretation: String,
        logger: LoggerProtocol?
    ) -> DCMPixelReadResult? {
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
        if let requestedBitDepth, requestedBitDepth > 8, bitDepth <= 8 {
            logger?.warning("ImageIO decoded \(bitDepth)-bit output for \(requestedBitDepth)-bit DICOM pixels; refusing precision-losing fallback")
            return nil
        }
        if bitDepth > 16 {
            logger?.warning("ImageIO decoded \(bitDepth)-bit output, but only 8-bit and 16-bit buffers are supported")
            return nil
        }
        if bitDepth > 8 && samplesPerPixel != 1 {
            logger?.warning("ImageIO \(backend) does not support >8-bit color output without precision loss")
            return nil
        }

        var result = DCMPixelReadResult(
            pixels8: nil,
            pixels16: nil,
            pixels24: nil,
            signedImage: pixelRepresentation == 1,
            width: width,
            height: height,
            bitDepth: bitDepth,
            samplesPerPixel: samplesPerPixel
        )

        if samplesPerPixel == 1 {
            if bitDepth > 8 {
                return decodeImageIOGrayscale16(
                    cgImage,
                    requestedBitDepth: requestedBitDepth,
                    pixelRepresentation: pixelRepresentation,
                    photometricInterpretation: photometricInterpretation,
                    logger: logger
                )
            }

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

    private static func decodeImageIOGrayscale16(
        _ cgImage: CGImage,
        requestedBitDepth: Int?,
        pixelRepresentation: Int,
        photometricInterpretation: String,
        logger: LoggerProtocol?
    ) -> DCMPixelReadResult? {
        let width = cgImage.width
        let height = cgImage.height
        let sampleCount = width * height
        let bytesPerRow = width * MemoryLayout<UInt16>.size
        var rawData = Data(count: sampleCount * MemoryLayout<UInt16>.size)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue

        let contextCreated = rawData.withUnsafeMutableBytes { rawBytes -> Bool in
            guard let baseAddress = rawBytes.baseAddress,
                  let ctx = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 16,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  ) else {
                return false
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard contextCreated else {
            logger?.warning("Failed to create 16-bit grayscale context")
            return nil
        }

        var pixels = rawData.withUnsafeBytes { rawBytes -> [UInt16] in
            let buffer = rawBytes.bindMemory(to: UInt16.self)
            return buffer.prefix(sampleCount).map { UInt16(littleEndian: $0) }
        }

        if pixelRepresentation == 1 {
            pixels = pixels.map { UInt16(Int(Int16(bitPattern: $0)) - Int(Int16.min)) }
        }
        if photometricInterpretation == "MONOCHROME1" {
            if pixelRepresentation == 1 {
                invertMonochrome1SignedVectorized(buffer: &pixels, count: sampleCount)
            } else {
                invertMonochrome1Vectorized(buffer: &pixels, count: sampleCount)
            }
        }

        return DCMPixelReadResult(
            pixels8: nil,
            pixels16: pixels,
            pixels24: nil,
            signedImage: pixelRepresentation == 1,
            width: width,
            height: height,
            bitDepth: requestedBitDepth ?? cgImage.bitsPerComponent,
            samplesPerPixel: 1
        )
    }

    private static func makeResult(
        from frame: DicomJPEGLSCodec.DecodedFrame,
        pixelRepresentation: Int,
        photometricInterpretation: String
    ) -> DCMPixelReadResult? {
        makeResult(
            bytes: frame.bytes,
            width: frame.width,
            height: frame.height,
            bitsPerSample: frame.bitsPerSample,
            componentCount: frame.componentCount,
            pixelRepresentation: pixelRepresentation,
            photometricInterpretation: photometricInterpretation
        )
    }

    private static func makeResult(
        bytes: Data,
        width: Int,
        height: Int,
        bitsPerSample: Int,
        componentCount: Int,
        pixelRepresentation: Int,
        photometricInterpretation: String
    ) -> DCMPixelReadResult? {
        let sampleCount = width * height
        if componentCount == 1 {
            if bitsPerSample <= 8 {
                guard bytes.count >= sampleCount else { return nil }
                var pixels = [UInt8](bytes.prefix(sampleCount))
                if pixelRepresentation == 1 {
                    pixels = pixels.map { UInt8(Int(Int8(bitPattern: $0)) - Int(Int8.min)) }
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
                    bitDepth: bitsPerSample,
                    samplesPerPixel: 1
                )
            }

            guard bitsPerSample <= 16, bytes.count >= sampleCount * 2 else {
                return nil
            }
            var pixels = [UInt16](repeating: 0, count: sampleCount)
            for index in 0..<sampleCount {
                let byteIndex = index * 2
                let sample = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
                if pixelRepresentation == 1 {
                    pixels[index] = UInt16(Int(Int16(bitPattern: sample)) - Int(Int16.min))
                } else {
                    pixels[index] = sample
                }
            }
            if photometricInterpretation == "MONOCHROME1" {
                if pixelRepresentation == 1 {
                    invertMonochrome1SignedVectorized(buffer: &pixels, count: sampleCount)
                } else {
                    invertMonochrome1Vectorized(buffer: &pixels, count: sampleCount)
                }
            }
            return DCMPixelReadResult(
                pixels8: nil,
                pixels16: pixels,
                pixels24: nil,
                signedImage: pixelRepresentation == 1,
                width: width,
                height: height,
                bitDepth: bitsPerSample,
                samplesPerPixel: 1
            )
        }

        if componentCount == 3 && bitsPerSample <= 8 {
            guard bytes.count >= sampleCount * 3 else { return nil }
            return DCMPixelReadResult(
                pixels8: nil,
                pixels16: nil,
                pixels24: [UInt8](bytes.prefix(sampleCount * 3)),
                signedImage: false,
                width: width,
                height: height,
                bitDepth: bitsPerSample,
                samplesPerPixel: 3
            )
        }

        return nil
    }

    private static func makeGrayscaleResult(
        pixels sourcePixels: [UInt16],
        width: Int,
        height: Int,
        bitDepth: Int,
        pixelRepresentation: Int,
        photometricInterpretation: String
    ) -> DCMPixelReadResult {
        let signedImage = pixelRepresentation == 1
        if bitDepth <= 8 {
            var pixels = sourcePixels.map { UInt8(truncatingIfNeeded: $0) }
            if signedImage {
                pixels = pixels.map { UInt8(Int(Int8(bitPattern: $0)) - Int(Int8.min)) }
            }
            if photometricInterpretation == "MONOCHROME1" {
                pixels = pixels.map { 255 - $0 }
            }
            return DCMPixelReadResult(
                pixels8: pixels,
                pixels16: nil,
                pixels24: nil,
                signedImage: signedImage,
                width: width,
                height: height,
                bitDepth: bitDepth,
                samplesPerPixel: 1
            )
        }

        var pixels = sourcePixels
        if signedImage {
            pixels = pixels.map { UInt16(Int(Int16(bitPattern: $0)) - Int(Int16.min)) }
        }
        if photometricInterpretation == "MONOCHROME1" {
            if signedImage {
                invertMonochrome1SignedVectorized(buffer: &pixels, count: pixels.count)
            } else {
                invertMonochrome1Vectorized(buffer: &pixels, count: pixels.count)
            }
        }
        return DCMPixelReadResult(
            pixels8: nil,
            pixels16: pixels,
            pixels24: nil,
            signedImage: signedImage,
            width: width,
            height: height,
            bitDepth: bitDepth,
            samplesPerPixel: 1
        )
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

    private static func isJPEGLosslessFrame(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == 0xFF && data[1] == 0xD8 && isJPEGLossless(data: data)
    }
}
