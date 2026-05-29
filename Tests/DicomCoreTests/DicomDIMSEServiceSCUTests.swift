import Foundation
@testable import DicomCore
import XCTest

final class DicomDIMSEServiceSCUTests: XCTestCase {
    func testVerificationSCUSendsCEchoAndReportsSuccess() throws {
        let transport = DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
            DicomNetworkUID.verificationSOPClass
        ])
        let service = makeService()
        var progress: [DicomDIMSEProgress] = []

        let result = try service.verify(using: transport) { progress.append($0) }

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(transport.writtenCommands.map(\.commandField), [
            DicomDIMSECommandField.cEchoRQ
        ])
        XCTAssertTrue(progress.contains(.associationAccepted(operation: .verification)))
        XCTAssertTrue(progress.contains(.completed(operation: .verification, status: 0)))
    }

    func testFindSCUReceivesPendingIdentifierMatches() throws {
        let transport = DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
            DicomNetworkUID.studyRootQueryRetrieveFind
        ])
        let service = makeService()
        let query = DicomDataSet(elements: [
            element(0x0008_0052, .CS, "STUDY"),
            element(DicomTag.patientName.rawValue, .PN, "DOE^JANE")
        ])

        let result = try service.find(identifier: query, using: transport)

        XCTAssertEqual(result.operation.status, 0)
        XCTAssertEqual(result.matches.count, 1)
        XCTAssertEqual(result.matches[0].string(for: .patientName), "DOE^JANE")
        XCTAssertEqual(result.matches[0].string(for: .studyInstanceUID), "2.25.100")
        XCTAssertEqual(transport.writtenCommands.map(\.commandField), [
            DicomDIMSECommandField.cFindRQ
        ])
        XCTAssertEqual(transport.writtenDataSets.first?.string(for: .patientName), "DOE^JANE")
    }

    func testMoveSCUReportsPendingAndCompletedSuboperations() throws {
        let transport = DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
            DicomNetworkUID.studyRootQueryRetrieveMove
        ])
        let service = makeService()
        var progress: [DicomDIMSEProgress] = []

        let result = try service.move(
            identifier: retrieveIdentifier(),
            moveDestinationAETitle: "VIEWER",
            using: transport
        ) { progress.append($0) }

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.completedSuboperations, 2)
        XCTAssertTrue(progress.contains(.pending(operation: .moveRetrieve,
                                                remaining: 1,
                                                completed: 1,
                                                failed: 0,
                                                warning: 0)))
        XCTAssertEqual(transport.writtenCommands.first?.moveDestination, "VIEWER")
    }

    func testGetSCUReceivesStoreSuboperationAndAcknowledgesIt() throws {
        let transport = DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
            DicomNetworkUID.studyRootQueryRetrieveGet,
            DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID
        ])
        let service = makeService()

        let result = try service.get(identifier: retrieveIdentifier(), using: transport)

        XCTAssertEqual(result.operation.status, 0)
        XCTAssertEqual(result.operation.completedSuboperations, 1)
        XCTAssertEqual(result.retrievedInstances.count, 1)
        XCTAssertEqual(result.retrievedInstances[0].sopInstanceUID, "2.25.instance")
        XCTAssertEqual(result.retrievedInstances[0].dataSet?.string(for: .patientName), "DOE^JANE")
        XCTAssertTrue(transport.writtenCommands.contains {
            $0.commandField == DicomDIMSECommandField.cStoreRSP && $0.status == 0
        })
    }

    func testModalityWorklistSCUMapsScheduledProcedureSteps() throws {
        let transport = DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
            DicomNetworkUID.modalityWorklistInformationModelFind
        ])
        let service = makeService()
        let query = DicomModalityWorklistQuery(patientName: "DOE",
                                               modality: "CT",
                                               scheduledStationAETitle: "CTSCANNER")

        let result = try service.findModalityWorklist(query: query, using: transport)

        XCTAssertEqual(result.operation.status, 0)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].patientName, "DOE^JANE")
        XCTAssertEqual(result.items[0].modality, "CT")
        XCTAssertEqual(result.items[0].scheduledProcedureStepID, "SPS-1")
        XCTAssertEqual(transport.writtenCommands.first?.requestedSOPClassUID,
                       DicomNetworkUID.modalityWorklistInformationModelFind)
        let scheduledQuery = transport.writtenDataSets.first?
            .element(for: DicomWorkflowTag.scheduledProcedureStepSequence)?
            .sequenceItems.first?.dataSet
        XCTAssertEqual(scheduledQuery?.string(for: DicomWorkflowTag.modality), "CT")
    }

    func testMPPSCreateAndUpdateSendStatusDatasets() throws {
        let transport = DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
            DicomNetworkUID.modalityPerformedProcedureStepSOPClass
        ])
        let service = makeService()
        let item = DicomModalityWorklistItem(dataSet: worklistDataSet())
        let create = DicomMPPSCreateRequest(
            sopInstanceUID: "2.25.mpps",
            status: .inProgress,
            performedStationAETitle: "VIEWER",
            startDate: "20260529",
            startTime: "120000",
            worklistItem: item
        )

        let createResult = try service.createMPPS(create, using: transport)
        let updateResult = try service.updateMPPS(
            DicomMPPSUpdateRequest(sopInstanceUID: "2.25.mpps",
                                   status: .completed,
                                   endDate: "20260529",
                                   endTime: "121500"),
            using: transport
        )

        XCTAssertEqual(createResult.status, 0)
        XCTAssertEqual(updateResult.status, 0)
        XCTAssertEqual(transport.writtenCommands.map(\.commandField), [
            DicomDIMSECommandField.nCreateRQ,
            DicomDIMSECommandField.nSetRQ
        ])
        XCTAssertEqual(transport.writtenCommands[0].affectedSOPInstanceUID, "2.25.mpps")
        XCTAssertEqual(transport.writtenCommands[1].requestedSOPInstanceUID, "2.25.mpps")
        XCTAssertEqual(transport.writtenDataSets[0].string(for: DicomWorkflowTag.performedProcedureStepStatus),
                       DicomMPPSStatus.inProgress.rawValue)
        XCTAssertEqual(transport.writtenDataSets[1].string(for: DicomWorkflowTag.performedProcedureStepStatus),
                       DicomMPPSStatus.completed.rawValue)
        XCTAssertNotNil(transport.writtenDataSets[0].element(for: DicomWorkflowTag.scheduledStepAttributesSequence))
    }

    func testPrintManagementCreatesFilmSessionImageBoxAndPrints() throws {
        let transport = DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
            DicomNetworkUID.basicGrayscalePrintManagementMetaSOPClass
        ])
        let service = makeService()
        let bitmap = try DicomRenderedBitmap(width: 1,
                                             height: 1,
                                             rgbData: Data([0x10, 0x20, 0x30]))
        let job = try DicomPrintJob(renderedBitmap: bitmap,
                                    template: .singleImage(label: "PRINT-1"),
                                    id: "print-job")

        let result = try service.sendPrintJob(job, using: transport)

        XCTAssertEqual(result.operation.status, 0)
        XCTAssertEqual(result.imageBoxSOPInstanceUIDs, ["2.25.imagebox.1"])
        XCTAssertEqual(transport.writtenCommands.map(\.commandField), [
            DicomDIMSECommandField.nCreateRQ,
            DicomDIMSECommandField.nCreateRQ,
            DicomDIMSECommandField.nSetRQ,
            DicomDIMSECommandField.nActionRQ
        ])
        XCTAssertEqual(transport.writtenDataSets[0].string(for: DicomPrintTag.filmSessionLabel), "PRINT-1")
        XCTAssertEqual(transport.writtenCommands[3].requestedSOPInstanceUID, job.filmBoxSOPInstanceUID)
        XCTAssertEqual(transport.writtenCommands[3].actionTypeID, 1)

        let imageDataSet = transport.writtenDataSets[2]
            .sequenceItems(for: DicomPrintTag.basicGrayscaleImageSequence)
            .first?.dataSet
        XCTAssertEqual(imageDataSet?.int(for: .rows), 1)
        XCTAssertEqual(imageDataSet?.int(for: .columns), 1)
        XCTAssertEqual(imageDataSet?.int(for: .bitsAllocated), 8)
    }

    func testStoreSCUSendsDataSetAndReportsSuccess() throws {
        let storageUID = DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID
        let transport = DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [storageUID])
        let service = makeService()
        let dataSet = storageDataSet()

        let result = try service.store(dataSet: dataSet, using: transport)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(transport.writtenCommands.map(\.commandField), [
            DicomDIMSECommandField.cStoreRQ
        ])
        XCTAssertEqual(transport.writtenDataSets.first?.string(for: .sopInstanceUID), "2.25.instance")
        XCTAssertEqual(transport.writtenDataSets.first?.string(for: .patientName), "DOE^JANE")
    }

    func testAssociationTimeoutReachesCaller() throws {
        let service = makeService()
        let transport = TimeoutTransport()

        XCTAssertThrowsError(try service.verify(using: transport)) { error in
            XCTAssertEqual(error as? DicomNetworkError, .networkTimeout("association response"))
        }
    }

    func testAssociationUsesConfiguredUserIdentity() throws {
        let identity = DicomUserIdentity.usernameAndPasscode(
            "operator",
            passcode: "secret",
            positiveResponseRequested: true
        )
        let service = DicomDIMSEServiceSCU(configuration: makeConfiguration(
            tls: DicomTLSConfiguration(mode: .enabled, serverName: "archive.example"),
            userIdentity: identity
        ))
        let transport = DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
            DicomNetworkUID.verificationSOPClass
        ])

        _ = try service.verify(using: transport)

        XCTAssertEqual(transport.associationRequests.first?.userIdentity, identity)
    }

    func testUserIdentityWithoutTLSIsRejectedBeforeAssociationRequest() throws {
        let identity = DicomUserIdentity.usernameAndPasscode("operator", passcode: "secret")
        let service = makeService(userIdentity: identity)
        let transport = DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
            DicomNetworkUID.verificationSOPClass
        ])

        XCTAssertThrowsError(try service.verify(using: transport)) { error in
            XCTAssertEqual(error as? DicomNetworkError, .insecureUserIdentityTransport)
        }
        XCTAssertTrue(transport.associationRequests.isEmpty)
    }

    func testDefaultSCURejectsUserIdentityWithoutTLSBeforeOpeningTransport() throws {
        let identity = DicomUserIdentity.username("operator")
        var transportFactoryCalls = 0
        let service = DicomDIMSEServiceSCU(
            configuration: makeConfiguration(userIdentity: identity),
            transportFactory: {
                transportFactoryCalls += 1
                return DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
                    DicomNetworkUID.verificationSOPClass
                ])
            }
        )

        XCTAssertThrowsError(try service.verify()) { error in
            XCTAssertEqual(error as? DicomNetworkError, .insecureUserIdentityTransport)
        }
        XCTAssertEqual(transportFactoryCalls, 0)
    }

    func testDefaultSCURetriesAndAuditsFailuresWithoutPayloadData() throws {
        let auditLog = DicomInMemoryNetworkAuditLog()
        var attempt = 0
        let service = DicomDIMSEServiceSCU(
            configuration: makeConfiguration(retryPolicy: DicomNetworkRetryPolicy(maxAttempts: 2)),
            auditLogger: auditLog,
            transportFactory: {
                attempt += 1
                if attempt == 1 {
                    return FailingReadTransport(error: DicomNetworkError.malformedCommandSet("DOE^JANE"))
                }
                return DIMSEScriptedTransport(supportedAbstractSyntaxUIDs: [
                    DicomNetworkUID.verificationSOPClass
                ])
            }
        )

        let result = try service.verify()

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(attempt, 2)
        XCTAssertEqual(auditLog.events.map(\.outcome), [
            .started,
            .retrying,
            .started,
            .succeeded
        ])
        XCTAssertFalse(auditLog.events.compactMap(\.errorDescription).contains { $0.contains("DOE") })
    }

    func testCircuitBreakerBlocksAfterFailureThreshold() throws {
        let auditLog = DicomInMemoryNetworkAuditLog()
        let breaker = DicomNetworkCircuitBreaker(policy: DicomCircuitBreakerPolicy(
            failureThreshold: 1,
            resetInterval: 60
        ))
        let service = DicomDIMSEServiceSCU(
            configuration: makeConfiguration(),
            auditLogger: auditLog,
            circuitBreaker: breaker,
            transportFactory: {
                FailingReadTransport(error: DicomNetworkError.networkTimeout("association response"))
            }
        )

        XCTAssertThrowsError(try service.verify()) { error in
            XCTAssertEqual(error as? DicomNetworkError, .networkTimeout("association response"))
        }
        XCTAssertThrowsError(try service.verify()) { error in
            XCTAssertEqual(error as? DicomNetworkError, .circuitBreakerOpen("C-ECHO"))
        }
        XCTAssertEqual(auditLog.events.map(\.outcome), [
            .started,
            .failed,
            .blocked
        ])
    }

    func testBandwidthLimitedTransportForwardsReadsAndWrites() throws {
        let raw = RecordingTransport(responses: [Data([0x01, 0x02])])
        let limited = DicomBandwidthLimitedTransport(wrapping: raw, bytesPerSecond: Int.max)
        let payload = Data([0x03, 0x04, 0x05])

        try limited.writePDU(payload)
        let read = try limited.readPDU()

        XCTAssertEqual(raw.writtenPDUs, [payload])
        XCTAssertEqual(read, Data([0x01, 0x02]))
    }
}

