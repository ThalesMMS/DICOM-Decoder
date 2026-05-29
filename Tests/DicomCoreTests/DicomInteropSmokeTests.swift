import Foundation
import XCTest
@testable import DicomCore

final class DicomInteropSmokeTests: XCTestCase {
    func testQA03Issue281SmokeConfigurationCoversRequiredInteropOperations() throws {
        let archives = try configuredArchives()
        let capabilities = Set(archives.flatMap(\.capabilities))

        XCTAssertTrue(capabilities.contains(.dicomweb), "At least one archive must cover DICOMweb.")
        XCTAssertTrue(capabilities.contains(.dimseEcho), "At least one archive must cover C-ECHO.")
        XCTAssertTrue(capabilities.contains(.dimseFind), "At least one archive must cover C-FIND.")
        XCTAssertTrue(capabilities.contains(.dimseStore), "At least one archive must cover C-STORE.")
        XCTAssertTrue(capabilities.contains(.dimseGet) || capabilities.contains(.dimseMove),
                      "At least one archive must cover C-GET or C-MOVE.")
        XCTAssertTrue(capabilities.contains(.storageSCP) || capabilities.contains(.dimseGet),
                      "Storage SCP coverage must be explicit, or C-GET must retrieve on the same association.")
    }

    func testQA03Issue281DICOMwebSmokeStoresQueriesAndRetrievesMetadata() async throws {
        let fixture = try fixture()
        let archives = try configuredArchives().filter { $0.capabilities.contains(.dicomweb) }
        guard !archives.isEmpty else {
            throw XCTSkip("No configured archive declares DICOMweb support.")
        }

        for archive in archives {
            guard let baseURL = archive.dicomWebURL else {
                XCTFail("\(archive.id) declares DICOMweb but has no URL.")
                continue
            }

            let client = DicomWebClient(configuration: DicomWebClientConfiguration(
                baseURL: baseURL,
                headers: archive.dicomWebHeaders,
                timeout: archive.timeout
            ))

            let store = try await client.storeInstances(
                [DicomWebStoreInstance(data: fixture.part10Data)],
                studyInstanceUID: fixture.studyInstanceUID
            )
            XCTAssertEqual(store.storedInstanceCount, 1, archive.id)

            let studies = try await retrying("QIDO \(archive.id)") {
                try await client.searchStudies(DicomWebQuery(patientID: fixture.patientID))
            } until: { studies in
                studies.contains { $0.studyInstanceUID == fixture.studyInstanceUID }
            }
            XCTAssertTrue(studies.contains { $0.studyInstanceUID == fixture.studyInstanceUID }, archive.id)

            let metadata = try await retrying("WADO metadata \(archive.id)") {
                try await client.retrieveStudyMetadata(studyInstanceUID: fixture.studyInstanceUID)
            } until: { dataSets in
                dataSets.contains { $0.string(for: .sopInstanceUID) == fixture.sopInstanceUID }
            }
            XCTAssertTrue(metadata.contains { $0.string(for: .sopInstanceUID) == fixture.sopInstanceUID }, archive.id)
        }
    }

    func testQA03Issue281DIMSESmokeEchoStoreFindRetrieveAndStorageSCP() throws {
        let fixture = try fixture()
        let archives = try configuredArchives().filter { $0.hasDIMSE }
        guard !archives.isEmpty else {
            throw XCTSkip("No configured archive declares DIMSE support.")
        }

        for archive in archives {
            let service = DicomDIMSEServiceSCU(configuration: archive.dimseConfiguration)

            if archive.capabilities.contains(.dimseEcho) {
                let echo = try service.verify()
                XCTAssertEqual(echo.status, 0, archive.id)
            }

            if archive.capabilities.contains(.dimseStore) {
                let store = try service.store(
                    dataSet: fixture.dataSet,
                    sopClassUID: fixture.sopClassUID,
                    sopInstanceUID: fixture.sopInstanceUID
                )
                XCTAssertEqual(store.status, 0, archive.id)
            }

            if archive.capabilities.contains(.dimseFind) {
                let result = try retrying("C-FIND \(archive.id)") {
                    try service.find(identifier: studyQuery(patientID: fixture.patientID))
                } until: { result in
                    result.matches.contains { $0.string(for: .studyInstanceUID) == fixture.studyInstanceUID }
                }
                XCTAssertTrue(result.matches.contains { $0.string(for: .studyInstanceUID) == fixture.studyInstanceUID }, archive.id)
            }

            if archive.capabilities.contains(.dimseGet) {
                let result = try service.get(
                    identifier: retrieveQuery(studyInstanceUID: fixture.studyInstanceUID),
                    storageSOPClassUIDs: [fixture.sopClassUID]
                )
                XCTAssertEqual(result.operation.status, 0, archive.id)
                XCTAssertTrue(result.retrievedInstances.contains { $0.sopInstanceUID == fixture.sopInstanceUID }, archive.id)
            }

            if archive.capabilities.contains(.dimseMove) {
                try runMoveSmoke(archive: archive, fixture: fixture, service: service)
            }
        }
    }

