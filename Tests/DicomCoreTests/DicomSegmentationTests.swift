import simd
import XCTest
@testable import DicomCore

final class DicomSegmentationTests: XCTestCase {
    func testBinarySegmentationRoundTripsSegmentMetadataLabelmapsAndGeometry() throws {
        let sourceReference = DicomSourceImageReference(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2.1",
            referencedSOPInstanceUID: "2.25.9001",
            referencedFrameNumbers: [7]
        )
        let segment = DicomSegment(
            number: 1,
            label: "Liver",
            description: "Binary liver mask",
            algorithmType: "AUTOMATIC",
            algorithmName: "UnitTestSegmenter",
            propertyCategory: DicomCodedConcept(codeValue: "T-D0050", codingSchemeDesignator: "SRT", codeMeaning: "Tissue"),
            propertyType: DicomCodedConcept(codeValue: "T-62000", codingSchemeDesignator: "SRT", codeMeaning: "Liver"),
            trackingID: "liver-mask",
            trackingUID: "2.25.9101",
            recommendedDisplayCIELabValue: [32896, 32896, 32896]
        )
        let segmentation = DicomSegmentation(
            sopInstanceUID: "2.25.9201",
            segmentationType: .binary,
            rows: 2,
            columns: 2,
            segments: [segment],
            frames: [
                DicomSegmentationFrame(
                    index: 0,
                    segmentNumber: 1,
                    geometry: geometry(frameIndex: 0, z: 0, sourceReference: sourceReference),
                    sourceImageReferences: [sourceReference],
                    pixelData: .binary([1, 0, 0, 1])
                ),
                DicomSegmentationFrame(
                    index: 1,
                    segmentNumber: 1,
                    geometry: geometry(frameIndex: 1, z: 1.5, sourceReference: sourceReference),
                    sourceImageReferences: [sourceReference],
                    pixelData: .binary([0, 1, 1, 0])
                )
            ]
        )

        let decoder = try open(segmentation)
        let parsed = try XCTUnwrap(decoder.segmentation)

        XCTAssertEqual(parsed.sopInstanceUID, "2.25.9201")
        XCTAssertEqual(parsed.segmentationType, .binary)
        XCTAssertNil(parsed.fractionalType)
        XCTAssertEqual(parsed.rows, 2)
        XCTAssertEqual(parsed.columns, 2)
        XCTAssertEqual(parsed.segments, [segment])
        XCTAssertEqual(parsed.frames.map(\.segmentNumber), [1, 1])
        XCTAssertEqual(parsed.frames[0].pixelData, .binary([1, 0, 0, 1]))
        XCTAssertEqual(parsed.frames[1].pixelData, .binary([0, 1, 1, 0]))

        let firstGeometry = try XCTUnwrap(parsed.frames[0].geometry)
        XCTAssertEqual(firstGeometry.imagePositionPatient, SIMD3<Double>(0, 0, 0))
        XCTAssertEqual(firstGeometry.imageOrientationPatient?.row, SIMD3<Double>(1, 0, 0))
        XCTAssertEqual(firstGeometry.imageOrientationPatient?.column, SIMD3<Double>(0, 1, 0))
        XCTAssertEqual(firstGeometry.pixelMeasures?.pixelSpacing, SIMD2<Double>(0.7, 0.8))
        XCTAssertEqual(firstGeometry.pixelMeasures?.sliceThickness, 1.5)
        XCTAssertEqual(firstGeometry.sourceImageReferences, [sourceReference])
        XCTAssertEqual(parsed.frames[1].geometry?.imagePositionPatient, SIMD3<Double>(0, 0, 1.5))

        let labelmap = try XCTUnwrap(parsed.labelmapsBySegment[1])
        XCTAssertEqual(labelmap.frameIndexes, [0, 1])
        XCTAssertEqual(labelmap.voxels, [1, 0, 0, 1, 0, 1, 1, 0])
        XCTAssertNil(labelmap.fractionalVoxels)
        XCTAssertEqual(labelmap.sourceImageReferences[0], [sourceReference])
    }

