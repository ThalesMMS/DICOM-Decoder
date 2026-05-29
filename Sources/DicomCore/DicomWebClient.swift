import Foundation

public enum DicomWebHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

public struct DicomWebHTTPRequest: Sendable {
    public var method: DicomWebHTTPMethod
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(method: DicomWebHTTPMethod,
                url: URL,
                headers: [String: String] = [:],
                body: Data? = nil,
                timeout: TimeInterval = 30) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct DicomWebHTTPResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol DicomWebHTTPTransport: Sendable {
    func send(_ request: DicomWebHTTPRequest) async throws -> DicomWebHTTPResponse
}

public final class URLSessionDicomWebHTTPTransport: DicomWebHTTPTransport, @unchecked Sendable {
    public static let shared = URLSessionDicomWebHTTPTransport()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: DicomWebHTTPRequest) async throws -> DicomWebHTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: urlRequest) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: DicomWebClientError.invalidHTTPResponse)
                    return
                }
                let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                    guard let key = pair.key as? String else { return }
                    result[key] = String(describing: pair.value)
                }
                continuation.resume(returning: DicomWebHTTPResponse(statusCode: httpResponse.statusCode,
                                                                    headers: headers,
                                                                    body: data ?? Data()))
            }
            task.resume()
        }
    }
}

public struct DicomWebClientConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var headers: [String: String]
    public var timeout: TimeInterval

    public init(baseURL: URL,
                headers: [String: String] = [:],
                timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.headers = headers
        self.timeout = timeout
    }

    public init(baseURL: URL,
                bearerToken: String?,
                timeout: TimeInterval = 30) {
        var headers: [String: String] = [:]
        if let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        self.init(baseURL: baseURL, headers: headers, timeout: timeout)
    }
}

public struct DicomWebQuery: Equatable, Sendable {
    public var patientName: String?
    public var patientID: String?
    public var studyInstanceUID: String?
    public var modality: String?
    public var limit: Int?
    public var offset: Int?
    public var includeAllFields: Bool

    public init(patientName: String? = nil,
                patientID: String? = nil,
                studyInstanceUID: String? = nil,
                modality: String? = nil,
                limit: Int? = nil,
                offset: Int? = nil,
                includeAllFields: Bool = true) {
        self.patientName = patientName
        self.patientID = patientID
        self.studyInstanceUID = studyInstanceUID
        self.modality = modality
        self.limit = limit
        self.offset = offset
        self.includeAllFields = includeAllFields
    }
}

public struct DicomWebStudySummary: Equatable, Sendable, Identifiable {
    public var id: String { studyInstanceUID }
    public var dataSet: DicomDataSet
    public var patientName: String
    public var patientID: String
    public var studyDate: String
    public var studyDescription: String
    public var studyInstanceUID: String

    public init(dataSet: DicomDataSet) {
        self.dataSet = dataSet
        self.patientName = dataSet.string(for: .patientName) ?? "Unknown"
        self.patientID = dataSet.string(for: .patientID) ?? ""
        self.studyDate = dataSet.string(for: .studyDate) ?? ""
        self.studyDescription = dataSet.string(for: .studyDescription) ?? ""
        self.studyInstanceUID = dataSet.string(for: .studyInstanceUID) ?? ""
    }
}

public struct DicomWebMultipartPart: Equatable, Sendable {
    public var headers: [String: String]
    public var body: Data

    public var contentType: String? {
        headers.dicomWebHeaderValue("Content-Type")
    }

    public init(headers: [String: String] = [:], body: Data) {
        self.headers = headers
        self.body = body
    }
}

public struct DicomWebRetrievedObject: Equatable, Sendable {
    public var statusCode: Int
    public var contentType: String?
    public var parts: [DicomWebMultipartPart]

    public var firstPayload: Data? {
        parts.first?.body
    }

    public init(statusCode: Int, contentType: String?, parts: [DicomWebMultipartPart]) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.parts = parts
    }
}

public struct DicomWebStoreInstance: Equatable, Sendable {
    public var data: Data
    public var contentType: String
    public var transferSyntax: String?

    public init(data: Data,
                contentType: String = "application/dicom",
                transferSyntax: String? = DicomTransferSyntax.explicitVRLittleEndian.rawValue) {
        self.data = data
        self.contentType = contentType
        self.transferSyntax = transferSyntax
    }
}