    private struct InteropArchive {
        var id: String
        var dimseHost: String?
        var dimsePort: UInt16?
        var calledAETitle: String
        var callingAETitle: String
        var dicomWebURL: URL?
        var dicomWebHeaders: [String: String]
        var capabilities: Set<InteropCapability>
        var moveDestinationAETitle: String?
        var storageSCPPort: UInt16
        var timeout: TimeInterval

        var hasDIMSE: Bool {
            dimseHost != nil && dimsePort != nil && capabilities.contains { $0.isDIMSE }
        }

        var dimseConfiguration: DicomDIMSEConnectionConfiguration {
            DicomDIMSEConnectionConfiguration(
                host: dimseHost ?? "127.0.0.1",
                port: dimsePort ?? 104,
                calledAETitle: calledAETitle,
                callingAETitle: callingAETitle,
                timeout: timeout
            )
        }
    }

    private enum InteropCapability: String {
        case dicomweb
        case dimseEcho = "dimse-echo"
        case dimseStore = "dimse-store"
        case dimseFind = "dimse-find"
        case dimseGet = "dimse-get"
        case dimseMove = "dimse-move"
        case storageSCP = "storage-scp"

        var isDIMSE: Bool {
            switch self {
            case .dimseEcho, .dimseStore, .dimseFind, .dimseGet, .dimseMove:
                return true
            case .dicomweb, .storageSCP:
                return false
            }
        }
    }

    private struct InteropFixture {
        var part10Data: Data
        var dataSet: DicomDataSet
        var patientID: String
        var studyInstanceUID: String
        var sopClassUID: String
        var sopInstanceUID: String
    }

    private func configuredArchives() throws -> [InteropArchive] {
        let env = ProcessInfo.processInfo.environment
        guard env["DICOM_INTEROP_SMOKE"] == "1" else {
            throw XCTSkip("Set DICOM_INTEROP_SMOKE=1 or run Scripts/interop/run_interop_smoke.sh.")
        }

        let requested = Set((env["DICOM_INTEROP_ARCHIVES"] ?? "orthanc,dcm4chee")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })

        let archives = [
            archive(id: "orthanc", prefix: "DICOM_INTEROP_ORTHANC", env: env),
            archive(id: "dcm4chee", prefix: "DICOM_INTEROP_DCM4CHEE", env: env)
        ].compactMap { $0 }
            .filter { requested.contains($0.id) }

