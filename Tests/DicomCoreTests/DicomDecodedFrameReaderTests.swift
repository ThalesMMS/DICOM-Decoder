//
//  DicomDecodedFrameReaderTests.swift
//  DicomCoreTests
//
//  Coverage for the production decoded frame reader (issue #1227): decoded
//  pixel hashes and metadata against curated non-PHI fixtures, multiframe
//  per-frame access, the unified typed error surface, cancellation, and the
//  dataset entry point.
//

import Foundation
import XCTest
@testable import DicomCore

final class DicomDecodedFrameReaderTests: XCTestCase {
    // MARK: - Curated fixture parity (pixel hashes pinned by #1224)

    func testJPEGLosslessParityFixtureDecodesWithPinnedHashAndMetadata() throws {
        let url = Self.fixturesDirectory.appendingPathComponent("DecoderParity/jpeg_lossless_sv1_parity.dcm")
        let reader = try DicomDecodedFrameReader(contentsOf: url)

        XCTAssertEqual(reader.frameCount, 1)
        let frame = try reader.frame(at: 0)
        guard case .gray16(let pixels) = frame.pixels else {
            return XCTFail("expected 16-bit grayscale, got \(frame.pixels)")
        }
        XCTAssertEqual(
            ClinicalParityCuratedFixtureTests.pixelHash(pixels.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }),
            ClinicalParityCuratedFixtureTests.jpegLosslessExpectedPixelHash,
            "decoded JPEG Lossless pixels must match the curated parity hash"
        )

