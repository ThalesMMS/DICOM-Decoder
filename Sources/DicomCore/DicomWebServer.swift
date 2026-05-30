import Foundation

public enum DicomWebUPSSupport: String, Sendable {
    case p2Deferred = "P2 deferred"
}

public struct DicomWebServerConfiguration: Equatable, Sendable {
    public var servicePath: String
    public var requiredBearerToken: String?
    public var cacheEnabled: Bool
    public var serverName: String

    public init(servicePath: String = "/dicom-web",
                requiredBearerToken: String? = nil,
                cacheEnabled: Bool = true,
                serverName: String = "DICOM-Decoder DICOMweb") {
        self.servicePath = servicePath.hasPrefix("/") ? servicePath : "/\(servicePath)"
        self.requiredBearerToken = requiredBearerToken
        self.cacheEnabled = cacheEnabled
        self.serverName = serverName
    }
}

public struct DicomWebConformanceStatement: Equatable, Sendable {
    public var serverName: String
    public var supportsQIDORS: Bool
    public var supportsWADORS: Bool
    public var supportsWADOURI: Bool
    public var supportsSTOWRS: Bool
    public var supportsJSON: Bool
    public var supportsXML: Bool
    public var supportsMultipart: Bool
    public var oauth2Optional: Bool
    public var upsSupport: DicomWebUPSSupport

    public init(serverName: String,
                supportsQIDORS: Bool = true,
                supportsWADORS: Bool = true,
                supportsWADOURI: Bool = true,
                supportsSTOWRS: Bool = true,
                supportsJSON: Bool = true,
                supportsXML: Bool = true,
                supportsMultipart: Bool = true,
                oauth2Optional: Bool = true,
                upsSupport: DicomWebUPSSupport = .p2Deferred) {
        self.serverName = serverName
        self.supportsQIDORS = supportsQIDORS
        self.supportsWADORS = supportsWADORS
        self.supportsWADOURI = supportsWADOURI
        self.supportsSTOWRS = supportsSTOWRS
        self.supportsJSON = supportsJSON
        self.supportsXML = supportsXML
        self.supportsMultipart = supportsMultipart
        self.oauth2Optional = oauth2Optional
        self.upsSupport = upsSupport
    }

    public var markdown: String {
        """
        # \(serverName) Conformance Statement

        Supported services:
        - QIDO-RS study search: \(supportsQIDORS ? "yes" : "no")
        - WADO-RS metadata and instance retrieve: \(supportsWADORS ? "yes" : "no")
        - WADO-URI object retrieve: \(supportsWADOURI ? "yes" : "no")
        - STOW-RS instance store: \(supportsSTOWRS ? "yes" : "no")

        Representations:
        - DICOM JSON: \(supportsJSON ? "yes" : "no")
        - DICOM XML: \(supportsXML ? "yes" : "no")
        - multipart/related: \(supportsMultipart ? "yes" : "no")

        Security:
        - OAuth2 bearer token validation: \(oauth2Optional ? "optional" : "not configured")

        Workflows:
        - UPS: \(upsSupport.rawValue)
        """
    }
}

public struct DicomWebStoredInstance: Equatable, Sendable {
    public var dataSet: DicomDataSet
    public var part10Data: Data
    public var studyInstanceUID: String
    public var seriesInstanceUID: String
    public var sopInstanceUID: String
    public var sopClassUID: String
    public var transferSyntax: DicomTransferSyntax

    public init(dataSet: DicomDataSet,
                part10Data: Data,
                studyInstanceUID: String,
                seriesInstanceUID: String,
                sopInstanceUID: String,
                sopClassUID: String,
                transferSyntax: DicomTransferSyntax = .explicitVRLittleEndian) {
        self.dataSet = dataSet
        self.part10Data = part10Data
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.transferSyntax = transferSyntax
    }
}

