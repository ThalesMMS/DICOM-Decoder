import Foundation

public enum DicomTLSMode: String, Codable, Equatable, Hashable, Sendable {
    case disabled
    case enabled
}

public enum DicomTLSSecurityProfile: String, Codable, Equatable, Hashable, Sendable {
    case none
    case nonDowngradingBCP195
    case bcp195
    case extendedBCP195
    case basicRetired
    case aesRetired
    case authenticatedUnencryptedRetired
}

public struct DicomTLSMaterial: Codable, Equatable, Sendable {
    public var certificatePath: String?
    public var privateKeyPath: String?
    public var trustStorePath: String?
    public var trustedCertificatePaths: [String]

    public init(certificatePath: String? = nil,
                privateKeyPath: String? = nil,
                trustStorePath: String? = nil,
                trustedCertificatePaths: [String] = []) {
        self.certificatePath = certificatePath
        self.privateKeyPath = privateKeyPath
        self.trustStorePath = trustStorePath
        self.trustedCertificatePaths = trustedCertificatePaths
    }
}

public struct DicomTLSConfiguration: Codable, Equatable, Sendable {
    public var mode: DicomTLSMode
    public var serverName: String?
    public var material: DicomTLSMaterial?
    public var securityProfile: DicomTLSSecurityProfile

    public init(mode: DicomTLSMode = .disabled,
                serverName: String? = nil,
                material: DicomTLSMaterial? = nil,
                securityProfile: DicomTLSSecurityProfile = .none) {
        self.mode = mode
        self.serverName = serverName
        self.material = material
        self.securityProfile = securityProfile
    }

    public static let disabled = DicomTLSConfiguration()
}

public final class DicomDIMSEOperationHandle: @unchecked Sendable {
    public let id: UUID

    private let lock = NSLock()
    private var cancelled = false
    private var cancelAction: (() -> Void)?

    public init(id: UUID = UUID()) {
        self.id = id
    }

    public var isCancelled: Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }

    public func cancel() {
        let action: (() -> Void)?
        lock.lock()
        cancelled = true
        action = cancelAction
        lock.unlock()
        action?()
    }

    public func setCancelAction(_ action: @escaping () -> Void) {
        var shouldCancelImmediately = false
        lock.lock()
        cancelAction = action
        shouldCancelImmediately = cancelled
        lock.unlock()
        if shouldCancelImmediately {
            action()
        }
    }

    public func clearCancelAction() {
        lock.lock()
        cancelAction = nil
        lock.unlock()
    }

    public func checkCancellation(operation: DicomDIMSEOperation) throws {
        guard !isCancelled else {
            throw DicomNetworkError.operationCancelled(operation.rawValue)
        }
    }
}

public struct DicomDIMSEAssociationPoolPolicy: Codable, Equatable, Sendable {
    public var maximumIdleServicesPerKey: Int
    public var idleTimeout: TimeInterval

    public init(maximumIdleServicesPerKey: Int = 2,
                idleTimeout: TimeInterval = 30) {
        self.maximumIdleServicesPerKey = max(1, maximumIdleServicesPerKey)
        self.idleTimeout = max(0, idleTimeout)
    }
}

public struct DicomDIMSEAssociationPoolKey: Codable, Equatable, Hashable, Sendable {
    public struct TLSMaterialKey: Codable, Equatable, Hashable, Sendable {
        public var certificatePath: String?
        public var privateKeyPath: String?
        public var trustStorePath: String?
        public var trustedCertificatePaths: [String]

        public init(material: DicomTLSMaterial?) {
            certificatePath = material?.certificatePath
            privateKeyPath = material?.privateKeyPath
            trustStorePath = material?.trustStorePath
            trustedCertificatePaths = material?.trustedCertificatePaths ?? []
        }
    }

    public struct UserIdentityKey: Codable, Equatable, Hashable, Sendable {
        public var type: DicomUserIdentityType
        public var primaryFieldLength: Int
        public var primaryFieldFingerprint: String
        public var secondaryFieldLength: Int
        public var secondaryFieldFingerprint: String
        public var positiveResponseRequested: Bool

