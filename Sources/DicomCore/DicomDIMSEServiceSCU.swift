import Foundation
#if canImport(Network)
import Network
#if canImport(Security)
import Security
#endif
#endif

public struct DicomDIMSEConnectionConfiguration: Equatable, Sendable {
    public var host: String
    public var port: UInt16
    public var calledAETitle: String
    public var callingAETitle: String
    public var timeout: TimeInterval
    public var maximumPDULength: UInt32
    public var transferSyntaxes: [DicomTransferSyntax]
    public var tls: DicomTLSConfiguration
    public var userIdentity: DicomUserIdentity?
    public var retryPolicy: DicomNetworkRetryPolicy
    public var circuitBreakerPolicy: DicomCircuitBreakerPolicy?
    public var bandwidthLimitBytesPerSecond: Int?

    public init(host: String,
                port: UInt16,
                calledAETitle: String,
                callingAETitle: String,
                timeout: TimeInterval = 10,
                maximumPDULength: UInt32 = 16_384,
                transferSyntaxes: [DicomTransferSyntax] = [.explicitVRLittleEndian, .implicitVRLittleEndian],
                tls: DicomTLSConfiguration = .disabled,
                userIdentity: DicomUserIdentity? = nil,
                retryPolicy: DicomNetworkRetryPolicy = .disabled,
                circuitBreakerPolicy: DicomCircuitBreakerPolicy? = nil,
                bandwidthLimitBytesPerSecond: Int? = nil) {
        self.host = host
        self.port = port
        self.calledAETitle = calledAETitle
        self.callingAETitle = callingAETitle
        self.timeout = timeout
        self.maximumPDULength = maximumPDULength
        self.transferSyntaxes = transferSyntaxes
        self.tls = tls
        self.userIdentity = userIdentity
        self.retryPolicy = retryPolicy
        self.circuitBreakerPolicy = circuitBreakerPolicy
        self.bandwidthLimitBytesPerSecond = bandwidthLimitBytesPerSecond
    }
}

public enum DicomDIMSEOperation: String, Codable, Equatable, Sendable {
    case verification = "C-ECHO"
    case query = "C-FIND"
    case modalityWorklist = "MWL C-FIND"
    case moveRetrieve = "C-MOVE"
    case getRetrieve = "C-GET"
    case store = "C-STORE"
    case mppsCreate = "MPPS N-CREATE"
    case mppsUpdate = "MPPS N-SET"
    case printManagement = "Print Management"
}

public enum DicomDIMSEProgress: Equatable, Sendable {
    case associationRequested(operation: DicomDIMSEOperation, calledAETitle: String)
    case associationAccepted(operation: DicomDIMSEOperation)
    case requestSent(operation: DicomDIMSEOperation, messageID: UInt16)
    case pending(operation: DicomDIMSEOperation,
                 remaining: UInt16?,
                 completed: UInt16?,
                 failed: UInt16?,
                 warning: UInt16?)
    case storeReceived(sopInstanceUID: String?)
    case completed(operation: DicomDIMSEOperation, status: UInt16)
    case released(operation: DicomDIMSEOperation)
}

public struct DicomDIMSEOperationResult: Equatable, Sendable {
    public var status: UInt16
    public var remainingSuboperations: UInt16?
    public var completedSuboperations: UInt16?
    public var failedSuboperations: UInt16?
    public var warningSuboperations: UInt16?

    public init(status: UInt16,
                remainingSuboperations: UInt16? = nil,
                completedSuboperations: UInt16? = nil,
                failedSuboperations: UInt16? = nil,
                warningSuboperations: UInt16? = nil) {
        self.status = status
        self.remainingSuboperations = remainingSuboperations
        self.completedSuboperations = completedSuboperations
        self.failedSuboperations = failedSuboperations
        self.warningSuboperations = warningSuboperations
    }
}

public struct DicomCFindResult: Equatable, Sendable {
    public var operation: DicomDIMSEOperationResult
    public var matches: [DicomDataSet]

    public init(operation: DicomDIMSEOperationResult, matches: [DicomDataSet]) {
        self.operation = operation
        self.matches = matches
    }
}

public struct DicomRetrievedInstance: Equatable, Sendable {
    public var sopClassUID: String?
    public var sopInstanceUID: String?
    public var transferSyntax: DicomTransferSyntax
    public var data: Data
    public var dataSet: DicomDataSet?

    public init(sopClassUID: String?,
                sopInstanceUID: String?,
                transferSyntax: DicomTransferSyntax,
                data: Data,
                dataSet: DicomDataSet?) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.transferSyntax = transferSyntax
        self.data = data
        self.dataSet = dataSet
    }
}

public struct DicomCGetResult: Equatable, Sendable {
    public var operation: DicomDIMSEOperationResult
    public var retrievedInstances: [DicomRetrievedInstance]

    public init(operation: DicomDIMSEOperationResult,
                retrievedInstances: [DicomRetrievedInstance]) {
        self.operation = operation
        self.retrievedInstances = retrievedInstances
    }
}

public struct DicomDIMSEServiceSCU {
    public var configuration: DicomDIMSEConnectionConfiguration
    public var auditLogger: DicomNetworkAuditLogging?
    private let circuitBreaker: DicomNetworkCircuitBreaker?
    private let transportFactory: (() throws -> DicomAssociationTransport)?

    public init(configuration: DicomDIMSEConnectionConfiguration,
                auditLogger: DicomNetworkAuditLogging? = nil,
                circuitBreaker: DicomNetworkCircuitBreaker? = nil) {
        self.init(configuration: configuration,
                  auditLogger: auditLogger,
                  circuitBreaker: circuitBreaker,
                  transportFactory: nil)
    }

    init(configuration: DicomDIMSEConnectionConfiguration,
         auditLogger: DicomNetworkAuditLogging? = nil,
         circuitBreaker: DicomNetworkCircuitBreaker? = nil,
         transportFactory: (() throws -> DicomAssociationTransport)?) {
        self.configuration = configuration
        self.auditLogger = auditLogger
        self.transportFactory = transportFactory
        if let circuitBreaker {
            self.circuitBreaker = circuitBreaker
        } else if let policy = configuration.circuitBreakerPolicy {
            self.circuitBreaker = DicomNetworkCircuitBreaker(policy: policy)
        } else {
            self.circuitBreaker = nil
        }
    }

