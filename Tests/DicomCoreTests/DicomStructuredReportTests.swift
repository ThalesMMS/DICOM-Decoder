import XCTest
@testable import DicomCore

final class DicomStructuredReportTests: XCTestCase {
    func testStructuredReportSemanticSupportMatrixDeclaresValidatedScope() {
        let matrix = DicomSRSupportMatrix.standard

        XCTAssertTrue(matrix.supportedSOPClassUIDs.contains(DicomSRDocument.enhancedSRStorageSOPClassUID))
        XCTAssertTrue(matrix.supportedSOPClassUIDs.contains(DicomSRDocument.comprehensiveSRStorageSOPClassUID))
        XCTAssertTrue(matrix.supportedSOPClassUIDs.contains(
            DicomSRDocument.keyObjectSelectionDocumentStorageSOPClassUID
        ))
        XCTAssertEqual(
            matrix.supportedTemplateIdentifiersBySOPClassUID[DicomSRDocument.comprehensiveSRStorageSOPClassUID],
            ["1500"]
        )
        XCTAssertEqual(
            matrix.supportedTemplateIdentifiersBySOPClassUID[
                DicomSRDocument.keyObjectSelectionDocumentStorageSOPClassUID
            ],
            []
        )
        XCTAssertTrue(matrix.supportedValueTypes.isSuperset(of: ["CONTAINER", "NUM", "IMAGE", "SCOORD", "CODE"]))
        XCTAssertTrue(matrix.supportedRelationshipTypes.isSuperset(of: ["CONTAINS", "INFERRED FROM", "SELECTED FROM"]))
        XCTAssertTrue(matrix.supportedByReferenceRelationshipTypes.isEmpty)
        XCTAssertTrue(matrix.supportedCodingSchemeDesignators.isSuperset(of: ["DCM", "SCT", "UCUM"]))
        XCTAssertTrue(matrix.supportedMeasurementUnitSchemes.contains("UCUM"))
        XCTAssertTrue(matrix.supportedMeasurementGroups.contains("TID1500 Imaging Measurement Report"))
        XCTAssertTrue(matrix.supportedObservationContextValueTypes.isSuperset(of: ["TEXT", "CODE", "PNAME"]))
        XCTAssertTrue(matrix.supportsEvidenceReferences)
        XCTAssertTrue(matrix.supportsTemplate("1500", sopClassUID: DicomSRDocument.comprehensiveSRStorageSOPClassUID))
        XCTAssertFalse(matrix.supportsTemplate("1501", sopClassUID: DicomSRDocument.comprehensiveSRStorageSOPClassUID))
    }

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

        let decoder = try openValidated(document: document)
        let parsed = try XCTUnwrap(decoder.structuredReport)

