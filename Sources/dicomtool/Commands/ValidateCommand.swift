//
//  ValidateCommand.swift
//
//  Command for validating DICOM file conformance
//

import Foundation
import ArgumentParser
import DicomCore

// MARK: - Validation Abstraction

protocol DICOMValidating {
    func validateDICOMFile(_ filename: String) -> (isValid: Bool, issues: [String])
}

extension DCMDecoder: DICOMValidating {}

// MARK: - Validate Command

/// Validates DICOM file conformance and reports issues.
///
/// ## Overview
///
/// ``ValidateCommand`` performs comprehensive validation checks on DICOM files including:
/// - File format and structure validation
/// - Required metadata presence
/// - Image dimensions and pixel data integrity
/// - Transfer syntax support
///
/// The command reports validation status along with any errors or warnings found.
/// Supports both human-readable text output and machine-readable JSON output
/// for automation workflows.
///
/// ## Usage
///
/// Validate a DICOM file with text output:
///
/// ```bash
/// dicomtool validate image.dcm
/// ```
///
/// Output validation results as JSON for scripting:
///
/// ```bash
/// dicomtool validate image.dcm --format json
/// ```
///
/// ## Topics
///
/// ### Command Execution
///
/// - ``run()``
///
/// ### Validation Checks
///
/// The command performs the following validation checks:
/// - File exists and is readable
/// - File size is appropriate (>= 132 bytes for DICOM preamble)
/// - DICOM file signature is present
/// - Required metadata tags are present
/// - Image dimensions are valid
/// - Pixel data is accessible
/// - Transfer syntax is supported
struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate DICOM file conformance",
        discussion: """
            Performs comprehensive validation checks on a DICOM file and reports
            any conformance issues or warnings.

            Validates file structure, required metadata, image properties, and
            pixel data accessibility. Returns exit code 0 if validation passes,
            or non-zero if validation fails.

            Supports both human-readable text output and JSON output for automation.
            """
    )

    // MARK: - Arguments

    @Argument(
        help: "Path to the DICOM file to validate",
        completion: .file(extensions: ["dcm", "dicom"])
    )
    var file: String

    // MARK: - Options

    @Option(
        name: [.short, .long],
        help: "Output format: text or json (default: text)"
    )
    var format: OutputFormat = .text

    /// Factory used to create validators, overridable in tests.
    static var makeValidator: () -> any DICOMValidating = { DCMDecoder() }

    // MARK: - Execution

    mutating func run() throws {
        // Create output formatter
        let formatter = OutputFormatter(format: format)

        // Validate file path
        let fileURL = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CLIError.fileNotReadable(
                path: file,
                reason: "File does not exist"
            )
        }

        // Perform validation using DCMDecoder
        let validationResult = Self.makeValidator().validateDICOMFile(fileURL.path)

        // Separate errors and warnings.
        // Classification is heuristic-based (message text) until upstream
        // validation exposes structured severity levels.
        var errors: [String] = []
        var warnings: [String] = []

        for issue in validationResult.issues {
            if ValidationIssueClassifier.isWarning(issue) {
                warnings.append(issue)
            } else {
                errors.append(issue)
            }
        }

        // Create validation result
        let result = ValidationResult(
            isValid: validationResult.isValid,
            errors: errors,
            warnings: warnings
        )

        // Format and output
        let output = try formatter.formatValidation(result)
        print(output)

        // Exit with error code if validation failed
        if !result.isValid {
            throw ExitCode.failure
        }
    }
}
