//
//  DCMDictionary.swift
//
//  A lightweight wrapper around the property list used to
//  look up human‑readable names for DICOM tags.
//  The Swift 6 port retains the
//  original semantics while embracing Swift idioms such as
//  singletons and generics.
//
//  The dictionary itself is stored in ``DCMDictionary.plist``
//  which must reside in the main bundle.  The keys in that
//  file are hexadecimal strings corresponding to the 32‑bit
//  tag and the values are two character VR codes followed by
//  a textual description.  The caller is responsible for
//  splitting the VR and description when needed.
//
//  Note: this class does not attempt to verify the contents
//  of the plist; if the file is missing or malformed the
//  dictionary will simply be empty.  Accesses to unknown keys
//  return ``nil`` rather than throwing.
//

import Foundation

/// Facade for looking up DICOM tag descriptions from a
/// bundled property list.  Unlike the Objective‑C version,
/// this implementation does not rely on ``NSObject`` or manual
/// memory management.  Instead, the dictionary is loaded once
/// lazily on first access and cached for the lifetime of the
/// instance.
///
/// **Migration:** This class now supports dependency injection.
/// Use the public initializer to create instances instead of
/// relying on the deprecated singleton.
public final class DCMDictionary: DicomDictionaryProtocol, @unchecked Sendable {
    // MARK: - Legacy Singleton Support (deprecated)

    /// Shared global instance.  The dictionary is loaded on demand
    /// using ``lazy`` so that applications which never access
    /// DICOM metadata do not pay the cost of parsing the plist.
    @available(*, deprecated, message: "Use dependency injection instead")
    public static let shared = DCMDictionary()

    /// Underlying storage for the tag mappings.  Keys are
    /// hex strings (e.g. ``"00020002"``) and values are
    /// strings beginning with the two character VR followed by
    /// ``":"`` and a description.  This type alias aids
    /// readability and makes testing easier.
    private typealias RawDictionary = [String: String]

    private let logger = AnyLogger.make(subsystem: "com.dicomviewer", category: "DCMDictionary")

    /// Internal backing store.  Marked as ``lazy`` so the
    /// property list is only read when first used.  In the event
    /// that the resource cannot be loaded the dictionary will be
    /// empty and lookups will safely return ``nil``.
    private lazy var dictionary: RawDictionary = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        
        guard let url = bundle.url(forResource: "DCMDictionary", withExtension: "plist") else {
            // If the plist cannot be located we log a warning once.
            #if DEBUG
            logger.warning("DCMDictionary.plist not found in bundle")
            #endif
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return plist as? RawDictionary ?? [:]
        } catch {
            // Parsing errors will result in an empty dictionary.  We
            // deliberately avoid throwing here to allow clients to
            // continue operating even if metadata is missing.
            #if DEBUG
            logger.warning("Error parsing DCMDictionary.plist: \(error)")
            #endif
            return [:]
        }
    }()

    // MARK: - Initialization

    /// Public initializer for dependency injection.
    /// Creates a new instance that loads the DCMDictionary.plist from the bundle.
    public init() {
        #if DEBUG
        logger.debug("DCMDictionary initialized with dependency injection")
        #endif
    }

    // MARK: - DicomDictionaryProtocol Implementation

    /// Returns the raw value associated with the supplied key.  The
    /// caller must split the VR code from the description if
    /// necessary.  Keys are expected to be eight hexadecimal
    /// characters representing the 32‑bit DICOM tag.
    ///
    /// - Parameter key: A hexadecimal string identifying a DICOM tag.
    /// - Returns: The string from the plist if present, otherwise
    ///   ``nil``.
    public func value(forKey key: String) -> String? {
        dictionary[key]
    }

    /// Returns just the VR code for a given tag
    /// - Parameter key: A hexadecimal string identifying a DICOM tag
    /// - Returns: The VR code (first 2 characters) or nil if not found
    public func vrCode(forKey key: String) -> String? {
        guard let value = value(forKey: key),
              value.count >= 2 else { return nil }
        return String(value.prefix(2))
    }

    /// Returns just the description for a given tag
    /// - Parameter key: A hexadecimal string identifying a DICOM tag
    /// - Returns: The description (after "XX:") or nil if not found
    public func description(forKey key: String) -> String? {
        guard let value = value(forKey: key),
              !value.isEmpty else { return nil }
        if let colonIndex = value.firstIndex(of: ":") {
            return String(value[value.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        } else {
            // Many dictionary entries are stored as "<VR><description>" without a colon separator.
            // Strip the 2-character VR prefix if present; otherwise return the raw string.
            if value.count > 2 {
                return String(value.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else {
                return value
            }
        }
    }

    /// Formats a tag as a standard DICOM tag string
    /// - Parameter tag: The 32-bit tag value
    /// - Returns: Formatted tag string in the format "(XXXX,XXXX)"
    public func formatTag(_ tag: UInt32) -> String {
        let group = (tag >> 16) & 0xFFFF
        let element = tag & 0xFFFF
        return String(format: "(%04X,%04X)", group, element)
    }
}

// MARK: - DCMDictionary Deprecated Static Methods

public extension DCMDictionary {

    // MARK: - Legacy Static Methods (deprecated)

    /// Returns just the VR code for a given tag
    /// - Parameter key: A hexadecimal string identifying a DICOM tag
    /// - Returns: The VR code (first 2 characters) or nil if not found
    @available(*, deprecated, message: "Use instance method instead: dictionary.vrCode(forKey:)")
    static func vrCode(forKey key: String) -> String? {
        shared.vrCode(forKey: key)
    }

    /// Returns just the description for a given tag
    /// - Parameter key: A hexadecimal string identifying a DICOM tag
    /// - Returns: The description (after "XX:") or nil if not found
    @available(*, deprecated, message: "Use instance method instead: dictionary.description(forKey:)")
    static func description(forKey key: String) -> String? {
        shared.description(forKey: key)
    }

    /// Formats a tag as a standard DICOM tag string
    /// - Parameter tag: The 32-bit tag value
    /// - Returns: Formatted tag string in the format "(XXXX,XXXX)"
    @available(*, deprecated, message: "Use instance method instead: dictionary.formatTag(_:)")
    static func formatTag(_ tag: UInt32) -> String {
        shared.formatTag(tag)
    }
}