        guard !archives.isEmpty else {
            throw XCTSkip("No interop archives selected by DICOM_INTEROP_ARCHIVES.")
        }
        return archives
    }

    private func archive(id: String, prefix: String, env: [String: String]) -> InteropArchive? {
        let capabilities = Set((env["\(prefix)_CAPABILITIES"] ?? "")
            .split(separator: ",")
            .compactMap { InteropCapability(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        guard !capabilities.isEmpty else { return nil }

        return InteropArchive(
            id: id,
            dimseHost: env["\(prefix)_DIMSE_HOST"],
            dimsePort: env["\(prefix)_DIMSE_PORT"].flatMap(UInt16.init),
            calledAETitle: env["\(prefix)_CALLED_AE"] ?? "ARCHIVE",
            callingAETitle: env["\(prefix)_CALLING_AE"] ?? "MTKSMOKE",
            dicomWebURL: env["\(prefix)_DICOMWEB_URL"].flatMap(URL.init(string:)),
            dicomWebHeaders: bearerHeaders(token: env["\(prefix)_DICOMWEB_BEARER_TOKEN"]),
            capabilities: capabilities,
            moveDestinationAETitle: env["\(prefix)_MOVE_DESTINATION_AE"],
            storageSCPPort: env["DICOM_INTEROP_STORAGE_SCP_PORT"].flatMap(UInt16.init) ?? 11114,
            timeout: env["DICOM_INTEROP_TIMEOUT"].flatMap(TimeInterval.init) ?? 30
        )
    }

    private func fixture() throws -> InteropFixture {
        let patientID = "QA03-281"
        let studyInstanceUID = "2.25.2810001"
        let seriesInstanceUID = "2.25.2810002"
        let sopClassUID = DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID
        let sopInstanceUID = "2.25.2810003"
        let dataSet = DicomDataSet(elements: [
            element(DicomTag.sopClassUID.rawValue, .UI, sopClassUID),
            element(DicomTag.sopInstanceUID.rawValue, .UI, sopInstanceUID),
            element(DicomTag.patientName.rawValue, .PN, "QA03^Interop"),
            element(DicomTag.patientID.rawValue, .LO, patientID),
            element(DicomTag.studyInstanceUID.rawValue, .UI, studyInstanceUID),
            element(DicomTag.seriesInstanceUID.rawValue, .UI, seriesInstanceUID),
            element(DicomTag.modality.rawValue, .CS, "OT"),
            us(.samplesPerPixel, 1),
            element(DicomTag.photometricInterpretation.rawValue, .CS, "MONOCHROME2"),
            us(.rows, 1),
            us(.columns, 1),
            us(.bitsAllocated, 8),
            us(.bitsStored, 8),
            us(.highBit, 7),
            us(.pixelRepresentation, 0),
            bytes(.pixelData, vr: .OB, Data([0x7F]))
        ])
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                mediaStorageSOPClassUID: sopClassUID,
                mediaStorageSOPInstanceUID: sopInstanceUID
            )
        )

        XCTAssertFalse(patientID.isEmpty)
        XCTAssertFalse(studyInstanceUID.isEmpty)
        XCTAssertFalse(sopInstanceUID.isEmpty)
        return InteropFixture(
            part10Data: data,
            dataSet: dataSet,
            patientID: patientID,
            studyInstanceUID: studyInstanceUID,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID
        )
    }

    private func runMoveSmoke(
        archive: InteropArchive,
        fixture: InteropFixture,
        service: DicomDIMSEServiceSCU
    ) throws {
        guard archive.capabilities.contains(.storageSCP) else {
            throw XCTSkip("\(archive.id) declares C-MOVE without storage-scp capability.")
        }
        guard let destination = archive.moveDestinationAETitle else {
            XCTFail("\(archive.id) declares C-MOVE but has no move destination AE title.")
            return
        }

        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-interop-scp-\(UUID().uuidString)", isDirectory: true)
        let storage = try DicomFileStorageCache(directoryURL: storageDirectory)
        let scpService = DicomStorageSCPService(
            configuration: DicomStorageSCPConfiguration(
                aeTitle: destination,
                port: archive.storageSCPPort,
                acceptAnyCalledAETitle: true
            ),
            storage: storage
        )
        #if canImport(Network)
        let server = try DicomStorageSCPServer(service: scpService)
        try server.start()
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: storageDirectory)
        }

        let result = try service.move(
            identifier: retrieveQuery(studyInstanceUID: fixture.studyInstanceUID),
            moveDestinationAETitle: destination
        )
        XCTAssertEqual(result.status, 0, archive.id)
        let storedURL = storageDirectory
            .appendingPathComponent(DicomFileStorageCache.fileName(for: fixture.sopInstanceUID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path), archive.id)
        #else
        throw XCTSkip("Network framework is unavailable on this platform.")
        #endif
    }

    private func studyQuery(patientID: String) -> DicomDataSet {
        DicomDataSet(elements: [
            element(0x0008_0052, .CS, "STUDY"),
            element(DicomTag.patientID.rawValue, .LO, patientID),
            element(DicomTag.patientName.rawValue, .PN, ""),
            element(DicomTag.studyInstanceUID.rawValue, .UI, "")
        ])
    }

    private func retrieveQuery(studyInstanceUID: String) -> DicomDataSet {
        DicomDataSet(elements: [
            element(0x0008_0052, .CS, "STUDY"),
            element(DicomTag.studyInstanceUID.rawValue, .UI, studyInstanceUID)
        ])
    }

    private func element(_ tag: Int, _ vr: DicomVR, _ value: String) -> DicomDataElement {
        DicomDataElement(tag: tag, vr: vr, value: .strings([value]))
    }

    private func us(_ tag: DicomTag, _ value: UInt) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .US, value: .unsignedIntegers([value]))
    }

    private func bytes(_ tag: DicomTag, vr: DicomVR, _ data: Data) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: vr, value: .bytes(data))
    }

    private func bearerHeaders(token: String?) -> [String: String] {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return [:]
        }
        return ["Authorization": "Bearer \(token)"]
    }

    private func retrying<T>(
        _ label: String,
        attempts: Int = 12,
        delayNanoseconds: UInt64 = 1_000_000_000,
        operation: () async throws -> T,
        until predicate: (T) -> Bool
    ) async throws -> T {
        var lastValue: T?
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                let value = try await operation()
                if predicate(value) || attempt == attempts {
                    return value
                }
                lastValue = value
            } catch {
                lastError = error
                if attempt == attempts {
                    throw error
                }
            }
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let lastValue {
            return lastValue
        }
        throw lastError ?? DicomNetworkError.networkTimeout(label)
    }

    private func retrying<T>(
        _ label: String,
        attempts: Int = 12,
        delay: TimeInterval = 1,
        operation: () throws -> T,
        until predicate: (T) -> Bool
    ) throws -> T {
        var lastValue: T?
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                let value = try operation()
                if predicate(value) || attempt == attempts {
                    return value
                }
                lastValue = value
            } catch {
                lastError = error
                if attempt == attempts {
                    throw error
                }
            }
            Thread.sleep(forTimeInterval: delay)
        }
        if let lastValue {
            return lastValue
        }
        throw lastError ?? DicomNetworkError.networkTimeout(label)
    }
}
