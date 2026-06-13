//
//  DicomEnhancedMultiframeVolumeTests.swift
//  DicomCoreTests
//
//  Enhanced CT/MR multiframe volume assembly (issue #1234): synthetic
//  non-PHI Enhanced objects with Shared/Per-Frame Functional Groups
//  assemble into volumes with frame ordering by Plane Position, mixed
//  per-frame rescale, geometry metadata, and the same path for native
//  and compressed (RLE) frames; unsupported shapes fail typed with SOP
//  Class, frame count, transfer syntax, and the missing functional-group
//  context.
//

import Foundation
import XCTest
import simd
@testable import DicomCore

final class DicomEnhancedMultiframeVolumeTests: XCTestCase {
    private static let enhancedCTSOPClassUID = "1.2.840.10008.5.1.4.1.1.2.1"

    // MARK: - Native Enhanced CT assembly

    func testEnhancedCTVolumeAssemblesWithSpatialOrderingAndPerFrameRescale() throws {
        // Frames are stored out of spatial order: z positions 5.0, 0.0, 2.5.
        let url = try Self.writeEnhancedObject(
            zPositions: [5.0, 0.0, 2.5],
            frameIntercepts: ["-1024", "-1000", "-1012"],
            framePixelValues: [[10, 20, 30, 40], [50, 60, 70, 80], [90, 100, 110, 120]]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let volume = try DicomSeriesLoader().loadEnhancedMultiframeVolume(at: url)

        XCTAssertEqual(volume.width, 2)
        XCTAssertEqual(volume.height, 2)
        XCTAssertEqual(volume.depth, 3)
        XCTAssertEqual(volume.spacing.x, 0.75, accuracy: 1e-9, "row spacing maps to in-plane x")
        XCTAssertEqual(volume.spacing.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(volume.spacing.z, 2.5, accuracy: 1e-9, "z spacing from ordered position deltas")
        XCTAssertEqual(volume.origin, SIMD3<Double>(0, 0, 0), "origin is the spatially first frame")
        XCTAssertEqual(volume.modality, "CT")

        // Spatial order: frame 1 (z=0), frame 2 (z=2.5), frame 0 (z=5).
        let voxels = volume.voxels.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(voxels, [50, 60, 70, 80, 90, 100, 110, 120, 10, 20, 30, 40])

        XCTAssertEqual(volume.sliceRescaleParameters.map(\.intercept), [-1000, -1012, -1024],
                       "per-frame Pixel Value Transformation intercepts follow the spatial order")
        XCTAssertEqual(volume.sliceRescaleParameters.map(\.slope), [1, 1, 1])
        XCTAssertEqual(volume.rescaleIntercept, -1000, accuracy: 1e-9, "volume rescale comes from the first spatial frame")
    }

    /// Compressed multiframe objects assemble through exactly the same
    /// decoded-frame path: per-frame RLE fragments decode one at a time.
    func testCompressedRLEEnhancedObjectAssemblesThroughTheSamePath() throws {
        let frameSamples: [[UInt8]] = [[10, 20, 30, 40], [50, 60, 70, 80]]
        let fragments = frameSamples.map { Self.rleSegment(samples: $0) }
        var dataSet = EncapsulatedFixtureFactory.makeDataSet(
            transferSyntax: .rleLossless,
            fragments: fragments,
            declaredFrames: 2,
            rows: 2,
            columns: 2
        )
        Self.appendFunctionalGroups(
            to: &dataSet,
            zPositions: [2.0, 0.0],
            frameIntercepts: ["-10", "-20"]
        )
        let url = try Self.write(dataSet: dataSet, transferSyntax: .rleLossless)
        defer { try? FileManager.default.removeItem(at: url) }

        let volume = try DicomSeriesLoader().loadEnhancedMultiframeVolume(at: url)

        XCTAssertEqual(volume.depth, 2)
        let voxels = volume.voxels.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        // Spatial order: frame 1 (z=0) before frame 0 (z=2).
        XCTAssertEqual(voxels, [50, 60, 70, 80, 10, 20, 30, 40])
        XCTAssertEqual(volume.sliceRescaleParameters.map(\.intercept), [-20, -10])
    }

    // MARK: - Typed rejections with full context

    func testMissingPlanePositionFailsTypedWithFunctionalGroupContext() throws {
        let url = try Self.writeEnhancedObject(
            zPositions: [0.0, 2.5],
            frameIntercepts: ["-1024", "-1024"],
            framePixelValues: [[1, 2, 3, 4], [5, 6, 7, 8]],
            omitPlanePositionForFrame: 1
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try DicomSeriesLoader().loadEnhancedMultiframeVolume(at: url)) { error in
            guard case DicomSeriesLoaderError.unsupportedEnhancedMultiframe(let context) = error else {
                return XCTFail("expected unsupportedEnhancedMultiframe, got \(error)")
            }
            XCTAssertEqual(context.sopClassUID, Self.enhancedCTSOPClassUID)
            XCTAssertEqual(context.frameCount, 2)
            XCTAssertEqual(context.transferSyntaxUID, DicomTransferSyntax.explicitVRLittleEndian.rawValue)
            XCTAssertTrue(context.reason.contains("Plane Position"), context.reason)
        }
    }

    func testObjectWithoutFunctionalGroupsFailsTyped() throws {
        var dataSet = EncapsulatedFixtureFactory.makeDataSet(
            transferSyntax: .explicitVRLittleEndian,
            fragments: [],
            declaredFrames: 2,
            rows: 2,
            columns: 2,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15
        )
        dataSet.set(DicomDataElement(tag: DicomTag.sopClassUID.rawValue, vr: .UI,
                                     value: .strings([Self.enhancedCTSOPClassUID])))
        dataSet.set(DicomDataElement(tag: DicomTag.numberOfFrames.rawValue, vr: .IS, value: .strings(["2"])))
        dataSet.set(DicomDataElement(tag: DicomTag.pixelData.rawValue, vr: .OW,
                                     value: .bytes(Data(count: 16))))
        let url = try Self.write(dataSet: dataSet, transferSyntax: .explicitVRLittleEndian)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try DicomSeriesLoader().loadEnhancedMultiframeVolume(at: url)) { error in
            guard case DicomSeriesLoaderError.unsupportedEnhancedMultiframe(let context) = error else {
                return XCTFail("expected unsupportedEnhancedMultiframe, got \(error)")
            }
            XCTAssertTrue(context.reason.contains("Functional Groups"), context.reason)
        }
    }

    func testSingleFrameObjectIsRedirectedTyped() throws {
        let url = try Self.writeEnhancedObject(
            zPositions: [0.0],
            frameIntercepts: ["-1024"],
            framePixelValues: [[1, 2, 3, 4]]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try DicomSeriesLoader().loadEnhancedMultiframeVolume(at: url)) { error in
            guard case DicomSeriesLoaderError.unsupportedEnhancedMultiframe(let context) = error else {
                return XCTFail("expected unsupportedEnhancedMultiframe, got \(error)")
            }
            XCTAssertEqual(context.frameCount, 1)
            XCTAssertTrue(context.reason.contains("single frame"), context.reason)
        }
    }

    func testDuplicateFramePositionsFailTyped() throws {
        let url = try Self.writeEnhancedObject(
            zPositions: [1.0, 1.0],
            frameIntercepts: ["-1024", "-1024"],
            framePixelValues: [[1, 2, 3, 4], [5, 6, 7, 8]]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try DicomSeriesLoader().loadEnhancedMultiframeVolume(at: url)) { error in
            guard case DicomSeriesLoaderError.duplicateSlicePosition = error else {
                return XCTFail("expected duplicateSlicePosition, got \(error)")
            }
        }
    }

    // MARK: - Builders (deterministic, non-PHI)

    private static func writeEnhancedObject(
        zPositions: [Double],
        frameIntercepts: [String],
        framePixelValues: [[Int16]],
        omitPlanePositionForFrame: Int? = nil
    ) throws -> URL {
        var pixelData = Data()
        for frame in framePixelValues {
            for value in frame {
                let pattern = UInt16(bitPattern: value)
                pixelData.append(UInt8(pattern & 0xFF))
                pixelData.append(UInt8(pattern >> 8))
            }
        }

        var dataSet = EncapsulatedFixtureFactory.makeDataSet(
            transferSyntax: .explicitVRLittleEndian,
            fragments: [],
            declaredFrames: zPositions.count,
            rows: 2,
            columns: 2,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15
        )
        dataSet.set(DicomDataElement(tag: DicomTag.pixelData.rawValue, vr: .OW, value: .bytes(pixelData)))
        appendFunctionalGroups(
            to: &dataSet,
            zPositions: zPositions,
            frameIntercepts: frameIntercepts,
            omitPlanePositionForFrame: omitPlanePositionForFrame
        )
        return try write(dataSet: dataSet, transferSyntax: .explicitVRLittleEndian)
    }

    private static func appendFunctionalGroups(
        to dataSet: inout DicomDataSet,
        zPositions: [Double],
        frameIntercepts: [String],
        omitPlanePositionForFrame: Int? = nil
    ) {
        dataSet.set(DicomDataElement(tag: DicomTag.sopClassUID.rawValue, vr: .UI,
                                     value: .strings([enhancedCTSOPClassUID])))
        dataSet.set(DicomDataElement(tag: DicomTag.modality.rawValue, vr: .CS, value: .strings(["CT"])))
        dataSet.set(DicomDataElement(tag: DicomTag.patientName.rawValue, vr: .PN, value: .strings(["PARITY^ENHANCED"])))
        dataSet.set(DicomDataElement(tag: DicomTag.patientID.rawValue, vr: .LO, value: .strings(["PARITY-1234"])))
        dataSet.set(DicomDataElement(tag: DicomTag.numberOfFrames.rawValue, vr: .IS,
                                     value: .strings(["\(zPositions.count)"])))

        let shared = DicomDataSet(elements: [
            sequence(.pixelMeasuresSequence, [
                DicomDataSet(elements: [
                    ds(.pixelSpacing, ["0.5", "0.75"]),
                    ds(.sliceThickness, ["2.5"])
                ])
            ]),
            sequence(.planeOrientationSequence, [
                DicomDataSet(elements: [
                    ds(.imageOrientationPatient, ["1", "0", "0", "0", "1", "0"])
                ])
            ])
        ])
        dataSet.set(sequence(.sharedFunctionalGroupsSequence, [shared]))

        let perFrame = zPositions.enumerated().map { index, z -> DicomDataSet in
            var elements = [DicomDataElement]()
            if index != omitPlanePositionForFrame {
                elements.append(sequence(.planePositionSequence, [
                    DicomDataSet(elements: [
                        ds(.imagePositionPatient, ["0", "0", String(z)])
                    ])
                ]))
            }
            elements.append(sequence(.pixelValueTransformationSequence, [
                DicomDataSet(elements: [
                    ds(.rescaleIntercept, [frameIntercepts[index]]),
                    ds(.rescaleSlope, ["1"])
                ])
            ]))
            return DicomDataSet(elements: elements)
        }
        dataSet.set(sequence(.perFrameFunctionalGroupsSequence, perFrame))
    }

    private static func write(dataSet: DicomDataSet, transferSyntax: DicomTransferSyntax) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("enhanced_volume_\(UUID().uuidString).dcm")
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                transferSyntax: transferSyntax,
                mediaStorageSOPClassUID: enhancedCTSOPClassUID,
                mediaStorageSOPInstanceUID: "2.25.12340001"
            )
        )
        try data.write(to: url)
        return url
    }

    private static func sequence(_ tag: DicomTag, _ dataSets: [DicomDataSet]) -> DicomDataElement {
        DicomDataElement(
            tag: tag.rawValue,
            vr: .SQ,
            value: .sequence(dataSets.map { DicomSequenceItem(dataSet: $0) })
        )
    }

    private static func ds(_ tag: DicomTag, _ values: [String]) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .DS, value: .strings(values))
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
}