public final class DicomWebInMemoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: DicomWebStoredInstance] = [:]

    public init(instances: [DicomWebStoredInstance] = []) {
        for instance in instances {
            storage[instance.sopInstanceUID] = instance
        }
    }

    @discardableResult
    public func add(dataSet: DicomDataSet,
                    part10Data: Data? = nil,
                    transferSyntax: DicomTransferSyntax = .explicitVRLittleEndian) throws -> DicomWebStoredInstance {
        let normalized = Self.normalizedDataSet(dataSet)
        let data = try part10Data ?? DicomDataSetWriter.part10Data(
            from: normalized.dataSet,
            options: DicomPart10WriterOptions(transferSyntax: transferSyntax,
                                              mediaStorageSOPClassUID: normalized.sopClassUID,
                                              mediaStorageSOPInstanceUID: normalized.sopInstanceUID)
        )
        let instance = DicomWebStoredInstance(dataSet: normalized.dataSet,
                                             part10Data: data,
                                             studyInstanceUID: normalized.studyInstanceUID,
                                             seriesInstanceUID: normalized.seriesInstanceUID,
                                             sopInstanceUID: normalized.sopInstanceUID,
                                             sopClassUID: normalized.sopClassUID,
                                             transferSyntax: transferSyntax)
        lock.lock()
        storage[instance.sopInstanceUID] = instance
        lock.unlock()
        return instance
    }

    @discardableResult
    public func add(part10Data: Data,
                    transferSyntax: DicomTransferSyntax = .explicitVRLittleEndian) -> DicomWebStoredInstance {
        let dataSet = Self.dataSet(fromPart10Data: part10Data)
        let normalized = Self.normalizedDataSet(dataSet)
        let instance = DicomWebStoredInstance(dataSet: normalized.dataSet,
                                             part10Data: part10Data,
                                             studyInstanceUID: normalized.studyInstanceUID,
                                             seriesInstanceUID: normalized.seriesInstanceUID,
                                             sopInstanceUID: normalized.sopInstanceUID,
                                             sopClassUID: normalized.sopClassUID,
                                             transferSyntax: transferSyntax)
        lock.lock()
        storage[instance.sopInstanceUID] = instance
        lock.unlock()
        return instance
    }

    public func allInstances() -> [DicomWebStoredInstance] {
        lock.lock()
        let values = Array(storage.values)
        lock.unlock()
        return values.sorted { $0.sopInstanceUID < $1.sopInstanceUID }
    }

    public func instances(studyInstanceUID: String) -> [DicomWebStoredInstance] {
        allInstances().filter { $0.studyInstanceUID == studyInstanceUID }
    }

    public func instance(studyInstanceUID: String,
                         seriesInstanceUID: String,
                         sopInstanceUID: String) -> DicomWebStoredInstance? {
        lock.lock()
        let value = storage[sopInstanceUID]
        lock.unlock()
        guard value?.studyInstanceUID == studyInstanceUID,
              value?.seriesInstanceUID == seriesInstanceUID else {
            return nil
        }
        return value
    }

    public var count: Int {
        lock.lock()
        let value = storage.count
        lock.unlock()
        return value
    }

    private static func normalizedDataSet(_ dataSet: DicomDataSet) -> (
        dataSet: DicomDataSet,
        studyInstanceUID: String,
        seriesInstanceUID: String,
        sopInstanceUID: String,
        sopClassUID: String
    ) {
        var copy = dataSet
        let studyUID = dataSet.string(for: .studyInstanceUID)?.dicomWebNonEmpty ?? DicomDataSetWriter.makeUID()
        let seriesUID = dataSet.string(for: .seriesInstanceUID)?.dicomWebNonEmpty ?? DicomDataSetWriter.makeUID()
        let sopUID = dataSet.string(for: .sopInstanceUID)?.dicomWebNonEmpty ?? DicomDataSetWriter.makeUID()
        let sopClassUID = dataSet.string(for: .sopClassUID)?.dicomWebNonEmpty ??
            DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID

        copy.set(dicomWebStringElement(DicomTag.studyInstanceUID.rawValue, .UI, studyUID))
        copy.set(dicomWebStringElement(DicomTag.seriesInstanceUID.rawValue, .UI, seriesUID))
        copy.set(dicomWebStringElement(DicomTag.sopInstanceUID.rawValue, .UI, sopUID))
        copy.set(dicomWebStringElement(DicomTag.sopClassUID.rawValue, .UI, sopClassUID))
        return (copy, studyUID, seriesUID, sopUID, sopClassUID)
    }

    private static func dataSet(fromPart10Data data: Data) -> DicomDataSet {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicomweb-\(UUID().uuidString).dcm")
        do {
            try data.write(to: url, options: [.atomic])
            defer { try? FileManager.default.removeItem(at: url) }
            let decoder = try DCMDecoder(contentsOf: url)
            return DicomDataSet(elements: [
                dicomWebStringElement(DicomTag.patientName.rawValue, .PN, decoder.info(for: .patientName)),
                dicomWebStringElement(DicomTag.patientID.rawValue, .LO, decoder.info(for: .patientID)),
                dicomWebStringElement(DicomTag.studyDate.rawValue, .DA, decoder.info(for: .studyDate)),
                dicomWebStringElement(DicomTag.studyDescription.rawValue, .LO, decoder.info(for: .studyDescription)),
                dicomWebStringElement(DicomTag.studyInstanceUID.rawValue, .UI, decoder.info(for: .studyInstanceUID)),
                dicomWebStringElement(DicomTag.seriesInstanceUID.rawValue, .UI, decoder.info(for: .seriesInstanceUID)),
                dicomWebStringElement(DicomTag.sopClassUID.rawValue, .UI, decoder.info(for: .sopClassUID)),
                dicomWebStringElement(DicomTag.sopInstanceUID.rawValue, .UI, decoder.info(for: .sopInstanceUID)),
                dicomWebStringElement(DicomTag.modality.rawValue, .CS, decoder.info(for: .modality))
            ].filter { !$0.stringValues.isEmpty })
        } catch {
            return DicomDataSet()
        }
    }
}