        public init(identity: DicomUserIdentity) {
            type = identity.type
            primaryFieldLength = identity.primaryField.count
            primaryFieldFingerprint = Self.fingerprint(identity.primaryField)
            secondaryFieldLength = identity.secondaryField.count
            secondaryFieldFingerprint = Self.fingerprint(identity.secondaryField)
            positiveResponseRequested = identity.positiveResponseRequested
        }

        private static func fingerprint(_ data: Data) -> String {
            DicomDIMSEAssociationPoolKey.fingerprint(data)
        }
    }

    public var host: String
    public var port: UInt16
    public var calledAETitle: String
    public var callingAETitle: String
    public var timeout: TimeInterval
    public var maximumPDULength: UInt32
    public var transferSyntaxUIDs: [String]
    public var tlsMode: DicomTLSMode
    public var tlsServerName: String?
    public var tlsMaterial: TLSMaterialKey
    public var tlsSecurityProfile: DicomTLSSecurityProfile
    public var userIdentity: UserIdentityKey?
    public var retryPolicy: DicomNetworkRetryPolicy
    public var circuitBreakerPolicy: DicomCircuitBreakerPolicy?
    public var bandwidthLimitBytesPerSecond: Int?

    public init(configuration: DicomDIMSEConnectionConfiguration) {
        host = configuration.host
        port = configuration.port
        calledAETitle = configuration.calledAETitle
        callingAETitle = configuration.callingAETitle
        timeout = configuration.timeout
        maximumPDULength = configuration.maximumPDULength
        transferSyntaxUIDs = configuration.transferSyntaxes.map(\.rawValue)
        tlsMode = configuration.tls.mode
        tlsServerName = configuration.tls.serverName
        tlsMaterial = TLSMaterialKey(material: configuration.tls.material)
        tlsSecurityProfile = configuration.tls.securityProfile
        userIdentity = configuration.userIdentity.map(UserIdentityKey.init(identity:))
        retryPolicy = configuration.retryPolicy
        circuitBreakerPolicy = configuration.circuitBreakerPolicy
        bandwidthLimitBytesPerSecond = configuration.bandwidthLimitBytesPerSecond
    }

    public var sanitizedHash: String {
        let userIdentityComponent: String
        if let userIdentity {
            userIdentityComponent = [
                String(userIdentity.type.rawValue),
                String(userIdentity.primaryFieldLength),
                userIdentity.primaryFieldFingerprint,
                String(userIdentity.secondaryFieldLength),
                userIdentity.secondaryFieldFingerprint,
                String(userIdentity.positiveResponseRequested)
            ].joined(separator: ":")
        } else {
            userIdentityComponent = ""
        }
        let circuitBreakerComponent: String
        if let circuitBreakerPolicy {
            circuitBreakerComponent = "\(circuitBreakerPolicy.failureThreshold):\(circuitBreakerPolicy.resetInterval)"
        } else {
            circuitBreakerComponent = ""
        }
        let bandwidthComponent = bandwidthLimitBytesPerSecond.map { String($0) } ?? ""
        let components = [
            host,
            String(port),
            calledAETitle,
            callingAETitle,
            String(timeout),
            String(maximumPDULength),
            transferSyntaxUIDs.joined(separator: ","),
            tlsMode.rawValue,
            tlsServerName ?? "",
            tlsMaterial.certificatePath ?? "",
            tlsMaterial.privateKeyPath ?? "",
            tlsMaterial.trustStorePath ?? "",
            tlsMaterial.trustedCertificatePaths.joined(separator: ","),
            tlsSecurityProfile.rawValue,
            userIdentityComponent,
            String(retryPolicy.maxAttempts),
            String(retryPolicy.retryDelay),
            circuitBreakerComponent,
            bandwidthComponent
        ]
        return Self.fingerprint(Data(components.joined(separator: "|").utf8))
    }

    private static func fingerprint(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

public struct DicomDIMSEAssociationPoolEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case created
        case reused
        case recycled
        case evicted
        case closedIdle
        case closedExplicit
        case failedAssociationEvicted
    }

