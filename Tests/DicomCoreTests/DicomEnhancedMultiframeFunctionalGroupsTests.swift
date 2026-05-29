import simd
import XCTest
@testable import DicomCore

final class DicomEnhancedMultiframeFunctionalGroupsTests: XCTestCase {
    func testEnhancedFunctionalGroupsResolveSharedAndPerFrameGeometry() throws {
        for fixture in Self.enhancedStorageFixtures {
            let decoder = try openEnhancedFixture(transferSyntax: .explicitVRLittleEndian, fixture: fixture)
            try assertEnhancedFunctionalGroups(on: decoder, referencedSOPClassUID: fixture.sopClassUID)
        }
    }

    func testEnhancedFunctionalGroupsParseImplicitVRLittleEndian() throws {
        let decoder = try openEnhancedFixture(transferSyntax: .implicitVRLittleEndian, fixture: Self.enhancedStorageFixtures[0])
        let groups = try XCTUnwrap(decoder.enhancedMultiframeFunctionalGroups)

        XCTAssertEqual(groups.frameCount, 3)
        XCTAssertEqual(groups.geometry(forFrame: 1)?.imagePositionPatient, SIMD3<Double>(0, 0, 1.5))
        XCTAssertEqual(groups.framesInSpatialOrder.map(\.index), [2, 1, 0])
        XCTAssertEqual(groups.framesInTemporalOrder.map(\.index), [1, 0, 2])
        XCTAssertTrue(decoder.pixelsNotLoaded)
    }

    func testEnhancedFunctionalGroupsReturnNilWhenSequencesAreAbsent() throws {
        let dataSet = baseImageDataSet(elements: [], fixture: Self.enhancedStorageFixtures[0])
        let decoder = try open(dataSet: dataSet, fixture: Self.enhancedStorageFixtures[0])

        XCTAssertNil(decoder.enhancedMultiframeFunctionalGroups)
        XCTAssertNil(decoder.enhancedFrameGeometry(at: 0))
    }

    private func assertEnhancedFunctionalGroups(
        on decoder: DCMDecoder,
        referencedSOPClassUID: String
    ) throws {
        let groups = try XCTUnwrap(decoder.enhancedMultiframeFunctionalGroups)

        XCTAssertTrue(decoder.pixelsNotLoaded)
        XCTAssertEqual(groups.frameCount, 3)
        XCTAssertEqual(groups.shared?.pixelMeasures?.pixelSpacing, SIMD2<Double>(0.5, 0.75))
        XCTAssertEqual(groups.shared?.pixelMeasures?.sliceThickness, 1.25)
        XCTAssertEqual(groups.shared?.pixelMeasures?.spacingBetweenSlices, 1.5)

        let first = try XCTUnwrap(groups.geometry(forFrame: 0))
        XCTAssertEqual(first.imagePositionPatient, SIMD3<Double>(0, 0, 3))
        XCTAssertEqual(first.imageOrientationPatient?.row, SIMD3<Double>(1, 0, 0))
        XCTAssertEqual(first.imageOrientationPatient?.column, SIMD3<Double>(0, 1, 0))
        XCTAssertEqual(first.positionAlongNormal, 3)
        XCTAssertEqual(first.frameContent?.dimensionIndexValues, [2, 3])
        XCTAssertEqual(first.frameContent?.stackID, "A")
        XCTAssertEqual(first.frameContent?.inStackPositionNumber, 3)
        XCTAssertEqual(first.frameContent?.temporalPositionIndex, 2)
        XCTAssertEqual(first.frameContent?.frameAcquisitionNumber, 20)

        let sourceReference = try XCTUnwrap(first.sourceImageReferences.first)
        XCTAssertEqual(sourceReference.referencedSOPClassUID, referencedSOPClassUID)
        XCTAssertEqual(sourceReference.referencedSOPInstanceUID, "1.2.826.0.1.3680043.10.221.1")
        XCTAssertEqual(sourceReference.referencedFrameNumbers, [7])

        XCTAssertEqual(groups.framesInSpatialOrder.map(\.index), [2, 1, 0])
        XCTAssertEqual(groups.framesInTemporalOrder.map(\.index), [1, 0, 2])
        XCTAssertEqual(decoder.enhancedFrameGeometry(at: 2)?.imagePositionPatient, SIMD3<Double>(0, 0, 0))
        XCTAssertNil(decoder.enhancedFrameGeometry(at: 3))
        XCTAssertTrue(decoder.pixelsNotLoaded)
    }

    private func openEnhancedFixture(
        transferSyntax: DicomTransferSyntax,
        fixture: EnhancedStorageFixture
    ) throws -> DCMDecoder {
        try open(dataSet: enhancedDataSet(fixture: fixture), transferSyntax: transferSyntax, fixture: fixture)
    }

