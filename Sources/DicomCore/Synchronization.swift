import Foundation
#if canImport(os)
import os.lock
#endif

/// Lightweight lock abstraction used for decoder synchronization.
final class DicomLock {
    #if canImport(os)
    private var unfairLock = os_unfair_lock_s()

    @inline(__always)
    func lock() {
        os_unfair_lock_lock(&unfairLock)
    }

    @inline(__always)
    func unlock() {
        os_unfair_lock_unlock(&unfairLock)
    }
    #else
    private let lockImpl = NSLock()

    @inline(__always)
    func lock() {
        lockImpl.lock()
    }

    @inline(__always)
    func unlock() {
        lockImpl.unlock()
    }
    #endif

    @inline(__always)
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