    public var timestamp: Date
    public var kind: Kind
    public var keyHash: String
    public var host: String
    public var port: UInt16
    public var calledAETitle: String
    public var idleCount: Int
    public var reason: String?

    public init(timestamp: Date = Date(),
                kind: Kind,
                key: DicomDIMSEAssociationPoolKey,
                idleCount: Int,
                reason: String? = nil) {
        self.timestamp = timestamp
        self.kind = kind
        keyHash = key.sanitizedHash
        host = key.host
        port = key.port
        calledAETitle = key.calledAETitle
        self.idleCount = idleCount
        self.reason = reason
    }
}

public protocol DicomDIMSEAssociationPoolLogging: AnyObject, Sendable {
    func record(_ event: DicomDIMSEAssociationPoolEvent)
}

public final class DicomInMemoryAssociationPoolLog: DicomDIMSEAssociationPoolLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DicomDIMSEAssociationPoolEvent] = []

    public init() {}

    public func record(_ event: DicomDIMSEAssociationPoolEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    public var events: [DicomDIMSEAssociationPoolEvent] {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        return snapshot
    }
}

public final class DicomDIMSEAssociationPool: @unchecked Sendable {
    private struct Entry {
        var service: DicomDIMSEServiceSCU
        var lastUsed: Date
    }

    public let policy: DicomDIMSEAssociationPoolPolicy
    private let logger: DicomDIMSEAssociationPoolLogging?

    private let lock = NSLock()
    private var entriesByKey: [DicomDIMSEAssociationPoolKey: [Entry]] = [:]

    public init(policy: DicomDIMSEAssociationPoolPolicy = DicomDIMSEAssociationPoolPolicy(),
                logger: DicomDIMSEAssociationPoolLogging? = nil) {
        self.policy = policy
        self.logger = logger
    }

    public func service(
        for configuration: DicomDIMSEConnectionConfiguration,
        auditLogger: DicomNetworkAuditLogging? = nil,
        circuitBreaker: DicomNetworkCircuitBreaker? = nil,
        operationHandle: DicomDIMSEOperationHandle? = nil,
        now: Date = Date()
    ) -> DicomDIMSEServiceSCU {
        let key = Self.key(for: configuration)
        lock.lock()
        pruneLocked(now: now)
        if var entries = entriesByKey[key], !entries.isEmpty {
            var entry = entries.removeFirst()
            entry.lastUsed = now
            entriesByKey[key] = entries
            recordLocked(kind: .reused, key: key, idleCount: entries.count, now: now)
            lock.unlock()
            return entry.service.replacingRuntimeDependencies(
                auditLogger: auditLogger,
                circuitBreaker: circuitBreaker,
                operationHandle: operationHandle
            )
        }
        recordLocked(kind: .created, key: key, idleCount: entriesByKey[key]?.count ?? 0, now: now)
        lock.unlock()
        return DicomDIMSEServiceSCU(
            configuration: configuration,
            auditLogger: auditLogger,
            circuitBreaker: circuitBreaker,
            operationHandle: operationHandle
        )
    }

    public func recycle(_ service: DicomDIMSEServiceSCU, now: Date = Date()) {
        let key = Self.key(for: service.configuration)
        lock.lock()
        pruneLocked(now: now)
        var entries = entriesByKey[key] ?? []
        entries.insert(Entry(service: service, lastUsed: now), at: 0)
        if entries.count > policy.maximumIdleServicesPerKey {
            let overflow = entries.count - policy.maximumIdleServicesPerKey
            entries.removeLast(overflow)
            for _ in 0..<overflow {
                recordLocked(kind: .evicted, key: key, idleCount: policy.maximumIdleServicesPerKey, now: now)
            }
        }
        entriesByKey[key] = entries
        recordLocked(kind: .recycled, key: key, idleCount: entries.count, now: now)
        lock.unlock()
    }

    public func discard(_ service: DicomDIMSEServiceSCU, error: Error? = nil, now: Date = Date()) {
        let key = Self.key(for: service.configuration)
        lock.lock()
        recordLocked(
            kind: .failedAssociationEvicted,
            key: key,
            idleCount: entriesByKey[key]?.count ?? 0,
            now: now,
            reason: error.map { String(describing: type(of: $0)) }
        )
        lock.unlock()
    }