public struct DicomWebStoreResult: Equatable, Sendable {
    public var statusCode: Int
    public var responseData: Data
    public var responseParts: [DicomWebMultipartPart]
    public var storedInstanceCount: Int

    public init(statusCode: Int,
                responseData: Data,
                responseParts: [DicomWebMultipartPart] = [],
                storedInstanceCount: Int) {
        self.statusCode = statusCode
        self.responseData = responseData
        self.responseParts = responseParts
        self.storedInstanceCount = storedInstanceCount
    }
}

public enum DicomWebClientError: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case invalidBaseURL(URL)
    case httpStatus(statusCode: Int, method: String, url: String, bodyPreview: String)
    case invalidJSONResponse
    case malformedDICOMJSONElement(String)
    case unsupportedDICOMJSONValue(tag: String, vr: String)
    case missingMultipartBoundary(contentType: String?)
    case malformedMultipartBody
    case emptyStoreRequest
}

extension DicomWebClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "DICOMweb response was not an HTTP response."
        case .invalidBaseURL(let url):
            return "Invalid DICOMweb base URL: \(url.absoluteString)"
        case .httpStatus(let statusCode, let method, let url, let bodyPreview):
            let suffix = bodyPreview.isEmpty ? "" : " Body: \(bodyPreview)"
            return "DICOMweb \(method) \(url) failed with HTTP \(statusCode).\(suffix)"
        case .invalidJSONResponse:
            return "DICOMweb response did not contain valid DICOM JSON."
        case .malformedDICOMJSONElement(let tag):
            return "DICOMweb JSON element \(tag) is malformed."
        case .unsupportedDICOMJSONValue(let tag, let vr):
            return "DICOMweb JSON element \(tag) with VR \(vr) is not supported."
        case .missingMultipartBoundary(let contentType):
            return "DICOMweb multipart response is missing a boundary in Content-Type \(contentType ?? "<none>")."
        case .malformedMultipartBody:
            return "DICOMweb multipart response is malformed."
        case .emptyStoreRequest:
            return "DICOMweb STOW request must include at least one DICOM instance."
        }
    }
}

public struct DicomWebClient: Sendable {
    public var configuration: DicomWebClientConfiguration
    private let transport: any DicomWebHTTPTransport

    public init(configuration: DicomWebClientConfiguration,
                transport: any DicomWebHTTPTransport = URLSessionDicomWebHTTPTransport.shared) {
        self.configuration = configuration
        self.transport = transport
    }

    public func searchStudies(_ query: DicomWebQuery = DicomWebQuery()) async throws -> [DicomWebStudySummary] {
        let response = try await send(
            .get,
            url: queryURL(path: ["studies"], query: studyQueryItems(query)),
            headers: ["Accept": "application/dicom+json"]
        )
        let dataSets = try DicomWebJSONParser.dataSets(from: response.body)
        return dataSets.map(DicomWebStudySummary.init).filter { !$0.studyInstanceUID.isEmpty }
    }

    public func retrieveStudyMetadata(studyInstanceUID: String) async throws -> [DicomDataSet] {
        let response = try await send(
            .get,
            url: endpoint(["studies", studyInstanceUID, "metadata"]),
            headers: ["Accept": "application/dicom+json"]
        )
        return try DicomWebJSONParser.dataSets(from: response.body)
    }

    public func retrieveInstance(studyInstanceUID: String,
                                 seriesInstanceUID: String,
                                 sopInstanceUID: String) async throws -> DicomWebRetrievedObject {
        let response = try await send(
            .get,
            url: endpoint(["studies", studyInstanceUID, "series", seriesInstanceUID, "instances", sopInstanceUID]),
            headers: ["Accept": "multipart/related; type=\"application/dicom\"; transfer-syntax=*"]
        )
        return try retrievedObject(from: response)
    }

    public func retrieveRenderedFrame(studyInstanceUID: String,
                                      seriesInstanceUID: String,
                                      sopInstanceUID: String,
                                      frameNumber: Int = 1,
                                      accept: String = "image/png, image/jpeg") async throws -> DicomWebRetrievedObject {
        let response = try await send(
            .get,
            url: endpoint([
                "studies", studyInstanceUID,
                "series", seriesInstanceUID,
                "instances", sopInstanceUID,
                "frames", String(max(1, frameNumber)),
                "rendered"
            ]),
            headers: ["Accept": accept]
        )
        return try retrievedObject(from: response)
    }

