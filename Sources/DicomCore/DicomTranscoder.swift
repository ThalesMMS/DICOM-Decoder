//
//  DicomTranscoder.swift
//  DicomCore
//
//  Executable transfer syntax transcoding routes (issue #1237). The
//  registry's transcode planner stays the decision authority; this
//  executor runs the supported routes as file-level operations:
//
//  - passThrough / rewriteNative: a safe Part 10 rewrite carrying every
//    element and the Pixel Data bytes unchanged (encapsulated payloads
//    byte-for-byte) into the destination syntax's writer path.
//  - decompress: compressed sources whose decode backend is active are
//    decoded frame-by-frame through DicomDecodedFrameReader and written
//    as Explicit VR Little Endian with stored-value pixel fidelity.
//  - compress: the explicitly chosen lossless encoder route — native
//    grayscale to JPEG-LS Lossless through the preflighted CharLS
//    runtime. Every other encoder route fails typed before any output
//    is produced.
//

import Foundation

public struct DicomTranscoder {
    public enum TranscodeError: Error, Equatable, LocalizedError, Sendable {
        /// The planner rejected the route; diagnostics carry the reasons.
        case routeUnsupported(sourceUID: String, destinationUID: String, diagnostics: [String])
        /// The source's frames could not be decoded.
        case decodeFailed(sourceUID: String, reason: String)
        /// The source's pixel shape cannot be converted with fidelity.
        case unsupportedPixelShape(reason: String)

        public var errorDescription: String? {
            switch self {
            case .routeUnsupported(let source, let destination, let diagnostics):
                return "Transcoding \(source) to \(destination) is unsupported: \(diagnostics.joined(separator: " "))"
            case .decodeFailed(let source, let reason):
                return "Decoding \(source) frames failed: \(reason)"
            case .unsupportedPixelShape(let reason):
                return "The pixel shape cannot be transcoded with fidelity: \(reason)"
            }
        }
    }

    public init() {}

    /// Transcodes a Part 10 file on disk into the destination syntax.
    public func transcode(contentsOf url: URL, to destination: DicomTransferSyntax) throws -> Data {
        try transcode(decoder: DCMDecoder(contentsOf: url), to: destination)
    }

