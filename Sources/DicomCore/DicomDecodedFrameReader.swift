//
//  DicomDecodedFrameReader.swift
//  DicomCore
//
//  Production decoded-frame surface (issue #1227): opens a Part 10 file or
//  dataset, resolves the transfer syntax, extracts the requested frame
//  (native byte-range or encapsulated fragment assembly via
//  `DicomEncapsulatedPixelFrameReader`, #1226), decodes it when a backend
//  supports the syntax, and returns typed pixels plus the image metadata an
//  Isis-style renderer needs. Uncompressed, RLE, JPEG, JPEG-LS, JPEG 2000,
//  and unsupported transfer syntaxes all surface through one typed
//  `ReadError`.
//
//  How this differs from neighboring layers:
//  - Display rendering (`DCMWindowingProcessor`, `DicomDisplayTransform`)
//    maps decoded pixels to display gray/RGB using VOI windowing, LUTs, and
//    presentation state. This reader stops earlier: it returns the decoded
//    buffer in the same normalization the legacy `getPixels8/16/24`
//    surface uses (signed samples offset to unsigned, MONOCHROME1
//    inverted) plus the stored VOI/rescale attributes so renderers decide
//    how to window.
//  - Volume assembly (`DicomSeriesLoader`, #1233/#1234) orders many slices
//    or multiframe groups into a 3D volume. This reader addresses exactly
//    one frame of one object and never materializes sibling frames, which
//    keeps multiframe access memory-bounded.
//

import Foundation

/// Typed decoded pixel payload of a single frame.
public enum DicomDecodedFramePixelBuffer: Equatable, Sendable {
    /// 8-bit grayscale samples (MONOCHROME1 already inverted).
    case gray8([UInt8])
    /// 16-bit grayscale samples (signed values offset to unsigned,
    /// MONOCHROME1 already inverted) — same contract as `getPixels16()`.
    case gray16([UInt16])
    /// Interleaved 8-bit R,G,B triplets.
    case rgb8(interleaved: [UInt8])

    /// Number of addressable pixel samples in the buffer.
    public var sampleCount: Int {
        switch self {
        case .gray8(let pixels): return pixels.count
        case .gray16(let pixels): return pixels.count
        case .rgb8(let interleaved): return interleaved.count / 3
        }
    }
}

/// Image attributes a renderer needs alongside the decoded buffer. Values
/// come from the DICOM header; optional fields are nil when the dataset
/// does not carry the attribute.
public struct DicomDecodedFrameMetadata: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Addressable frame count (mapped frames for encapsulated objects).
    public let frameCount: Int
    public let bitsAllocated: Int
    public let bitsStored: Int
    public let highBit: Int
    public let pixelRepresentation: Int
    public let samplesPerPixel: Int
    public let photometricInterpretation: String
    public let planarConfiguration: Int?
    public let transferSyntaxUID: String
    /// Stored VOI window, nil when the dataset has no usable window.
    public let windowSettings: WindowSettings?
    public let rescaleParameters: RescaleParameters
    public let smallestImagePixelValue: Int?
    public let largestImagePixelValue: Int?
}

/// One decoded frame: typed pixels plus renderer-facing metadata.
public struct DicomDecodedFrame: Equatable, Sendable {
    public let index: Int
    public let pixels: DicomDecodedFramePixelBuffer
    public let metadata: DicomDecodedFrameMetadata
}

/// Production frame reader over one DICOM object. Thread-safe (the wrapped
/// decoder synchronizes its state) and cheap to copy.
public struct DicomDecodedFrameReader: Sendable {
    public enum ReadError: Error, Equatable, LocalizedError, Sendable {
        /// The object carries no decodable Pixel Data element.
        case noPixelData
        case frameIndexOutOfRange(index: Int, frameCount: Int)
        /// The transfer syntax has no decode backend in this build; the
        /// diagnostics carry the deterministic resolver reasons.
        case unsupportedTransferSyntax(uid: String, diagnostics: [String])
        /// Encapsulated fragments exist but no safe frame map could be
        /// derived (`DicomEncapsulatedPixelFrameReader` diagnostics).
        case unusableEncapsulation(diagnostics: [String])
        /// The selected backend failed to produce a typed pixel buffer.
        case decodeFailed(transferSyntaxUID: String, reason: String)

        public var errorDescription: String? {
            switch self {
            case .noPixelData:
                return "The DICOM object carries no decodable Pixel Data."
            case .frameIndexOutOfRange(let index, let frameCount):
                return "Frame index \(index) is outside the addressable range of \(frameCount) frame(s)."
            case .unsupportedTransferSyntax(let uid, let diagnostics):
                return "Transfer syntax \(uid) has no decode backend: \(diagnostics.joined(separator: " "))"
            case .unusableEncapsulation(let diagnostics):
                return "Encapsulated Pixel Data has no usable frame mapping: \(diagnostics.joined(separator: " "))"
            case .decodeFailed(let uid, let reason):
                return "Decoding a \(uid) frame failed: \(reason)"
            }
        }
    }

