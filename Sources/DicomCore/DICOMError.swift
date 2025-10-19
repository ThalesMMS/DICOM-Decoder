//
//  DICOMError.swift
//
//  Modern Swift error handling system for DICOM operations
//

import Foundation

// MARK: - DICOM Error Types

/// Comprehensive error types for DICOM operations
public enum DICOMError: Error, LocalizedError, Equatable {
    
    // MARK: - File Operation Errors
    case fileNotFound(path: String)
    case fileReadError(path: String, underlyingError: String)
    case invalidFileFormat(path: String, expectedFormat: String)
    case fileCorrupted(path: String, reason: String)
    
    // MARK: - DICOM Parsing Errors
    case invalidDICOMFormat(reason: String)
    case missingRequiredTag(tag: String, description: String)
    case unsupportedTransferSyntax(syntax: String)
    case invalidPixelData(reason: String)
    
    // MARK: - Medical Data Errors
    case invalidWindowLevel(window: Double, level: Double, reason: String)
    case invalidPatientData(field: String, value: String, reason: String)
    case missingStudyInformation(missingFields: [String])
    case invalidModality(modality: String)
    
    // MARK: - Network Errors
    case networkUnavailable
    case serverError(statusCode: Int, message: String)
    case authenticationFailed(reason: String)
    
    // MARK: - System Errors
    case memoryAllocationFailed(requestedSize: Int64)
    case imageProcessingFailed(operation: String, reason: String)
    case unknown(underlyingError: String)
    
    // MARK: - LocalizedError Implementation
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "DICOM file not found at path: \(path)"
        case .fileReadError(let path, let error):
            return "Failed to read DICOM file at \(path): \(error)"
        case .invalidFileFormat(let path, let expectedFormat):
            return "Invalid file format at \(path). Expected: \(expectedFormat)"
        case .fileCorrupted(let path, let reason):
            return "File corrupted at \(path): \(reason)"
        case .invalidDICOMFormat(let reason):
            return "Invalid DICOM format: \(reason)"
        case .missingRequiredTag(let tag, let description):
            return "Missing required DICOM tag \(tag): \(description)"
        case .unsupportedTransferSyntax(let syntax):
            return "Unsupported transfer syntax: \(syntax)"
        case .invalidPixelData(let reason):
            return "Invalid pixel data: \(reason)"
        case .invalidWindowLevel(let window, let level, let reason):
            return "Invalid window/level settings (W:\(window) L:\(level)): \(reason)"
        case .invalidPatientData(let field, let value, let reason):
            return "Invalid patient data - \(field): '\(value)' - \(reason)"
        case .missingStudyInformation(let missingFields):
            return "Missing study information: \(missingFields.joined(separator: ", "))"
        case .invalidModality(let modality):
            return "Invalid or unsupported modality: \(modality)"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .memoryAllocationFailed(let requestedSize):
            return "Memory allocation failed for \(requestedSize) bytes"
        case .imageProcessingFailed(let operation, let reason):
            return "Image processing failed during \(operation): \(reason)"
        case .unknown(let underlyingError):
            return "Unknown error: \(underlyingError)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "Please check the file path and ensure the file exists."
        case .fileReadError, .fileCorrupted:
            return "Try opening a different DICOM file or check file permissions."
        case .invalidFileFormat:
            return "Please select a valid DICOM file (.dcm, .dicom)."
        case .invalidDICOMFormat, .missingRequiredTag:
            return "This file may not be a valid DICOM image or may be corrupted."
        case .unsupportedTransferSyntax:
            return "This DICOM file uses an unsupported format. Try converting it first."
        case .invalidWindowLevel:
            return "Please enter valid window/level values or select a preset."
        case .networkUnavailable:
            return "Please check your internet connection and try again."
        case .serverError:
            return "Please try again later or contact your system administrator."
        case .memoryAllocationFailed:
            return "Close other applications to free up memory and try again."
        default:
            return "Please try again or contact support if the problem persists."
        }
    }
}

// MARK: - Error Classification Enums

/// Severity levels for DICOM errors
public enum ErrorSeverity: String, CaseIterable {
    case warning = "Warning"
    case error = "Error" 
    case critical = "Critical"
}

/// Categories for DICOM error types
public enum ErrorCategory: String, CaseIterable {
    case file = "File Operation"
    case dicom = "DICOM Processing"
    case medical = "Medical Data"
    case network = "Network"
    case system = "System"
}

// MARK: - DICOMError Extensions

extension DICOMError {
    
    // MARK: - Error Classification
    
    /// Severity level of the error
    public var severity: ErrorSeverity {
        switch self {
        case .fileNotFound, .invalidFileFormat:
            return .warning
        case .networkUnavailable:
            return .error
        case .memoryAllocationFailed:
            return .critical
        default:
            return .error
        }
    }
    
    /// Category classification of the error
    public var category: ErrorCategory {
        switch self {
        case .fileNotFound, .fileReadError, .invalidFileFormat, .fileCorrupted:
            return .file
        case .invalidDICOMFormat, .missingRequiredTag, .unsupportedTransferSyntax, .invalidPixelData:
            return .dicom
        case .invalidWindowLevel, .invalidPatientData, .missingStudyInformation, .invalidModality:
            return .medical
        case .networkUnavailable, .serverError, .authenticationFailed:
            return .network
        case .memoryAllocationFailed, .imageProcessingFailed, .unknown:
            return .system
        }
    }
}

// MARK: - Objective-C Bridge

@objc public class DICOMErrorObjC: NSError, @unchecked Sendable {
    private let swiftError: DICOMError
    
    public init(from swiftError: DICOMError) {
        self.swiftError = swiftError
        super.init(
            domain: "com.dicomviewer.error",
            code: 1001,
            userInfo: [
                NSLocalizedDescriptionKey: swiftError.localizedDescription,
                NSLocalizedRecoverySuggestionErrorKey: swiftError.recoverySuggestion ?? "Try again"
            ]
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
