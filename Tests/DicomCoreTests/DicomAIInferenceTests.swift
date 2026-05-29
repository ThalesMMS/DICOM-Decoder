import XCTest
@testable import DicomCore

final class DicomAIInferenceTests: XCTestCase {
    func testFindingBecomesStructuredReportWithTrackingAndSourceReferences() throws {
        let source = DicomKeyObjectReference(
            studyInstanceUID: "2.25.9001",
            seriesInstanceUID: "2.25.9002",
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "2.25.9003",
            referencedFrameNumbers: [4]
        )
        let region = DicomSRGraphicRegion(
            graphicType: "POLYLINE",
            graphicData: [1, 1, 5, 1, 5, 5, 1, 1],
            sourceImageReferences: [source.sourceImageReference]
        )
        let area = DicomAIFindingMeasurement(
            concept: DicomCodedConcept(codeValue: "42798000", codingSchemeDesignator: "SCT", codeMeaning: "Area"),
            value: 14.5,
            units: DicomCodedConcept(codeValue: "mm2", codingSchemeDesignator: "UCUM", codeMeaning: "square millimeter")
        )
        let finding = DicomAIFinding(
            title: DicomCodedConcept(codeValue: "111001", codingSchemeDesignator: "DCM", codeMeaning: "CAD Finding"),
            findingCode: DicomCodedConcept(codeValue: "85756007", codingSchemeDesignator: "SCT", codeMeaning: "Lesion"),
            description: "Synthetic test finding",
            confidence: 0.92,
            trackingID: "finding-1",
            trackingUID: "2.25.9010",
            sourceImageReferences: [source],
            regions: [region],
            measurements: [area]
        )

        let data = try DicomAIInferenceBuilder.structuredReportPart10Data(
            findings: [finding],
            options: DicomAIInferenceBuildOptions(
                sopInstanceUID: "2.25.9020",
                studyInstanceUID: "2.25.9001",
                seriesInstanceUID: "2.25.9021",
                contentLabel: "AI_SR"
            )
        )

        let decoder = try open(data: data, name: "ai_sr")
        let report = try XCTUnwrap(decoder.structuredReport)

        XCTAssertEqual(report.sopClassUID, DicomSRDocument.comprehensiveSRStorageSOPClassUID)
        XCTAssertEqual(report.sopInstanceUID, "2.25.9020")
        XCTAssertEqual(report.templateIdentifier, "1500")
        XCTAssertEqual(report.keyObjectReferences, [source])
        XCTAssertEqual(report.cadFindings.count, 1)
        XCTAssertEqual(report.cadFindings.first?.trackingID, "finding-1")
        XCTAssertEqual(report.cadFindings.first?.trackingUID, "2.25.9010")
        XCTAssertEqual(report.cadFindings.first?.sourceImageReferences, [source.sourceImageReference])
        XCTAssertEqual(report.measurements.map(\.value).sorted(), [0.92, 14.5])
        XCTAssertEqual(report.measurements.first { $0.value == 14.5 }?.roi?.graphicData, region.graphicData)
    }

    func testSyntheticMaskBecomesSegmentationWithTrackingAndLabelmap() throws {
        let source = DicomSourceImageReference(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "2.25.9101",
            referencedFrameNumbers: [1]
        )
        let segment = DicomSegment(
            number: 1,
            label: "Lesion",
            algorithmType: "AUTOMATIC",
            algorithmName: "SyntheticInference",
            trackingID: "mask-1",
            trackingUID: "2.25.9102",
            recommendedDisplayCIELabValue: [42000, 52000, 32000]
        )
        let mask = DicomAIMask(
            rows: 2,
            columns: 2,
            segment: segment,
            frames: [
                DicomAIMaskFrame(
                    index: 0,
                    sourceImageReferences: [source],
                    pixels: [1, 0, 0, 1]
                )
            ]
        )

        let data = try DicomAIInferenceBuilder.segmentationPart10Data(
            mask: mask,
            options: DicomAIInferenceBuildOptions(
                sopInstanceUID: "2.25.9103",
                studyInstanceUID: "2.25.9104",
                seriesInstanceUID: "2.25.9105",
                algorithmName: "SyntheticInference",
                contentLabel: "AI_SEG"
            )
        )

        let decoder = try open(data: data, name: "ai_seg")
        let parsed = try XCTUnwrap(decoder.segmentation)

        XCTAssertEqual(parsed.sopInstanceUID, "2.25.9103")
        XCTAssertEqual(parsed.segments.first?.trackingID, "mask-1")
        XCTAssertEqual(parsed.segments.first?.trackingUID, "2.25.9102")
        XCTAssertEqual(parsed.frames.first?.sourceImageReferences, [source])
        XCTAssertEqual(parsed.labelmaps.first?.voxels, [1, 0, 0, 1])
    }