private func makeService(userIdentity: DicomUserIdentity? = nil) -> DicomDIMSEServiceSCU {
    DicomDIMSEServiceSCU(configuration: makeConfiguration(userIdentity: userIdentity))
}

private func makeConfiguration(tls: DicomTLSConfiguration = .disabled,
                               userIdentity: DicomUserIdentity? = nil,
                               retryPolicy: DicomNetworkRetryPolicy = .disabled) -> DicomDIMSEConnectionConfiguration {
    DicomDIMSEConnectionConfiguration(
        host: "127.0.0.1",
        port: 104,
        calledAETitle: "ARCHIVE",
        callingAETitle: "VIEWER",
        transferSyntaxes: [.explicitVRLittleEndian],
        tls: tls,
        userIdentity: userIdentity,
        retryPolicy: retryPolicy
    )
}

private func retrieveIdentifier() -> DicomDataSet {
    DicomDataSet(elements: [
        element(0x0008_0052, .CS, "SERIES"),
        element(DicomTag.studyInstanceUID.rawValue, .UI, "2.25.100"),
        element(DicomTag.seriesInstanceUID.rawValue, .UI, "2.25.200")
    ])
}

private func storageDataSet() -> DicomDataSet {
    DicomDataSet(elements: [
        element(DicomTag.sopClassUID.rawValue, .UI, DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID),
        element(DicomTag.sopInstanceUID.rawValue, .UI, "2.25.instance"),
        element(DicomTag.patientName.rawValue, .PN, "DOE^JANE"),
        element(DicomTag.studyInstanceUID.rawValue, .UI, "2.25.100"),
        element(DicomTag.seriesInstanceUID.rawValue, .UI, "2.25.200"),
        DicomDataElement(tag: DicomTag.samplesPerPixel.rawValue, vr: .US, value: .unsignedIntegers([1])),
        element(DicomTag.photometricInterpretation.rawValue, .CS, "MONOCHROME2"),
        DicomDataElement(tag: DicomTag.rows.rawValue, vr: .US, value: .unsignedIntegers([1])),
        DicomDataElement(tag: DicomTag.columns.rawValue, vr: .US, value: .unsignedIntegers([1])),
        DicomDataElement(tag: DicomTag.bitsAllocated.rawValue, vr: .US, value: .unsignedIntegers([8])),
        DicomDataElement(tag: DicomTag.bitsStored.rawValue, vr: .US, value: .unsignedIntegers([8])),
        DicomDataElement(tag: DicomTag.highBit.rawValue, vr: .US, value: .unsignedIntegers([7])),
        DicomDataElement(tag: DicomTag.pixelRepresentation.rawValue, vr: .US, value: .unsignedIntegers([0])),
        DicomDataElement(tag: DicomTag.pixelData.rawValue, vr: .OB, value: .bytes(Data([0x7F])))
    ])
}

