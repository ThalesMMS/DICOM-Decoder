import XCTest
@testable import DicomCore

final class DicomEncapsulatedDocumentTests: XCTestCase {
    func testEncapsulatedPDFRoundTripsMetadataPayloadAndSourceReferences() throws {
        let payload = Data("%PDF-1.4\n".utf8)
        let concept = DicomCodedConcept(
            codeValue: "18748-4",
            codingSchemeDesignator: "LN",
            codeMeaning: "Diagnostic Imaging Report"
        )
        let source = DicomEncapsulatedDocumentSourceInstance(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "2.25.9203"
        )
        let options = DicomEncapsulatedDocumentBuildOptions(
            kind: .pdf,
            sopInstanceUID: "2.25.9200",
            studyInstanceUID: "2.25.9201",
            seriesInstanceUID: "2.25.9202",
            patientName: "Document^Patient",
            patientID: "DOC-1",
            studyID: "DOC-STUDY",
            studyDate: "20260528",
            studyTime: "140000",
            seriesNumber: 9,
            instanceNumber: 4,
            seriesDate: "20260528",
            seriesTime: "140100",
            contentDate: "20260528",
            contentTime: "140200",
            documentTitle: "Consult Report",
            conceptName: concept,
            sourceInstances: [source]
        )

        let decoder = try open(documentData: payload, options: options)
        let document = try XCTUnwrap(decoder.encapsulatedDocument)

        XCTAssertEqual(document.kind, .pdf)
        XCTAssertEqual(document.sopClassUID, DicomEncapsulatedDocument.encapsulatedPDFStorageSOPClassUID)
        XCTAssertEqual(document.sopInstanceUID, "2.25.9200")
        XCTAssertEqual(document.studyInstanceUID, "2.25.9201")
        XCTAssertEqual(document.seriesInstanceUID, "2.25.9202")
        XCTAssertEqual(document.modality, "DOC")
        XCTAssertEqual(document.patientName?.familyName, "Document")
        XCTAssertEqual(document.patientName?.givenName, "Patient")
        XCTAssertEqual(document.patientID, "DOC-1")
        XCTAssertEqual(document.documentTitle, "Consult Report")
        XCTAssertEqual(document.conceptName, concept)
        XCTAssertEqual(document.mimeType, "application/pdf")
        XCTAssertEqual(document.documentData, payload)
        XCTAssertEqual(document.encapsulatedDocumentLength, payload.count)
        XCTAssertEqual(document.sourceInstances, [source])
        XCTAssertEqual(document.preferredFileExtension, "pdf")

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("encapsulated_pdf_\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: exportURL) }
        try document.writeDocument(to: exportURL)
        XCTAssertEqual(try Data(contentsOf: exportURL), payload)
    }

    func testCDAAndSTLKindsRoundTripWithDefaultMIMEAndExtension() throws {
        let cases: [(DicomEncapsulatedDocumentKind, Data, String, String)] = [
            (.cda, Data("<ClinicalDocument/>".utf8), "text/xml", "xml"),
            (.stl, Data("solid mesh\nendsolid mesh\n".utf8), "model/stl", "stl")
        ]

        for (kind, payload, mimeType, fileExtension) in cases {
            let decoder = try open(
                documentData: payload,
                options: DicomEncapsulatedDocumentBuildOptions(
                    kind: kind,
                    sopInstanceUID: "2.25.\(90000 + payload.count)",
                    studyInstanceUID: "2.25.9211",
                    seriesInstanceUID: "2.25.9212",
                    documentTitle: "\(kind) document"
                )
            )
            let document = try XCTUnwrap(decoder.encapsulatedDocument)

            XCTAssertEqual(document.kind, kind)
            XCTAssertEqual(document.mimeType, mimeType)
            XCTAssertEqual(document.documentData, payload)
            XCTAssertEqual(document.preferredFileExtension, fileExtension)
        }
    }

    func testBuilderCanPreserveSourceDecoderClinicalContext() throws {
        let sourceDecoder = try open(dataSet: sourceImageDataSet())
        let options = DicomEncapsulatedDocumentBuildOptions.preservingClinicalContext(
            from: sourceDecoder,
            kind: .pdf,
            documentTitle: "Attached PDF",
            sopInstanceUID: "2.25.9300"
        )

        let decoder = try open(documentData: Data("%PDF context".utf8), options: options)
        let document = try XCTUnwrap(decoder.encapsulatedDocument)

        XCTAssertEqual(document.sopInstanceUID, "2.25.9300")
        XCTAssertEqual(document.studyInstanceUID, "2.25.9301")
        XCTAssertEqual(document.seriesInstanceUID, "2.25.9302")
        XCTAssertEqual(document.patientName?.familyName, "Source")
        XCTAssertEqual(document.patientID, "SRC-DOC")
        XCTAssertEqual(document.sourceInstances, [
            DicomEncapsulatedDocumentSourceInstance(
                referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
                referencedSOPInstanceUID: "2.25.9303"
            )
        ])
    }

    func testSeriesLoaderSkipsEncapsulatedDocumentAsNonImageVolumeInput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("encapsulated_document_series_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("document.dcm")
        try DicomEncapsulatedDocumentBuilder.write(
            documentData: Data("%PDF".utf8),
            to: url,
            options: DicomEncapsulatedDocumentBuildOptions(documentTitle: "Not a volume")
        )

        XCTAssertThrowsError(try DicomSeriesLoader().loadSeries(in: directory)) { error in
            guard case DicomSeriesLoaderError.noDicomFiles = error else {
                return XCTFail("Expected noDicomFiles after skipping Encapsulated Document, got \(error)")
            }
        }
    }

    private func open(
        documentData: Data,
        options: DicomEncapsulatedDocumentBuildOptions
    ) throws -> DCMDecoder {
        let data = try DicomEncapsulatedDocumentBuilder.part10Data(documentData: documentData, options: options)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("encapsulated_document_\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DCMDecoder(contentsOf: url)
    }

    private func open(dataSet: DicomDataSet) throws -> DCMDecoder {
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                mediaStorageSOPClassUID: dataSet.string(for: .sopClassUID),
                mediaStorageSOPInstanceUID: dataSet.string(for: .sopInstanceUID)
            )
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("encapsulated_document_source_\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DCMDecoder(contentsOf: url)
    }

    private func sourceImageDataSet() -> DicomDataSet {
        DicomDataSet(elements: [
            string(.sopClassUID, vr: .UI, "1.2.840.10008.5.1.4.1.1.2"),
            string(.sopInstanceUID, vr: .UI, "2.25.9303"),
            string(.studyInstanceUID, vr: .UI, "2.25.9301"),
            string(.seriesInstanceUID, vr: .UI, "2.25.9302"),
            string(.patientName, vr: .PN, "Source^Document"),
            string(.patientID, vr: .LO, "SRC-DOC"),
            string(.studyID, vr: .SH, "SOURCE-DOC-STUDY"),
            string(.studyDate, vr: .DA, "20260528"),
            string(.studyTime, vr: .TM, "150000"),
            string(.seriesDate, vr: .DA, "20260528"),
            string(.seriesTime, vr: .TM, "150100"),
            string(.modality, vr: .CS, "CT"),
            us(.samplesPerPixel, 1),
            string(.photometricInterpretation, vr: .CS, "MONOCHROME2"),
            us(.rows, 1),
            us(.columns, 1),
            us(.bitsAllocated, 16),
            us(.bitsStored, 16),
            us(.highBit, 15),
            us(.pixelRepresentation, 0),
            DicomDataElement(tag: DicomTag.pixelData.rawValue, vr: .OW, value: .bytes(Data([0x2A, 0x00])))
        ])
    }

    private func string(_ tag: DicomTag, vr: DicomVR, _ value: String) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: vr, value: .strings([value]))
    }

    private func us(_ tag: DicomTag, _ value: Int) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .US, value: .unsignedIntegers([UInt(clamping: value)]))
    }
}
