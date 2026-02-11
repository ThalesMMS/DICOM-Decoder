//
//  DCMDecoder+Async.swift
//
//  Async/await extensions for DCMDecoder providing modern concurrency
//  support for loading DICOM files and retrieving pixel data.
//
//  All async methods run on detached tasks with appropriate priority
//  levels to avoid blocking the main thread while preserving thread
//  safety guarantees of the underlying synchronous methods.
//

import Foundation

// MARK: - Async/Await Extensions

extension DCMDecoder {

    // MARK: - Async Throwing Initializers

    /// Asynchronously initializes a decoder by loading a DICOM file from
    /// the specified URL.  This async throwing initializer provides the
    /// same functionality as ``init(contentsOf:)`` but can be called from
    /// async contexts.
    ///
    /// The file loading is performed on a background thread using Task.detached
    /// to avoid blocking the calling thread.  For UI contexts, this provides
    /// a non-blocking alternative to the synchronous throwing initializer.
    ///
    /// Example usage:
    ///
    ///     Task {
    ///         do {
    ///             let decoder = try await DCMDecoder(contentsOf: fileURL)
    ///             let pixels = decoder.getPixels16()
    ///             // process pixels...
    ///         } catch {
    ///             print("Failed to load DICOM: \(error)")
    ///         }
    ///     }
    ///
    /// - Parameter url: File URL pointing to the DICOM file to load.
    /// - Throws: ``DICOMError/fileNotFound(path:)`` if the file does not exist,
    ///   or ``DICOMError/invalidDICOMFormat(reason:)`` if the file cannot be
    ///   parsed as valid DICOM.
    @available(macOS 10.15, iOS 13.0, *)
    public convenience init(contentsOf url: URL) async throws {
        // Initialize with default state
        self.init()

        // Perform file loading on background thread
        try await Task.detached(priority: .userInitiated) {
            // Verify file exists before attempting to load
            let path = url.path
            guard FileManager.default.fileExists(atPath: path) else {
                throw DICOMError.fileNotFound(path: path)
            }

            // Load the DICOM file using existing setDicomFilename method
            self.setDicomFilename(path)

            // Check if loading succeeded
            guard self.dicomFileReadSuccess else {
                // Provide detailed error reason if available
                let reason: String
                if !self.dicomFound {
                    reason = "Missing DICM signature or invalid DICOM header"
                } else if self.width <= 0 || self.height <= 0 {
                    reason = "Invalid image dimensions (width: \(self.width), height: \(self.height))"
                } else {
                    reason = "File could not be parsed as valid DICOM"
                }
                throw DICOMError.invalidDICOMFormat(reason: reason)
            }
        }.value
    }

    /// Asynchronously initializes a decoder by loading a DICOM file from
    /// the specified file path.  This async throwing initializer provides
    /// the same functionality as ``init(contentsOfFile:)`` but can be called
    /// from async contexts.
    ///
    /// The file loading is performed on a background thread using Task.detached
    /// to avoid blocking the calling thread.  For UI contexts, this provides
    /// a non-blocking alternative to the synchronous throwing initializer.
    ///
    /// Example usage:
    ///
    ///     Task {
    ///         do {
    ///             let decoder = try await DCMDecoder(contentsOfFile: "/path/to/file.dcm")
    ///             let pixels = decoder.getPixels16()
    ///             // process pixels...
    ///         } catch {
    ///             print("Failed to load DICOM: \(error)")
    ///         }
    ///     }
    ///
    /// - Parameter path: Absolute file system path to the DICOM file to load.
    /// - Throws: ``DICOMError/fileNotFound(path:)`` if the file does not exist,
    ///   or ``DICOMError/invalidDICOMFormat(reason:)`` if the file cannot be
    ///   parsed as valid DICOM.
    @available(macOS 10.15, iOS 13.0, *)
    public convenience init(contentsOfFile path: String) async throws {
        // Initialize with default state
        self.init()

        // Perform file loading on background thread
        try await Task.detached(priority: .userInitiated) {
            // Verify file exists before attempting to load
            guard FileManager.default.fileExists(atPath: path) else {
                throw DICOMError.fileNotFound(path: path)
            }

            // Load the DICOM file using existing setDicomFilename method
            self.setDicomFilename(path)

            // Check if loading succeeded
            guard self.dicomFileReadSuccess else {
                // Provide detailed error reason if available
                let reason: String
                if !self.dicomFound {
                    reason = "Missing DICM signature or invalid DICOM header"
                } else if self.width <= 0 || self.height <= 0 {
                    reason = "Invalid image dimensions (width: \(self.width), height: \(self.height))"
                } else {
                    reason = "File could not be parsed as valid DICOM"
                }
                throw DICOMError.invalidDICOMFormat(reason: reason)
            }
        }.value
    }

    // MARK: - Async Static Factory Methods