private func worklistDataSet() -> DicomDataSet {
    DicomDataSet(elements: [
        element(DicomTag.patientName.rawValue, .PN, "DOE^JANE"),
        element(DicomTag.patientID.rawValue, .LO, "P-1"),
        element(DicomWorkflowTag.accessionNumber, .SH, "ACC-1"),
        element(DicomWorkflowTag.requestedProcedureID, .SH, "RP-1"),
        element(DicomWorkflowTag.requestedProcedureDescription, .LO, "CT CHEST"),
        DicomDataElement(tag: DicomWorkflowTag.scheduledProcedureStepSequence,
                         vr: .SQ,
                         value: .sequence([
                            DicomSequenceItem(dataSet: DicomDataSet(elements: [
                                element(DicomWorkflowTag.scheduledStationAETitle, .AE, "CTSCANNER"),
                                element(DicomWorkflowTag.modality, .CS, "CT"),
                                element(DicomWorkflowTag.scheduledProcedureStepStartDate, .DA, "20260529"),
                                element(DicomWorkflowTag.scheduledProcedureStepStartTime, .TM, "120000"),
                                element(DicomWorkflowTag.scheduledProcedureStepDescription, .LO, "CHEST ROUTINE"),
                                element(DicomWorkflowTag.scheduledProcedureStepID, .SH, "SPS-1")
                            ]))
                         ]))
    ])
}

