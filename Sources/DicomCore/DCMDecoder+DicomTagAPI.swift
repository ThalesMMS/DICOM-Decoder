//
//  DCMDecoder+DicomTagAPI.swift
//
//  Type-safe DicomTag overloads for DCMDecoder.
//

import Foundation

extension DCMDecoder {

    /// Retrieves the value of a parsed header as a string using DicomTag enum.
    /// Provides type-safe access to common DICOM tags without requiring hex values.
    ///
    /// - Parameter tag: The DICOM tag enum case (e.g., .patientName, .modality)
    /// Retrieves the value of a parsed DICOM header entry identified by the given tag.
    /// - Parameter tag: The DICOM tag to look up.
    /// - Returns: The header value as a `String`; an empty string if the tag is not found.
    public func info(for tag: DicomTag) -> String {
        info(for: tag.rawValue)
    }

    /// Retrieves an integer value for a DICOM tag using DicomTag enum.
    ///
    /// - Parameter tag: The DICOM tag enum case (e.g., .rows, .columns)
    /// Retrieve the integer value for the given DICOM tag.
    /// - Parameters:
    ///   - tag: The `DicomTag` to look up in the decoded header.
    /// - Returns: The `Int` value associated with `tag`, or `nil` if the tag is missing or cannot be parsed as an integer.
    public func intValue(for tag: DicomTag) -> Int? {
        intValue(for: tag.rawValue)
    }

    /// Retrieves a double value for a DICOM tag using DicomTag enum.
    ///
    /// - Parameter tag: The DICOM tag enum case (e.g., .windowCenter, .windowWidth)
    /// Retrieves the `Double` value associated with the specified `DicomTag`.
    /// - Parameter tag: The DICOM tag to look up.
    /// - Returns: The `Double` value for `tag`, or `nil` if the tag is missing or the value cannot be parsed.
    public func doubleValue(for tag: DicomTag) -> Double? {
        doubleValue(for: tag.rawValue)
    }
}