    func testFractionalSegmentationRoundTripsValuesAndLabelmap() throws {
        let segment = DicomSegment(
            number: 2,
            label: "Probability",
            algorithmType: "SEMIAUTOMATIC",
            algorithmName: "UnitTestFractional",
            trackingUID: "2.25.9301"
        )
        let segmentation = DicomSegmentation(
            sopInstanceUID: "2.25.9302",
            segmentationType: .fractional,
            fractionalType: .probability,
            maximumFractionalValue: 255,
            rows: 2,
            columns: 2,
            segments: [segment],
            frames: [
                DicomSegmentationFrame(
                    index: 0,
                    segmentNumber: 2,
                    geometry: geometry(frameIndex: 0, z: 3, sourceReference: nil),
                    pixelData: .fractional(values: [0, 64, 128, 255], maximumFractionalValue: 255)
                )
            ]
        )

        let decoder = try open(segmentation)
        let parsed = try XCTUnwrap(decoder.segmentation)

        XCTAssertEqual(parsed.segmentationType, .fractional)
        XCTAssertEqual(parsed.fractionalType, .probability)
        XCTAssertEqual(parsed.maximumFractionalValue, 255)
        XCTAssertEqual(parsed.segments, [segment])
        XCTAssertEqual(parsed.frames.first?.pixelData, .fractional(values: [0, 64, 128, 255], maximumFractionalValue: 255))
        XCTAssertEqual(parsed.frames.first?.geometry?.imagePositionPatient, SIMD3<Double>(0, 0, 3))

        let labelmap = try XCTUnwrap(parsed.labelmapsBySegment[2])
        XCTAssertEqual(labelmap.voxels, [0, 2, 2, 2])
        XCTAssertEqual(labelmap.fractionalVoxels, [0, 64, 128, 255])
    }

    func testSegmentationParsesImplicitVRLittleEndian() throws {
        let segment = DicomSegment(number: 3, label: "Implicit")
        let segmentation = DicomSegmentation(
            sopInstanceUID: "2.25.9501",
            segmentationType: .binary,
            rows: 2,
            columns: 2,
            segments: [segment],
            frames: [
                DicomSegmentationFrame(
                    index: 0,
                    segmentNumber: 3,
                    pixelData: .binary([1, 0, 1, 0])
                )
            ]
        )

        let decoder = try open(segmentation, transferSyntax: .implicitVRLittleEndian)
        let parsed = try XCTUnwrap(decoder.segmentation)

        XCTAssertEqual(parsed.segments, [segment])
        XCTAssertEqual(parsed.frames.first?.pixelData, .binary([1, 0, 1, 0]))
        XCTAssertEqual(parsed.labelmapsBySegment[3]?.voxels, [3, 0, 3, 0])
    }

    private func open(
        _ segmentation: DicomSegmentation,
        transferSyntax: DicomTransferSyntax = .explicitVRLittleEndian
    ) throws -> DCMDecoder {
        let dataSet = DicomSegmentationBuilder.dataSet(
            from: segmentation,
            studyInstanceUID: "2.25.9401",
            seriesInstanceUID: "2.25.9402"
        )
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                transferSyntax: transferSyntax,
                mediaStorageSOPClassUID: DicomSegmentationBuilder.segmentationStorageSOPClassUID,
                mediaStorageSOPInstanceUID: segmentation.sopInstanceUID
            )
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("segmentation_\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DCMDecoder(contentsOf: url)
    }

    private func geometry(
        frameIndex: Int,
        z: Double,
        sourceReference: DicomSourceImageReference?
    ) -> DicomFrameGeometry {
        let derivationImage = sourceReference.map { DicomDerivationImage(sourceImages: [$0]) }
        return DicomFrameGeometry(
            frameIndex: frameIndex,
            functionalGroups: DicomFrameFunctionalGroups(
                frameContent: DicomFrameContent(
                    dimensionIndexValues: [frameIndex + 1],
                    stackID: "SEG",
                    inStackPositionNumber: frameIndex + 1,
                    temporalPositionIndex: nil,
                    frameAcquisitionNumber: nil
                ),
                pixelMeasures: DicomPixelMeasures(
                    pixelSpacing: SIMD2<Double>(0.7, 0.8),
                    sliceThickness: 1.5,
                    spacingBetweenSlices: 1.5
                ),
                planePosition: DicomPlanePosition(imagePositionPatient: SIMD3<Double>(0, 0, z)),
                planeOrientation: DicomPlaneOrientation(
                    row: SIMD3<Double>(1, 0, 0),
                    column: SIMD3<Double>(0, 1, 0)
                ),
                derivationImage: derivationImage
            )
        )!
    }
}