    /// Transcodes in-memory Part 10 bytes into the destination syntax.
    public func transcode(_ data: Data, to destination: DicomTransferSyntax) throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcoder_\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try transcode(contentsOf: url, to: destination)
    }

    func transcode(decoder: DCMDecoder, to destination: DicomTransferSyntax) throws -> Data {
        let source = DicomTransferSyntax(uid: decoder.info(for: .transferSyntaxUID)) ?? .explicitVRLittleEndian
        let plan = DicomTransferSyntaxRegistry.standard.transcodePlan(from: source, to: destination)

        switch plan.route {
        case .passThrough, .rewriteNative:
            return try writeCarryingDataset(decoder: decoder, destination: destination)

        case .decompress:
            guard destination == .explicitVRLittleEndian else {
                throw TranscodeError.routeUnsupported(
                    sourceUID: source.rawValue,
                    destinationUID: destination.rawValue,
                    diagnostics: ["Decompression targets Explicit VR Little Endian only."]
                )
            }
            return try decompressToNative(decoder: decoder, source: source)

        case .compress:
            guard destination == .jpegLSLossless else {
                throw TranscodeError.routeUnsupported(
                    sourceUID: source.rawValue,
                    destinationUID: destination.rawValue,
                    diagnostics: plan.diagnostics.map(\.message)
                        + ["JPEG-LS Lossless is the only executable lossless encoder route."]
                )
            }
            return try compressToJPEGLSLossless(decoder: decoder, source: source)

        case .reference, .recompress:
            throw TranscodeError.routeUnsupported(
                sourceUID: source.rawValue,
                destinationUID: destination.rawValue,
                diagnostics: plan.diagnostics.map(\.message)
            )
        }
    }

    // MARK: - Routes

    private func writeCarryingDataset(decoder: DCMDecoder, destination: DicomTransferSyntax) throws -> Data {
        let dataSet = DicomAnonymizer.datasetCarryingPixelBytes(from: decoder)
        return try write(dataSet, decoder: decoder, transferSyntax: destination)
    }

    private func decompressToNative(decoder: DCMDecoder, source: DicomTransferSyntax) throws -> Data {
        let (pixelBytes, samplesPerPixel) = try nativePixelBytes(decoder: decoder, source: source)

        var dataSet = decoder.dataSet
        dataSet.set(DicomDataElement(
            tag: DicomTag.pixelData.rawValue,
            vr: decoder.bitDepth > 8 ? .OW : .OB,
            value: .bytes(pixelBytes)
        ))
        if samplesPerPixel == 3 {
            // Decoded color output is interleaved.
            dataSet.set(DicomDataElement(tag: DicomTag.planarConfiguration.rawValue, vr: .US,
                                         value: .unsignedIntegers([0])))
        }
        return try write(dataSet, decoder: decoder, transferSyntax: .explicitVRLittleEndian)
    }

    private func compressToJPEGLSLossless(decoder: DCMDecoder, source: DicomTransferSyntax) throws -> Data {
        guard DicomJPEGLSCodec.isAvailable else {
            throw TranscodeError.routeUnsupported(
                sourceUID: source.rawValue,
                destinationUID: DicomTransferSyntax.jpegLSLossless.rawValue,
                diagnostics: ["The CharLS runtime is unavailable; JPEG-LS encoding requires it."]
            )
        }
        guard decoder.samplesPerPixel == 1,
              decoder.photometricInterpretation == "MONOCHROME2" || decoder.photometricInterpretation.isEmpty else {
            throw TranscodeError.unsupportedPixelShape(
                reason: "JPEG-LS lossless encoding covers single-sample MONOCHROME2 frames "
                    + "(Photometric Interpretation=\(decoder.photometricInterpretation), "
                    + "Samples per Pixel=\(decoder.samplesPerPixel))."
            )
        }

        let bitsStored = decoder.intValue(for: .bitsStored) ?? decoder.bitDepth
        let frameReader = DicomDecodedFrameReader(decoder: decoder)
        var fragments = [Data]()
        for index in 0..<max(1, frameReader.frameCount) {
            let storedBytes = try storedFrameBytes(frameReader: frameReader, decoder: decoder, frameIndex: index)
            var encoded = try DicomJPEGLSCodec.encode(
                bytes: storedBytes,
                width: decoder.width,
                height: decoder.height,
                bitsPerSample: bitsStored
            )
            if encoded.count % 2 != 0 {
                encoded.append(0x00)
            }
            fragments.append(encoded)
        }

        var dataSet = decoder.dataSet
        dataSet.set(DicomDataElement(
            tag: DicomTag.pixelData.rawValue,
            vr: .OB,
            value: .bytes(Self.encapsulate(fragments: fragments))
        ))
        return try write(dataSet, decoder: decoder, transferSyntax: .jpegLSLossless)
    }

    // MARK: - Stored-value pixel reconstruction

    private func nativePixelBytes(decoder: DCMDecoder, source: DicomTransferSyntax) throws -> (Data, Int) {
        let frameReader = DicomDecodedFrameReader(decoder: decoder)
        var pixelBytes = Data()
        var samplesPerPixel = 1
        for index in 0..<max(1, frameReader.frameCount) {
            let frame: DicomDecodedFrame
            do {
                frame = try frameReader.frame(at: index)
            } catch {
                throw TranscodeError.decodeFailed(
                    sourceUID: source.rawValue,
                    reason: (error as? LocalizedError)?.errorDescription ?? "\(error)"
                )
            }
            if case .rgb8 = frame.pixels { samplesPerPixel = 3 }
            pixelBytes.append(try storedBytes(from: frame, decoder: decoder))
        }
        if pixelBytes.count % 2 != 0 {
            pixelBytes.append(0x00)
        }
        return (pixelBytes, samplesPerPixel)
    }

    private func storedFrameBytes(
        frameReader: DicomDecodedFrameReader,
        decoder: DCMDecoder,
        frameIndex: Int
    ) throws -> Data {
        let frame: DicomDecodedFrame
        do {
            frame = try frameReader.frame(at: frameIndex)
        } catch {
            throw TranscodeError.decodeFailed(
                sourceUID: decoder.info(for: .transferSyntaxUID),
                reason: (error as? LocalizedError)?.errorDescription ?? "\(error)"
            )
        }
        return try storedBytes(from: frame, decoder: decoder)
    }

    /// Rebuilds little-endian stored-value bytes from a decoded frame by
    /// undoing the display normalization in reverse order: decoding
    /// applies the signed offset first and then the MONOCHROME1
    /// full-range inversion (255/65535 − value, regardless of Bits
    /// Stored), so this path un-inverts first and then removes the
    /// signed offset. The output dataset keeps Photometric
    /// Interpretation=MONOCHROME1, so stored values and the tag stay
    /// consistent.
    private func storedBytes(from frame: DicomDecodedFrame, decoder: DCMDecoder) throws -> Data {
        let inverted = decoder.photometricInterpretation == "MONOCHROME1"
        let signed = decoder.pixelRepresentationTagValue == 1

        switch frame.pixels {
        case .gray16(let pixels):
            var bytes = Data(capacity: pixels.count * 2)
            for value in pixels {
                let unInverted = inverted ? UInt16.max - value : value
                let pattern: UInt16
                if signed {
                    pattern = UInt16(bitPattern: Int16(truncatingIfNeeded: Int32(unInverted) + Int32(Int16.min)))
                } else {
                    pattern = unInverted
                }
                bytes.append(UInt8(pattern & 0xFF))
                bytes.append(UInt8(pattern >> 8))
            }
            return bytes
        case .gray8(let pixels):
            return Data(pixels.map { value -> UInt8 in
                let unInverted = inverted ? UInt8.max - value : value
                if signed {
                    return UInt8(bitPattern: Int8(truncatingIfNeeded: Int(unInverted) - 128))
                }
                return unInverted
            })
        case .rgb8(let interleaved):
            return Data(interleaved)
        }
    }

    // MARK: - Helpers

    private func write(
        _ dataSet: DicomDataSet,
        decoder: DCMDecoder,
        transferSyntax: DicomTransferSyntax
    ) throws -> Data {
        let sopClassUID = decoder.info(for: .sopClassUID)
        let sopInstanceUID = decoder.info(for: .sopInstanceUID)
        return try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                transferSyntax: transferSyntax,
                mediaStorageSOPClassUID: sopClassUID.isEmpty ? nil : sopClassUID,
                mediaStorageSOPInstanceUID: sopInstanceUID.isEmpty ? nil : sopInstanceUID
            )
        )
    }

    static func encapsulate(fragments: [Data]) -> Data {
        var data = Data()
        var offsets = [UInt32]()
        var running: UInt32 = 0
        for fragment in fragments {
            offsets.append(running)
            running += UInt32(8 + fragment.count)
        }
        var offsetTable = Data()
        for offset in offsets {
            withUnsafeBytes(of: offset.littleEndian) { offsetTable.append(contentsOf: $0) }
        }
        appendItem(offsetTable, to: &data)
        for fragment in fragments {
            appendItem(fragment, to: &data)
        }
        // Sequence delimiter.
        data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])
        return data
    }

    private static func appendItem(_ payload: Data, to data: inout Data) {
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(payload)
    }
}