    public func retrieveWADOURIObject(studyInstanceUID: String,
                                      seriesInstanceUID: String,
                                      sopInstanceUID: String,
                                      contentType: String = "application/dicom") async throws -> DicomWebRetrievedObject {
        let response = try await send(
            .get,
            url: queryURL(path: ["wado"], query: [
                URLQueryItem(name: "requestType", value: "WADO"),
                URLQueryItem(name: "studyUID", value: studyInstanceUID),
                URLQueryItem(name: "seriesUID", value: seriesInstanceUID),
                URLQueryItem(name: "objectUID", value: sopInstanceUID),
                URLQueryItem(name: "contentType", value: contentType)
            ]),
            headers: ["Accept": contentType]
        )
        return try retrievedObject(from: response)
    }

    public func store(dataSet: DicomDataSet,
                      studyInstanceUID: String? = nil,
                      transferSyntax: DicomTransferSyntax = .explicitVRLittleEndian) async throws -> DicomWebStoreResult {
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(transferSyntax: transferSyntax)
        )
        let instance = DicomWebStoreInstance(data: data,
                                             transferSyntax: transferSyntax.rawValue)
        return try await storeInstances([instance],
                                        studyInstanceUID: studyInstanceUID ?? dataSet.string(for: .studyInstanceUID))
    }

    public func storeInstances(_ instances: [DicomWebStoreInstance],
                               studyInstanceUID: String? = nil) async throws -> DicomWebStoreResult {
        guard !instances.isEmpty else {
            throw DicomWebClientError.emptyStoreRequest
        }
        let boundary = "dicomweb-\(UUID().uuidString)"
        let body = multipartBody(instances: instances, boundary: boundary)
        let response = try await send(
            .post,
            url: endpoint(studyInstanceUID.map { ["studies", $0] } ?? ["studies"]),
            headers: [
                "Content-Type": "multipart/related; type=\"application/dicom\"; boundary=\(boundary)",
                "Accept": "application/dicom+json, multipart/related"
            ],
            body: body
        )

        let contentType = response.headers.dicomWebHeaderValue("Content-Type")
        let parts = try multipartPartsIfNeeded(body: response.body, contentType: contentType)
        return DicomWebStoreResult(statusCode: response.statusCode,
                                   responseData: response.body,
                                   responseParts: parts,
                                   storedInstanceCount: instances.count)
    }

    private func send(_ method: DicomWebHTTPMethod,
                      url: URL,
                      headers: [String: String],
                      body: Data? = nil) async throws -> DicomWebHTTPResponse {
        var requestHeaders = configuration.headers
        for (field, value) in headers {
            requestHeaders[field] = value
        }
        let request = DicomWebHTTPRequest(method: method,
                                          url: url,
                                          headers: requestHeaders,
                                          body: body,
                                          timeout: configuration.timeout)
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw DicomWebClientError.httpStatus(statusCode: response.statusCode,
                                                 method: method.rawValue,
                                                 url: url.absoluteString,
                                                 bodyPreview: String.dicomWebPreview(response.body))
        }
        return response
    }

    private func retrievedObject(from response: DicomWebHTTPResponse) throws -> DicomWebRetrievedObject {
        let contentType = response.headers.dicomWebHeaderValue("Content-Type")
        let parts = try multipartPartsIfNeeded(body: response.body, contentType: contentType)
        if !parts.isEmpty {
            return DicomWebRetrievedObject(statusCode: response.statusCode,
                                           contentType: contentType,
                                           parts: parts)
        }
        return DicomWebRetrievedObject(statusCode: response.statusCode,
                                       contentType: contentType,
                                       parts: [DicomWebMultipartPart(headers: response.headers, body: response.body)])
    }

    private func multipartPartsIfNeeded(body: Data, contentType: String?) throws -> [DicomWebMultipartPart] {
        guard let contentType, contentType.lowercased().contains("multipart/related") else {
            return []
        }
        guard let boundary = DicomWebMultipartParser.boundary(from: contentType) else {
            throw DicomWebClientError.missingMultipartBoundary(contentType: contentType)
        }
        return try DicomWebMultipartParser.parts(from: body, boundary: boundary)
    }

    private func endpoint(_ pathComponents: [String]) -> URL {
        var url = configuration.baseURL
        for component in pathComponents {
            url.appendPathComponent(component)
        }
        return url
    }

    private func queryURL(path: [String], query: [URLQueryItem]) -> URL {
        let url = endpoint(path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = query.isEmpty ? nil : query
        return components.url ?? url
    }

    private func studyQueryItems(_ query: DicomWebQuery) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        appendQueryItem("PatientName", value: query.patientName, to: &items)
        appendQueryItem("PatientID", value: query.patientID, to: &items)
        appendQueryItem("StudyInstanceUID", value: query.studyInstanceUID, to: &items)
        appendQueryItem("Modality", value: query.modality, to: &items)
        if let limit = query.limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let offset = query.offset {
            items.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        if query.includeAllFields {
            items.append(URLQueryItem(name: "includefield", value: "all"))
        }
        return items
    }

    private func appendQueryItem(_ name: String, value: String?, to items: inout [URLQueryItem]) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        items.append(URLQueryItem(name: name, value: value))
    }

    private func multipartBody(instances: [DicomWebStoreInstance], boundary: String) -> Data {
        var data = Data()
        for instance in instances {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            var contentType = instance.contentType
            if let transferSyntax = instance.transferSyntax {
                contentType += "; transfer-syntax=\(transferSyntax)"
            }
            data.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
            data.append(instance.data)
            data.append("\r\n".data(using: .utf8)!)
        }
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }
}

