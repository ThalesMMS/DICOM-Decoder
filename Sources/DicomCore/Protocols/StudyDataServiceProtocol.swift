//
//  StudyDataServiceProtocol.swift
//
//  Protocol abstraction for DICOM study metadata extraction and validation.
//  Defines the public API for processing DICOM files, extracting comprehensive
//  study metadata, validating file integrity, and organizing studies/series.
//  Implementations must support async operations for file I/O and provide
//  thread-safe access to all methods.
//
//  Thread Safety:
//
//  All protocol methods must be thread-safe and support concurrent access
//  from multiple threads without requiring external synchronization.
//  Async methods should handle concurrency internally.
//

import Foundation
import CoreGraphics

/// Protocol defining the public API for DICOM study data operations.
/// Implementations must handle metadata extraction, file validation,
/// study grouping, and thumbnail generation from DICOM files.
///
/// **Thread Safety:** All methods must be thread-safe and support
/// concurrent access without data races. Implementations should use
/// internal synchronization mechanisms as needed.
public protocol StudyDataServiceProtocol {

    // MARK: - Metadata Extraction

    /// Extract comprehensive study metadata from DICOM file.
    /// Parses all patient, study, series, and instance level tags
    /// from the DICOM header and returns structured metadata.
    /// Returns nil if the file is invalid or missing required tags.
    /// - Parameter filePath: Path to the DICOM file
    /// - Returns: Extracted study metadata or nil if extraction fails
    func extractStudyMetadata(from filePath: String) async -> StudyMetadata?

    /// Batch extract metadata from multiple DICOM files concurrently.
    /// Processes all files in parallel and returns successfully
    /// extracted metadata. Failed extractions are filtered out.
    /// - Parameter filePaths: Array of DICOM file paths to process
    /// - Returns: Array of extracted metadata (may be fewer than input if some fail)
    func extractBatchMetadata(from filePaths: [String]) async -> [StudyMetadata]

    // MARK: - Validation

    /// Validate DICOM file integrity and format.
    /// Performs comprehensive validation including file existence,
    /// size checks, DICOM header signature verification, and
    /// required tag validation.
    /// - Parameter filePath: Path to the DICOM file to validate
    /// - Returns: Validation result with detailed issues if any
    func validateDICOMFile(_ filePath: String) async -> DICOMValidationResult

    // MARK: - Data Transformation

    /// Create PatientModel from study metadata.
    /// Converts extracted DICOM metadata into a PatientModel
    /// structure for application use.
    /// - Parameter metadata: Study metadata to convert
    /// - Returns: PatientModel instance
    func createPatientModel(from metadata: StudyMetadata) -> PatientModel

    // MARK: - Study Organization

    /// Group studies by Study Instance UID.
    /// Organizes multiple DICOM file metadata into studies,
    /// grouping all files belonging to the same study together.
    /// - Parameter metadata: Array of study metadata to group
    /// - Returns: Dictionary mapping Study Instance UID to metadata array
    func groupStudiesByUID(_ metadata: [StudyMetadata]) -> [String: [StudyMetadata]]

    // MARK: - Thumbnail Generation

    /// Extract thumbnail data from DICOM file (first frame).
    /// Generates a downsampled image suitable for preview display.
    /// Returns nil if pixel data cannot be extracted.
    /// - Parameters:
    ///   - filePath: Path to the DICOM file
    ///   - maxSize: Maximum dimensions for thumbnail (default: 120x120)
    /// - Returns: Image data or nil if extraction fails
    func extractThumbnail(from filePath: String, maxSize: CGSize) async -> Data?
}