    public func verify(progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomDIMSEOperationResult {
        try performWithResilience(operation: .verification, progress: progress) { transport in
            try verify(using: transport, progress: progress)
        }
    }

    public func verify(using transport: DicomAssociationTransport,
                       progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomDIMSEOperationResult {
        let operation = DicomDIMSEOperation.verification
        let association = try openAssociation(
            for: operation,
            abstractSyntaxUIDs: [DicomNetworkUID.verificationSOPClass],
            using: transport,
            progress: progress
        )
        defer { try? release(operation: operation, using: transport, progress: progress) }

        let context = try acceptedContext(DicomNetworkUID.verificationSOPClass, in: association)
        let messageID: UInt16 = 1
        let command = DicomDIMSECommandSet(
            affectedSOPClassUID: DicomNetworkUID.verificationSOPClass,
            commandField: DicomDIMSECommandField.cEchoRQ,
            messageID: messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.noDataSet
        )
        try sendCommand(command,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        progress?(.requestSent(operation: operation, messageID: messageID))

        let reader = DicomDIMSEMessageReader()
        let response = try readCommand(using: transport, reader: reader)
        try expect(response, commandField: DicomDIMSECommandField.cEchoRSP)
        try validateSuccessStatus(response)
        let result = operationResult(from: response)
        progress?(.completed(operation: operation, status: result.status))
        return result
    }

    public func find(identifier: DicomDataSet,
                     queryModelUID: String = DicomNetworkUID.studyRootQueryRetrieveFind,
                     progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomCFindResult {
        try performWithResilience(operation: .query, progress: progress) { transport in
            try find(identifier: identifier,
                     queryModelUID: queryModelUID,
                     operation: .query,
                     using: transport,
                     progress: progress)
        }
    }

    public func find(identifier: DicomDataSet,
                     queryModelUID: String = DicomNetworkUID.studyRootQueryRetrieveFind,
                     using transport: DicomAssociationTransport,
                     progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomCFindResult {
        try find(identifier: identifier,
                 queryModelUID: queryModelUID,
                 operation: .query,
                 using: transport,
                 progress: progress)
    }

    func find(identifier: DicomDataSet,
              queryModelUID: String,
              operation: DicomDIMSEOperation,
              using transport: DicomAssociationTransport,
              progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomCFindResult {
        let association = try openAssociation(
            for: operation,
            abstractSyntaxUIDs: [queryModelUID],
            using: transport,
            progress: progress
        )
        defer { try? release(operation: operation, using: transport, progress: progress) }

        let context = try acceptedContext(queryModelUID, in: association)
        let transferSyntax = context.transferSyntax ?? .explicitVRLittleEndian
        let messageID: UInt16 = 1
        let command = DicomDIMSECommandSet(
            requestedSOPClassUID: queryModelUID,
            commandField: DicomDIMSECommandField.cFindRQ,
            messageID: messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.hasDataSet,
            priority: 0
        )
        try sendCommand(command,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        try sendDataSet(identifier,
                        transferSyntax: transferSyntax,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        progress?(.requestSent(operation: operation, messageID: messageID))

        let reader = DicomDIMSEMessageReader()
        var matches: [DicomDataSet] = []
        while true {
            let response = try readCommand(using: transport, reader: reader)
            try expect(response, commandField: DicomDIMSECommandField.cFindRSP)
            let status = response.status ?? 0
            if isPending(status) {
                if response.commandDataSetType != DicomDIMSECommandDataSetType.noDataSet {
                    let payload = try reader.readMessage(from: transport)
                    guard !payload.isCommand else {
                        throw DicomNetworkError.malformedCommandSet("Expected C-FIND identifier dataset.")
                    }
                    matches.append(try DicomDataSetParser.dataSet(from: payload.data,
                                                                  transferSyntax: transferSyntax))
                }
                progressPending(operation: operation, response: response, progress: progress)
                continue
            }
            try validateSuccessStatus(response)
            let result = operationResult(from: response)
            progress?(.completed(operation: operation, status: result.status))
            return DicomCFindResult(operation: result, matches: matches)
        }
    }

    public func findModalityWorklist(query: DicomModalityWorklistQuery,
                                     progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomModalityWorklistResult {
        let result = try performWithResilience(operation: .modalityWorklist, progress: progress) { transport in
            try find(identifier: query.identifier,
                     queryModelUID: DicomNetworkUID.modalityWorklistInformationModelFind,
                     operation: .modalityWorklist,
                     using: transport,
                     progress: progress)
        }
        return DicomModalityWorklistResult(
            operation: result.operation,
            items: result.matches.map(DicomModalityWorklistItem.init(dataSet:))
        )
    }

    public func findModalityWorklist(query: DicomModalityWorklistQuery,
                                     using transport: DicomAssociationTransport,
                                     progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomModalityWorklistResult {
        let result = try find(identifier: query.identifier,
                              queryModelUID: DicomNetworkUID.modalityWorklistInformationModelFind,
                              operation: .modalityWorklist,
                              using: transport,
                              progress: progress)
        return DicomModalityWorklistResult(
            operation: result.operation,
            items: result.matches.map(DicomModalityWorklistItem.init(dataSet:))
        )
    }

    public func move(identifier: DicomDataSet,
                     moveDestinationAETitle: String,
                     queryModelUID: String = DicomNetworkUID.studyRootQueryRetrieveMove,
                     progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomDIMSEOperationResult {
        try performWithResilience(operation: .moveRetrieve, progress: progress) { transport in
            try move(identifier: identifier,
                     moveDestinationAETitle: moveDestinationAETitle,
                     queryModelUID: queryModelUID,
                     using: transport,
                     progress: progress)
        }
    }

    public func move(identifier: DicomDataSet,
                     moveDestinationAETitle: String,
                     queryModelUID: String = DicomNetworkUID.studyRootQueryRetrieveMove,
                     using transport: DicomAssociationTransport,
                     progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomDIMSEOperationResult {
        let operation = DicomDIMSEOperation.moveRetrieve
        let association = try openAssociation(
            for: operation,
            abstractSyntaxUIDs: [queryModelUID],
            using: transport,
            progress: progress
        )
        defer { try? release(operation: operation, using: transport, progress: progress) }

        let context = try acceptedContext(queryModelUID, in: association)
        let transferSyntax = context.transferSyntax ?? .explicitVRLittleEndian
        let messageID: UInt16 = 1
        let command = DicomDIMSECommandSet(
            requestedSOPClassUID: queryModelUID,
            commandField: DicomDIMSECommandField.cMoveRQ,
            messageID: messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.hasDataSet,
            moveDestination: moveDestinationAETitle,
            priority: 0
        )
        try sendCommand(command,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        try sendDataSet(identifier,
                        transferSyntax: transferSyntax,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        progress?(.requestSent(operation: operation, messageID: messageID))

        let reader = DicomDIMSEMessageReader()
        while true {
            let response = try readCommand(using: transport, reader: reader)
            try expect(response, commandField: DicomDIMSECommandField.cMoveRSP)
            let status = response.status ?? 0
            if isPending(status) {
                progressPending(operation: operation, response: response, progress: progress)
                continue
            }
            try validateSuccessStatus(response)
            let result = operationResult(from: response)
            progress?(.completed(operation: operation, status: result.status))
            return result
        }
    }

    public func get(identifier: DicomDataSet,
                    storageSOPClassUIDs: [String] = [DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID],
                    queryModelUID: String = DicomNetworkUID.studyRootQueryRetrieveGet,
                    progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomCGetResult {
        try performWithResilience(operation: .getRetrieve, progress: progress) { transport in
            try get(identifier: identifier,
                    storageSOPClassUIDs: storageSOPClassUIDs,
                    queryModelUID: queryModelUID,
                    using: transport,
                    progress: progress)
        }
    }

    public func get(identifier: DicomDataSet,
                    storageSOPClassUIDs: [String] = [DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID],
                    queryModelUID: String = DicomNetworkUID.studyRootQueryRetrieveGet,
                    using transport: DicomAssociationTransport,
                    progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomCGetResult {
        let operation = DicomDIMSEOperation.getRetrieve
        let association = try openAssociation(
            for: operation,
            abstractSyntaxUIDs: [queryModelUID] + storageSOPClassUIDs,
            using: transport,
            progress: progress
        )
        defer { try? release(operation: operation, using: transport, progress: progress) }

        let context = try acceptedContext(queryModelUID, in: association)
        let transferSyntax = context.transferSyntax ?? .explicitVRLittleEndian
        let messageID: UInt16 = 1
        let command = DicomDIMSECommandSet(
            requestedSOPClassUID: queryModelUID,
            commandField: DicomDIMSECommandField.cGetRQ,
            messageID: messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.hasDataSet,
            priority: 0
        )
        try sendCommand(command,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        try sendDataSet(identifier,
                        transferSyntax: transferSyntax,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        progress?(.requestSent(operation: operation, messageID: messageID))

        let reader = DicomDIMSEMessageReader()
        var retrieved: [DicomRetrievedInstance] = []
        while true {
            let response = try readCommand(using: transport, reader: reader)
            switch response.commandField {
            case DicomDIMSECommandField.cStoreRQ:
                let stored = try receiveStoreRequest(response,
                                                     association: association,
                                                     transport: transport,
                                                     reader: reader)
                retrieved.append(stored)
                progress?(.storeReceived(sopInstanceUID: stored.sopInstanceUID))
            case DicomDIMSECommandField.cGetRSP:
                let status = response.status ?? 0
                if isPending(status) {
                    progressPending(operation: operation, response: response, progress: progress)
                    continue
                }
                try validateSuccessStatus(response)
                let result = operationResult(from: response)
                progress?(.completed(operation: operation, status: result.status))
                return DicomCGetResult(operation: result, retrievedInstances: retrieved)
            default:
                throw DicomNetworkError.unexpectedDIMSECommand(expected: DicomDIMSECommandField.cGetRSP,
                                                               actual: response.commandField)
            }
        }
    }

    public func store(dataSet: DicomDataSet,
                      sopClassUID: String? = nil,
                      sopInstanceUID: String? = nil,
                      progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomDIMSEOperationResult {
        try performWithResilience(operation: .store, progress: progress) { transport in
            try store(dataSet: dataSet,
                      sopClassUID: sopClassUID,
                      sopInstanceUID: sopInstanceUID,
                      using: transport,
                      progress: progress)
        }
    }

    public func store(dataSet: DicomDataSet,
                      sopClassUID: String? = nil,
                      sopInstanceUID: String? = nil,
                      using transport: DicomAssociationTransport,
                      progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomDIMSEOperationResult {
        let operation = DicomDIMSEOperation.store
        let storage = storageDataSet(dataSet,
                                     sopClassUID: sopClassUID,
                                     sopInstanceUID: sopInstanceUID)
        let association = try openAssociation(
            for: operation,
            abstractSyntaxUIDs: [storage.sopClassUID],
            using: transport,
            progress: progress
        )
        defer { try? release(operation: operation, using: transport, progress: progress) }

        let context = try acceptedContext(storage.sopClassUID, in: association)
        let transferSyntax = context.transferSyntax ?? .explicitVRLittleEndian
        let messageID: UInt16 = 1
        let command = DicomDIMSECommandSet(
            affectedSOPClassUID: storage.sopClassUID,
            commandField: DicomDIMSECommandField.cStoreRQ,
            messageID: messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.hasDataSet,
            priority: 0,
            affectedSOPInstanceUID: storage.sopInstanceUID
        )
        try sendCommand(command,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        try sendDataSet(storage.dataSet,
                        transferSyntax: transferSyntax,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        progress?(.requestSent(operation: operation, messageID: messageID))

        let reader = DicomDIMSEMessageReader()
        let response = try readCommand(using: transport, reader: reader)
        try expect(response, commandField: DicomDIMSECommandField.cStoreRSP)
        try validateSuccessStatus(response)
        let result = operationResult(from: response)
        progress?(.completed(operation: operation, status: result.status))
        return result
    }

    public func createMPPS(_ request: DicomMPPSCreateRequest,
                           progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomDIMSEOperationResult {
        try performWithResilience(operation: .mppsCreate, progress: progress) { transport in
            try createMPPS(request, using: transport, progress: progress)
        }
    }

    public func createMPPS(_ request: DicomMPPSCreateRequest,
                           using transport: DicomAssociationTransport,
                           progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomDIMSEOperationResult {
        let operation = DicomDIMSEOperation.mppsCreate
        let association = try openAssociation(
            for: operation,
            abstractSyntaxUIDs: [DicomNetworkUID.modalityPerformedProcedureStepSOPClass],
            using: transport,
            progress: progress
        )
        defer { try? release(operation: operation, using: transport, progress: progress) }

        let context = try acceptedContext(DicomNetworkUID.modalityPerformedProcedureStepSOPClass, in: association)
        let transferSyntax = context.transferSyntax ?? .explicitVRLittleEndian
        let messageID: UInt16 = 1
        let command = DicomDIMSECommandSet(
            affectedSOPClassUID: DicomNetworkUID.modalityPerformedProcedureStepSOPClass,
            commandField: DicomDIMSECommandField.nCreateRQ,
            messageID: messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.hasDataSet,
            affectedSOPInstanceUID: request.sopInstanceUID
        )
        try sendCommand(command,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        try sendDataSet(request.dataSet,
                        transferSyntax: transferSyntax,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        progress?(.requestSent(operation: operation, messageID: messageID))

        let reader = DicomDIMSEMessageReader()
        let response = try readCommand(using: transport, reader: reader)
        try expect(response, commandField: DicomDIMSECommandField.nCreateRSP)
        try validateSuccessStatus(response)
        let result = operationResult(from: response)
        progress?(.completed(operation: operation, status: result.status))
        return result
    }

    public func updateMPPS(_ request: DicomMPPSUpdateRequest,
                           progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomDIMSEOperationResult {
        try performWithResilience(operation: .mppsUpdate, progress: progress) { transport in
            try updateMPPS(request, using: transport, progress: progress)
        }
    }

    public func updateMPPS(_ request: DicomMPPSUpdateRequest,
                           using transport: DicomAssociationTransport,
                           progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomDIMSEOperationResult {
        let operation = DicomDIMSEOperation.mppsUpdate
        let association = try openAssociation(
            for: operation,
            abstractSyntaxUIDs: [DicomNetworkUID.modalityPerformedProcedureStepSOPClass],
            using: transport,
            progress: progress
        )
        defer { try? release(operation: operation, using: transport, progress: progress) }

        let context = try acceptedContext(DicomNetworkUID.modalityPerformedProcedureStepSOPClass, in: association)
        let transferSyntax = context.transferSyntax ?? .explicitVRLittleEndian
        let messageID: UInt16 = 1
        let command = DicomDIMSECommandSet(
            requestedSOPClassUID: DicomNetworkUID.modalityPerformedProcedureStepSOPClass,
            commandField: DicomDIMSECommandField.nSetRQ,
            messageID: messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.hasDataSet,
            requestedSOPInstanceUID: request.sopInstanceUID
        )
        try sendCommand(command,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        try sendDataSet(request.dataSet,
                        transferSyntax: transferSyntax,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        progress?(.requestSent(operation: operation, messageID: messageID))

        let reader = DicomDIMSEMessageReader()
        let response = try readCommand(using: transport, reader: reader)
        try expect(response, commandField: DicomDIMSECommandField.nSetRSP)
        try validateSuccessStatus(response)
        let result = operationResult(from: response)
        progress?(.completed(operation: operation, status: result.status))
        return result
    }

    public func sendPrintJob(_ job: DicomPrintJob,
                             progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomPrintJobResult {
        try performWithResilience(operation: .printManagement, progress: progress) { transport in
            try sendPrintJob(job, using: transport, progress: progress)
        }
    }

    public func sendPrintJob(_ job: DicomPrintJob,
                             using transport: DicomAssociationTransport,
                             progress: ((DicomDIMSEProgress) -> Void)? = nil) throws -> DicomPrintJobResult {
        let operation = DicomDIMSEOperation.printManagement
        let association = try openAssociation(
            for: operation,
            abstractSyntaxUIDs: [
                DicomNetworkUID.basicGrayscalePrintManagementMetaSOPClass,
                DicomNetworkUID.basicFilmSessionSOPClass,
                DicomNetworkUID.basicFilmBoxSOPClass,
                DicomNetworkUID.basicGrayscaleImageBoxSOPClass
            ],
            using: transport,
            progress: progress
        )
        defer { try? release(operation: operation, using: transport, progress: progress) }

        let context = try acceptedPrintContext(in: association)
        let transferSyntax = context.transferSyntax ?? .explicitVRLittleEndian
        let reader = DicomDIMSEMessageReader()

        _ = try sendNormalizedCreate(
            operation: operation,
            affectedSOPClassUID: DicomNetworkUID.basicFilmSessionSOPClass,
            affectedSOPInstanceUID: job.filmSessionSOPInstanceUID,
            dataSet: job.filmSession.dataSet,
            responseCommandField: DicomDIMSECommandField.nCreateRSP,
            messageID: 1,
            context: context,
            transferSyntax: transferSyntax,
            association: association,
            transport: transport,
            reader: reader,
            progress: progress
        )

        let filmBoxCreate = try sendNormalizedCreate(
            operation: operation,
            affectedSOPClassUID: DicomNetworkUID.basicFilmBoxSOPClass,
            affectedSOPInstanceUID: job.filmBoxSOPInstanceUID,
            dataSet: job.filmBox.dataSet(referencingFilmSessionUID: job.filmSessionSOPInstanceUID),
            responseCommandField: DicomDIMSECommandField.nCreateRSP,
            messageID: 2,
            context: context,
            transferSyntax: transferSyntax,
            association: association,
            transport: transport,
            reader: reader,
            progress: progress
        )

        let imageBoxUIDs = imageBoxUIDs(from: filmBoxCreate.dataSet,
                                       expectedCount: job.imageBoxes.count)
        for (index, imageBox) in job.imageBoxes.enumerated() {
            let imageBoxUID = imageBoxUIDs[index]
            _ = try sendNormalizedSet(
                operation: operation,
                requestedSOPClassUID: DicomNetworkUID.basicGrayscaleImageBoxSOPClass,
                requestedSOPInstanceUID: imageBoxUID,
                dataSet: imageBox.dataSet,
                messageID: UInt16(index + 3),
                context: context,
                transferSyntax: transferSyntax,
                association: association,
                transport: transport,
                reader: reader,
                progress: progress
            )
        }

        let printResult = try sendNormalizedAction(
            operation: operation,
            requestedSOPClassUID: DicomNetworkUID.basicFilmBoxSOPClass,
            requestedSOPInstanceUID: job.filmBoxSOPInstanceUID,
            actionTypeID: 1,
            messageID: UInt16(job.imageBoxes.count + 3),
            context: context,
            association: association,
            transport: transport,
            reader: reader,
            progress: progress
        )
        progress?(.completed(operation: operation, status: printResult.status))
        return DicomPrintJobResult(operation: printResult,
                                   filmSessionSOPInstanceUID: job.filmSessionSOPInstanceUID,
                                   filmBoxSOPInstanceUID: job.filmBoxSOPInstanceUID,
                                   imageBoxSOPInstanceUIDs: imageBoxUIDs)
    }
}

private extension DicomDIMSEServiceSCU {
    func performWithResilience<Result>(
        operation: DicomDIMSEOperation,
        progress: ((DicomDIMSEProgress) -> Void)?,
        _ body: (DicomAssociationTransport) throws -> Result
    ) throws -> Result {
        try validateSecureUserIdentityTransport()

        let retryPolicy = configuration.retryPolicy
        var lastError: Error?

        for attempt in 1...retryPolicy.maxAttempts {
            if let circuitBreaker, !circuitBreaker.allowRequest() {
                let error = DicomNetworkError.circuitBreakerOpen(operation.rawValue)
                recordAudit(operation: operation,
                            outcome: .blocked,
                            attempt: attempt,
                            error: error)
                throw error
            }

            recordAudit(operation: operation,
                        outcome: .started,
                        attempt: attempt)
            do {
                let transport = try makeTransport()
                defer { closeIfNeeded(transport) }
                let result = try body(transport)
                circuitBreaker?.recordSuccess()
                recordAudit(operation: operation,
                            outcome: .succeeded,
                            attempt: attempt,
                            status: statusCode(from: result))
                return result
            } catch {
                circuitBreaker?.recordFailure()
                lastError = error
                let shouldRetry = attempt < retryPolicy.maxAttempts
                recordAudit(operation: operation,
                            outcome: shouldRetry ? .retrying : .failed,
                            attempt: attempt,
                            error: error)
                if shouldRetry, retryPolicy.retryDelay > 0 {
                    Thread.sleep(forTimeInterval: retryPolicy.retryDelay)
                }
            }
        }

        throw lastError ?? DicomNetworkError.networkUnavailable("DIMSE operation failed without an underlying error.")
    }

    func makeTransport() throws -> DicomAssociationTransport {
        if let transportFactory {
            return try transportFactory()
        }
        #if canImport(Network)
        let transport = DicomTCPAssociationTransport(host: configuration.host,
                                                     port: configuration.port,
                                                     timeout: configuration.timeout,
                                                     tls: configuration.tls)
        try transport.open()
        if let bytesPerSecond = configuration.bandwidthLimitBytesPerSecond {
            return DicomBandwidthLimitedTransport(wrapping: transport,
                                                 bytesPerSecond: bytesPerSecond)
        }
        return transport
        #else
        throw DicomNetworkError.networkUnavailable("Network.framework is not available on this platform.")
        #endif
    }

    func closeIfNeeded(_ transport: DicomAssociationTransport) {
        #if canImport(Network)
        (transport as? DicomTCPAssociationTransport)?.close()
        #endif
    }

    func openAssociation(for operation: DicomDIMSEOperation,
                         abstractSyntaxUIDs: [String],
                         using transport: DicomAssociationTransport,
                         progress: ((DicomDIMSEProgress) -> Void)?) throws -> DicomAssociation {
        try validateSecureUserIdentityTransport()

        progress?(.associationRequested(operation: operation,
                                        calledAETitle: configuration.calledAETitle))
        let request = DicomAssociationRequest(
            calledAETitle: configuration.calledAETitle,
            callingAETitle: configuration.callingAETitle,
            presentationContexts: presentationContexts(for: abstractSyntaxUIDs),
            maximumPDULength: configuration.maximumPDULength,
            userIdentity: configuration.userIdentity
        )
        let association = try DicomAssociationSCU(request: request).open(using: transport)
        progress?(.associationAccepted(operation: operation))
        return association
    }

    func recordAudit(operation: DicomDIMSEOperation,
                     outcome: DicomNetworkAuditEvent.Outcome,
                     attempt: Int,
                     status: UInt16? = nil,
                     error: Error? = nil) {
        auditLogger?.record(DicomNetworkAuditEvent(
            operation: operation,
            outcome: outcome,
            host: configuration.host,
            port: configuration.port,
            calledAETitle: configuration.calledAETitle,
            attempt: attempt,
            status: status,
            errorDescription: error.map { auditDescription(for: $0) }
        ))
    }

    func statusCode<Result>(from result: Result) -> UInt16? {
        switch result {
        case let value as DicomDIMSEOperationResult:
            return value.status
        case let value as DicomCFindResult:
            return value.operation.status
        case let value as DicomCGetResult:
            return value.operation.status
        case let value as DicomPrintJobResult:
            return value.operation.status
        default:
            return nil
        }
    }

    func validateSecureUserIdentityTransport() throws {
        guard configuration.userIdentity == nil || configuration.tls.mode == .enabled else {
            throw DicomNetworkError.insecureUserIdentityTransport
        }
    }

    func auditDescription(for error: Error) -> String {
        guard let networkError = error as? DicomNetworkError else {
            return String(describing: type(of: error))
        }
        switch networkError {
        case .invalidAEString:
            return "Invalid AE title."
        case .invalidPDUType:
            return "Unsupported PDU type."
        case .invalidPDULength:
            return "Invalid PDU length."
        case .invalidItemType:
            return "Unsupported association item type."
        case .invalidPresentationContextID:
            return "Invalid presentation context ID."
        case .missingApplicationContext:
            return "Missing application context."
        case .missingPresentationContext:
            return "Missing presentation context."
        case .missingTransferSyntax:
            return "Missing transfer syntax."
        case .associationRejected:
            return "Association rejected by peer."
        case .associationAborted:
            return "Association aborted by peer."
        case .invalidAssociationState:
            return "Invalid association state."
        case .unsupportedPDU:
            return "Unsupported PDU."
        case .malformedCommandSet:
            return "Malformed DIMSE command set."
        case .missingAcceptedPresentationContext:
            return "Missing accepted presentation context."
        case .unexpectedDIMSECommand:
            return "Unexpected DIMSE command."
        case .dimseStatusFailure(let status):
            return String(format: "DIMSE status failure 0x%04X.", status)
        case .networkTimeout(let operation):
            return "Network timeout while \(operation)."
        case .networkUnavailable:
            return "Network transport unavailable."
        case .circuitBreakerOpen:
            return "Circuit breaker open."
        case .insecureUserIdentityTransport:
            return "User identity requires TLS."
        }
    }

    func presentationContexts(for abstractSyntaxUIDs: [String]) -> [DicomPresentationContextRequest] {
        var nextID: UInt8 = 1
        var seen: Set<String> = []
        var contexts: [DicomPresentationContextRequest] = []
        for uid in abstractSyntaxUIDs where !seen.contains(uid) {
            seen.insert(uid)
            contexts.append(DicomPresentationContextRequest(
                id: nextID,
                abstractSyntaxUID: uid,
                transferSyntaxes: configuration.transferSyntaxes
            ))
            nextID += 2
        }
        return contexts
    }

    func acceptedContext(_ abstractSyntaxUID: String,
                         in association: DicomAssociation) throws -> DicomAcceptedPresentationContext {
        guard let context = association.acceptedPresentationContext(for: abstractSyntaxUID) else {
            throw DicomNetworkError.missingAcceptedPresentationContext(abstractSyntaxUID)
        }
        return context
    }

    func acceptedPrintContext(in association: DicomAssociation) throws -> DicomAcceptedPresentationContext {
        let supported = [
            DicomNetworkUID.basicGrayscalePrintManagementMetaSOPClass,
            DicomNetworkUID.basicFilmSessionSOPClass,
            DicomNetworkUID.basicFilmBoxSOPClass,
            DicomNetworkUID.basicGrayscaleImageBoxSOPClass
        ]
        for uid in supported {
            if let context = association.acceptedPresentationContext(for: uid) {
                return context
            }
        }
        throw DicomNetworkError.missingAcceptedPresentationContext(DicomNetworkUID.basicGrayscalePrintManagementMetaSOPClass)
    }

    func sendCommand(_ command: DicomDIMSECommandSet,
                     presentationContextID: UInt8,
                     association: DicomAssociation,
                     transport: DicomAssociationTransport) throws {
        let pdu = try association.commandPData(command,
                                               presentationContextID: presentationContextID)
        try transport.writePDU(DicomPDUCodec.encode(pdu))
    }

    func sendDataSet(_ dataSet: DicomDataSet,
                     transferSyntax: DicomTransferSyntax,
                     presentationContextID: UInt8,
                     association: DicomAssociation,
                     transport: DicomAssociationTransport) throws {
        let data = try DicomDataSetWriter.dataSetData(from: dataSet,
                                                      transferSyntax: transferSyntax)
        let pdu = try association.dataSetPData(data,
                                               presentationContextID: presentationContextID)
        try transport.writePDU(DicomPDUCodec.encode(pdu))
    }

    func readCommand(using transport: DicomAssociationTransport,
                     reader: DicomDIMSEMessageReader) throws -> DicomDIMSECommandSet {
        let message = try reader.readMessage(from: transport)
        guard message.isCommand else {
            throw DicomNetworkError.malformedCommandSet("Expected DIMSE command PDV.")
        }
        return try DicomDIMSECommandSet.decode(message.data)
    }

    func release(operation: DicomDIMSEOperation,
                 using transport: DicomAssociationTransport,
                 progress: ((DicomDIMSEProgress) -> Void)?) throws {
        try transport.writePDU(DicomPDUCodec.encode(.releaseRequest))
        let response = try DicomPDUCodec.decode(try transport.readPDU())
        switch response {
        case .releaseResponse:
            progress?(.released(operation: operation))
        case .abort(let abort):
            throw DicomNetworkError.associationAborted(abort)
        default:
            throw DicomNetworkError.unsupportedPDU(response.type)
        }
    }

    func expect(_ command: DicomDIMSECommandSet, commandField: UInt16) throws {
        guard command.commandField == commandField else {
            throw DicomNetworkError.unexpectedDIMSECommand(expected: commandField,
                                                           actual: command.commandField)
        }
    }

    func validateSuccessStatus(_ command: DicomDIMSECommandSet) throws {
        let status = command.status ?? 0
        guard status == 0 else {
            throw DicomNetworkError.dimseStatusFailure(status)
        }
    }

    func isPending(_ status: UInt16) -> Bool {
        status == 0xFF00 || status == 0xFF01
    }

    func operationResult(from command: DicomDIMSECommandSet) -> DicomDIMSEOperationResult {
        DicomDIMSEOperationResult(status: command.status ?? 0,
                                  remainingSuboperations: command.remainingSuboperations,
                                  completedSuboperations: command.completedSuboperations,
                                  failedSuboperations: command.failedSuboperations,
                                  warningSuboperations: command.warningSuboperations)
    }

    func sendNormalizedCreate(operation: DicomDIMSEOperation,
                              affectedSOPClassUID: String,
                              affectedSOPInstanceUID: String,
                              dataSet: DicomDataSet,
                              responseCommandField: UInt16,
                              messageID: UInt16,
                              context: DicomAcceptedPresentationContext,
                              transferSyntax: DicomTransferSyntax,
                              association: DicomAssociation,
                              transport: DicomAssociationTransport,
                              reader: DicomDIMSEMessageReader,
                              progress: ((DicomDIMSEProgress) -> Void)?) throws -> (result: DicomDIMSEOperationResult, dataSet: DicomDataSet?) {
        let command = DicomDIMSECommandSet(
            affectedSOPClassUID: affectedSOPClassUID,
            commandField: DicomDIMSECommandField.nCreateRQ,
            messageID: messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.hasDataSet,
            affectedSOPInstanceUID: affectedSOPInstanceUID
        )
        try sendCommand(command,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        try sendDataSet(dataSet,
                        transferSyntax: transferSyntax,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        progress?(.requestSent(operation: operation, messageID: messageID))
        let response = try readCommand(using: transport, reader: reader)
        try expect(response, commandField: responseCommandField)
        try validateSuccessStatus(response)
        return (operationResult(from: response),
                try readOptionalDataSet(response: response,
                                        transferSyntax: transferSyntax,
                                        transport: transport,
                                        reader: reader))
    }

    func sendNormalizedSet(operation: DicomDIMSEOperation,
                           requestedSOPClassUID: String,
                           requestedSOPInstanceUID: String,
                           dataSet: DicomDataSet,
                           messageID: UInt16,
                           context: DicomAcceptedPresentationContext,
                           transferSyntax: DicomTransferSyntax,
                           association: DicomAssociation,
                           transport: DicomAssociationTransport,
                           reader: DicomDIMSEMessageReader,
                           progress: ((DicomDIMSEProgress) -> Void)?) throws -> DicomDIMSEOperationResult {
        let command = DicomDIMSECommandSet(
            requestedSOPClassUID: requestedSOPClassUID,
            commandField: DicomDIMSECommandField.nSetRQ,
            messageID: messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.hasDataSet,
            requestedSOPInstanceUID: requestedSOPInstanceUID
        )
        try sendCommand(command,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        try sendDataSet(dataSet,
                        transferSyntax: transferSyntax,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        progress?(.requestSent(operation: operation, messageID: messageID))
        let response = try readCommand(using: transport, reader: reader)
        try expect(response, commandField: DicomDIMSECommandField.nSetRSP)
        try validateSuccessStatus(response)
        return operationResult(from: response)
    }

    func sendNormalizedAction(operation: DicomDIMSEOperation,
                              requestedSOPClassUID: String,
                              requestedSOPInstanceUID: String,
                              actionTypeID: UInt16,
                              messageID: UInt16,
                              context: DicomAcceptedPresentationContext,
                              association: DicomAssociation,
                              transport: DicomAssociationTransport,
                              reader: DicomDIMSEMessageReader,
                              progress: ((DicomDIMSEProgress) -> Void)?) throws -> DicomDIMSEOperationResult {
        let command = DicomDIMSECommandSet(
            requestedSOPClassUID: requestedSOPClassUID,
            commandField: DicomDIMSECommandField.nActionRQ,
            messageID: messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.noDataSet,
            requestedSOPInstanceUID: requestedSOPInstanceUID,
            actionTypeID: actionTypeID
        )
        try sendCommand(command,
                        presentationContextID: context.id,
                        association: association,
                        transport: transport)
        progress?(.requestSent(operation: operation, messageID: messageID))
        let response = try readCommand(using: transport, reader: reader)
        try expect(response, commandField: DicomDIMSECommandField.nActionRSP)
        try validateSuccessStatus(response)
        return operationResult(from: response)
    }

    func readOptionalDataSet(response: DicomDIMSECommandSet,
                             transferSyntax: DicomTransferSyntax,
                             transport: DicomAssociationTransport,
                             reader: DicomDIMSEMessageReader) throws -> DicomDataSet? {
        guard response.commandDataSetType != DicomDIMSECommandDataSetType.noDataSet else {
            return nil
        }
        let payload = try reader.readMessage(from: transport)
        guard !payload.isCommand else {
            throw DicomNetworkError.malformedCommandSet("Expected DIMSE response dataset.")
        }
        return try DicomDataSetParser.dataSet(from: payload.data,
                                              transferSyntax: transferSyntax)
    }

    func imageBoxUIDs(from dataSet: DicomDataSet?, expectedCount: Int) -> [String] {
        let referenced = dataSet?
            .sequenceItems(for: DicomPrintTag.referencedImageBoxSequence)
            .compactMap { $0.dataSet.string(for: .referencedSOPInstanceUID) } ?? []
        guard referenced.count >= expectedCount else {
            return (0..<expectedCount).map { _ in DicomDataSetWriter.makeUID() }
        }
        return Array(referenced.prefix(expectedCount))
    }

    func progressPending(operation: DicomDIMSEOperation,
                         response: DicomDIMSECommandSet,
                         progress: ((DicomDIMSEProgress) -> Void)?) {
        progress?(.pending(operation: operation,
                           remaining: response.remainingSuboperations,
                           completed: response.completedSuboperations,
                           failed: response.failedSuboperations,
                           warning: response.warningSuboperations))
    }

    func receiveStoreRequest(_ command: DicomDIMSECommandSet,
                             association: DicomAssociation,
                             transport: DicomAssociationTransport,
                             reader: DicomDIMSEMessageReader) throws -> DicomRetrievedInstance {
        let sopClassUID = command.affectedSOPClassUID
        let context = try acceptedContext(sopClassUID ?? DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID,
                                          in: association)
        let transferSyntax = context.transferSyntax ?? .explicitVRLittleEndian
        let payload = try reader.readMessage(from: transport)
        guard !payload.isCommand else {
            throw DicomNetworkError.malformedCommandSet("Expected C-STORE dataset.")
        }
        let parsed = try? DicomDataSetParser.dataSet(from: payload.data,
                                                     transferSyntax: transferSyntax)
        let response = DicomDIMSECommandSet(
            affectedSOPClassUID: sopClassUID,
            commandField: DicomDIMSECommandField.cStoreRSP,
            messageIDBeingRespondedTo: command.messageID,
            commandDataSetType: DicomDIMSECommandDataSetType.noDataSet,
            status: 0,
            affectedSOPInstanceUID: command.affectedSOPInstanceUID
        )
        try sendCommand(response,
                        presentationContextID: payload.presentationContextID,
                        association: association,
                        transport: transport)
        return DicomRetrievedInstance(sopClassUID: sopClassUID,
                                      sopInstanceUID: command.affectedSOPInstanceUID,
                                      transferSyntax: transferSyntax,
                                      data: payload.data,
                                      dataSet: parsed)
    }

    func storageDataSet(_ dataSet: DicomDataSet,
                        sopClassUID: String?,
                        sopInstanceUID: String?) -> (dataSet: DicomDataSet, sopClassUID: String, sopInstanceUID: String) {
        let resolvedClassUID = sopClassUID ??
            dataSet.string(for: .sopClassUID) ??
            DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID
        let resolvedInstanceUID = sopInstanceUID ??
            dataSet.string(for: .sopInstanceUID) ??
            DicomDataSetWriter.makeUID()
        var updated = dataSet
        if updated.string(for: .sopClassUID) == nil {
            updated.set(DicomDataElement(tag: DicomTag.sopClassUID.rawValue,
                                         vr: .UI,
                                         value: .strings([resolvedClassUID])))
        }
        if updated.string(for: .sopInstanceUID) == nil {
            updated.set(DicomDataElement(tag: DicomTag.sopInstanceUID.rawValue,
                                         vr: .UI,
                                         value: .strings([resolvedInstanceUID])))
        }
        return (updated, resolvedClassUID, resolvedInstanceUID)
    }
}

enum DicomDIMSEReadResult {
    case message(DicomDIMSEMessage)
    case releaseRequest
}

struct DicomDIMSEMessage {
    var presentationContextID: UInt8
    var isCommand: Bool
    var data: Data
}

final class DicomDIMSEMessageReader {
    private var pendingPDVs: [DicomPDV] = []

    func readMessage(from transport: DicomAssociationTransport) throws -> DicomDIMSEMessage {
        switch try readNext(from: transport) {
        case .message(let message):
            return message
        case .releaseRequest:
            throw DicomNetworkError.unsupportedPDU(DicomPDUType.releaseRequest)
        }
    }

    func readNext(from transport: DicomAssociationTransport) throws -> DicomDIMSEReadResult {
        var contextID: UInt8?
        var isCommand: Bool?
        var data = Data()

        while true {
            if pendingPDVs.isEmpty {
                let pdu = try DicomPDUCodec.decode(try transport.readPDU())
                switch pdu {
                case .pData(let pdvs):
                    pendingPDVs.append(contentsOf: pdvs)
                case .releaseRequest:
                    return .releaseRequest
                case .abort(let abort):
                    throw DicomNetworkError.associationAborted(abort)
                default:
                    throw DicomNetworkError.unsupportedPDU(pdu.type)
                }
            }

            let pdv = pendingPDVs.removeFirst()
            if contextID == nil {
                contextID = pdv.presentationContextID
                isCommand = pdv.isCommand
            }
            guard contextID == pdv.presentationContextID,
                  isCommand == pdv.isCommand else {
                throw DicomNetworkError.malformedCommandSet("Mixed PDV fragments in one DIMSE message.")
            }
            data.append(pdv.data)
            if pdv.isLastFragment {
                return .message(DicomDIMSEMessage(presentationContextID: contextID ?? pdv.presentationContextID,
                                                  isCommand: isCommand ?? pdv.isCommand,
                                                  data: data))
            }
        }
    }
}

#if canImport(Network)
public final class DicomTCPAssociationTransport: DicomAssociationTransport {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "DicomTCPAssociationTransport")
    private let timeout: TimeInterval

    public init(host: String,
                port: UInt16,
                timeout: TimeInterval = 10,
                tls: DicomTLSConfiguration = .disabled) {
        let nwPort = NWEndpoint.Port(rawValue: port) ?? 104
        let parameters: NWParameters
        switch tls.mode {
        case .disabled:
            parameters = .tcp
        case .enabled:
            let tlsOptions = NWProtocolTLS.Options()
            #if canImport(Security)
            if let serverName = tls.serverName {
                serverName.withCString {
                    sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, $0)
                }
            }
            #endif
            parameters = NWParameters(tls: tlsOptions,
                                      tcp: NWProtocolTCP.Options())
        }
        self.connection = NWConnection(host: NWEndpoint.Host(host),
                                       port: nwPort,
                                       using: parameters)
        self.timeout = timeout
    }

    public init(acceptedConnection: NWConnection, timeout: TimeInterval = 10) {
        self.connection = acceptedConnection
        self.timeout = timeout
    }

    public func open() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, Error>?
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                result = .success(())
                semaphore.signal()
            case .failed(let error):
                result = .failure(error)
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw DicomNetworkError.networkTimeout("opening TCP connection")
        }
        try result?.get()
    }

    public func startAcceptedConnection() {
        connection.start(queue: queue)
    }

    public func writePDU(_ data: Data) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, Error>?
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                result = .failure(error)
            } else {
                result = .success(())
            }
            semaphore.signal()
        })
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw DicomNetworkError.networkTimeout("writing PDU")
        }
        try result?.get()
    }

    public func readPDU() throws -> Data {
        let header = try readExact(count: 6)
        let bytes = [UInt8](header)
        let length = Int(UInt32(bytes[2]) << 24 |
                         UInt32(bytes[3]) << 16 |
                         UInt32(bytes[4]) << 8 |
                         UInt32(bytes[5]))
        var data = header
        data.append(try readExact(count: length))
        return data
    }

    public func close() {
        connection.cancel()
    }

    deinit {
        connection.cancel()
    }

    private func readExact(count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            let chunk = try receive(maximumLength: count - data.count)
            guard !chunk.isEmpty else {
                throw DicomNetworkError.networkUnavailable("Peer closed the TCP connection.")
            }
            data.append(chunk)
        }
        return data
    }

    private func receive(maximumLength: Int) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?
        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: maximumLength) { content, _, isComplete, error in
            if let error {
                result = .failure(error)
            } else if let content, !content.isEmpty {
                result = .success(content)
            } else if isComplete {
                result = .success(Data())
            } else {
                result = .success(Data())
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw DicomNetworkError.networkTimeout("reading PDU")
        }
        return try result?.get() ?? Data()
    }
}
#endif
