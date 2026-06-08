import Foundation
import XCTest
@testable import DicomCore

final class DicomWebServerTests: XCTestCase {
    func testConformanceMatrixListsProductionScopeAndResponsibilities() throws {
        let matrix = DicomWebConformanceMatrix.packageDefault

        XCTAssertNotNil(matrix.row(feature: "QIDO-RS"))
        XCTAssertNotNil(matrix.row(feature: "WADO-RS metadata"))
        XCTAssertNotNil(matrix.row(feature: "WADO-URI"))
        XCTAssertNotNil(matrix.row(feature: "STOW-RS"))
        XCTAssertEqual(matrix.row(feature: "UPS-RS")?.server, "stable 501")
        XCTAssertEqual(matrix.row(feature: "BulkDataURI")?.client, "transport-injected")
        XCTAssertEqual(matrix.row(feature: "JPIP")?.responsibility, "DicomJPIPClient with DicomJPIPTransport")
        XCTAssertEqual(matrix.row(feature: "WADO-RS rendered frame")?.server, "stable 501")
        XCTAssertEqual(matrix.row(feature: "Pagination")?.server, "limit/offset applied")
        XCTAssertTrue(try XCTUnwrap(matrix.row(feature: "Large payload streaming")?.notes).contains("true streaming is outside"))
    }

    func testDICOMwebDocumentationExposesScopedConformanceMatrix() throws {
        let conformance = try Self.packageText("Sources/DicomCore/DicomCore.docc/Articles/ConformanceStatement.md")
        let readme = try Self.packageText("README.md")

        for row in DicomWebConformanceMatrix.packageDefault.rows {
            XCTAssertTrue(conformance.contains(row.feature), "Missing \(row.feature) from conformance DocC.")
        }
        XCTAssertTrue(conformance.contains("not a complete production PACS"))
        XCTAssertFalse(conformance.contains("| **No DICOM Network** |"))
        XCTAssertTrue(readme.contains("DicomWebConformanceMatrix.packageDefault"))
    }

    func testQIDOWADOAndSTOWRoutesThroughClientSmoke() async throws {
        let store = DicomWebInMemoryStore()
        let fixture = try store.add(dataSet: Self.imageDataSet(patientName: "DOE^JANE",
                                                               studyInstanceUID: "2.25.1",
                                                               seriesInstanceUID: "2.25.2",
                                                               sopInstanceUID: "2.25.3"))
        let server = DicomWebServer(store: store)
        let client = DicomWebClient(
            configuration: DicomWebClientConfiguration(baseURL: URL(string: "https://server.example/dicom-web")!),
            transport: server
        )

        let studies = try await client.searchStudies(DicomWebQuery(patientName: "DOE"))
        let metadata = try await client.retrieveStudyMetadata(studyInstanceUID: "2.25.1")
        let object = try await client.retrieveInstance(studyInstanceUID: "2.25.1",
                                                       seriesInstanceUID: "2.25.2",
                                                       sopInstanceUID: "2.25.3")
        let storeResult = try await client.store(
            dataSet: Self.imageDataSet(patientName: "DOE^JOHN",
                                       studyInstanceUID: "2.25.4",
                                       seriesInstanceUID: "2.25.5",
                                       sopInstanceUID: "2.25.6")
        )
        let storedStudies = try await client.searchStudies(DicomWebQuery(studyInstanceUID: "2.25.4"))

        XCTAssertEqual(studies.count, 1)
        XCTAssertEqual(studies.first?.studyInstanceUID, "2.25.1")
        XCTAssertEqual(metadata.first?.string(for: .sopInstanceUID), "2.25.3")
        XCTAssertNil(metadata.first?.element(for: .pixelData))
        XCTAssertEqual(object.parts.count, 1)
        XCTAssertEqual(object.firstPayload, fixture.part10Data)
        XCTAssertEqual(storeResult.statusCode, 200)
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(storedStudies.first?.studyInstanceUID, "2.25.4")
    }

