import Foundation
import XCTest
@testable import DicomCore

final class DicomWebClientTests: XCTestCase {
    func testSearchStudiesBuildsQIDORequestAndParsesDICOMJSON() async throws {
        let transport = DicomWebScriptedTransport(responses: [
            DicomWebHTTPResponse(statusCode: 200,
                                 headers: ["Content-Type": "application/dicom+json"],
                                 body: Data("""
                                 [{
                                   "00100010": { "vr": "PN", "Value": [{ "Alphabetic": "DOE^JANE" }] },
                                   "00100020": { "vr": "LO", "Value": ["P-1"] },
                                   "00080020": { "vr": "DA", "Value": ["20260529"] },
                                   "00081030": { "vr": "LO", "Value": ["CT CHEST"] },
                                   "0020000D": { "vr": "UI", "Value": ["2.25.study"] }
                                 }]
                                 """.utf8))
        ])
        let client = DicomWebClient(
            configuration: DicomWebClientConfiguration(
                baseURL: URL(string: "https://archive.example/dicom-web")!,
                headers: ["Authorization": "Bearer token"]
            ),
            transport: transport
        )

        let studies = try await client.searchStudies(DicomWebQuery(patientName: "DOE"))

        XCTAssertEqual(studies.count, 1)
        XCTAssertEqual(studies.first?.patientName, "DOE^JANE")
        XCTAssertEqual(studies.first?.studyInstanceUID, "2.25.study")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.path, "/dicom-web/studies")
        XCTAssertTrue(try XCTUnwrap(request.url.query).contains("PatientName=DOE"))
        XCTAssertTrue(try XCTUnwrap(request.url.query).contains("includefield=all"))
        XCTAssertEqual(request.headers["Authorization"], "Bearer token")
        XCTAssertEqual(request.headers["Accept"], "application/dicom+json")
    }

    func testRetrieveMetadataAndMultipartInstance() async throws {
        let transport = DicomWebScriptedTransport(responses: [
            DicomWebHTTPResponse(statusCode: 200,
                                 headers: ["Content-Type": "application/dicom+json"],
                                 body: Data("""
                                 [{
                                   "0020000D": { "vr": "UI", "Value": ["2.25.study"] },
                                   "0020000E": { "vr": "UI", "Value": ["2.25.series"] },
                                   "00080018": { "vr": "UI", "Value": ["2.25.instance"] },
                                   "00280010": { "vr": "US", "Value": [2] }
                                 }]
                                 """.utf8)),
            DicomWebHTTPResponse(statusCode: 200,
                                 headers: ["Content-Type": "multipart/related; type=\"application/dicom\"; boundary=abc"],
                                 body: Self.multipartBody(boundary: "abc",
                                                          contentType: "application/dicom",
                                                          payload: Data([0x44, 0x49, 0x43, 0x4D])))
        ])
        let client = DicomWebClient(
            configuration: DicomWebClientConfiguration(baseURL: URL(string: "https://archive.example/dicom-web")!),
            transport: transport
        )

        let metadata = try await client.retrieveStudyMetadata(studyInstanceUID: "2.25.study")
        let object = try await client.retrieveInstance(studyInstanceUID: "2.25.study",
                                                       seriesInstanceUID: "2.25.series",
                                                       sopInstanceUID: "2.25.instance")

        XCTAssertEqual(metadata.first?.string(for: .sopInstanceUID), "2.25.instance")
        XCTAssertEqual(metadata.first?.int(for: .rows), 2)
        XCTAssertEqual(object.parts.count, 1)
        XCTAssertEqual(object.parts.first?.contentType, "application/dicom")
        XCTAssertEqual(object.firstPayload, Data([0x44, 0x49, 0x43, 0x4D]))
        XCTAssertEqual(transport.requests.map(\.url.path), [
            "/dicom-web/studies/2.25.study/metadata",
            "/dicom-web/studies/2.25.study/series/2.25.series/instances/2.25.instance"
        ])
    }

    func testRetrieveRenderedFrameAndWADOURI() async throws {
        let transport = DicomWebScriptedTransport(responses: [
            DicomWebHTTPResponse(statusCode: 200,
                                 headers: ["Content-Type": "image/png"],
                                 body: Data([0x89, 0x50, 0x4E, 0x47])),
            DicomWebHTTPResponse(statusCode: 200,
                                 headers: ["Content-Type": "application/dicom"],
                                 body: Data([0x44, 0x49, 0x43, 0x4D]))
        ])
        let client = DicomWebClient(
            configuration: DicomWebClientConfiguration(baseURL: URL(string: "https://archive.example/dicom-web")!),
            transport: transport
        )

        let frame = try await client.retrieveRenderedFrame(studyInstanceUID: "2.25.study",
                                                           seriesInstanceUID: "2.25.series",
                                                           sopInstanceUID: "2.25.instance",
                                                           frameNumber: 1)
        let object = try await client.retrieveWADOURIObject(studyInstanceUID: "2.25.study",
                                                            seriesInstanceUID: "2.25.series",
                                                            sopInstanceUID: "2.25.instance")

        XCTAssertEqual(frame.firstPayload, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(object.firstPayload, Data([0x44, 0x49, 0x43, 0x4D]))
        XCTAssertEqual(transport.requests[0].url.path, "/dicom-web/studies/2.25.study/series/2.25.series/instances/2.25.instance/frames/1/rendered")
        XCTAssertEqual(transport.requests[1].url.path, "/dicom-web/wado")
        XCTAssertTrue(try XCTUnwrap(transport.requests[1].url.query).contains("requestType=WADO"))
    }

    func testSTOWMultipartAndHTTPDiagnostics() async throws {
        let transport = DicomWebScriptedTransport(responses: [
            DicomWebHTTPResponse(statusCode: 200,
                                 headers: ["Content-Type": "application/dicom+json"],
                                 body: Data("[]".utf8)),
            DicomWebHTTPResponse(statusCode: 404,
                                 headers: ["Content-Type": "text/plain"],
                                 body: Data("missing study".utf8))
        ])
        let client = DicomWebClient(
            configuration: DicomWebClientConfiguration(baseURL: URL(string: "https://archive.example/dicom-web")!),
            transport: transport
        )

        let result = try await client.storeInstances([
            DicomWebStoreInstance(data: Data("DICM".utf8))
        ], studyInstanceUID: "2.25.study")

        XCTAssertEqual(result.storedInstanceCount, 1)
        let storeRequest = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(storeRequest.method, .post)
        XCTAssertEqual(storeRequest.url.path, "/dicom-web/studies/2.25.study")
        XCTAssertTrue(try XCTUnwrap(storeRequest.headers["Content-Type"]).contains("multipart/related"))
        XCTAssertTrue(try XCTUnwrap(String(data: XCTUnwrap(storeRequest.body), encoding: .utf8)).contains("Content-Type: application/dicom"))

        do {
            _ = try await client.retrieveStudyMetadata(studyInstanceUID: "2.25.missing")
            XCTFail("Expected HTTP diagnostic error.")
        } catch let error as DicomWebClientError {
            XCTAssertEqual(error, .httpStatus(statusCode: 404,
                                             method: "GET",
                                             url: "https://archive.example/dicom-web/studies/2.25.missing/metadata",
                                             bodyPreview: "missing study"))
            XCTAssertTrue(try XCTUnwrap(error.errorDescription).contains("HTTP 404"))
        }
    }

    private static func multipartBody(boundary: String, contentType: String, payload: Data) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        data.append(payload)
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }
}

private final class DicomWebScriptedTransport: DicomWebHTTPTransport, @unchecked Sendable {
    private(set) var requests: [DicomWebHTTPRequest] = []
    private var responses: [DicomWebHTTPResponse]

    init(responses: [DicomWebHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: DicomWebHTTPRequest) async throws -> DicomWebHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            return DicomWebHTTPResponse(statusCode: 500, body: Data("No scripted response".utf8))
        }
        return responses.removeFirst()
    }
}