public final class DicomWebServer: DicomWebHTTPTransport, @unchecked Sendable {
    public let configuration: DicomWebServerConfiguration
    public let store: DicomWebInMemoryStore
    public let conformanceStatement: DicomWebConformanceStatement

    private let lock = NSLock()
    private var cache: [String: DicomWebHTTPResponse] = [:]

    public init(configuration: DicomWebServerConfiguration = DicomWebServerConfiguration(),
                store: DicomWebInMemoryStore = DicomWebInMemoryStore()) {
        self.configuration = configuration
        self.store = store
        self.conformanceStatement = DicomWebConformanceStatement(
            serverName: configuration.serverName,
            oauth2Optional: configuration.requiredBearerToken != nil
        )
    }

    public func send(_ request: DicomWebHTTPRequest) async throws -> DicomWebHTTPResponse {
        handle(request)
    }

    public func handle(_ request: DicomWebHTTPRequest) -> DicomWebHTTPResponse {
        guard isAuthorized(request) else {
            return response(statusCode: 401,
                            headers: ["WWW-Authenticate": "Bearer realm=\"DICOMweb\""],
                            text: "Bearer token required.")
        }

        let cacheKey = self.cacheKey(for: request)
        if configuration.cacheEnabled, request.method == .get, let cached = cachedResponse(for: cacheKey) {
            var hit = cached
            hit.headers["X-DICOMweb-Cache"] = "HIT"
            return hit
        }

        let routed = route(request)
        if configuration.cacheEnabled, request.method == .get, (200..<300).contains(routed.statusCode) {
            storeCachedResponse(routed, for: cacheKey)
        }
        return routed
    }