    private let decoder: DCMDecoder

    /// Opens a Part 10 file.
    public init(contentsOf url: URL) throws {
        self.init(decoder: try DCMDecoder(contentsOf: url))
    }

    /// Reads frames of an in-memory dataset by encoding it as Part 10 bytes
    /// in memory (the options select the encoded transfer syntax).
    public init(dataSet: DicomDataSet, options: DicomPart10WriterOptions) throws {
        let fileData = try DicomDataSetWriter.part10Data(from: dataSet, options: options)
        self.init(decoder: try DCMDecoder(data: fileData))
    }

    /// Wraps an already-loaded decoder without re-parsing the file.
    public init(decoder: DCMDecoder) {
        self.decoder = decoder
    }

    /// Number of frames this reader can address: mapped frames for
    /// encapsulated objects, declared frames for native objects, and 1 for
    /// defined-length compressed payloads (which carry no frame map).
    public var frameCount: Int {
        if decoder.compressedImage {
            if let reader = try? decoder.makeEncapsulatedPixelFrameReader() {
                return reader.frameCount
            }
            return decoder.fileReadSucceeded ? 1 : 0
        }
        if let descriptor = decoder.pixelDataDescriptor {
            return descriptor.numberOfFrames
        }
        return decoder.fileReadSucceeded ? max(1, decoder.nImages) : 0
    }

    /// Header metadata shared by every frame of the object.
    public func metadata() throws -> DicomDecodedFrameMetadata {
        guard decoder.fileReadSucceeded else {
            throw ReadError.noPixelData
        }
        return makeMetadata(width: decoder.width, height: decoder.height)
    }

    /// Decodes one frame. Extraction and decode touch only the requested
    /// frame's bytes, so multiframe access stays memory-bounded.
    public func frame(at index: Int) throws -> DicomDecodedFrame {
        guard decoder.fileReadSucceeded else {
            throw ReadError.noPixelData
        }
        let count = frameCount
        guard index >= 0, index < count else {
            throw ReadError.frameIndexOutOfRange(index: index, frameCount: count)
        }
        if decoder.compressedImage {
            return try decodeCompressedFrame(at: index, frameCount: count)
        }
        return try decodeNativeFrame(at: index, frameCount: count)
    }