    public func idleCount(for configuration: DicomDIMSEConnectionConfiguration, now: Date = Date()) -> Int {
        let key = Self.key(for: configuration)
        lock.lock()
        pruneLocked(now: now)
        let count = entriesByKey[key]?.count ?? 0
        lock.unlock()
        return count
    }

    @discardableResult
    public func closeExpiredIdle(now: Date = Date()) -> Int {
        lock.lock()
        let closed = closeExpiredLocked(now: now)
        lock.unlock()
        return closed
    }

    @discardableResult
    public func closeAll(now: Date = Date()) -> Int {
        lock.lock()
        var closed = 0
        for (key, entries) in entriesByKey {
            closed += entries.count
            for _ in entries {
                recordLocked(kind: .closedExplicit, key: key, idleCount: 0, now: now)
            }
        }
        entriesByKey.removeAll()
        lock.unlock()
        return closed
    }

    public static func key(for configuration: DicomDIMSEConnectionConfiguration) -> DicomDIMSEAssociationPoolKey {
        DicomDIMSEAssociationPoolKey(configuration: configuration)
    }

    private func pruneLocked(now: Date) {
        _ = closeExpiredLocked(now: now)
    }

    @discardableResult
    private func closeExpiredLocked(now: Date) -> Int {
        guard policy.idleTimeout > 0 else { return 0 }
        var closed = 0
        for key in Array(entriesByKey.keys) {
            let entries = entriesByKey[key] ?? []
            let retained = entries.filter { now.timeIntervalSince($0.lastUsed) <= policy.idleTimeout }
            let removed = entries.count - retained.count
            if removed > 0 {
                closed += removed
                for _ in 0..<removed {
                    recordLocked(kind: .closedIdle, key: key, idleCount: retained.count, now: now)
                }
            }
            if retained.isEmpty {
                entriesByKey.removeValue(forKey: key)
            } else {
                entriesByKey[key] = retained
            }
        }
        return closed
    }

    private func recordLocked(kind: DicomDIMSEAssociationPoolEvent.Kind,
                              key: DicomDIMSEAssociationPoolKey,
                              idleCount: Int,
                              now: Date,
                              reason: String? = nil) {
        logger?.record(DicomDIMSEAssociationPoolEvent(
            timestamp: now,
            kind: kind,
            key: key,
            idleCount: idleCount,
            reason: reason
        ))
    }
}

public enum DicomUserIdentityType: UInt8, Codable, Equatable, Hashable, Sendable {
    case username = 1
    case usernameAndPasscode = 2
    case kerberos = 3
    case saml = 4
    case jwt = 5
}

public struct DicomUserIdentity: Codable, Equatable, Sendable {
    public var type: DicomUserIdentityType
    public var primaryField: Data
    public var secondaryField: Data
    public var positiveResponseRequested: Bool

    public init(type: DicomUserIdentityType,
                primaryField: Data,
                secondaryField: Data = Data(),
                positiveResponseRequested: Bool = false) {
        self.type = type
        self.primaryField = primaryField
        self.secondaryField = secondaryField
        self.positiveResponseRequested = positiveResponseRequested
    }

    public static func username(_ username: String,
                                positiveResponseRequested: Bool = false) -> DicomUserIdentity {
        DicomUserIdentity(type: .username,
                          primaryField: Data(username.utf8),
                          positiveResponseRequested: positiveResponseRequested)
    }

    public static func usernameAndPasscode(_ username: String,
                                           passcode: String,
                                           positiveResponseRequested: Bool = false) -> DicomUserIdentity {
        DicomUserIdentity(type: .usernameAndPasscode,
                          primaryField: Data(username.utf8),
                          secondaryField: Data(passcode.utf8),
                          positiveResponseRequested: positiveResponseRequested)
    }
}

public struct DicomNetworkRetryPolicy: Codable, Equatable, Hashable, Sendable {
    public var maxAttempts: Int
    public var retryDelay: TimeInterval

