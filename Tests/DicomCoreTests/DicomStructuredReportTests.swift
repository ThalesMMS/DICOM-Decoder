import XCTest
@testable import DicomCore

final class DicomStructuredReportTests: XCTestCase {
    func testStructuredReportParsesMeasurementsROIsCADFindingsAndRoundTrips() throws {
        let source = DicomSourceImageReference(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "2.25.7001",
            referencedFrameNumbers: [3]
        )
        let keyReference = DicomKeyObjectReference(
            studyInstanceUID: "2.25.7000",
            seriesInstanceUID: "2.25.7002",
            referencedSOPClassUID: source.referencedSOPClassUID,
            referencedSOPInstanceUID: source.referencedSOPInstanceUID,
            referencedFrameNumbers: source.referencedFrameNumbers
        )
        let area = DicomCodedConcept(codeValue: "42798000", codingSchemeDesignator: "SCT", codeMeaning: "Area")
        let squareMillimeter = DicomCodedConcept(codeValue: "mm2", codingSchemeDesignator: "UCUM", codeMeaning: "square millimeter")
        let reportTitle = DicomCodedConcept(codeValue: "126000", codingSchemeDesignator: "DCM", codeMeaning: "Imaging Measurement Report")
        let findingTitle = DicomCodedConcept(codeValue: "111001", codingSchemeDesignator: "DCM", codeMeaning: "CAD Finding")
        let keyImage = DicomCodedConcept(codeValue: "113000", codingSchemeDesignator: "DCM", codeMeaning: "Key Object")

        let roi = DicomSRContentItem(
            relationshipType: "INFERRED FROM",
            valueType: "SCOORD",
            conceptName: DicomCodedConcept(codeValue: "111030", codingSchemeDesignator: "DCM", codeMeaning: "Image Region"),
            graphicType: "POLYLINE",
            graphicData: [1, 2, 3, 4, 5, 6],
            children: [
                DicomSRContentItem(
                    relationshipType: "SELECTED FROM",
                    valueType: "IMAGE",
                    conceptName: keyImage,
                    referencedSOPs: [source]
                )
            ]
        )
        let measurement = DicomSRContentItem(
            relationshipType: "CONTAINS",
            valueType: "NUM",
            conceptName: area,
            numericValue: 42.5,
            measurementUnits: squareMillimeter,
            trackingID: "lesion-area",
            trackingUID: "2.25.7101",
            children: [roi]
        )
        let cadFinding = DicomSRContentItem(
            relationshipType: "CONTAINS",
            valueType: "CONTAINER",
            conceptName: findingTitle,
            trackingID: "cad-finding-1",
            children: [
                DicomSRContentItem(
                    relationshipType: "CONTAINS",
                    valueType: "IMAGE",
                    conceptName: keyImage,
                    referencedSOPs: [source]
                ),
                DicomSRContentItem(
                    relationshipType: "CONTAINS",
                    valueType: "NUM",
                    conceptName: area,
                    numericValue: 12.0,
                    measurementUnits: squareMillimeter
                )
            ]
        )
        let document = DicomSRDocument(
            sopClassUID: DicomSRDocument.comprehensiveSRStorageSOPClassUID,
            sopInstanceUID: "2.25.7201",
            contentLabel: "MEASUREMENTS",
            completionFlag: "COMPLETE",
            verificationFlag: "UNVERIFIED",
            templateIdentifier: "1500",
            root: DicomSRContentItem(
                valueType: "CONTAINER",
                conceptName: reportTitle,
                continuityOfContent: "SEPARATE",
                children: [measurement, cadFinding]
            ),
            evidenceReferences: [keyReference]
        )

        let decoder = try open(document: document)
        let parsed = try XCTUnwrap(decoder.structuredReport)

        XCTAssertEqual(parsed.sopInstanceUID, "2.25.7201")
        XCTAssertEqual(parsed.templateIdentifier, "1500")
        XCTAssertEqual(parsed.root.conceptName, reportTitle)
        XCTAssertEqual(parsed.flattenedContentItems.count, 7)
        XCTAssertEqual(parsed.measurements.count, 2)
        XCTAssertEqual(parsed.measurements.first?.name, area)
        XCTAssertEqual(parsed.measurements.first?.value, 42.5)
        XCTAssertEqual(parsed.measurements.first?.units, squareMillimeter)
        XCTAssertEqual(parsed.measurements.first?.trackingID, "lesion-area")
        XCTAssertEqual(parsed.measurements.first?.roi?.graphicType, "POLYLINE")
        XCTAssertEqual(parsed.measurements.first?.roi?.graphicData, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(parsed.measurements.first?.sourceImageReferences, [source])
        XCTAssertEqual(parsed.cadFindings.count, 1)
        XCTAssertEqual(parsed.cadFindings.first?.title, findingTitle)
        XCTAssertEqual(parsed.cadFindings.first?.measurements.first?.value, 12.0)
        XCTAssertEqual(parsed.keyObjectReferences, [keyReference])

        let reopened = try open(document: parsed)
        let reparsed = try XCTUnwrap(reopened.structuredReport)
        XCTAssertEqual(reparsed.measurements.map(\.value), [42.5, 12.0])
        XCTAssertEqual(reparsed.cadFindings.first?.sourceImageReferences, [source])
    }

    func testKeyObjectSelectionBuilderProducesNavigableReferences() throws {
        let keyObject = DicomKeyObjectReference(
            studyInstanceUID: "2.25.8001",
            seriesInstanceUID: "2.25.8002",
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "2.25.8003",
            referencedFrameNumbers: [5]
        )
        let title = DicomCodedConcept(codeValue: "113000", codingSchemeDesignator: "DCM", codeMeaning: "Key Object")
        let dataSet = DicomKeyObjectSelectionBuilder.dataSet(
            title: title,
            keyObjects: [keyObject],
            studyInstanceUID: "2.25.8001",
            seriesInstanceUID: "2.25.8100",
            sopInstanceUID: "2.25.8200"
        )

        let decoder = try open(dataSet: dataSet, sopClassUID: DicomSRDocument.keyObjectSelectionDocumentStorageSOPClassUID)
        let kos = try XCTUnwrap(decoder.keyObjectSelection)

        XCTAssertEqual(kos.sopClassUID, DicomSRDocument.keyObjectSelectionDocumentStorageSOPClassUID)
        XCTAssertEqual(kos.modality, "KO")
        XCTAssertEqual(kos.root.conceptName, title)
        XCTAssertEqual(kos.keyObjectReferences, [keyObject])
        XCTAssertEqual(kos.contentItems(matching: { $0.valueType == "IMAGE" }).first?.referencedSOPs.first, keyObject.sourceImageReference)
    }

    private func open(document: DicomSRDocument) throws -> DCMDecoder {
        let dataSet = DicomStructuredReportBuilder.dataSet(
            from: document,
            studyInstanceUID: "2.25.7000",
            seriesInstanceUID: "2.25.7300",
            sopInstanceUID: document.sopInstanceUID
        )
        return try open(dataSet: dataSet, sopClassUID: document.sopClassUID ?? DicomSRDocument.enhancedSRStorageSOPClassUID)
    }

    private func open(dataSet: DicomDataSet, sopClassUID: String) throws -> DCMDecoder {
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                mediaStorageSOPClassUID: sopClassUID,
                mediaStorageSOPInstanceUID: dataSet.string(for: .sopInstanceUID)
            )
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("structured_report_\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DCMDecoder(contentsOf: url)
    }
}