    private func route(_ request: DicomWebHTTPRequest) -> DicomWebHTTPResponse {
        let path = pathComponents(for: request.url)
        switch (request.method, path) {
        case (.get, []), (.get, ["conformance"]):
            return response(statusCode: 200,
                            headers: ["Content-Type": "text/markdown"],
                            body: Data(conformanceStatement.markdown.utf8))
        case (.get, ["ups"]), (.get, ["workitems"]):
            return response(statusCode: 501,
                            headers: ["Content-Type": "text/plain"],
                            text: "UPS is explicitly \(conformanceStatement.upsSupport.rawValue).")
        case (.get, ["studies"]):
            return qidoStudies(request)
        case (.get, ["wado"]):
            return wadoURI(request)
        case (.post, ["studies"]):
            return stow(request, forcedStudyInstanceUID: nil)
        default:
            break
        }

        if request.method == .get,
           path.count == 3,
           path[0] == "studies",
           path[2] == "metadata" {
            return wadoMetadata(studyInstanceUID: path[1], request: request)
        }

        if request.method == .get,
           path.count == 6,
           path[0] == "studies",
           path[2] == "series",
           path[4] == "instances" {
            return wadoInstance(studyInstanceUID: path[1],
                                seriesInstanceUID: path[3],
                                sopInstanceUID: path[5])
        }

        if request.method == .post,
           path.count == 2,
           path[0] == "studies" {
            return stow(request, forcedStudyInstanceUID: path[1])
        }

        return response(statusCode: 404, text: "DICOMweb route not found.")
    }

    private func qidoStudies(_ request: DicomWebHTTPRequest) -> DicomWebHTTPResponse {
        let filters = queryItems(for: request.url)
        let modalityFilter = filters["ModalitiesInStudy"] ?? filters["Modality"]
        let studies = uniqueStudies().filter { dataSet in
            matches(dataSet: dataSet, tag: .patientName, filter: filters["PatientName"]) &&
            matches(dataSet: dataSet, tag: .patientID, filter: filters["PatientID"]) &&
            matches(dataSet: dataSet, tag: 0x0008_0050, filter: filters["AccessionNumber"]) &&
            matches(dataSet: dataSet, tag: .studyDate, filter: filters["StudyDate"]) &&
            matches(dataSet: dataSet, tag: .studyDescription, filter: filters["StudyDescription"]) &&
            matches(dataSet: dataSet, tag: .referringPhysicianName, filter: filters["ReferringPhysicianName"]) &&
            matches(dataSet: dataSet, tag: .institutionName, filter: filters["InstitutionName"]) &&
            matches(dataSet: dataSet, tag: .studyInstanceUID, filter: filters["StudyInstanceUID"]) &&
            matches(dataSet: dataSet, tag: .modalitiesInStudy, fallbackTag: .modality, filter: modalityFilter)
        }
        return encodedDataSets(studies, request: request)
    }

    private func wadoMetadata(studyInstanceUID: String, request: DicomWebHTTPRequest) -> DicomWebHTTPResponse {
        let dataSets = store.instances(studyInstanceUID: studyInstanceUID)
            .map { $0.dataSet.removing(.pixelData) }
        guard !dataSets.isEmpty else {
            return response(statusCode: 404, text: "Study not found.")
        }
        return encodedDataSets(dataSets, request: request)
    }

    private func wadoInstance(studyInstanceUID: String,
                              seriesInstanceUID: String,
                              sopInstanceUID: String) -> DicomWebHTTPResponse {
        guard let instance = store.instance(studyInstanceUID: studyInstanceUID,
                                            seriesInstanceUID: seriesInstanceUID,
                                            sopInstanceUID: sopInstanceUID) else {
            return response(statusCode: 404, text: "Instance not found.")
        }
        return multipartResponse(contentType: "application/dicom", payload: instance.part10Data)
    }

    private func wadoURI(_ request: DicomWebHTTPRequest) -> DicomWebHTTPResponse {
        let query = queryItems(for: request.url)
        guard query["requestType"]?.caseInsensitiveCompare("WADO") == .orderedSame,
              let studyUID = query["studyUID"],
              let seriesUID = query["seriesUID"],
              let objectUID = query["objectUID"] else {
            return response(statusCode: 400, text: "Invalid WADO-URI request.")
        }
        guard let instance = store.instance(studyInstanceUID: studyUID,
                                            seriesInstanceUID: seriesUID,
                                            sopInstanceUID: objectUID) else {
            return response(statusCode: 404, text: "Instance not found.")
        }
        return response(statusCode: 200,
                        headers: ["Content-Type": query["contentType"] ?? "application/dicom"],
                        body: instance.part10Data)
    }

