//
//  DicomTranscoderTests.swift
//  DicomCoreTests
//
//  Executable transcoding routes (issue #1237): native-to-native rewrite,
//  compressed pass-through, compressed-to-native decompression with
//  stored-value fidelity, the explicitly chosen JPEG-LS lossless encoder
//  route, and typed failures for every unsupported route before any
//  output is produced.
//

import Foundation
import XCTest
import DicomTestSupport
@testable import DicomCore

final class DicomTranscoderTests: XCTestCase {
    // MARK: - Native-to-native rewrite and compressed pass-through

    func testNativeToNativeRewritePreservesMetadataAndPixels() throws {
        let source = try Self.makeNativeFile(storedValues: [-1000, -500, 0, 250])
        let output = try DicomTranscoder().transcode(source, to: .explicitVRLittleEndian)

        let decoder = try Self.open(output)
        XCTAssertEqual(decoder.info(for: .transferSyntaxUID), DicomTransferSyntax.explicitVRLittleEndian.rawValue)
        XCTAssertEqual(decoder.info(for: .patientName), "PARITY^TRANSCODE")
        XCTAssertEqual(decoder.intValue(for: .bitsStored), 16)
        XCTAssertEqual(Self.storedInt16Pixels(decoder), [-1000, -500, 0, 250],
                       "stored pixel values must survive the rewrite")
    }

    func testCompressedPassThroughPreservesEncapsulatedBytes() throws {
        let source = try Self.makeJPEGLosslessFile(storedValues: [100, 200, 300, 400])
        let output = try DicomTranscoder().transcode(source, to: .jpegLosslessFirstOrder)

        let sourceReader = try Self.open(source).makeEncapsulatedPixelFrameReader()
        let outputDecoder = try Self.open(output)
        XCTAssertEqual(outputDecoder.info(for: .transferSyntaxUID),
                       DicomTransferSyntax.jpegLosslessFirstOrder.rawValue)
        let outputReader = try outputDecoder.makeEncapsulatedPixelFrameReader()
        XCTAssertEqual(try outputReader.frameData(at: 0), try sourceReader.frameData(at: 0),
                       "compressed pass-through must preserve the frame payload byte-for-byte")
    }

    // MARK: - Compressed-to-native decompression

    func testCompressedToNativeDecompressionPreservesStoredValuesAndMetadata() throws {
        let stored = [100, 200, 300, 400]
        let source = try Self.makeJPEGLosslessFile(storedValues: stored)
        let output = try DicomTranscoder().transcode(source, to: .explicitVRLittleEndian)

        let decoder = try Self.open(output)
        XCTAssertEqual(decoder.info(for: .transferSyntaxUID), DicomTransferSyntax.explicitVRLittleEndian.rawValue)
        XCTAssertFalse(decoder.compressedImage)
        XCTAssertEqual(decoder.info(for: .patientName), "PARITY^TRANSCODE")
        XCTAssertEqual(decoder.intValue(for: .bitsAllocated), 16)
        XCTAssertEqual(decoder.intValue(for: .bitsStored), 16)
        XCTAssertEqual(try XCTUnwrap(decoder.getPixels16()).map(Int.init), stored,
                       "decompressed stored values must match the compressed source")
    }

    func testSignedCompressedSourceDecompressesWithStoredValueFidelity() throws {
        let stored: [Int16] = [-1000, -500, 0, 250]
        let patterns = stored.map { Int(UInt16(bitPattern: $0)) }
        let codestream = makeJPEGLosslessStream(planes: [patterns], width: 2, height: 2, precision: 16)
        let source = try Self.makeEncapsulatedFile(
            codestream: codestream, pixelRepresentation: 1
        )
        let output = try DicomTranscoder().transcode(source, to: .explicitVRLittleEndian)

        let decoder = try Self.open(output)
        XCTAssertEqual(decoder.pixelRepresentationTagValue, 1)
        XCTAssertEqual(Self.storedInt16Pixels(decoder), stored.map(Int.init),
                       "signed stored values must survive decompression")
    }

    // MARK: - MONOCHROME1 decompression