private func printFilmBoxResponseDataSet() -> DicomDataSet {
    DicomDataSet(elements: [
        DicomDataElement(tag: DicomPrintTag.referencedImageBoxSequence,
                         vr: .SQ,
                         value: .sequence([
                            DicomSequenceItem(dataSet: DicomDataSet(elements: [
                                element(DicomTag.referencedSOPClassUID.rawValue,
                                        .UI,
                                        DicomNetworkUID.basicGrayscaleImageBoxSOPClass),
                                element(DicomTag.referencedSOPInstanceUID.rawValue,
                                        .UI,
                                        "2.25.imagebox.1")
                            ]))
                         ]))
    ])
}

private func element(_ tag: Int, _ vr: DicomVR, _ value: String) -> DicomDataElement {
    DicomDataElement(tag: tag, vr: vr, value: .strings([value]))
}

private final class DIMSEScriptedTransport: DicomAssociationTransport {
    private let supportedAbstractSyntaxUIDs: Set<String>
    private var responses: [Data] = []
    private var acceptedContextsByID: [UInt8: DicomAcceptedPresentationContext] = [:]
    private var lastRequestCommand: DicomDIMSECommandSet?

    private(set) var associationRequests: [DicomAssociationRequest] = []
    private(set) var writtenCommands: [DicomDIMSECommandSet] = []
    private(set) var writtenDataSets: [DicomDataSet] = []

