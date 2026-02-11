//
//  LoggerProtocol.swift
//
//  Protocol abstraction for logging implementations.
//  Defines the public API for logging messages at different
//  severity levels (debug, info, warning, error).
//  Implementations must support iOS 13+ and macOS 12+ with
//  appropriate fallback mechanisms for older OS versions.
//
//  Thread Safety:
//
//  All protocol methods must be thread-safe and support
//  concurrent access from multiple threads without requiring
//  external synchronization.
//

import Foundation

/// Protocol defining the public API for logging functionality.
/// Implementations must provide methods for all standard log
/// levels and ensure thread-safe operation across concurrent
/// contexts.
///
/// **Thread Safety:** All methods must be thread-safe and
/// support concurrent access without data races. Implementations
/// should use internal synchronization mechanisms to ensure
/// message ordering and consistency.
///
/// **Platform Compatibility:** Implementations must support
/// iOS 13+ and macOS 12+, using OSLog when available and
/// falling back to NSLog on older platforms.
public protocol LoggerProtocol {

    // MARK: - Logging Methods

    /// Logs a debug-level message.
    /// Use for detailed diagnostic information useful during development.
    ///
    /// - Parameter message: The message to log
    func debug(_ message: String)

    /// Logs an informational message.
    /// Use for general informational messages about normal operation.
    ///
    /// - Parameter message: The message to log
    func info(_ message: String)

    /// Logs a warning message.
    /// Use for potentially problematic situations that don't prevent operation.
    ///
    /// - Parameter message: The message to log
    func warning(_ message: String)

    /// Logs an error message.
    /// Use for error conditions that may require attention but allow recovery.
    ///
    /// - Parameter message: The message to log
    func error(_ message: String)
}