private enum DicomWebJSONParser {
    static func dataSets(from data: Data) throws -> [DicomDataSet] {
        guard !data.isEmpty else { return [] }
        let object = try JSONSerialization.jsonObject(with: data)
        if let array = object as? [[String: Any]] {
            return try array.map(dataSet(from:))
        }
        if let dictionary = object as? [String: Any] {
            return [try dataSet(from: dictionary)]
        }
        throw DicomWebClientError.invalidJSONResponse
    }

    private static func dataSet(from object: [String: Any]) throws -> DicomDataSet {
        let elements = try object.keys.sorted().map { tagKey -> DicomDataElement in
            guard let tag = Int(tagKey, radix: 16),
                  let elementObject = object[tagKey] as? [String: Any],
                  let vrCode = elementObject["vr"] as? String else {
                throw DicomWebClientError.malformedDICOMJSONElement(tagKey)
            }
            let vr = DicomVR.dicomWebVR(for: vrCode)
            return DicomDataElement(tag: tag,
                                    vr: vr,
                                    value: try dataValue(for: vr, element: elementObject, tagKey: tagKey))
        }
        return DicomDataSet(elements: elements)
    }

    private static func dataValue(for vr: DicomVR,
                                  element: [String: Any],
                                  tagKey: String) throws -> DicomDataValue {
        if let inlineBinary = element["InlineBinary"] as? String {
            return .bytes(Data(base64Encoded: inlineBinary) ?? Data())
        }
        if let bulkDataURI = element["BulkDataURI"] as? String {
            return .strings([bulkDataURI])
        }
        guard let values = element["Value"] as? [Any], !values.isEmpty else {
            return .empty
        }

        switch vr {
        case .US, .UL, .AT:
            return .unsignedIntegers(try values.map { try unsignedInteger($0, tagKey: tagKey, vr: vr) })
        case .SS, .SL, .IS:
            return .signedIntegers(try values.map { try signedInteger($0, tagKey: tagKey, vr: vr) })
        case .FD, .FL, .DS:
            return .floats(try values.map { try floatingPoint($0, tagKey: tagKey, vr: vr) })
        case .SQ:
            return .sequence(try values.map { value in
                guard let object = value as? [String: Any] else {
                    throw DicomWebClientError.unsupportedDICOMJSONValue(tag: tagKey, vr: vr.dicomWebCode)
                }
                return DicomSequenceItem(dataSet: try dataSet(from: object))
            })
        default:
            return .strings(try values.map { try stringValue($0, tagKey: tagKey, vr: vr) })
        }
    }

