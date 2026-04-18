import Foundation

extension DCMDecoder {
    /// Convenience initializer that loads a DICOM file from the
    /// specified URL.  This is the recommended Swift-idiomatic way to
    /// create a decoder.  The file is loaded and parsed immediately;
    /// if loading fails an error is thrown.
    ///
    /// Example usage:
    ///
    ///     do {
    ///         let decoder = try DCMDecoder(contentsOf: fileURL)
    ///         let pixels = decoder.getPixels16()
    ///         // process pixels...
    ///     } catch DICOMError.fileNotFound(let path) {
    ///         print("File not found: \(path)")
    ///     } catch DICOMError.invalidDICOMFormat(let reason) {
    ///         print("Invalid DICOM: \(reason)")
    ///     } catch {
    ///         print("Unexpected error: \(error)")
    ///     }
    ///
    /// - Parameter url: File URL pointing to the DICOM file to load.
    /// - Throws: ``DICOMError/fileNotFound(path:)`` if the file does
    ///   not exist, or ``DICOMError/invalidDICOMFormat(reason:)`` if
    ///   the file cannot be parsed as valid DICOM.
    public convenience init(contentsOf url: URL) throws {
        self.init()
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw DICOMError.fileNotFound(path: path)
        }
        try loadDicomFile(at: path)
    }

    /// Convenience initializer that loads a DICOM file from the
    /// specified file path.  This is a Swift-idiomatic alternative
    /// to ``init(contentsOf:)`` for workflows that work directly with
    /// String paths instead of URL objects.  The file is loaded and
    /// parsed immediately; if loading fails an error is thrown.
    ///
    /// The initializer validates file existence and DICOM format,
    /// throwing descriptive errors if any validation fails.  Unlike
    /// the legacy ``setDicomFilename(_:)`` API, this initializer follows
    /// Swift best practices by throwing errors instead of relying on
    /// boolean success flags.  The underlying file loading mechanism is
    /// identical to ``init(contentsOf:)``.
    ///
    /// Example usage:
    ///
    ///     do {
    ///         let decoder = try DCMDecoder(contentsOfFile: "/path/to/file.dcm")
    ///         let pixels = decoder.getPixels16()
    ///         // process pixels...
    ///     } catch DICOMError.fileNotFound(let path) {
    ///         print("File not found: \(path)")
    ///     } catch DICOMError.invalidDICOMFormat(let reason) {
    ///         print("Invalid DICOM: \(reason)")
    ///     } catch {
    ///         print("Unexpected error: \(error)")
    ///     }
    ///
    /// - Parameter path: Absolute file system path to the DICOM file to load.
    /// - Throws: ``DICOMError/fileNotFound(path:)`` if the file does
    ///   not exist, or ``DICOMError/invalidDICOMFormat(reason:)`` if
    ///   the file cannot be parsed as valid DICOM.
    public convenience init(contentsOfFile path: String) throws {
        self.init()
        guard FileManager.default.fileExists(atPath: path) else {
            throw DICOMError.fileNotFound(path: path)
        }
        try loadDicomFile(at: path)
    }

    /// Static factory method that loads a DICOM file from the
    /// specified URL.  This provides an alternative to the throwing
    /// initializer for developers who prefer static factory methods.
    /// The file is loaded and parsed immediately; if loading fails
    /// an error is thrown.
    ///
    /// This method is semantically equivalent to ``init(contentsOf:)``
    /// but may be preferred in contexts where factory methods are more
    /// idiomatic (e.g., when chaining with other static methods or
    /// when explicitly showing the allocation step).
    ///
    /// Example usage:
    ///
    ///     do {
    ///         let decoder = try DCMDecoder.load(from: fileURL)
    ///         let pixels = decoder.getPixels16()
    ///         // process pixels...
    ///     } catch DICOMError.fileNotFound(let path) {
    ///         print("File not found: \(path)")
    ///     } catch DICOMError.invalidDICOMFormat(let reason) {
    ///         print("Invalid DICOM: \(reason)")
    ///     } catch {
    ///         print("Unexpected error: \(error)")
    ///     }
    ///
    /// - Parameter url: A file URL pointing to the DICOM file to load.
    /// - Returns: A `DCMDecoder` configured with metadata from the specified file.
    /// - Throws: `DICOMError.fileNotFound(path:)` if the file does not exist; `DICOMError.invalidDICOMFormat(reason:)` if the file cannot be parsed as a valid DICOM.
    public static func load(from url: URL) throws -> Self {
        try Self(contentsOf: url)
    }

    /// Static factory method for loading DICOM files from a String file path.
    ///
    /// Provides an alternative factory pattern for developers who prefer
    /// static method initialization or work primarily with String paths.
    /// This is a convenience wrapper around ``init(contentsOfFile:)`` that
    /// provides the same functionality with a factory method style.
    ///
    /// **Example:**
    ///
    ///     do {
    ///         let decoder = try DCMDecoder.load(fromFile: "/path/to/scan.dcm")
    ///         let patientName = decoder.info(for: 0x00100010)
    ///         print("Patient: \(patientName)")
    ///     } catch DICOMError.fileNotFound(let path) {
    ///         print("File not found: \(path)")
    ///     } catch DICOMError.invalidDICOMFormat(let reason) {
    ///         print("Invalid DICOM: \(reason)")
    ///     } catch {
    ///         print("Unexpected error: \(error)")
    ///     }
    ///
    /// - Parameter path: Filesystem path to the DICOM file to load.
    /// - Returns: A configured `DCMDecoder` loaded from the specified file.
    /// - Throws: `DICOMError.fileNotFound(path:)` if the file does not exist; `DICOMError.invalidDICOMFormat(reason:)` if the file cannot be parsed as a valid DICOM.
    public static func load(fromFile path: String) throws -> Self {
        try Self(contentsOfFile: path)
    }


    // MARK: - Public API

    /// Loads a DICOM file by filesystem path, parsing header/metadata only.
    ///
    /// A no-op if `filename` is empty, if the same file is already loaded, or if a different file
    /// is already loaded successfully (a warning is logged in that case). Pixel data is decoded
    /// lazily on the first `getPixels*` call.
    ///
    /// - Parameter filename: Filesystem path of the DICOM file to load.
    @available(*, deprecated, message: "Use init(contentsOf:) throws or init(contentsOfFile:) throws instead.")
    public func setDicomFilename(_ filename: String) {
        do {
            try loadDicomFile(at: filename)
        } catch {
            logger.warning("Failed to load file at \(filename): \(error)")
            synchronized {
                dicomFileName = ""
                dicomFileReadSuccess = false
            }
        }
    }

    /// Loads a DICOM file into the decoder, preserving original I/O errors for throwing APIs.
    func loadDicomFile(at filename: String) throws {
        try synchronized {
            try loadDicomFileUnsafe(at: filename)
        }
    }

    private func loadDicomFileUnsafe(at filename: String) throws {
        guard !filename.isEmpty else {
            return
        }
        // Avoid re-reading the same file
        if dicomFileName == filename {
            return
        }
        // Prevent loading different file if one is already loaded successfully
        // DCMDecoder is designed for single-file use per instance
        if dicomFileReadSuccess && !dicomFileName.isEmpty {
            logger.warning("Attempting to load '\(filename)' but decoder already has '\(dicomFileName)' loaded. Create a new DCMDecoder instance for each file.")
            return
        }

        do {
            let fileURL = URL(fileURLWithPath: filename)

            // OPTIMIZATION: Use memory-mapped reading for large files (>10MB)
            let attributes = try FileManager.default.attributesOfItem(atPath: filename)
            fileSize = attributes[.size] as? Int ?? 0

            let startTime = CFAbsoluteTimeGetCurrent()

            if fileSize > 10_000_000 { // >10MB - use memory mapping
                // Memory-mapped access for large files - dramatically faster
                dicomData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                mappedData = dicomData
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                debugPerfLog("[PERF] Memory-mapped DICOM load: \(String(format: "%.2f", elapsed))ms | size: \(fileSize/1024/1024)MB")
            } else {
                // Regular loading for smaller files
                dicomData = try Data(contentsOf: fileURL)
                mappedData = nil
            }
        } catch {
            dicomFileName = ""
            dicomFileReadSuccess = false
            throw error
        }

        // Reset state
        dicomFileReadSuccess = false
        signedImage = false
        dicomDir = false
        pixelsNotLoaded = true
        pixels8 = nil
        pixels16 = nil
        pixels24 = nil
        location = 0
        windowCenter = 0
        windowWidth = 0
        dicomInfoDict.removeAll()
        cachedInfo.removeAll()
        tagMetadataCache.removeAll()
        // Initialize binary reader with little endian by default
        reader = DCMBinaryReader(data: dicomData, littleEndian: true)
        // Initialize tag parser
        if let reader = reader {
            tagParser = DCMTagParser(data: dicomData, dict: dict, binaryReader: reader)
        }
        // Parse the header (readFileInfo is called within synchronized block)
        if readFileInfoUnsafe() {
            // Pixel payload stays lazy until first getPixels* call.
            pixelsNotLoaded = true
            dicomFileName = filename
            dicomFileReadSuccess = true
        } else {
            dicomFileName = ""
            dicomFileReadSuccess = false
            pixelsNotLoaded = true
            try throwIfLoadFailed()
        }
    }

    /// Throws `DICOMError.invalidDICOMFormat` with a descriptive reason if the last load attempt failed.
    private func throwIfLoadFailed() throws {
        guard !dicomFileReadSuccess else { return }
        let reason: String
        if !dicomFound {
            reason = "Missing DICM signature or invalid DICOM header"
        } else if width <= 0 || height <= 0 {
            reason = "Invalid image dimensions (width: \(width), height: \(height))"
        } else {
            reason = "File could not be parsed as valid DICOM"
        }
        throw DICOMError.invalidDICOMFormat(reason: reason)
    }

}