    private func stow(_ request: DicomWebHTTPRequest, forcedStudyInstanceUID: String?) -> DicomWebHTTPResponse {
        let body = request.body ?? Data()
        let contentType = request.headers.dicomWebHeaderValue("Content-Type")
        let payloads: [Data]
        do {
            if let contentType, contentType.lowercased().contains("multipart/related") {
                guard let boundary = DicomWebMultipartParser.boundary(from: contentType) else {
                    return response(statusCode: 400, text: "Missing multipart boundary.")
                }
                payloads = try DicomWebMultipartParser.parts(from: body, boundary: boundary).map(\.body)
            } else if !body.isEmpty {
                payloads = [body]
            } else {
                payloads = []
            }
        } catch {
            return response(statusCode: 400, text: error.localizedDescription)
        }

        guard !payloads.isEmpty else {
            return response(statusCode: 400, text: "STOW request did not include DICOM payloads.")
        }

        var stored: [DicomWebStoredInstance] = []
        for payload in payloads {
            let instance = store.add(part10Data: payload)
            if let forcedStudyInstanceUID, instance.studyInstanceUID != forcedStudyInstanceUID {
                var dataSet = instance.dataSet
                dataSet.set(dicomWebStringElement(DicomTag.studyInstanceUID.rawValue, .UI, forcedStudyInstanceUID))
                if let replacement = try? store.add(dataSet: dataSet, part10Data: payload, transferSyntax: instance.transferSyntax) {
                    stored.append(replacement)
                } else {
                    stored.append(instance)
                }
            } else {
                stored.append(instance)
            }
        }
        clearCache()

        let json: [String: Any] = [
            "storedInstanceCount": stored.count,
            "sopInstanceUIDs": stored.map(\.sopInstanceUID)
        ]
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
        return response(statusCode: 200,
                        headers: ["Content-Type": "application/json"],
                        body: data)
    }

    private func encodedDataSets(_ dataSets: [DicomDataSet], request: DicomWebHTTPRequest) -> DicomWebHTTPResponse {
        let accept = request.headers.dicomWebHeaderValue("Accept") ?? "application/dicom+json"
        if accept.lowercased().contains("application/dicom+xml") {
            return response(statusCode: 200,
                            headers: ["Content-Type": "application/dicom+xml"],
                            body: DicomWebDataSetEncoder.xmlData(from: dataSets))
        }
        do {
            return response(statusCode: 200,
                            headers: ["Content-Type": "application/dicom+json"],
                            body: try DicomWebDataSetEncoder.jsonData(from: dataSets))
        } catch {
            return response(statusCode: 500, text: error.localizedDescription)
        }
    }

    private func uniqueStudies() -> [DicomDataSet] {
        var seen: Set<String> = []
        return store.allInstances().compactMap { instance in
            guard !seen.contains(instance.studyInstanceUID) else { return nil }
            seen.insert(instance.studyInstanceUID)
            return instance.dataSet.removing(.pixelData)
        }
    }

    private func matches(dataSet: DicomDataSet,
                         tag: DicomTag,
                         fallbackTag: DicomTag? = nil,
                         filter: String?) -> Bool {
        guard let filter = filter?.dicomWebNonEmpty else { return true }
        let value = dataSet.string(for: tag) ?? fallbackTag.flatMap { dataSet.string(for: $0) } ?? ""
        if tag == .patientName {
            return value.localizedCaseInsensitiveContains(filter)
        }
        return value == filter
    }

    private func matches(dataSet: DicomDataSet, tag: Int, filter: String?) -> Bool {
        guard let filter = filter?.dicomWebNonEmpty else { return true }
        return dataSet.string(for: tag) == filter
    }