    private static func stringValue(_ value: Any, tagKey: String, vr: DicomVR) throws -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if vr == .PN, let personName = value as? [String: Any] {
            return (personName["Alphabetic"] as? String) ??
                (personName["Ideographic"] as? String) ??
                (personName["Phonetic"] as? String) ??
                ""
        }
        throw DicomWebClientError.unsupportedDICOMJSONValue(tag: tagKey, vr: vr.dicomWebCode)
    }

    private static func signedInteger(_ value: Any, tagKey: String, vr: DicomVR) throws -> Int {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String, let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return int
        }
        throw DicomWebClientError.unsupportedDICOMJSONValue(tag: tagKey, vr: vr.dicomWebCode)
    }

    private static func unsignedInteger(_ value: Any, tagKey: String, vr: DicomVR) throws -> UInt {
        let int = try signedInteger(value, tagKey: tagKey, vr: vr)
        guard let unsigned = UInt(exactly: int) else {
            throw DicomWebClientError.unsupportedDICOMJSONValue(tag: tagKey, vr: vr.dicomWebCode)
        }
        return unsigned
    }

    private static func floatingPoint(_ value: Any, tagKey: String, vr: DicomVR) throws -> Double {
        if let double = value as? Double {
            return double
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String, let double = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return double
        }
        throw DicomWebClientError.unsupportedDICOMJSONValue(tag: tagKey, vr: vr.dicomWebCode)
    }
}

enum DicomWebMultipartParser {
    static func boundary(from contentType: String) -> String? {
        for component in contentType.components(separatedBy: ";") {
            let pair = component.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pair.count == 2, pair[0].lowercased() == "boundary" else { continue }
            return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    static func parts(from data: Data, boundary: String) throws -> [DicomWebMultipartPart] {
        let delimiter = Data("--\(boundary)".utf8)
        let headerSeparator = Data([13, 10, 13, 10])
        var cursor = data.startIndex
        var parts: [DicomWebMultipartPart] = []

        while let markerRange = data.range(of: delimiter, options: [], in: cursor..<data.endIndex) {
            cursor = markerRange.upperBound
            if data.hasBytes([45, 45], at: cursor) {
                break
            }
            if data.hasBytes([13, 10], at: cursor) {
                cursor += 2
            }
            guard let nextRange = data.range(of: delimiter, options: [], in: cursor..<data.endIndex) else {
                throw DicomWebClientError.malformedMultipartBody
            }
            let rawPart = data[cursor..<nextRange.lowerBound].dicomWebStrippingTrailingCRLF()
            guard let separatorRange = rawPart.range(of: headerSeparator) else {
                throw DicomWebClientError.malformedMultipartBody
            }
            let headerData = rawPart[rawPart.startIndex..<separatorRange.lowerBound]
            let body = Data(rawPart[separatorRange.upperBound..<rawPart.endIndex])
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                throw DicomWebClientError.malformedMultipartBody
            }
            parts.append(DicomWebMultipartPart(headers: headers(from: headerText), body: body))
            cursor = nextRange.lowerBound
        }

        return parts
    }

    private static func headers(from text: String) -> [String: String] {
        text.components(separatedBy: "\r\n").reduce(into: [String: String]()) { result, line in
            let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return }
            result[pair[0].trimmingCharacters(in: .whitespacesAndNewlines)] =
                pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

extension DicomVR {
    static func dicomWebVR(for code: String) -> DicomVR {
        let upper = code.uppercased()
        guard upper.count == 2, let first = upper.utf8.first, let last = upper.utf8.last else {
            return .unknown
        }
        return DicomVR(rawValue: Int(first) << 8 | Int(last)) ?? .unknown
    }

    var dicomWebCode: String {
        guard self != .unknown else { return "UN" }
        let high = UInt8((rawValue >> 8) & 0xFF)
        let low = UInt8(rawValue & 0xFF)
        return String(bytes: [high, low], encoding: .ascii) ?? "UN"
    }
}

extension Dictionary where Key == String, Value == String {
    func dicomWebHeaderValue(_ field: String) -> String? {
        first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
    }
}

private extension String {
    static func dicomWebPreview(_ data: Data) -> String {
        let prefix = data.prefix(512)
        return String(data: prefix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private extension Data {
    func hasBytes(_ bytes: [UInt8], at index: Data.Index) -> Bool {
        guard distance(from: index, to: endIndex) >= bytes.count else { return false }
        for (offset, byte) in bytes.enumerated() where self[index + offset] != byte {
            return false
        }
        return true
    }
}

private extension Data.SubSequence {
    func dicomWebStrippingTrailingCRLF() -> Data {
        guard distance(from: startIndex, to: endIndex) >= 2 else {
            return Data(self)
        }
        let previous = index(before: endIndex)
        let penultimate = index(before: previous)
        guard self[penultimate] == 13, self[previous] == 10 else {
            return Data(self)
        }
        return Data(self[startIndex..<penultimate])
    }
}
