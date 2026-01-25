import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Minimal logger wrapper to avoid OSLog availability issues on iOS 13.
struct AnyLogger {
    private let _info: (String) -> Void
    private let _debug: (String) -> Void
    private let _warning: (String) -> Void

    func info(_ message: String) { _info(message) }
    func debug(_ message: String) { _debug(message) }
    func warning(_ message: String) { _warning(message) }

    static func make(subsystem: String, category: String) -> AnyLogger {
        #if canImport(OSLog)
        if #available(iOS 14.0, macOS 11.0, *) {
            let logger = Logger(subsystem: subsystem, category: category)
            return AnyLogger(
                _info: { logger.info("\($0, privacy: .public)") },
                _debug: { logger.debug("\($0, privacy: .public)") },
                _warning: { logger.warning("\($0, privacy: .public)") }
            )
        }
        #endif
        return AnyLogger(
            _info: { NSLog("[INFO] %@", $0) },
            _debug: { NSLog("[DEBUG] %@", $0) },
            _warning: { NSLog("[WARN] %@", $0) }
        )
    }
}