    func testQIDOPaginationIsAppliedOnServer() async throws {
        let store = DicomWebInMemoryStore()
        try store.add(dataSet: Self.imageDataSet(patientName: "DOE^A",
                                                 studyInstanceUID: "2.25.1",
                                                 seriesInstanceUID: "2.25.2",
                                                 sopInstanceUID: "2.25.3"))
        try store.add(dataSet: Self.imageDataSet(patientName: "DOE^B",
                                                 studyInstanceUID: "2.25.4",
                                                 seriesInstanceUID: "2.25.5",
                                                 sopInstanceUID: "2.25.6"))
        try store.add(dataSet: Self.imageDataSet(patientName: "DOE^C",
                                                 studyInstanceUID: "2.25.7",
                                                 seriesInstanceUID: "2.25.8",
                                                 sopInstanceUID: "2.25.9"))
        let client = DicomWebClient(
            configuration: DicomWebClientConfiguration(baseURL: URL(string: "https://server.example/dicom-web")!),
            transport: DicomWebServer(store: store)
        )

        let studies = try await client.searchStudies(DicomWebQuery(limit: 1, offset: 1))

        XCTAssertEqual(studies.map(\.studyInstanceUID), ["2.25.4"])
    }

    func testXMLMetadataRoute() async throws {
        let store = DicomWebInMemoryStore()
        try store.add(dataSet: Self.imageDataSet(patientName: "DOE^JANE",
                                                 studyInstanceUID: "2.25.1",
                                                 seriesInstanceUID: "2.25.2",
                                                 sopInstanceUID: "2.25.3"))
        let server = DicomWebServer(store: store)

        let response = try await server.send(DicomWebHTTPRequest(
            method: .get,
            url: URL(string: "https://server.example/dicom-web/studies/2.25.1/metadata")!,
            headers: ["Accept": "application/dicom+xml"]
        ))

        let xml = try XCTUnwrap(String(data: response.body, encoding: .utf8))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["Content-Type"], "application/dicom+xml")
        XCTAssertTrue(xml.contains("NativeDicomModel"))
        XCTAssertTrue(xml.contains("0020000D"))
        XCTAssertTrue(xml.contains("2.25.1"))
    }

    func testStableUnsupportedFrameRenderedAndUPSResponses() async throws {
        let server = DicomWebServer()
        let frame = try await server.send(DicomWebHTTPRequest(
            method: .get,
            url: URL(string: "https://server.example/dicom-web/studies/1/series/2/instances/3/frames/4")!
        ))
        let rendered = try await server.send(DicomWebHTTPRequest(
            method: .get,
            url: URL(string: "https://server.example/dicom-web/studies/1/series/2/instances/3/frames/4/rendered")!
        ))
        let ups = try await server.send(DicomWebHTTPRequest(
            method: .get,
            url: URL(string: "https://server.example/dicom-web/ups")!
        ))

        XCTAssertEqual(frame.statusCode, 501)
        XCTAssertEqual(frame.headers["X-DICOMweb-Error-Code"], DicomWebServerErrorCode.frameRetrievalUnsupported.rawValue)
        XCTAssertEqual(rendered.statusCode, 501)
        XCTAssertEqual(rendered.headers["X-DICOMweb-Error-Code"], DicomWebServerErrorCode.renderedFrameUnsupported.rawValue)
        XCTAssertEqual(ups.statusCode, 501)
        XCTAssertEqual(ups.headers["X-DICOMweb-Error-Code"], DicomWebServerErrorCode.upsDeferred.rawValue)
    }

    func testLargeSTOWPayloadIsPreservedByInMemoryServer() async throws {
        let store = DicomWebInMemoryStore()
        let server = DicomWebServer(store: store)
        let client = DicomWebClient(
            configuration: DicomWebClientConfiguration(baseURL: URL(string: "https://server.example/dicom-web")!),
            transport: server
        )
        let payload = Data(repeating: 0x5A, count: 1024 * 1024)

        let result = try await client.storeInstances([DicomWebStoreInstance(data: payload)])

        XCTAssertEqual(result.statusCode, 200)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.allInstances().first?.part10Data, payload)
    }

    func testOAuth2CacheConformanceAndUPSP2() async throws {
        let store = DicomWebInMemoryStore()
        try store.add(dataSet: Self.imageDataSet(patientName: "DOE^JANE",
                                                 studyInstanceUID: "2.25.1",
                                                 seriesInstanceUID: "2.25.2",
                                                 sopInstanceUID: "2.25.3"))
        let server = DicomWebServer(
            configuration: DicomWebServerConfiguration(requiredBearerToken: "secret",
                                                       cacheEnabled: true),
            store: store
        )
        let studiesURL = URL(string: "https://server.example/dicom-web/studies")!

        let unauthorized = try await server.send(DicomWebHTTPRequest(method: .get, url: studiesURL))
        let first = try await server.send(DicomWebHTTPRequest(method: .get,
                                                              url: studiesURL,
                                                              headers: ["Authorization": "Bearer secret"]))
        let second = try await server.send(DicomWebHTTPRequest(method: .get,
                                                               url: studiesURL,
                                                               headers: ["Authorization": "Bearer secret"]))
        let conformance = try await server.send(DicomWebHTTPRequest(
            method: .get,
            url: URL(string: "https://server.example/dicom-web/conformance")!,
            headers: ["Authorization": "Bearer secret"]
        ))
        let ups = try await server.send(DicomWebHTTPRequest(
            method: .get,
            url: URL(string: "https://server.example/dicom-web/ups")!,
            headers: ["Authorization": "Bearer secret"]
        ))

        XCTAssertEqual(unauthorized.statusCode, 401)
        XCTAssertEqual(unauthorized.headers["WWW-Authenticate"], "Bearer realm=\"DICOMweb\"")
        XCTAssertEqual(first.statusCode, 200)
        XCTAssertNil(first.headers["X-DICOMweb-Cache"])
        XCTAssertEqual(second.headers["X-DICOMweb-Cache"], "HIT")
        XCTAssertEqual(conformance.statusCode, 200)
        XCTAssertTrue(try XCTUnwrap(String(data: conformance.body, encoding: .utf8)).contains("UPS: P2 deferred"))
        XCTAssertTrue(try XCTUnwrap(String(data: conformance.body, encoding: .utf8)).contains("BulkDataURI"))
        XCTAssertTrue(try XCTUnwrap(String(data: conformance.body, encoding: .utf8)).contains("DICOMWEB_RENDERED_FRAME_UNSUPPORTED"))
        XCTAssertEqual(ups.statusCode, 501)
        XCTAssertEqual(ups.headers["X-DICOMweb-Error-Code"], DicomWebServerErrorCode.upsDeferred.rawValue)
        XCTAssertTrue(try XCTUnwrap(String(data: ups.body, encoding: .utf8)).contains("P2 deferred"))
    }

    private static func imageDataSet(patientName: String,
                                     studyInstanceUID: String,
                                     seriesInstanceUID: String,
                                     sopInstanceUID: String) -> DicomDataSet {
        DicomDataSet(elements: [
            string(DicomTag.sopClassUID.rawValue,
                   .UI,
                   DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID),
            string(DicomTag.sopInstanceUID.rawValue, .UI, sopInstanceUID),
            string(DicomTag.patientName.rawValue, .PN, patientName),
            string(DicomTag.patientID.rawValue, .LO, "P-1"),
            string(DicomTag.studyDate.rawValue, .DA, "20260529"),
            string(DicomTag.studyDescription.rawValue, .LO, "CT CHEST"),
            string(DicomTag.studyInstanceUID.rawValue, .UI, studyInstanceUID),
            string(DicomTag.seriesInstanceUID.rawValue, .UI, seriesInstanceUID),
            string(DicomTag.modality.rawValue, .CS, "CT"),
            string(DicomTag.conversionType.rawValue, .CS, "WSD"),
            DicomDataElement(tag: DicomTag.samplesPerPixel.rawValue, vr: .US, value: .unsignedIntegers([1])),
            string(DicomTag.photometricInterpretation.rawValue, .CS, "MONOCHROME2"),
            DicomDataElement(tag: DicomTag.rows.rawValue, vr: .US, value: .unsignedIntegers([1])),
            DicomDataElement(tag: DicomTag.columns.rawValue, vr: .US, value: .unsignedIntegers([1])),
            DicomDataElement(tag: DicomTag.bitsAllocated.rawValue, vr: .US, value: .unsignedIntegers([8])),
            DicomDataElement(tag: DicomTag.bitsStored.rawValue, vr: .US, value: .unsignedIntegers([8])),
            DicomDataElement(tag: DicomTag.highBit.rawValue, vr: .US, value: .unsignedIntegers([7])),
            DicomDataElement(tag: DicomTag.pixelRepresentation.rawValue, vr: .US, value: .unsignedIntegers([0])),
            DicomDataElement(tag: DicomTag.pixelData.rawValue, vr: .OB, value: .bytes(Data([0x7F])))
        ])
    }

    private static func string(_ tag: Int, _ vr: DicomVR, _ value: String) -> DicomDataElement {
        DicomDataElement(tag: tag, vr: vr, value: .strings([value]))
    }

    private static func packageText(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func packageRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: candidate.path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(domain: "DicomWebServerTests",
                      code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not locate DICOM-Decoder package root."])
    }
}