    private func multipartResponse(contentType: String, payload: Data) -> DicomWebHTTPResponse {
        let boundary = "dicomweb-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(payload)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return response(statusCode: 200,
                        headers: ["Content-Type": "multipart/related; type=\"\(contentType)\"; boundary=\(boundary)"],
                        body: body)
    }

    private func isAuthorized(_ request: DicomWebHTTPRequest) -> Bool {
        guard let token = configuration.requiredBearerToken?.dicomWebNonEmpty else { return true }
        return request.headers.dicomWebHeaderValue("Authorization") == "Bearer \(token)"
    }

    private func pathComponents(for url: URL) -> [String] {
        var path = url.path
        if path.hasPrefix(configuration.servicePath) {
            path.removeFirst(configuration.servicePath.count)
        }
        return path.split(separator: "/").map(String.init)
    }

    private func queryItems(for url: URL) -> [String: String] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { result, item in
                result[item.name] = item.value
            } ?? [:]
    }

    private func response(statusCode: Int,
                          headers: [String: String] = [:],
                          text: String) -> DicomWebHTTPResponse {
        response(statusCode: statusCode,
                 headers: ["Content-Type": "text/plain"].merging(headers) { _, new in new },
                 body: Data(text.utf8))
    }

    private func response(statusCode: Int,
                          headers: [String: String] = [:],
                          body: Data) -> DicomWebHTTPResponse {
        DicomWebHTTPResponse(statusCode: statusCode, headers: headers, body: body)
    }

    private func cacheKey(for request: DicomWebHTTPRequest) -> String {
        "\(request.method.rawValue) \(request.url.absoluteString) \(request.headers.dicomWebHeaderValue("Accept") ?? "")"
    }

    private func cachedResponse(for key: String) -> DicomWebHTTPResponse? {
        lock.lock()
        let value = cache[key]
        lock.unlock()
        return value
    }

    private func storeCachedResponse(_ response: DicomWebHTTPResponse, for key: String) {
        lock.lock()
        cache[key] = response
        lock.unlock()
    }

    private func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}

private enum DicomWebDataSetEncoder {
    static func jsonData(from dataSets: [DicomDataSet]) throws -> Data {
        let objects = try dataSets.map { try jsonObject(from: $0) }
        return try JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
    }

    static func xmlData(from dataSets: [DicomDataSet]) -> Data {
        let models = dataSets.map { dataSet in
            let attributes = dataSet.elements
                .filter { $0.tag != DicomTag.pixelData.rawValue }
                .map(xmlAttribute)
                .joined()
            return "<NativeDicomModel>\(attributes)</NativeDicomModel>"
        }.joined()
        return Data("<DicomWebMetadata>\(models)</DicomWebMetadata>".utf8)
    }

    private static func jsonObject(from dataSet: DicomDataSet) throws -> [String: Any] {
        var object: [String: Any] = [:]
        for element in dataSet.elements where element.tag != DicomTag.pixelData.rawValue {
            object[String(format: "%08X", element.tag)] = try jsonElement(from: element)
        }
        return object
    }

    private static func jsonElement(from element: DicomDataElement) throws -> [String: Any] {
        var object: [String: Any] = ["vr": element.vr.dicomWebCode]
        switch element.value {
        case .empty:
            break
        case .strings(let values):
            if element.vr == .PN {
                object["Value"] = values.map { ["Alphabetic": $0] }
            } else {
                object["Value"] = values
            }
        case .signedIntegers(let values):
            object["Value"] = values
        case .unsignedIntegers(let values):
            object["Value"] = values.map { Int($0) }
        case .floats(let values):
            object["Value"] = values
        case .bytes(let data):
            object["InlineBinary"] = data.base64EncodedString()
        case .sequence(let items):
            object["Value"] = try items.map { try jsonObject(from: $0.dataSet) }
        }
        return object
    }

    private static func xmlAttribute(_ element: DicomDataElement) -> String {
        let tag = String(format: "%08X", element.tag)
        let vr = element.vr.dicomWebCode
        let values = element.stringValues.enumerated().map { index, value in
            "<Value number=\"\(index + 1)\">\(escape(value))</Value>"
        }.joined()
        return "<DicomAttribute tag=\"\(tag)\" vr=\"\(vr)\">\(values)</DicomAttribute>"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private func dicomWebStringElement(_ tag: Int, _ vr: DicomVR, _ value: String) -> DicomDataElement {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return DicomDataElement(tag: tag, vr: vr, value: trimmed.isEmpty ? .empty : .strings([trimmed]))
}

private extension String {
    var dicomWebNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