    public init(maxAttempts: Int = 1,
                retryDelay: TimeInterval = 0) {
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelay = max(0, retryDelay)
    }

    public static let disabled = DicomNetworkRetryPolicy()
}

public struct DicomCircuitBreakerPolicy: Codable, Equatable, Hashable, Sendable {
    public var failureThreshold: Int
    public var resetInterval: TimeInterval

    public init(failureThreshold: Int = 3,
                resetInterval: TimeInterval = 30) {
        self.failureThreshold = max(1, failureThreshold)
        self.resetInterval = max(0, resetInterval)
    }
}

public final class DicomNetworkCircuitBreaker: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case closed
        case open(openedAt: Date)
        case halfOpen
    }

    public let policy: DicomCircuitBreakerPolicy
    private let lock = NSLock()
    private var failureCount = 0
    private var stateStorage: State = .closed

    public init(policy: DicomCircuitBreakerPolicy) {
        self.policy = policy
    }

    public var state: State {
        lock.lock()
        let value = stateStorage
        lock.unlock()
        return value
    }

    public func allowRequest(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch stateStorage {
        case .closed, .halfOpen:
            return true
        case .open(let openedAt):
            if now.timeIntervalSince(openedAt) >= policy.resetInterval {
                stateStorage = .halfOpen
                return true
            }
            return false
        }
    }

    public func recordSuccess() {
        lock.lock()
        failureCount = 0
        stateStorage = .closed
        lock.unlock()
    }

    public func recordFailure(now: Date = Date()) {
        lock.lock()
        failureCount += 1
        if failureCount >= policy.failureThreshold {
            stateStorage = .open(openedAt: now)
        }
        lock.unlock()
    }
}

public struct DicomNetworkAuditEvent: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Equatable, Sendable {
        case started
        case succeeded
        case failed
        case retrying
        case blocked
    }

    public var timestamp: Date
    public var operation: DicomDIMSEOperation
    public var outcome: Outcome
    public var host: String
    public var port: UInt16
    public var calledAETitle: String
    public var attempt: Int
    public var status: UInt16?
    public var errorDescription: String?

    public init(timestamp: Date = Date(),
                operation: DicomDIMSEOperation,
                outcome: Outcome,
                host: String,
                port: UInt16,
                calledAETitle: String,
                attempt: Int,
                status: UInt16? = nil,
                errorDescription: String? = nil) {
        self.timestamp = timestamp
        self.operation = operation
        self.outcome = outcome
        self.host = host
        self.port = port
        self.calledAETitle = calledAETitle
        self.attempt = attempt
        self.status = status
        self.errorDescription = errorDescription
    }
}

public protocol DicomNetworkAuditLogging: AnyObject, Sendable {
    func record(_ event: DicomNetworkAuditEvent)
}

public final class DicomInMemoryNetworkAuditLog: DicomNetworkAuditLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DicomNetworkAuditEvent] = []

    public init() {}

    public func record(_ event: DicomNetworkAuditEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    public var events: [DicomNetworkAuditEvent] {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        return snapshot
    }
}

public final class DicomBandwidthLimitedTransport: DicomCancellableAssociationTransport {
    private let wrapped: DicomAssociationTransport
    private let bytesPerSecond: Int

    public init(wrapping wrapped: DicomAssociationTransport,
                bytesPerSecond: Int) {
        self.wrapped = wrapped
        self.bytesPerSecond = max(1, bytesPerSecond)
    }

    public func writePDU(_ data: Data) throws {
        throttle(byteCount: data.count)
        try wrapped.writePDU(data)
    }

    public func readPDU() throws -> Data {
        let data = try wrapped.readPDU()
        throttle(byteCount: data.count)
        return data
    }

    public func close() {
        (wrapped as? DicomCancellableAssociationTransport)?.close()
    }

    private func throttle(byteCount: Int) {
        guard byteCount > bytesPerSecond else { return }
        let delay = TimeInterval(byteCount) / TimeInterval(bytesPerSecond)
        Thread.sleep(forTimeInterval: delay)
    }
}