    private func open(
        dataSet: DicomDataSet,
        transferSyntax: DicomTransferSyntax = .explicitVRLittleEndian,
        fixture: EnhancedStorageFixture
    ) throws -> DCMDecoder {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("enhanced_multiframe_\(UUID().uuidString).dcm")
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                transferSyntax: transferSyntax,
                mediaStorageSOPClassUID: fixture.sopClassUID
            )
        )
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DCMDecoder(contentsOf: url)
    }

    private func enhancedDataSet(fixture: EnhancedStorageFixture) -> DicomDataSet {
        baseImageDataSet(elements: [
            sequence(.sharedFunctionalGroupsSequence, [
                DicomDataSet(elements: [
                    sequence(.pixelMeasuresSequence, [
                        DicomDataSet(elements: [
                            ds(.pixelSpacing, ["0.5", "0.75"]),
                            ds(.sliceThickness, ["1.25"]),
                            ds(.sliceSpacing, ["1.5"])
                        ])
                    ]),
                    sequence(.planeOrientationSequence, [
                        DicomDataSet(elements: [
                            ds(.imageOrientationPatient, ["1", "0", "0", "0", "1", "0"])
                        ])
                    ])
                ])
            ]),
            sequence(.perFrameFunctionalGroupsSequence, [
                perFrameDataSet(
                    z: 3,
                    dimensionIndexValues: [2, 3],
                    inStackPositionNumber: 3,
                    temporalPositionIndex: 2,
                    frameAcquisitionNumber: 20,
                    sourceFrame: 7,
                    fixture: fixture
                ),
                perFrameDataSet(
                    z: 1.5,
                    dimensionIndexValues: [1, 2],
                    inStackPositionNumber: 2,
                    temporalPositionIndex: 1,
                    frameAcquisitionNumber: 10,
                    sourceFrame: nil,
                    fixture: fixture
                ),
                perFrameDataSet(
                    z: 0,
                    dimensionIndexValues: [3, 1],
                    inStackPositionNumber: 1,
                    temporalPositionIndex: 3,
                    frameAcquisitionNumber: 30,
                    sourceFrame: nil,
                    fixture: fixture
                )
            ])
        ], fixture: fixture)
    }

    private func perFrameDataSet(
        z: Double,
        dimensionIndexValues: [Int],
        inStackPositionNumber: Int,
        temporalPositionIndex: Int,
        frameAcquisitionNumber: Int,
        sourceFrame: Int?,
        fixture: EnhancedStorageFixture
    ) -> DicomDataSet {
        var elements = [
            sequence(.frameContentSequence, [
                DicomDataSet(elements: [
                    ul(.dimensionIndexValues, dimensionIndexValues),
                    string(.stackID, vr: .SH, "A"),
                    ul(.inStackPositionNumber, [inStackPositionNumber]),
                    ul(.temporalPositionIndex, [temporalPositionIndex]),
                    ul(.frameAcquisitionNumber, [frameAcquisitionNumber])
                ])
            ]),
            sequence(.planePositionSequence, [
                DicomDataSet(elements: [
                    ds(.imagePositionPatient, ["0", "0", String(z)])
                ])
            ])
        ]

        if let sourceFrame {
            elements.append(sequence(.derivationImageSequence, [
                DicomDataSet(elements: [
                    sequence(.sourceImageSequence, [
                        DicomDataSet(elements: [
                            string(.referencedSOPClassUID, vr: .UI, fixture.sopClassUID),
                            string(.referencedSOPInstanceUID, vr: .UI, "1.2.826.0.1.3680043.10.221.1"),
                            string(.referencedFrameNumber, vr: .IS, String(sourceFrame))
                        ])
                    ])
                ])
            ]))
        }

        return DicomDataSet(elements: elements)
    }

    private func baseImageDataSet(
        elements extraElements: [DicomDataElement],
        fixture: EnhancedStorageFixture
    ) -> DicomDataSet {
        DicomDataSet(elements: [
            string(0x00080016, vr: .UI, fixture.sopClassUID),
            string(.sopInstanceUID, vr: .UI, "1.2.826.0.1.3680043.10.221.221"),
            string(.modality, vr: .CS, fixture.modality),
            us(.samplesPerPixel, 1),
            string(.photometricInterpretation, vr: .CS, "MONOCHROME2"),
            string(.numberOfFrames, vr: .IS, "3"),
            us(.rows, 1),
            us(.columns, 1),
            us(.bitsAllocated, 16),
            us(.bitsStored, 16),
            us(.highBit, 15),
            us(.pixelRepresentation, 0),
            bytes(.pixelData, vr: .OW, Data([1, 0, 2, 0, 3, 0]))
        ] + extraElements)
    }

    private func sequence(_ tag: DicomTag, _ dataSets: [DicomDataSet]) -> DicomDataElement {
        DicomDataElement(
            tag: tag.rawValue,
            vr: .SQ,
            value: .sequence(dataSets.map { DicomSequenceItem(dataSet: $0) })
        )
    }

    private func string(_ tag: DicomTag, vr: DicomVR, _ value: String) -> DicomDataElement {
        string(tag.rawValue, vr: vr, value)
    }

    private func string(_ tag: Int, vr: DicomVR, _ value: String) -> DicomDataElement {
        DicomDataElement(tag: tag, vr: vr, value: .strings([value]))
    }

    private func ds(_ tag: DicomTag, _ values: [String]) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .DS, value: .strings(values))
    }

    private func us(_ tag: DicomTag, _ value: Int) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .US, value: .unsignedIntegers([UInt(value)]))
    }

    private func ul(_ tag: DicomTag, _ values: [Int]) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .UL, value: .unsignedIntegers(values.map(UInt.init)))
    }

    private func bytes(_ tag: DicomTag, vr: DicomVR, _ value: Data) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: vr, value: .bytes(value))
    }

    private struct EnhancedStorageFixture {
        let modality: String
        let sopClassUID: String
    }

    private static let enhancedStorageFixtures = [
        EnhancedStorageFixture(modality: "CT", sopClassUID: "1.2.840.10008.5.1.4.1.1.2.1"),
        EnhancedStorageFixture(modality: "MR", sopClassUID: "1.2.840.10008.5.1.4.1.1.4.1"),
        EnhancedStorageFixture(modality: "PT", sopClassUID: "1.2.840.10008.5.1.4.1.1.130")
    ]
}