        XCTAssertEqual(frame.metadata.transferSyntaxUID, DicomTransferSyntax.jpegLosslessFirstOrder.rawValue)
        XCTAssertEqual(frame.metadata.samplesPerPixel, 1)
        XCTAssertEqual(frame.metadata.pixelRepresentation, 0)
        XCTAssertEqual(frame.metadata.frameCount, 1)
        XCTAssertEqual(pixels.count, frame.metadata.width * frame.metadata.height)
    }

    func testRLEParityFixtureDecodesWithPinnedHashViaAsyncPath() async throws {
        let url = Self.fixturesDirectory.appendingPathComponent("DecoderParity/rle_parity.dcm")
        let reader = try DicomDecodedFrameReader(contentsOf: url)

        let frame = try await reader.frame(at: 0)
        guard case .gray8(let pixels) = frame.pixels else {
            return XCTFail("expected 8-bit grayscale, got \(frame.pixels)")
        }
        XCTAssertEqual(
            ClinicalParityCuratedFixtureTests.pixelHash(pixels),
            ClinicalParityCuratedFixtureTests.rleExpectedPixelHash,
            "decoded RLE pixels must match the curated parity hash"
        )
        XCTAssertEqual(frame.metadata.transferSyntaxUID, DicomTransferSyntax.rleLossless.rawValue)
    }

    /// The reader must agree with the legacy whole-buffer surface for
    /// native files (same normalization contract).
    func testNativeCTFixtureMatchesLegacyPixelBufferAndExposesVOI() throws {
        let url = Self.fixturesDirectory.appendingPathComponent("CT/ct_synthetic.dcm")
        let decoder = try DCMDecoder(contentsOf: url)
        let reader = DicomDecodedFrameReader(decoder: decoder)

        let frame = try reader.frame(at: 0)
        guard case .gray16(let pixels) = frame.pixels else {
            return XCTFail("expected 16-bit grayscale, got \(frame.pixels)")
        }
        XCTAssertEqual(pixels, try XCTUnwrap(decoder.getPixels16()),
                       "frame 0 of a native file must match getPixels16()")

        let metadata = frame.metadata
        XCTAssertEqual(metadata.width, decoder.width)
        XCTAssertEqual(metadata.height, decoder.height)
        XCTAssertEqual(metadata.bitsAllocated, 16)
        XCTAssertEqual(metadata.transferSyntaxUID, decoder.info(for: .transferSyntaxUID))
        if let window = metadata.windowSettings {
            XCTAssertTrue(window.isValid)
            XCTAssertEqual(window, decoder.windowSettingsV2)
        }
        XCTAssertEqual(metadata.rescaleParameters, decoder.rescaleParametersV2)
    }

    // MARK: - Multiframe access (native and encapsulated)

    func testNativeMultiframeDecodesEachFrameWithoutFullSeriesDecode() throws {
        let frames: [[UInt8]] = [
            [0x10, 0x20, 0x30, 0x40],
            [0x50, 0x60, 0x70, 0x80],
            [0x90, 0xA0, 0xB0, 0xC0]
        ]
        let file = try Self.makeNativeMultiframeFile(framePixels: frames)
        let reader = try Self.reader(for: file)

        XCTAssertEqual(reader.frameCount, 3)
        for (index, expected) in frames.enumerated() {
            let frame = try reader.frame(at: index)
            guard case .gray8(let pixels) = frame.pixels else {
                return XCTFail("expected 8-bit grayscale for frame \(index)")
            }
            XCTAssertEqual(pixels, expected, "frame \(index) must decode only its own bytes")
            XCTAssertEqual(frame.metadata.frameCount, 3)
        }
    }

    func testEncapsulatedRLEMultiframeDecodesEachFrame() throws {
        let frameSamples: [[UInt8]] = [[10, 20, 30, 40], [50, 60, 70, 80]]
        let fragments = frameSamples.map { Self.rleSegment(samples: $0) }
        let file = try EncapsulatedFixtureFactory.makeFile(
            transferSyntax: .rleLossless,
            fragments: fragments,
            declaredFrames: 2
        )
        let reader = try Self.reader(for: file)

        XCTAssertEqual(reader.frameCount, 2)
        for (index, expected) in frameSamples.enumerated() {
            let frame = try reader.frame(at: index)
            guard case .gray8(let pixels) = frame.pixels else {
                return XCTFail("expected 8-bit grayscale for frame \(index)")
            }
            XCTAssertEqual(Array(pixels.prefix(4)), expected)
        }
    }

    func testFrameStreamDeliversFramesInOrderAndHonorsCancellation() async throws {
        let frameSamples: [[UInt8]] = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12]]
        let file = try Self.makeNativeMultiframeFile(framePixels: frameSamples)
        let reader = try Self.reader(for: file)

        var indexes: [Int] = []
        for try await frame in reader.frames() {
            indexes.append(frame.index)
        }
        XCTAssertEqual(indexes, [0, 1, 2])

        let consumed = expectation(description: "first frame consumed")
        let task = Task {
            var count = 0
            for try await _ in reader.frames() {
                count += 1
                consumed.fulfill()
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }
            return count
        }
        await fulfillment(of: [consumed], timeout: 10)
        task.cancel()
        let count = try? await task.value
        XCTAssertNotEqual(count, frameSamples.count, "cancellation must stop the stream early")
    }

    // MARK: - Unified typed error surface

    func testUnsupportedTransferSyntaxIsTypedWithResolverDiagnostics() throws {
        let file = try EncapsulatedFixtureFactory.makeFile(
            transferSyntax: .jpeg2000Part2MulticomponentLossless,
            fragments: [Data([0xFF, 0x4F, 0xFF, 0x51])],
            declaredFrames: 1
        )
        let reader = try Self.reader(for: file)

        XCTAssertThrowsError(try reader.frame(at: 0)) { error in
            guard case DicomDecodedFrameReader.ReadError.unsupportedTransferSyntax(let uid, let diagnostics) = error else {
                return XCTFail("expected unsupportedTransferSyntax, got \(error)")
            }
            XCTAssertEqual(uid, DicomTransferSyntax.jpeg2000Part2MulticomponentLossless.rawValue)
            XCTAssertTrue(diagnostics.contains { $0.contains("multi-component volume") })
        }
    }

    func testCorruptPayloadFailsTypedThroughTheSameSurface() throws {
        let file = try EncapsulatedFixtureFactory.makeFile(
            transferSyntax: .jpegLosslessFirstOrder,
            fragments: [Data([0x00, 0x01, 0x02, 0x03])],
            declaredFrames: 1
        )
        let reader = try Self.reader(for: file)

        XCTAssertThrowsError(try reader.frame(at: 0)) { error in
            guard case DicomDecodedFrameReader.ReadError.decodeFailed(let uid, _) = error else {
                return XCTFail("expected decodeFailed, got \(error)")
            }
            XCTAssertEqual(uid, DicomTransferSyntax.jpegLosslessFirstOrder.rawValue)
        }
    }

    func testFrameIndexOutOfRangeIsTypedForNativeAndEncapsulated() throws {
        let nativeReader = try Self.reader(for: Self.makeNativeMultiframeFile(framePixels: [[1, 2, 3, 4]]))
        XCTAssertThrowsError(try nativeReader.frame(at: 5)) { error in
            XCTAssertEqual(
                error as? DicomDecodedFrameReader.ReadError,
                .frameIndexOutOfRange(index: 5, frameCount: 1)
            )
        }

        let encapsulatedReader = try Self.reader(for: EncapsulatedFixtureFactory.makeFile(
            transferSyntax: .rleLossless,
            fragments: [Self.rleSegment(samples: [1, 2, 3, 4])],
            declaredFrames: 1
        ))
        XCTAssertThrowsError(try encapsulatedReader.frame(at: 2)) { error in
            XCTAssertEqual(
                error as? DicomDecodedFrameReader.ReadError,
                .frameIndexOutOfRange(index: 2, frameCount: 1)
            )
        }
    }

    // MARK: - Dataset entry point

    func testDataSetEntryPointDecodesEncapsulatedFrames() throws {
        let dataSet = EncapsulatedFixtureFactory.makeDataSet(
            transferSyntax: .rleLossless,
            fragments: [Self.rleSegment(samples: [11, 22, 33, 44])],
            declaredFrames: 1
        )
        let reader = try DicomDecodedFrameReader(
            dataSet: dataSet,
            options: DicomPart10WriterOptions(
                transferSyntax: .rleLossless,
                mediaStorageSOPClassUID: DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID,
                mediaStorageSOPInstanceUID: "2.25.12270001"
            )
        )

        let frame = try reader.frame(at: 0)
        guard case .gray8(let pixels) = frame.pixels else {
            return XCTFail("expected 8-bit grayscale, got \(frame.pixels)")
        }
        XCTAssertEqual(Array(pixels.prefix(4)), [11, 22, 33, 44])
        XCTAssertEqual(frame.metadata.transferSyntaxUID, DicomTransferSyntax.rleLossless.rawValue)
    }

    func testDataSetEntryPointDoesNotSerializeThroughTemporaryFile() throws {
        let source = try String(
            contentsOf: Self.packageRoot.appendingPathComponent("Sources/DicomCore/DicomDecodedFrameReader.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("decoded-frame-reader-"))
    }

    // MARK: - Helpers

    private static func reader(for fileData: Data) throws -> DicomDecodedFrameReader {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("decoded-frame-\(UUID().uuidString).dcm")
        try fileData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DicomDecodedFrameReader(contentsOf: url)
    }

    private static func makeNativeMultiframeFile(framePixels: [[UInt8]]) throws -> Data {
        var pixelData = Data()
        for frame in framePixels {
            pixelData.append(contentsOf: frame)
        }
        if pixelData.count % 2 != 0 {
            pixelData.append(0x00)
        }
        let dataSet = DicomDataSet(elements: [
            DicomDataElement(tag: DicomTag.sopClassUID.rawValue, vr: .UI,
                             value: .strings([DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID])),
            DicomDataElement(tag: DicomTag.sopInstanceUID.rawValue, vr: .UI, value: .strings(["2.25.12270002"])),
            DicomDataElement(tag: DicomTag.patientName.rawValue, vr: .PN, value: .strings(["PARITY^DECODED"])),
            DicomDataElement(tag: DicomTag.patientID.rawValue, vr: .LO, value: .strings(["PARITY-1227"])),
            DicomDataElement(tag: DicomTag.studyInstanceUID.rawValue, vr: .UI, value: .strings(["2.25.12270003"])),
            DicomDataElement(tag: DicomTag.seriesInstanceUID.rawValue, vr: .UI, value: .strings(["2.25.12270004"])),
            DicomDataElement(tag: DicomTag.modality.rawValue, vr: .CS, value: .strings(["OT"])),
            DicomDataElement(tag: DicomTag.samplesPerPixel.rawValue, vr: .US, value: .unsignedIntegers([1])),
            DicomDataElement(tag: DicomTag.photometricInterpretation.rawValue, vr: .CS, value: .strings(["MONOCHROME2"])),
            DicomDataElement(tag: DicomTag.rows.rawValue, vr: .US, value: .unsignedIntegers([2])),
            DicomDataElement(tag: DicomTag.columns.rawValue, vr: .US, value: .unsignedIntegers([2])),
            DicomDataElement(tag: DicomTag.bitsAllocated.rawValue, vr: .US, value: .unsignedIntegers([8])),
            DicomDataElement(tag: DicomTag.bitsStored.rawValue, vr: .US, value: .unsignedIntegers([8])),
            DicomDataElement(tag: DicomTag.highBit.rawValue, vr: .US, value: .unsignedIntegers([7])),
            DicomDataElement(tag: DicomTag.pixelRepresentation.rawValue, vr: .US, value: .unsignedIntegers([0])),
            DicomDataElement(tag: DicomTag.numberOfFrames.rawValue, vr: .IS,
                             value: .strings(["\(framePixels.count)"])),
            DicomDataElement(tag: DicomTag.pixelData.rawValue, vr: .OB, value: .bytes(pixelData))
        ])
        return try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                transferSyntax: .explicitVRLittleEndian,
                mediaStorageSOPClassUID: DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID,
                mediaStorageSOPInstanceUID: "2.25.12270002"
            )
        )
    }

    private static func rleSegment(samples: [UInt8]) -> Data {
        var rle = Data()
        var header = [UInt32](repeating: 0, count: 16)
        header[0] = 1
        header[1] = 64
        for value in header {
            withUnsafeBytes(of: value.littleEndian) { rle.append(contentsOf: $0) }
        }
        rle.append(UInt8(samples.count - 1))
        rle.append(contentsOf: samples)
        if rle.count % 2 != 0 {
            rle.append(0x00)
        }
        return rle
    }

    private static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