    func testMonochrome1CompressedSourceDecompressesWithStoredValueFidelity() throws {
        let stored = [100, 200, 300, 400]
        let source = try Self.makeJPEGLosslessFile(storedValues: stored, photometricInterpretation: "MONOCHROME1")
        let output = try DicomTranscoder().transcode(source, to: .explicitVRLittleEndian)

        let decoder = try Self.open(output)
        XCTAssertEqual(decoder.info(for: .transferSyntaxUID), DicomTransferSyntax.explicitVRLittleEndian.rawValue)
        XCTAssertEqual(decoder.photometricInterpretation, "MONOCHROME1",
                       "the photometric interpretation must survive decompression")
        XCTAssertEqual(try XCTUnwrap(decoder.getPixels16()).map(Int.init), stored.map { 65535 - $0 },
                       "native MONOCHROME1 display buffers re-invert, so stored values must round-trip exactly")
    }

    func testSignedMonochrome1CompressedSourceDecompressesWithStoredValueFidelity() throws {
        let stored: [Int16] = [-1000, -500, 0, 250]
        let patterns = stored.map { Int(UInt16(bitPattern: $0)) }
        let codestream = makeJPEGLosslessStream(planes: [patterns], width: 2, height: 2, precision: 16)
        let source = try Self.makeEncapsulatedFile(
            codestream: codestream, pixelRepresentation: 1, photometricInterpretation: "MONOCHROME1"
        )
        let output = try DicomTranscoder().transcode(source, to: .explicitVRLittleEndian)

        let decoder = try Self.open(output)
        XCTAssertEqual(decoder.pixelRepresentationTagValue, 1)
        XCTAssertEqual(decoder.photometricInterpretation, "MONOCHROME1")
        XCTAssertEqual(try XCTUnwrap(decoder.getPixels16()).map(Int.init),
                       stored.map { 65535 - (Int($0) + 32768) },
                       "signed stored values must survive decompression of display-inverted sources")
    }

    func testCompressRouteStillRejectsMonochrome1WithUnsupportedPixelShape() throws {
        try DicomTestRuntimePreflight.require(.charLS)
        let native = try Self.makeNativeFile(storedValues: [1, 2, 3, 4], photometricInterpretation: "MONOCHROME1")
        XCTAssertThrowsError(try DicomTranscoder().transcode(native, to: .jpegLSLossless)) { error in
            guard case DicomTranscoder.TranscodeError.unsupportedPixelShape = error else {
                return XCTFail("expected unsupportedPixelShape, got \(error)")
            }
        }
    }

    // MARK: - JPEG-LS lossless encoder route (CharLS-gated)

    func testNativeToJPEGLSLosslessRoundTripsThroughCharLS() throws {
        try DicomTestRuntimePreflight.require(.charLS)
        let stored = [-1000, -500, 0, 250]
        let source = try Self.makeNativeFile(storedValues: stored)

        let compressed = try DicomTranscoder().transcode(source, to: .jpegLSLossless)
        let compressedDecoder = try Self.open(compressed)
        XCTAssertEqual(compressedDecoder.info(for: .transferSyntaxUID),
                       DicomTransferSyntax.jpegLSLossless.rawValue)
        XCTAssertNotNil(try compressedDecoder.makeEncapsulatedPixelFrameReader(),
                        "the encoded output must be properly encapsulated")

        // Round trip back to native: stored values must be identical.
        let roundTrip = try DicomTranscoder().transcode(compressed, to: .explicitVRLittleEndian)
        let decoder = try Self.open(roundTrip)
        XCTAssertEqual(Self.storedInt16Pixels(decoder), stored,
                       "JPEG-LS lossless round trip must preserve stored values exactly")
    }

    // MARK: - Unsupported routes stay typed

    func testUnsupportedEncoderRoutesFailTypedBeforeOutput() throws {
        let native = try Self.makeNativeFile(storedValues: [1, 2, 3, 4])
        XCTAssertThrowsError(try DicomTranscoder().transcode(native, to: .jpeg2000Lossless)) { error in
            guard case DicomTranscoder.TranscodeError.routeUnsupported(_, let destination, _) = error else {
                return XCTFail("expected routeUnsupported, got \(error)")
            }
            XCTAssertEqual(destination, DicomTransferSyntax.jpeg2000Lossless.rawValue)
        }

        let compressed = try Self.makeJPEGLosslessFile(storedValues: [1, 2, 3, 4])
        XCTAssertThrowsError(try DicomTranscoder().transcode(compressed, to: .rleLossless)) { error in
            guard case DicomTranscoder.TranscodeError.routeUnsupported = error else {
                return XCTFail("expected routeUnsupported for compressed-to-compressed, got \(error)")
            }
        }
    }