    /// Asynchronously loads a DICOM file from the specified URL using a
    /// static factory method pattern.  This async throwing factory method
    /// provides the same functionality as ``load(from:)`` but can be called
    /// from async contexts.
    ///
    /// This is a convenience wrapper around ``init(contentsOf:)`` that provides
    /// the same functionality with a factory method style.  The file loading is
    /// performed on a background thread using Task.detached to avoid blocking
    /// the calling thread.
    ///
    /// Example usage:
    ///
    ///     Task {
    ///         do {
    ///             let decoder = try await DCMDecoder.load(from: fileURL)
    ///             let pixels = decoder.getPixels16()
    ///             // process pixels...
    ///         } catch {
    ///             print("Failed to load DICOM: \(error)")
    ///         }
    ///     }
    ///
    /// - Parameter url: File URL pointing to the DICOM file to load.
    /// - Returns: Initialized DCMDecoder instance with the loaded DICOM file.
    /// - Throws: ``DICOMError/fileNotFound(path:)`` if the file does not exist,
    ///   or ``DICOMError/invalidDICOMFormat(reason:)`` if the file cannot be
    ///   parsed as valid DICOM.
    @available(macOS 10.15, iOS 13.0, *)
    public static func load(from url: URL) async throws -> Self {
        try await Self(contentsOf: url)
    }

    /// Asynchronously loads a DICOM file from the specified file path using a
    /// static factory method pattern.  This async throwing factory method
    /// provides the same functionality as ``load(fromFile:)`` but can be called
    /// from async contexts.
    ///
    /// This is a convenience wrapper around ``init(contentsOfFile:)`` that provides
    /// the same functionality with a factory method style.  The file loading is
    /// performed on a background thread using Task.detached to avoid blocking
    /// the calling thread.
    ///
    /// Example usage:
    ///
    ///     Task {
    ///         do {
    ///             let decoder = try await DCMDecoder.load(fromFile: "/path/to/file.dcm")
    ///             let pixels = decoder.getPixels16()
    ///             // process pixels...
    ///         } catch {
    ///             print("Failed to load DICOM: \(error)")
    ///         }
    ///     }
    ///
    /// - Parameter path: Absolute file system path to the DICOM file to load.
    /// - Returns: Initialized DCMDecoder instance with the loaded DICOM file.
    /// - Throws: ``DICOMError/fileNotFound(path:)`` if the file does not exist,
    ///   or ``DICOMError/invalidDICOMFormat(reason:)`` if the file cannot be
    ///   parsed as valid DICOM.
    @available(macOS 10.15, iOS 13.0, *)
    public static func load(fromFile path: String) async throws -> Self {
        try await Self(contentsOfFile: path)
    }

    // MARK: - Async File Loading Methods

    /// Loads and decodes a DICOM file asynchronously
    /// - Parameter filename: Path to the DICOM file
    /// - Returns: True if the file was successfully loaded and decoded
    @available(macOS 10.15, iOS 13.0, *)
    public func loadDICOMFileAsync(_ filename: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                self.setDicomFilename(filename)
                continuation.resume(returning: self.dicomFileReadSuccess)
            }
        }
    }

    // MARK: - Async Pixel Retrieval Methods

    /// Retrieves 16-bit pixels asynchronously
    /// - Returns: Array of 16-bit pixel values or nil
    @available(macOS 10.15, iOS 13.0, *)
    public func getPixels16Async() async -> [UInt16]? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                continuation.resume(returning: self.getPixels16())
            }
        }
    }

    /// Retrieves 8-bit pixels asynchronously
    /// - Returns: Array of 8-bit pixel values or nil
    @available(macOS 10.15, iOS 13.0, *)
    public func getPixels8Async() async -> [UInt8]? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                continuation.resume(returning: self.getPixels8())
            }
        }
    }

    /// Retrieves 24-bit RGB pixels asynchronously
    /// - Returns: Array of 24-bit pixel values or nil
    @available(macOS 10.15, iOS 13.0, *)
    public func getPixels24Async() async -> [UInt8]? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                continuation.resume(returning: self.getPixels24())
            }
        }
    }

    /// Retrieves downsampled thumbnail pixels asynchronously
    /// - Parameter maxDimension: Maximum dimension for the thumbnail
    /// - Returns: Tuple with downsampled pixels and dimensions, or nil
    @available(macOS 10.15, iOS 13.0, *)
    public func getDownsampledPixels16Async(maxDimension: Int = 150) async -> (pixels: [UInt16], width: Int, height: Int)? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                continuation.resume(returning: self.getDownsampledPixels16(maxDimension: maxDimension))
            }
        }
    }

    /// Retrieves downsampled 8-bit thumbnail pixels asynchronously
    /// - Parameter maxDimension: Maximum dimension for the thumbnail
    /// - Returns: Tuple with downsampled pixels and dimensions, or nil
    @available(macOS 10.15, iOS 13.0, *)
    public func getDownsampledPixels8Async(maxDimension: Int = 150) async -> (pixels: [UInt8], width: Int, height: Int)? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                continuation.resume(returning: self.getDownsampledPixels8(maxDimension: maxDimension))
            }
        }
    }
}