    func testGraphicAnnotationBecomesGrayscalePresentationState() throws {
        let source = DicomKeyObjectReference(
            studyInstanceUID: "2.25.9201",
            seriesInstanceUID: "2.25.9202",
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "2.25.9203",
            referencedFrameNumbers: [2]
        )
        let dataSet = DicomAIInferenceBuilder.presentationStateDataSet(
            annotations: [
                DicomAIAnnotation(
                    layer: DicomPresentationGraphicLayer(name: "AI", order: 1, recommendedDisplayGrayscaleValue: 65535),
                    sourceImageReferences: [source],
                    graphicObject: DicomPresentationGraphicObject(
                        graphicType: "POLYLINE",
                        graphicData: [2, 2, 6, 2, 6, 6, 2, 2],
                        graphicFilled: false,
                        trackingID: "annotation-1",
                        trackingUID: "2.25.9204"
                    )
                )
            ],
            options: DicomAIInferenceBuildOptions(
                sopInstanceUID: "2.25.9205",
                studyInstanceUID: "2.25.9201",
                seriesInstanceUID: "2.25.9206",
                contentLabel: "AI_PR"
            ),
            displayedArea: DicomPresentationDisplayedArea(bottomRight: SIMD2<Int32>(512, 512))
        )
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                mediaStorageSOPClassUID: DicomGrayscalePresentationState.storageSOPClassUID,
                mediaStorageSOPInstanceUID: dataSet.string(for: .sopInstanceUID)
            )
        )

        let decoder = try open(data: data, name: "ai_pr")
        let presentation = try XCTUnwrap(decoder.grayscalePresentationState)

        XCTAssertEqual(presentation.sopInstanceUID, "2.25.9205")
        XCTAssertEqual(presentation.referencedSeries.first?.seriesInstanceUID, "2.25.9202")
        XCTAssertEqual(presentation.graphicLayers.first?.name, "AI")
        XCTAssertEqual(presentation.graphicAnnotations.first?.graphicObjects.first?.trackingID, "annotation-1")
        XCTAssertEqual(presentation.graphicAnnotations.first?.graphicObjects.first?.graphicData, [2, 2, 6, 2, 6, 6, 2, 2])
    }

    func testGrayscalePresentationStateParsesDisplayStateAndTextObjects() throws {
        let source = DicomPresentationReferencedImage(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "2.25.9303",
            referencedFrameNumbers: [1]
        )
        let window = DicomDisplayWindow(
            settings: WindowSettings(center: 50, width: 100),
            explanation: "Soft tissue",
            source: .dicom(index: 0)
        )
        let dataSet = DicomGrayscalePresentationStateBuilder.dataSet(
            referencedSeries: [
                DicomPresentationReferencedSeries(seriesInstanceUID: "2.25.9302", images: [source])
            ],
            graphicAnnotations: [
                DicomPresentationGraphicAnnotation(
                    graphicLayer: "AI",
                    referencedImages: [source],
                    graphicObjects: [
                        DicomPresentationGraphicObject(
                            graphicType: "POLYLINE",
                            graphicData: [2, 2, 4, 2, 4, 4],
                            trackingID: "display-annotation"
                        )
                    ],
                    textObjects: [
                        DicomPresentationTextObject(text: "Finding", anchorPoint: SIMD2<Double>(3, 3))
                    ]
                )
            ],
            graphicLayers: [DicomPresentationGraphicLayer(name: "AI", recommendedDisplayGrayscaleValue: 65_535)],
            options: DicomPresentationStateBuildOptions(
                sopInstanceUID: "2.25.9305",
                studyInstanceUID: "2.25.9301",
                seriesInstanceUID: "2.25.9306",
                contentLabel: "DISPLAY",
                displayedArea: DicomPresentationDisplayedArea(
                    topLeft: SIMD2<Int32>(2, 2),
                    bottomRight: SIMD2<Int32>(4, 4)
                ),
                spatialTransform: DicomPresentationSpatialTransform(
                    isHorizontallyFlipped: true,
                    rotationDegrees: 90
                ),
                shutters: [
                    .rectangular(left: 2, right: 4, upper: 2, lower: 4)
                ],
                displayTransformProfile: DicomDisplayTransformProfile(
                    windows: [window],
                    presentationLUTShape: .inverse
                ),
                iccProfile: Data([1, 2, 3])
            )
        )
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                mediaStorageSOPClassUID: DicomGrayscalePresentationState.storageSOPClassUID,
                mediaStorageSOPInstanceUID: dataSet.string(for: .sopInstanceUID)
            )
        )

        let decoder = try open(data: data, name: "display_pr")
        let presentation = try XCTUnwrap(decoder.grayscalePresentationState)

        XCTAssertEqual(presentation.displayedAreas.first?.topLeft, SIMD2<Int32>(2, 2))
        XCTAssertEqual(presentation.displayedAreas.first?.bottomRight, SIMD2<Int32>(4, 4))
        XCTAssertEqual(presentation.spatialTransform.rotationDegrees, 90)
        XCTAssertTrue(presentation.spatialTransform.isHorizontallyFlipped)
        XCTAssertEqual(presentation.shutters, [.rectangular(left: 2, right: 4, upper: 2, lower: 4)])
        XCTAssertEqual(presentation.displayTransformProfile.windows.first?.settings, window.settings)
        XCTAssertEqual(presentation.displayTransformProfile.presentationLUTShape, .inverse)
        XCTAssertEqual(presentation.graphicAnnotations.first?.textObjects.first?.text, "Finding")
        XCTAssertEqual(presentation.iccProfile, Data([1, 2, 3, 0]))
    }

    private func open(data: Data, name: String) throws -> DCMDecoder {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DCMDecoder(contentsOf: url)
    }
}
