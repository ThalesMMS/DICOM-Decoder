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

        let studies = try await client.searchStudies(
            DicomWebQuery(patientName: "DOE",
                          patientID: "P-1",
                          accessionNumber: "ACC-1",
                          studyDate: "20260529",
                          studyDescription: "CT CHEST",
                          referringPhysicianName: "SMITH",
                          institutionName: "Hospital",
                          studyInstanceUID: "2.25.study",
                          modality: "CT",
                          limit: 25,
                          offset: 50)
        )

        XCTAssertEqual(studies.count, 1)
        XCTAssertEqual(studies.first?.patientName, "DOE^JANE")
        XCTAssertEqual(studies.first?.studyInstanceUID, "2.25.study")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.path, "/dicom-web/studies")
        let queryItems = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(query["PatientName"], "DOE")
        XCTAssertEqual(query["PatientID"], "P-1")
        XCTAssertEqual(query["AccessionNumber"], "ACC-1")
        XCTAssertEqual(query["StudyDate"], "20260529")
        XCTAssertEqual(query["StudyDescription"], "CT CHEST")
        XCTAssertEqual(query["ReferringPhysicianName"], "SMITH")
        XCTAssertEqual(query["InstitutionName"], "Hospital")
        XCTAssertEqual(query["StudyInstanceUID"], "2.25.study")
        XCTAssertEqual(query["ModalitiesInStudy"], "CT")
        XCTAssertEqual(query["limit"], "25")
        XCTAssertEqual(query["offset"], "50")
        XCTAssertEqual(query["includefield"], "all")
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

    func testRetrieveFrameBulkDataURIAndLargeSTOWSerialization() async throws {
        let largePayload = Data(repeating: 0xA5, count: 1024 * 1024)
        let transport = DicomWebScriptedTransport(responses: [
            DicomWebHTTPResponse(statusCode: 200,
                                 headers: ["Content-Type": "multipart/related; type=\"application/octet-stream\"; boundary=frame"],
                                 body: Self.multipartBody(boundary: "frame",
                                                          contentType: "application/octet-stream",
                                                          payload: Data([0x01, 0x02, 0x03]))),
            DicomWebHTTPResponse(statusCode: 200,
                                 headers: ["Content-Type": "application/octet-stream"],
                                 body: Data([0x10, 0x11])),
            DicomWebHTTPResponse(statusCode: 200,
                                 headers: ["Content-Type": "application/json"],
                                 body: Data("{\"storedInstanceCount\":1}".utf8))
        ])
        let client = DicomWebClient(
            configuration: DicomWebClientConfiguration(baseURL: URL(string: "https://archive.example/dicom-web")!),
            transport: transport
        )

        let frame = try await client.retrieveFrame(studyInstanceUID: "2.25.study",
                                                   seriesInstanceUID: "2.25.series",
                                                   sopInstanceUID: "2.25.instance",
                                                   frameNumber: 2)
        let bulk = try await client.retrieveBulkData(uri: "studies/2.25.study/bulk/7FE00010")
        let store = try await client.storeInstances([DicomWebStoreInstance(data: largePayload)])

        XCTAssertEqual(frame.firstPayload, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(bulk.firstPayload, Data([0x10, 0x11]))
        XCTAssertEqual(store.storedInstanceCount, 1)
        XCTAssertEqual(transport.requests[0].url.path, "/dicom-web/studies/2.25.study/series/2.25.series/instances/2.25.instance/frames/2")
        XCTAssertEqual(transport.requests[0].headers["Accept"], "multipart/related; type=\"application/octet-stream\"; transfer-syntax=*")
        XCTAssertEqual(transport.requests[1].url.path, "/dicom-web/studies/2.25.study/bulk/7FE00010")
        XCTAssertEqual(transport.requests[1].headers["Accept"], "application/octet-stream, multipart/related; type=\"application/octet-stream\"")

        let storeRequest = try XCTUnwrap(transport.requests.last)
        let contentType = try XCTUnwrap(storeRequest.headers["Content-Type"])
        let boundary = try XCTUnwrap(DicomWebMultipartParser.boundary(from: contentType))
        let parts = try DicomWebMultipartParser.parts(from: try XCTUnwrap(storeRequest.body), boundary: boundary)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first?.body, largePayload)
    }

    func testBulkDataURIValuesArePreservedInDICOMJSON() async throws {
        let transport = DicomWebScriptedTransport(responses: [
            DicomWebHTTPResponse(statusCode: 200,
                                 headers: ["Content-Type": "application/dicom+json"],
                                 body: Data("""
                                 [{
                                   "0020000D": { "vr": "UI", "Value": ["2.25.study"] },
                                   "7FE00010": { "vr": "OB", "BulkDataURI": "/dicom-web/studies/2.25.study/bulk/7FE00010" }
                                 }]
                                 """.utf8))
        ])
        let client = DicomWebClient(
            configuration: DicomWebClientConfiguration(baseURL: URL(string: "https://archive.example/dicom-web")!),
            transport: transport
        )

        let metadata = try await client.retrieveStudyMetadata(studyInstanceUID: "2.25.study")

        XCTAssertEqual(metadata.first?.string(for: .pixelData), "/dicom-web/studies/2.25.study/bulk/7FE00010")
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

    func testURLSessionTransportSerializesHTTPRequests() async throws {
        let capture = DicomWebURLProtocolCapture()
        DicomWebCapturingURLProtocol.capture = capture
        defer { DicomWebCapturingURLProtocol.capture = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DicomWebCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let transport = URLSessionDicomWebHTTPTransport(session: session)

        let response = try await transport.send(DicomWebHTTPRequest(
            method: .post,
            url: URL(string: "https://archive.example/dicom-web/studies")!,
            headers: ["Accept": "application/dicom+json", "Authorization": "Bearer token"],
            body: Data("payload".utf8),
            timeout: 5
        ))

        let request = try XCTUnwrap(capture.request)
        XCTAssertEqual(response.statusCode, 202)
        XCTAssertEqual(response.headers["X-Test"], "captured")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/dicom-web/studies")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/dicom+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(Self.bodyData(from: request), Data("payload".utf8))
    }

    private static func multipartBody(boundary: String, contentType: String, payload: Data) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        data.append(payload)
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
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

private final class DicomWebURLProtocolCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        lock.lock()
        let value = storedRequest
        lock.unlock()
        return value
    }

    func store(_ request: URLRequest) {
        lock.lock()
        storedRequest = request
        lock.unlock()
    }
}

private final class DicomWebCapturingURLProtocol: URLProtocol {
    static var capture: DicomWebURLProtocolCapture?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capture?.store(request)
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: 202,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["X-Test": "captured"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("accepted".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