    init(supportedAbstractSyntaxUIDs: Set<String>) {
        self.supportedAbstractSyntaxUIDs = supportedAbstractSyntaxUIDs
    }

    func writePDU(_ data: Data) throws {
        switch try DicomPDUCodec.decode(data) {
        case .associationRequest(let request):
            associationRequests.append(request)
            let accept = DicomAssociationNegotiator.accept(
                request,
                supportedAbstractSyntaxUIDs: supportedAbstractSyntaxUIDs,
                preferredTransferSyntaxes: [.explicitVRLittleEndian]
            )
            acceptedContextsByID = accept.presentationContexts.reduce(into: [:]) { partial, accepted in
                guard accepted.result == .acceptance,
                      let requested = request.presentationContexts.first(where: { $0.id == accepted.id }),
                      let transferSyntaxUID = accepted.transferSyntaxUID else {
                    return
                }
                partial[accepted.id] = DicomAcceptedPresentationContext(
                    id: accepted.id,
                    abstractSyntaxUID: requested.abstractSyntaxUID,
                    transferSyntaxUID: transferSyntaxUID
                )
            }
            responses.append(try DicomPDUCodec.encode(.associationAccept(accept)))
        case .pData(let pdvs):
            try handlePData(pdvs)
        case .releaseRequest:
            responses.append(try DicomPDUCodec.encode(.releaseResponse))
        default:
            break
        }
    }

    func readPDU() throws -> Data {
        guard !responses.isEmpty else {
            throw DicomNetworkError.invalidPDULength(expected: 1, actual: 0)
        }
        return responses.removeFirst()
    }

    private func handlePData(_ pdvs: [DicomPDV]) throws {
        for pdv in pdvs {
            if pdv.isCommand {
                let command = try DicomDIMSECommandSet.decode(pdv.data)
                writtenCommands.append(command)
                lastRequestCommand = command
                try handleCommand(command, presentationContextID: pdv.presentationContextID)
            } else {
                let transferSyntax = acceptedContextsByID[pdv.presentationContextID]?.transferSyntax ?? .explicitVRLittleEndian
                let dataSet = try DicomDataSetParser.dataSet(from: pdv.data, transferSyntax: transferSyntax)
                writtenDataSets.append(dataSet)
                try handleDataSetAfterCommand(presentationContextID: pdv.presentationContextID)
            }
        }
    }

