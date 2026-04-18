//
//  DCMDecoder+Validation.swift
//
//  Validation helpers for DCMDecoder.
//

import Foundation

extension DCMDecoder {

    /// Validates DICOM file structure and required tags
    /// - Parameter filename: Path to the DICOM file
    /// Performs basic filesystem and header-level validation of a DICOM file at the given path.
    /// 
    /// The check includes file existence, readable file attributes, file size (empty or too small),
    /// and — when the file is at least 132 bytes — an attempt to read the 4-byte `DICM` signature at offset 128.
    /// - Parameters:
    ///   - filename: Path to the DICOM file to validate.
    /// - Returns: A tuple where `isValid` is `true` if no hard issues were detected, and `issues` is an array of
    ///   human-readable issues and warnings found during validation.
    public func validateDICOMFile(_ filename: String) -> (isValid: Bool, issues: [String]) {
        synchronized {
            var issues: [String] = []
            var warnings: [String] = []

            guard FileManager.default.fileExists(atPath: filename) else {
                return (false, ["File does not exist"])
            }

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: filename),
                  let fileSize = attributes[.size] as? Int else {
                return (false, ["Cannot read file attributes"])
            }

            if fileSize == 0 {
                issues.append("File is empty")
            } else if fileSize < 132 {
                warnings.append("File smaller than 132 bytes; DICOM preamble may be missing")
            }

            if fileSize >= 132 {
                if let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: filename)) {
                    defer { try? handle.close() }
                    do {
                        try handle.seek(toOffset: 128)
                        let bytes: Data
                        if #available(iOS 13.4, macOS 10.15.4, *) {
                            bytes = try handle.read(upToCount: 4) ?? Data()
                        } else {
                            bytes = handle.readData(ofLength: 4)
                        }
                        if bytes.count == 4 && bytes != Data([0x44, 0x49, 0x43, 0x4D]) {
                            warnings.append("Missing DICM signature at offset 128 (preamble optional)")
                        } else if bytes.count < 4 {
                            warnings.append("Could not read full DICM signature (preamble optional)")
                        }
                    } catch {
                        warnings.append("Could not read DICM signature (preamble optional)")
                    }
                } else {
                    warnings.append("Could not open file for validation")
                }
            }

            let isValid = issues.isEmpty
            return (isValid, issues + warnings)
        }
    }

    /// Checks if the decoder has successfully read and parsed the DICOM file
    /// Indicates whether the decoder currently considers the loaded DICOM file structurally valid.
    /// - Returns: `true` if a DICOM file was successfully read, a DICOM dataset was found, and both `width` and `height` are greater than zero; `false` otherwise.
    public func isValid() -> Bool {
        synchronized {
            dicomFileReadSuccess && dicomFound && width > 0 && height > 0
        }
    }

    /// Returns validation and pixel-related status for the currently loaded DICOM file.
    /// - Returns: A tuple containing:
    ///   - isValid: `true` if the decoder successfully read and found a DICOM file, `false` otherwise.
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    ///   - hasPixels: `true` if decoded pixel buffers are present or a pixel payload is available, `false` otherwise.
    ///   - isCompressed: `true` if the image is stored compressed, `false` otherwise.
    public func getValidationStatus() -> (isValid: Bool, width: Int, height: Int, hasPixels: Bool, isCompressed: Bool) {
        synchronized {
            let hasDecodedPixels = hasDecodedPixelBuffers()
            let hasPixelPayload = dicomFileReadSuccess && offset > 0
            let hasPixels = hasDecodedPixels || hasPixelPayload
            let valid = dicomFileReadSuccess && dicomFound && width > 0 && height > 0
            return (valid, width, height, hasPixels, compressedImage)
        }
    }
}