    /// Cancellation-aware variant: the decode runs off the caller's thread
    /// and honors `Task` cancellation before extraction starts.
    @available(macOS 10.15, iOS 13.0, *)
    public func frame(at index: Int) async throws -> DicomDecodedFrame {
        let reader = self
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try reader.frame(at: index)
        }.value
    }

    /// Streams decoded frames one at a time (memory-bounded: only the
    /// in-flight frame is materialized). Cancelling the consuming task
    /// stops decoding before the next frame.
    @available(macOS 10.15, iOS 13.0, *)
    public func frames(in range: Range<Int>? = nil) -> AsyncThrowingStream<DicomDecodedFrame, Error> {
        let reader = self
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let resolvedRange = range ?? 0..<reader.frameCount
                    for index in resolvedRange {
                        try Task.checkCancellation()
                        continuation.yield(try reader.frame(at: index))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Native path

    private func decodeNativeFrame(at index: Int, frameCount: Int) throws -> DicomDecodedFrame {
        guard let descriptor = decoder.pixelDataDescriptor,
              let byteRange = descriptor.byteRange(forFrame: index) else {
            throw ReadError.noPixelData
        }
        let result = DCMPixelReader.readPixels(
            data: decoder.dicomDataSnapshot(),
            width: descriptor.columns,
            height: descriptor.rows,
            bitDepth: descriptor.bitsAllocated,
            samplesPerPixel: descriptor.samplesPerPixel,
            offset: byteRange.lowerBound,
            pixelRepresentation: decoder.pixelRepresentationTagValue,
            littleEndian: decoder.currentLittleEndian(),
            photometricInterpretation: descriptor.photometricInterpretation
        )
        guard let pixels = Self.typedPixels(from: result) else {
            throw ReadError.decodeFailed(
                transferSyntaxUID: decoder.transferSyntaxUID,
                reason: "native \(descriptor.bitsAllocated)-bit, \(descriptor.samplesPerPixel)-sample layout"
                    + " is not representable as gray8/gray16/rgb8"
            )
        }
        return DicomDecodedFrame(
            index: index,
            pixels: pixels,
            metadata: makeMetadata(width: descriptor.columns, height: descriptor.rows, frameCount: frameCount)
        )
    }

    // MARK: - Compressed path

    private func decodeCompressedFrame(at index: Int, frameCount: Int) throws -> DicomDecodedFrame {
        let transferSyntax = DicomTransferSyntax(uid: decoder.transferSyntaxUID)
        let bitsStored = decoder.intValue(for: Int(DicomTag.bitsStored.rawValue))
        let decision = DicomCompressedPixelBackendResolver.resolve(
            transferSyntax: transferSyntax,
            requestedBitDepth: decoder.bitDepth,
            samplesPerPixel: decoder.samplesPerPixel,
            photometricInterpretation: decoder.photometricInterpretation,
            bitsStored: bitsStored
        )
        if decision.backend == .unsupported {
            throw ReadError.unsupportedTransferSyntax(
                uid: decoder.transferSyntaxUID,
                diagnostics: decision.diagnostics
            )
        }

        let result: DCMPixelReadResult?
        do {
            let encapsulated = try decoder.makeEncapsulatedPixelFrameReader()
            result = DCMPixelReader.decodeCompressedFrameData(
                data: try encapsulated.frameData(at: index),
                transferSyntax: transferSyntax,
                width: decoder.width,
                height: decoder.height,
                bitDepth: decoder.bitDepth,
                samplesPerPixel: decoder.samplesPerPixel,
                pixelRepresentation: decoder.pixelRepresentationTagValue,
                photometricInterpretation: decoder.photometricInterpretation,
                bitsStored: bitsStored
            )
        } catch let error as DicomEncapsulatedPixelFrameReader.ReaderError {
            switch error {
            case .notEncapsulated:
                // Defined-length compressed payload: one addressable frame
                // starting at the Pixel Data value offset.
                result = DCMPixelReader.decodeCompressedPixelData(
                    data: decoder.dicomDataSnapshot(),
                    offset: decoder.offset,
                    transferSyntax: transferSyntax,
                    width: decoder.width,
                    height: decoder.height,
                    bitDepth: decoder.bitDepth,
                    samplesPerPixel: decoder.samplesPerPixel,
                    pixelRepresentation: decoder.pixelRepresentationTagValue,
                    photometricInterpretation: decoder.photometricInterpretation,
                    bitsStored: bitsStored
                )
            case .unusableFrameMap(let diagnostics):
                throw ReadError.unusableEncapsulation(diagnostics: diagnostics.map(\.message))
            case .frameIndexOutOfRange(let index, let frameCount):
                throw ReadError.frameIndexOutOfRange(index: index, frameCount: frameCount)
            case .declaredFrameCountMismatch(let declared, let mapped):
                throw ReadError.unusableEncapsulation(
                    diagnostics: ["NumberOfFrames declares \(declared) frame(s) but \(mapped) were mapped."]
                )
            }
        }

        guard let result, let pixels = Self.typedPixels(from: result) else {
            throw ReadError.decodeFailed(
                transferSyntaxUID: decoder.transferSyntaxUID,
                reason: "the \(decision.backend) backend did not produce a typed pixel buffer"
            )
        }
        return DicomDecodedFrame(
            index: index,
            pixels: pixels,
            metadata: makeMetadata(width: result.width, height: result.height, frameCount: frameCount)
        )
    }

    // MARK: - Shared helpers

    private func makeMetadata(width: Int, height: Int, frameCount: Int? = nil) -> DicomDecodedFrameMetadata {
        let bitsAllocated = decoder.bitDepth
        let bitsStored = decoder.intValue(for: Int(DicomTag.bitsStored.rawValue)) ?? bitsAllocated
        let window = decoder.windowSettingsV2
        return DicomDecodedFrameMetadata(
            width: width,
            height: height,
            frameCount: frameCount ?? self.frameCount,
            bitsAllocated: bitsAllocated,
            bitsStored: bitsStored,
            highBit: decoder.intValue(for: Int(DicomTag.highBit.rawValue)) ?? max(0, bitsStored - 1),
            pixelRepresentation: decoder.pixelRepresentationTagValue,
            samplesPerPixel: decoder.samplesPerPixel,
            photometricInterpretation: decoder.photometricInterpretation,
            planarConfiguration: decoder.intValue(for: Int(DicomTag.planarConfiguration.rawValue)),
            transferSyntaxUID: decoder.transferSyntaxUID,
            windowSettings: window.isValid ? window : nil,
            rescaleParameters: decoder.rescaleParametersV2,
            smallestImagePixelValue: decoder.intValue(for: 0x0028_0106),
            largestImagePixelValue: decoder.intValue(for: 0x0028_0107)
        )
    }

    private static func typedPixels(from result: DCMPixelReadResult) -> DicomDecodedFramePixelBuffer? {
        if let interleaved = result.pixels24 {
            return .rgb8(interleaved: interleaved)
        }
        if let pixels = result.pixels16 {
            return .gray16(pixels)
        }
        if let pixels = result.pixels8 {
            return .gray8(pixels)
        }
        return nil
    }
}