        XCTAssertTrue(parsed.semanticValidation.isValid)
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
        XCTAssertTrue(reparsed.semanticValidation.isValid)
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
        XCTAssertTrue(kos.semanticValidation.isValid)
        XCTAssertEqual(kos.root.conceptName, title)
        XCTAssertEqual(kos.keyObjectReferences, [keyObject])
        XCTAssertEqual(kos.contentItems(matching: { $0.valueType == "IMAGE" }).first?.referencedSOPs.first, keyObject.sourceImageReference)
    }

    func testStructuredReportSemanticValidatorRejectsUnsupportedTemplateWithStableError() throws {
        let document = supportedMeasurementDocument(templateIdentifier: "9999")

        XCTAssertEqual(
            document.semanticValidation.errors.first,
            .unsupportedTemplateIdentifier("9999", sopClassUID: DicomSRDocument.comprehensiveSRStorageSOPClassUID)
        )
        XCTAssertThrowsError(try DicomStructuredReportBuilder.validatedDataSet(
            from: document,
            studyInstanceUID: "2.25.7000",
            seriesInstanceUID: "2.25.7300",
            sopInstanceUID: document.sopInstanceUID
        )) { error in
            let failure = error as? DicomSRSemanticValidationFailure
            XCTAssertEqual(
                failure?.errors.first,
                .unsupportedTemplateIdentifier("9999", sopClassUID: DicomSRDocument.comprehensiveSRStorageSOPClassUID)
            )
        }

        let syntacticDecoder = try open(document: document)
        let syntacticReport = try XCTUnwrap(syntacticDecoder.structuredReport)
        XCTAssertFalse(syntacticReport.semanticValidation.isValid)
    }

    func testStructuredReportSemanticValidatorRejectsUnsupportedRelationshipPattern() {
        let document = supportedMeasurementDocument(measurement: DicomSRContentItem(
            relationshipType: "HAS ACQ CONTEXT",
            valueType: "NUM",
            conceptName: areaConcept,
            numericValue: 42.5,
            measurementUnits: squareMillimeterConcept
        ))

        XCTAssertTrue(document.semanticValidation.errors.contains(
            .unsupportedRelationshipType(path: "root/0", relationshipType: "HAS ACQ CONTEXT")
        ))
    }

    func testStructuredReportSemanticValidatorRejectsByReferenceRelationshipPattern() {
        let document = supportedMeasurementDocument(measurement: DicomSRContentItem(
            relationshipType: "R-CONTAINS",
            valueType: "NUM",
            conceptName: areaConcept,
            numericValue: 42.5,
            measurementUnits: squareMillimeterConcept
        ))

        XCTAssertTrue(document.semanticValidation.errors.contains(
            .unsupportedByReferenceRelationship(path: "root/0", relationshipType: "R-CONTAINS")
        ))
    }

    func testStructuredReportSemanticValidatorRejectsMalformedNumericMeasurement() {
        let document = supportedMeasurementDocument(measurement: DicomSRContentItem(
            relationshipType: "CONTAINS",
            valueType: "NUM",
            conceptName: areaConcept
        ))

        XCTAssertTrue(document.semanticValidation.errors.contains(.missingNumericValue(path: "root/0")))
        XCTAssertTrue(document.semanticValidation.errors.contains(.missingMeasurementUnits(path: "root/0")))
    }

    func testStructuredReportSemanticValidatorRejectsUnsupportedMeasurementUnits() {
        let document = supportedMeasurementDocument(measurement: DicomSRContentItem(
            relationshipType: "CONTAINS",
            valueType: "NUM",
            conceptName: areaConcept,
            numericValue: 42.5,
            measurementUnits: DicomCodedConcept(codeValue: "1", codingSchemeDesignator: "99UNITS")
        ))

        XCTAssertTrue(document.semanticValidation.errors.contains(
            .unsupportedMeasurementUnit(path: "root/0", codingSchemeDesignator: "99UNITS")
        ))
    }

    func testKeyObjectSelectionSemanticValidationRejectsMissingReferences() {
        let document = DicomSRDocument(
            sopClassUID: DicomSRDocument.keyObjectSelectionDocumentStorageSOPClassUID,
            modality: "KO",
            completionFlag: "COMPLETE",
            verificationFlag: "UNVERIFIED",
            root: DicomSRContentItem(
                valueType: "CONTAINER",
                conceptName: keyObjectConcept,
                continuityOfContent: "SEPARATE",
                children: [
                    DicomSRContentItem(
                        relationshipType: "CONTAINS",
                        valueType: "IMAGE",
                        conceptName: keyObjectConcept
                    )
                ]
            )
        )

        XCTAssertTrue(document.semanticValidation.errors.contains(.missingReferencedSOP(path: "root/0")))
        XCTAssertTrue(document.semanticValidation.errors.contains(.missingEvidenceReference))
    }

    func testStructuredReportSemanticValidatorRejectsUnsupportedSOPClassScope() {
        let document = supportedMeasurementDocument(sopClassUID: DicomSRDocument.basicTextSRStorageSOPClassUID)

        XCTAssertEqual(
            document.semanticValidation.errors.first,
            .unsupportedSOPClassUID(DicomSRDocument.basicTextSRStorageSOPClassUID)
        )
    }

    func testStructuredReportSemanticValidatorPreservesObservationContextValueTypes() throws {
        let observerName = try XCTUnwrap(DicomPersonName("Reader^One"))
        let document = supportedMeasurementDocument(children: [
            DicomSRContentItem(
                relationshipType: "HAS OBS CONTEXT",
                valueType: "PNAME",
                conceptName: DicomCodedConcept(
                    codeValue: "121008",
                    codingSchemeDesignator: "DCM",
                    codeMeaning: "Person Observer Name"
                ),
                personNameValue: observerName
            ),
            supportedMeasurementItem()
        ])

        XCTAssertTrue(document.semanticValidation.isValid)
    }

    private var areaConcept: DicomCodedConcept {
        DicomCodedConcept(codeValue: "42798000", codingSchemeDesignator: "SCT", codeMeaning: "Area")
    }

    private var squareMillimeterConcept: DicomCodedConcept {
        DicomCodedConcept(codeValue: "mm2", codingSchemeDesignator: "UCUM", codeMeaning: "square millimeter")
    }

    private var reportTitleConcept: DicomCodedConcept {
        DicomCodedConcept(codeValue: "126000", codingSchemeDesignator: "DCM", codeMeaning: "Imaging Measurement Report")
    }

    private var keyObjectConcept: DicomCodedConcept {
        DicomCodedConcept(codeValue: "113000", codingSchemeDesignator: "DCM", codeMeaning: "Key Object")
    }

    private var sourceImageReference: DicomSourceImageReference {
        DicomSourceImageReference(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "2.25.7001",
            referencedFrameNumbers: [3]
        )
    }

    private var evidenceReference: DicomKeyObjectReference {
        DicomKeyObjectReference(
            studyInstanceUID: "2.25.7000",
            seriesInstanceUID: "2.25.7002",
            referencedSOPClassUID: sourceImageReference.referencedSOPClassUID,
            referencedSOPInstanceUID: sourceImageReference.referencedSOPInstanceUID,
            referencedFrameNumbers: sourceImageReference.referencedFrameNumbers
        )
    }

    private func supportedMeasurementItem() -> DicomSRContentItem {
        DicomSRContentItem(
            relationshipType: "CONTAINS",
            valueType: "NUM",
            conceptName: areaConcept,
            numericValue: 42.5,
            measurementUnits: squareMillimeterConcept,
            children: [
                DicomSRContentItem(
                    relationshipType: "INFERRED FROM",
                    valueType: "SCOORD",
                    conceptName: DicomCodedConcept(
                        codeValue: "111030",
                        codingSchemeDesignator: "DCM",
                        codeMeaning: "Image Region"
                    ),
                    graphicType: "POLYLINE",
                    graphicData: [1, 2, 3, 4],
                    children: [
                        DicomSRContentItem(
                            relationshipType: "SELECTED FROM",
                            valueType: "IMAGE",
                            conceptName: keyObjectConcept,
                            referencedSOPs: [sourceImageReference]
                        )
                    ]
                )
            ]
        )
    }

    private func supportedMeasurementDocument(
        templateIdentifier: String? = "1500",
        sopClassUID: String? = DicomSRDocument.comprehensiveSRStorageSOPClassUID,
        measurement: DicomSRContentItem? = nil,
        children: [DicomSRContentItem]? = nil
    ) -> DicomSRDocument {
        DicomSRDocument(
            sopClassUID: sopClassUID,
            sopInstanceUID: "2.25.7201",
            contentLabel: "MEASUREMENTS",
            completionFlag: "COMPLETE",
            verificationFlag: "UNVERIFIED",
            templateIdentifier: templateIdentifier,
            root: DicomSRContentItem(
                valueType: "CONTAINER",
                conceptName: reportTitleConcept,
                continuityOfContent: "SEPARATE",
                children: children ?? [measurement ?? supportedMeasurementItem()]
            ),
            evidenceReferences: [evidenceReference]
        )
    }

    private func openValidated(document: DicomSRDocument) throws -> DCMDecoder {
        let dataSet = try DicomStructuredReportBuilder.validatedDataSet(
            from: document,
            studyInstanceUID: "2.25.7000",
            seriesInstanceUID: "2.25.7300",
            sopInstanceUID: document.sopInstanceUID
        )
        return try open(
            dataSet: dataSet,
            sopClassUID: document.sopClassUID ?? DicomSRDocument.enhancedSRStorageSOPClassUID
        )
    }

    private func open(document: DicomSRDocument) throws -> DCMDecoder {
        let dataSet = DicomStructuredReportBuilder.dataSet(
            from: document,
            studyInstanceUID: "2.25.7000",
            seriesInstanceUID: "2.25.7300",
            sopInstanceUID: document.sopInstanceUID
        )
        return try open(
            dataSet: dataSet,
            sopClassUID: document.sopClassUID ?? DicomSRDocument.enhancedSRStorageSOPClassUID
        )
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