    func testDecompressionToNonNativeTargetFailsTyped() throws {
        let compressed = try Self.makeJPEGLosslessFile(storedValues: [1, 2, 3, 4])
        XCTAssertThrowsError(try DicomTranscoder().transcode(compressed, to: .explicitVRBigEndian)) { error in
            guard case DicomTranscoder.TranscodeError.routeUnsupported(_, _, let diagnostics) = error else {
                return XCTFail("expected routeUnsupported, got \(error)")
            }
            XCTAssertTrue(diagnostics.joined().contains("Explicit VR Little Endian"))
        }
    }

    // MARK: - Builders

    private static func makeNativeFile(
        storedValues: [Int],
        photometricInterpretation: String = "MONOCHROME2"
    ) throws -> Data {
        var pixelData = Data()
        for value in storedValues {
            let pattern = UInt16(bitPattern: Int16(value))
            pixelData.append(UInt8(pattern & 0xFF))
            pixelData.append(UInt8(pattern >> 8))
        }
        var dataSet = EncapsulatedFixtureFactory.makeDataSet(
            transferSyntax: .explicitVRLittleEndian,
            fragments: [],
            declaredFrames: 1,
            rows: 2,
            columns: 2,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            photometricInterpretation: photometricInterpretation,
            pixelRepresentation: 1
        )
        dataSet.set(DicomDataElement(tag: DicomTag.patientName.rawValue, vr: .PN, value: .strings(["PARITY^TRANSCODE"])))
        dataSet.set(DicomDataElement(tag: DicomTag.pixelData.rawValue, vr: .OW, value: .bytes(pixelData)))
        return try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                transferSyntax: .explicitVRLittleEndian,
                mediaStorageSOPClassUID: DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID,
                mediaStorageSOPInstanceUID: "2.25.12370001"
            )
        )
    }

    private static func makeJPEGLosslessFile(
        storedValues: [Int],
        photometricInterpretation: String = "MONOCHROME2"
    ) throws -> Data {
        let codestream = makeJPEGLosslessStream(planes: [storedValues], width: 2, height: 2, precision: 16)
        return try makeEncapsulatedFile(
            codestream: codestream,
            pixelRepresentation: 0,
            photometricInterpretation: photometricInterpretation
        )
    }

    private static func makeEncapsulatedFile(
        codestream: Data,
        pixelRepresentation: Int,
        photometricInterpretation: String = "MONOCHROME2"
    ) throws -> Data {
        var dataSet = EncapsulatedFixtureFactory.makeDataSet(
            transferSyntax: .jpegLosslessFirstOrder,
            fragments: [codestream],
            declaredFrames: 1,
            rows: 2,
            columns: 2,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            photometricInterpretation: photometricInterpretation,
            pixelRepresentation: pixelRepresentation
        )
        dataSet.set(DicomDataElement(tag: DicomTag.patientName.rawValue, vr: .PN, value: .strings(["PARITY^TRANSCODE"])))
        return try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                transferSyntax: .jpegLosslessFirstOrder,
                mediaStorageSOPClassUID: DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID,
                mediaStorageSOPInstanceUID: "2.25.12370001"
            )
        )
    }

    private static func storedInt16Pixels(_ decoder: DCMDecoder) -> [Int] {
        guard let normalized = decoder.getPixels16() else { return [] }
        if decoder.pixelRepresentationTagValue == 1 {
            return normalized.map { Int(Int16(truncatingIfNeeded: Int32($0) + Int32(Int16.min))) }
        }
        return normalized.map(Int.init)
    }

    private static func open(_ data: Data) throws -> DCMDecoder {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcoder_test_\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DCMDecoder(contentsOf: url)
    }
}