    private func handleCommand(_ command: DicomDIMSECommandSet,
                               presentationContextID: UInt8) throws {
        switch command.commandField {
        case DicomDIMSECommandField.cEchoRQ:
            try enqueueCommand(DicomDIMSECommandSet(
                affectedSOPClassUID: DicomNetworkUID.verificationSOPClass,
                commandField: DicomDIMSECommandField.cEchoRSP,
                messageIDBeingRespondedTo: command.messageID,
                commandDataSetType: DicomDIMSECommandDataSetType.noDataSet,
                status: 0
            ), contextID: presentationContextID)
        case DicomDIMSECommandField.cStoreRQ:
            break
        case DicomDIMSECommandField.nActionRQ:
            try enqueueCommand(DicomDIMSECommandSet(
                requestedSOPClassUID: command.requestedSOPClassUID,
                commandField: DicomDIMSECommandField.nActionRSP,
                messageIDBeingRespondedTo: command.messageID,
                commandDataSetType: DicomDIMSECommandDataSetType.noDataSet,
                status: 0,
                requestedSOPInstanceUID: command.requestedSOPInstanceUID,
                actionTypeID: command.actionTypeID
            ), contextID: presentationContextID)
        default:
            break
        }
    }

    private func handleDataSetAfterCommand(presentationContextID: UInt8) throws {
        guard let command = lastRequestCommand else { return }
        switch command.commandField {
        case DicomDIMSECommandField.cFindRQ:
            let requestedSOPClassUID = command.requestedSOPClassUID ?? DicomNetworkUID.studyRootQueryRetrieveFind
            try enqueueCommand(DicomDIMSECommandSet(
                requestedSOPClassUID: requestedSOPClassUID,
                commandField: DicomDIMSECommandField.cFindRSP,
                messageIDBeingRespondedTo: command.messageID,
                commandDataSetType: DicomDIMSECommandDataSetType.hasDataSet,
                status: 0xFF00
            ), contextID: presentationContextID)
            if requestedSOPClassUID == DicomNetworkUID.modalityWorklistInformationModelFind {
                try enqueueDataSet(worklistDataSet(), contextID: presentationContextID)
            } else {
                try enqueueDataSet(DicomDataSet(elements: [
                    element(DicomTag.patientName.rawValue, .PN, "DOE^JANE"),
                    element(DicomTag.studyInstanceUID.rawValue, .UI, "2.25.100")
                ]), contextID: presentationContextID)
            }
            try enqueueCommand(DicomDIMSECommandSet(
                requestedSOPClassUID: requestedSOPClassUID,
                commandField: DicomDIMSECommandField.cFindRSP,
                messageIDBeingRespondedTo: command.messageID,
                commandDataSetType: DicomDIMSECommandDataSetType.noDataSet,
                status: 0
            ), contextID: presentationContextID)
        case DicomDIMSECommandField.cMoveRQ:
            try enqueueCommand(DicomDIMSECommandSet(
                requestedSOPClassUID: DicomNetworkUID.studyRootQueryRetrieveMove,
                commandField: DicomDIMSECommandField.cMoveRSP,
                messageIDBeingRespondedTo: command.messageID,
                commandDataSetType: DicomDIMSECommandDataSetType.noDataSet,
                status: 0xFF00,
                remainingSuboperations: 1,
                completedSuboperations: 1,
                failedSuboperations: 0,
                warningSuboperations: 0
            ), contextID: presentationContextID)
            try enqueueCommand(DicomDIMSECommandSet(
                requestedSOPClassUID: DicomNetworkUID.studyRootQueryRetrieveMove,
                commandField: DicomDIMSECommandField.cMoveRSP,
                messageIDBeingRespondedTo: command.messageID,
                commandDataSetType: DicomDIMSECommandDataSetType.noDataSet,
                status: 0,
                remainingSuboperations: 0,
                completedSuboperations: 2,
                failedSuboperations: 0,
                warningSuboperations: 0
            ), contextID: presentationContextID)
        case DicomDIMSECommandField.cGetRQ:
            try enqueueCommand(DicomDIMSECommandSet(
                affectedSOPClassUID: DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID,
                commandField: DicomDIMSECommandField.cStoreRQ,
                messageID: 33,
                commandDataSetType: DicomDIMSECommandDataSetType.hasDataSet,
                affectedSOPInstanceUID: "2.25.instance"
            ), contextID: 3)
            try enqueueDataSet(storageDataSet(), contextID: 3)
            try enqueueCommand(DicomDIMSECommandSet(
                requestedSOPClassUID: DicomNetworkUID.studyRootQueryRetrieveGet,
                commandField: DicomDIMSECommandField.cGetRSP,
                messageIDBeingRespondedTo: command.messageID,
                commandDataSetType: DicomDIMSECommandDataSetType.noDataSet,
                status: 0,
                remainingSuboperations: 0,
                completedSuboperations: 1,
                failedSuboperations: 0,
                warningSuboperations: 0
            ), contextID: presentationContextID)
        case DicomDIMSECommandField.cStoreRQ:
            try enqueueCommand(DicomDIMSECommandSet(
                affectedSOPClassUID: command.affectedSOPClassUID,
                commandField: DicomDIMSECommandField.cStoreRSP,
                messageIDBeingRespondedTo: command.messageID,
                commandDataSetType: DicomDIMSECommandDataSetType.noDataSet,
                status: 0,
                affectedSOPInstanceUID: command.affectedSOPInstanceUID
            ), contextID: presentationContextID)
        case DicomDIMSECommandField.nCreateRQ:
            let hasFilmBoxDataSet = command.affectedSOPClassUID == DicomNetworkUID.basicFilmBoxSOPClass
            try enqueueCommand(DicomDIMSECommandSet(
                affectedSOPClassUID: command.affectedSOPClassUID,
                commandField: DicomDIMSECommandField.nCreateRSP,
                messageIDBeingRespondedTo: command.messageID,
                commandDataSetType: hasFilmBoxDataSet
                    ? DicomDIMSECommandDataSetType.hasDataSet
                    : DicomDIMSECommandDataSetType.noDataSet,
                status: 0,
                affectedSOPInstanceUID: command.affectedSOPInstanceUID
            ), contextID: presentationContextID)
            if hasFilmBoxDataSet {
                try enqueueDataSet(printFilmBoxResponseDataSet(), contextID: presentationContextID)
            }
        case DicomDIMSECommandField.nSetRQ:
            try enqueueCommand(DicomDIMSECommandSet(
                requestedSOPClassUID: command.requestedSOPClassUID,
                commandField: DicomDIMSECommandField.nSetRSP,
                messageIDBeingRespondedTo: command.messageID,
                commandDataSetType: DicomDIMSECommandDataSetType.noDataSet,
                status: 0,
                requestedSOPInstanceUID: command.requestedSOPInstanceUID
            ), contextID: presentationContextID)
        default:
            break
        }
    }

