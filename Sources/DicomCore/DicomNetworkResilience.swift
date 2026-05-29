import Foundation

public enum DicomTLSMode: String, Codable, Equatable, Sendable {
    case disabled
    case enabled
}

public struct DicomTLSConfiguration: Codable, Equatable, Sendable {
    public var mode: DicomTLSMode
    public var serverName: String?

    public init(mode: DicomTLSMode = .disabled,
                serverName: String? = nil) {
        self.mode = mode
        self.serverName = serverName
    }

    public static let disabled = DicomTLSConfiguration()
}

public enum DicomUserIdentityType: UInt8, Codable, Equatable, Sendable {
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

public struct DicomNetworkRetryPolicy: Codable, Equatable, Sendable {
    public var maxAttempts: Int
    public var retryDelay: TimeInterval

    public init(maxAttempts: Int = 1,
                retryDelay: TimeInterval = 0) {
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelay = max(0, retryDelay)
    }

    public static let disabled = DicomNetworkRetryPolicy()
}

public struct DicomCircuitBreakerPolicy: Codable, Equatable, Sendable {
    public var failureThreshold: Int
    public var resetInterval: TimeInterval

    public init(failureThreshold: Int = 3,
                resetInterval: TimeInterval = 30) {
        self.failureThreshold = max(1, failureThreshold)
        self.resetInterval = max(0, resetInterval)
    }
}

public final class DicomNetworkCircuitBreaker {
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

public protocol DicomNetworkAuditLogging: AnyObject {
    func record(_ event: DicomNetworkAuditEvent)
}

public final class DicomInMemoryNetworkAuditLog: DicomNetworkAuditLogging {
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

public final class DicomBandwidthLimitedTransport: DicomAssociationTransport {
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

    private func throttle(byteCount: Int) {
        guard byteCount > bytesPerSecond else { return }
        let delay = TimeInterval(byteCount) / TimeInterval(bytesPerSecond)
        Thread.sleep(forTimeInterval: delay)
    }
}