    private func enqueueCommand(_ command: DicomDIMSECommandSet, contextID: UInt8) throws {
        responses.append(try DicomPDUCodec.encode(.pData([
            DicomPDV(presentationContextID: contextID,
                    isCommand: true,
                    isLastFragment: true,
                    data: try command.encoded())
        ])))
    }

    private func enqueueDataSet(_ dataSet: DicomDataSet, contextID: UInt8) throws {
        responses.append(try DicomPDUCodec.encode(.pData([
            DicomPDV(presentationContextID: contextID,
                    isCommand: false,
                    isLastFragment: true,
                    data: try DicomDataSetWriter.dataSetData(from: dataSet,
                                                             transferSyntax: .explicitVRLittleEndian))
        ])))
    }
}

private final class TimeoutTransport: DicomAssociationTransport {
    func writePDU(_ data: Data) throws {}

    func readPDU() throws -> Data {
        throw DicomNetworkError.networkTimeout("association response")
    }
}

private final class FailingReadTransport: DicomAssociationTransport {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func writePDU(_ data: Data) throws {}

    func readPDU() throws -> Data {
        throw error
    }
}

private final class RecordingTransport: DicomAssociationTransport {
    private var responses: [Data]
    private(set) var writtenPDUs: [Data] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func writePDU(_ data: Data) throws {
        writtenPDUs.append(data)
    }

    func readPDU() throws -> Data {
        guard !responses.isEmpty else {
            throw DicomNetworkError.invalidPDULength(expected: 1, actual: 0)
        }
        return responses.removeFirst()
    }
}
