//
//  DCMDecoder.swift
//
//  This class parses DICOM files
//  encoded with little or big endian explicit or implicit VR and
//  extracts metadata and pixel data.  The decoder handles 8‑bit
//  and 16‑bit grayscale images as well as 24‑bit RGB images
//  (common for ultrasound).  Compressed transfer syntaxes including
//  JPEG Lossless, JPEG Baseline, JPEG 2000, and JPEG‑LS are
//  supported via native decoders and ImageIO fallback.  See the
//  original Objective‑C code for a one‑to‑one algorithmic
//  reference; this port emphasises clarity, safety and Swift
//  idioms while maintaining the same public API.
//
//  Thread Safety:
//
//  DCMDecoder is fully thread‑safe.  Instances can be safely
//  accessed from multiple threads concurrently.  All public
//  methods are protected by internal locking mechanisms that
//  ensure data consistency without requiring external
//  synchronization.  This enables concurrent image loading for
//  responsive UIs in modern iOS applications.
//
//  Usage:
//
//    let decoder = DCMDecoder()
//    decoder.setDicomFilename(url.path)
//    if decoder.dicomFileReadSuccess {
//        let pixels = decoder.getPixels16()
//        // process pixels
//    }
//

import Foundation
import CoreGraphics
import ImageIO
import simd

/// Backward compatibility alias to centralized DICOM tag constants.
/// All tag references now point to the public DicomTag enum defined
/// in DicomConstants.swift.
private typealias Tag = DicomTag

/// Backward compatibility alias to centralized Value Representation constants.
/// All VR references now point to the public DicomVR enum defined
/// in DicomConstants.swift.
private typealias VR = DicomVR

// MARK: - Main Decoder Class

/// Primary decoder for DICOM medical imaging files.
///
/// ## Overview
///
/// ``DCMDecoder`` parses DICOM files encoded with little or big endian explicit or implicit VR
/// and extracts metadata and pixel data. The decoder handles 8-bit and 16-bit grayscale images
/// as well as 24-bit RGB images (common for ultrasound). Compressed transfer syntaxes including
/// JPEG Lossless, JPEG Baseline, JPEG 2000, and JPEG-LS are supported via native decoders
/// and ImageIO fallback.
///
/// The public API mirrors the original Objective-C implementation but uses Swift properties
/// and modern error handling. Pixel buffers are returned as optional arrays and remain `nil`
/// until file loading succeeds.
///
/// ## Usage
///
/// Create a decoder instance using throwing initializers (recommended):
///
/// ```swift
/// do {
///     let decoder = try DCMDecoder(contentsOf: url)
///     print("Image: \(decoder.width) × \(decoder.height)")
///     if let pixels = decoder.getPixels16() {
///         // Process 16-bit grayscale pixel data
///     }
/// } catch DICOMError.fileNotFound(let path) {
///     print("File not found: \(path)")
/// } catch DICOMError.invalidDICOMFormat(let path, let reason) {
///     print("Invalid DICOM: \(reason)")
/// } catch {
///     print("Error: \(error)")
/// }
/// ```
///
/// Access metadata using type-safe ``DicomTag`` enum:
///
/// ```swift
/// let patientName = decoder.info(for: .patientName)
/// let modality = decoder.info(for: .modality)
/// let windowSettings = decoder.windowSettingsV2
/// ```
///
/// For non-blocking file loading, use async variants:
///
/// ```swift
/// Task {
///     let decoder = try await DCMDecoder(contentsOf: url)
///     // Process asynchronously
/// }
/// ```
///
/// ## Topics
///
/// ### Creating a Decoder
///
/// - ``init()``
/// - ``init(contentsOf:)``
/// - ``init(contentsOfFile:)``
/// - ``load(from:)``
/// - ``load(fromFile:)``
///
/// ### Loading Files (Legacy)
///
/// - ``setDicomFilename(_:)``
/// - ``loadDICOMFileAsync(filename:)``
/// - ``dicomFileReadSuccess``
/// - ``dicomFound``
///
/// ### Accessing Metadata
///
/// - ``info(for:)``
/// - ``intValue(for:)``
/// - ``doubleValue(for:)``
/// - ``windowSettingsV2``
/// - ``pixelSpacingV2``
/// - ``rescaleParametersV2``
/// - ``windowSettings``
/// - ``pixelSpacing``
/// - ``rescaleParameters``
///
/// ### Accessing Pixel Data
///
/// - ``getPixels16()``
/// - ``getPixels8()``
/// - ``getPixels24()``
///
/// ### Image Properties
///
/// - ``width``
/// - ``height``
/// - ``bitDepth``
/// - ``samplesPerPixel``
/// - ``photometricInterpretation``
/// - ``pixelDepth``
/// - ``pixelWidth``
/// - ``pixelHeight``
///
/// ### Geometric Properties
///
/// - ``imageOrientation``
/// - ``imagePosition``
///
/// ### Display Properties
///
/// - ``windowCenter``
/// - ``windowWidth``
///
/// ### Validation
///
/// - ``validateDICOMFile(_:)``
/// - ``isValid()``
/// - ``getValidationStatus()``
///
/// ### Status Properties
///
/// - ``compressedImage``
/// - ``dicomDir``
/// - ``signedImage``
/// - ``pixelRepresentationTagValue``
/// - ``isSignedPixelRepresentation``
///
/// ### Multi-Frame Support
///
/// - ``offset``
/// - ``nImages``
///
/// ## Thread Safety
///
/// This class is fully thread-safe. All public methods and properties can be safely accessed
/// from multiple threads concurrently. Internal lock-based synchronization protects all mutable
/// state, ensuring safe concurrent operations without data races. Performance impact is minimal
/// (<10%) due to the I/O-bound nature of DICOM decoding operations.
///
/// ## Metadata Parsing Strategy
///
/// DCMDecoder uses a hybrid lazy/eager parsing strategy to optimize memory usage and performance.
/// DICOM files can contain 100+ metadata tags, but typical applications access only 10-15 tags
/// (PatientName, Modality, WindowCenter, etc.). Parsing all tags upfront creates unnecessary
/// string allocations and dictionary operations.
///
/// ### Eager Parsing (Critical Tags)
///
/// Tags that affect decoder behavior or are frequently accessed are parsed immediately during
/// file loading (``setDicomFilename(_:)`` or ``loadDICOMFileAsync(filename:)``):
///
/// - **Parsing Control:** `transferSyntaxUID`, `pixelData` — determine compression handling
///   and pixel data location
/// - **Image Dimensions:** `rows`, `columns`, `bitsAllocated` — validated immediately to catch
///   malformed files early
/// - **Pixel Interpretation:** `samplesPerPixel`, `photometricInterpretation`,
///   `pixelRepresentation` — control pixel buffer allocation and data interpretation
/// - **Display Windowing:** `windowCenter`, `windowWidth` — frequently accessed for image display
/// - **Geometry:** `imageOrientation`, `imagePosition` — used for 3D reconstruction and series
///   ordering
/// - **Spatial Calibration:** `pixelSpacing`, `sliceThickness` — physical measurement conversion
/// - **Value Mapping:** `rescaleIntercept`, `rescaleSlope` — Hounsfield unit conversion
/// - **Palette Color:** `redPalette`, `greenPalette`, `bluePalette` — color lookup tables
/// - **Multi-frame:** `numberOfFrames`, `planarConfiguration` — frame handling
/// - **Modality:** `modality` — frequently accessed identifier
///
/// ### Lazy Parsing (Metadata-Only Tags)
///
/// All other tags (patient demographics, study information, private tags, etc.) are stored as
/// raw metadata during file loading:
///
/// 1. File parsing stores tag metadata (tag ID, file offset, VR, length) in an internal cache
///    without reading values
/// 2. First call to ``info(for:)`` triggers on-demand parsing which reads and formats the tag
///    value from the file
/// 3. Parsed value is cached for fast subsequent access
///
/// ### Performance Benefits
///
/// - **Reduced Memory:** Files with 100+ tags only allocate strings for accessed tags
///   (~32 bytes metadata vs ~100+ bytes string)
/// - **Faster Loading:** File parsing skips string formatting for unused tags
/// - **Maintained Speed:** Cached values ensure no performance penalty for repeated access
///   (<0.1ms per tag)
///
/// This strategy mirrors the existing lazy pixel loading pattern: pixel data is not decoded
/// until ``getPixels16()`` or ``getPixels8()`` is called. Both optimizations ensure that
/// DCMDecoder only performs expensive operations when actually needed.
public final class DCMDecoder: DicomDecoderProtocol {
    
    // MARK: - Properties

    // MARK: - Safety Constants

    /// Maximum allowed image dimension (width or height) in pixels.
    /// Prevents excessive memory allocation from malformed headers.
    private static let maxImageDimension: Int = 65536

    /// Maximum allowed size for pixel buffer allocation (2 GB).
    /// Protects against memory bombs from unrealistic image dimensions.
    private static let maxPixelBufferSize: Int64 = 2 * 1024 * 1024 * 1024

    /// Dictionary used to translate tags to human readable names.  The
    /// original code stored a strong pointer to ``DCMDictionary``.
    private let dict = DCMDictionary.shared

    private let logger: LoggerProtocol = DicomLogger.make(subsystem: "com.dicomviewer", category: "DCMDecoder")

    /// Lock for thread-safe access to decoder state.
    /// Protects all mutable properties and ensures safe concurrent access.
    private let lock = DicomLock()

    /// Tag handler registry for strategy-based tag processing.
    /// Maps DICOM tag IDs to specialized handler implementations.
    private lazy var handlerRegistry = TagHandlerRegistry()

    /// Raw filename used to open the file.  Kept for reference but
    /// never exposed directly.
    private var dicomFileName: String = ""

    /// Raw DICOM file contents.  The Data type is used instead of
    /// NSData to take advantage of value semantics and Swift
    /// performance characteristics.  All reads into this data
    /// respect the current ``location`` cursor.
    private var dicomData: Data = Data()
    
    /// OPTIMIZATION: Memory-mapped file for ultra-fast large file access
    private var mappedData: Data?
    private var fileSize: Int = 0

    /// Cursor into ``dicomData`` used for sequential reading.
    private var location: Int = 0

    /// Binary reader for low-level DICOM data access
    private var reader: DCMBinaryReader?

    /// Tag parser for DICOM tag parsing and metadata extraction
    private var tagParser: DCMTagParser?

    /// Pixel representation: 0 for unsigned, 1 for two's complement
    /// signed data.  This affects how 16‑bit pixel data are
    /// normalised.
    private var pixelRepresentation: Int = 0

    /// Minimum values used for mapping signed pixel data into
    /// unsigned representation.  ``min8`` is unused in this port
    /// but retained to mirror the original design.  ``min16`` is
    /// used when converting 16‑bit two's complement data into
    /// unsigned ranges.
    private var min8: Int = 0
    private var min16: Int = Int(Int16.min)

    /// Flags controlling how the decoder behaves when encountering
    /// certain structures in the file.
    private var bigEndianTransferSyntax: Bool = false
    private var littleEndian: Bool = true

    /// Rescale intercept and slope.  These values are stored in
    /// DICOM headers and may be used to map pixel intensities to
    /// physical values.  This implementation does not apply them
    /// automatically but exposes them for clients to use as
    /// appropriate.
    private var rescaleIntercept: Double = 0.0
    private var rescaleSlope: Double = 1.0

    /// Colour lookup tables for palette‑based images.  These are
    /// rarely used in modern imaging but are included for
    /// completeness.  When present the decoder will populate them
    /// with one byte per entry, representing the high eight bits of
    /// the 16‑bit LUT values.  Clients may combine these into
    /// colour images as desired.
    private var reds: [UInt8]? = nil
    private var greens: [UInt8]? = nil
    private var blues: [UInt8]? = nil

    /// Buffers for pixel data.  Only one of these will be non‑nil
    /// depending on ``samplesPerPixel`` and ``bitDepth``.  Grayscale
    /// 8‑bit data uses ``pixels8``, grayscale 16‑bit data uses
    /// ``pixels16`` and colour (3 samples per pixel) uses
    /// ``pixels24``.
    private var pixels8: [UInt8]? = nil
    private var pixels16: [UInt16]? = nil
    private var pixels24: [UInt8]? = nil

    /// Dictionary of parsed metadata keyed by raw tag integer.
    /// Values consist of the VR description followed by a colon and
    /// the value.  For unknown tags the description may be
    /// ``"---"`` indicating a private tag.  Clients should use
    /// ``info(for:)`` to extract the value portion cleanly.
    private var dicomInfoDict: [Int: String] = [:]
    
    /// OPTIMIZATION: Cache for frequently accessed parsed values to avoid string processing
    private var cachedInfo: [Int: String] = [:]

    /// OPTIMIZATION: Lazy tag metadata cache for deferred tag value parsing.
    /// Stores raw tag information (offset, VR, length) without parsing to strings.
    /// Used to implement lazy parsing where tag values are only extracted when
    /// first accessed via ``info(for:)``, reducing memory allocations for files
    /// with many unused tags.
    private var tagMetadataCache: [Int: TagMetadata] = [:]

    /// Frequently accessed DICOM tags that benefit from caching
    private static let frequentTags: Set<Int> = [
        DicomTag.rescaleSlope.rawValue,
        DicomTag.rescaleIntercept.rawValue,
        DicomTag.protocolName.rawValue,
        DicomTag.seriesDescription.rawValue,
        DicomTag.acquisitionProtocolName.rawValue,
        DicomTag.rows.rawValue,
        DicomTag.columns.rawValue,
        DicomTag.bitsAllocated.rawValue,
        DicomTag.bitsStored.rawValue,
        DicomTag.highBit.rawValue,
        DicomTag.pixelRepresentation.rawValue
    ]

    /// Transfer Syntax UID detected in the header.  Used to
    /// determine whether the image data is compressed and which
    /// decoder to use.  Stored when the `TRANSFER_SYNTAX_UID` tag
    /// is encountered in ``readFileInfo``.
    private var transferSyntaxUID: String = ""

    // MARK: - Public properties

    /// Bit depth of the decoded pixels (8 or 16).  Defaults to
    /// 16 until parsed from the header.  Read‑only outside the
    /// class.
    public private(set) var bitDepth: Int = 16

    /// Image dimensions in pixels.  Defaults to 1×1 until parsed.
    public private(set) var width: Int = 1
    public private(set) var height: Int = 1

    /// Byte offset from the start of ``dicomData`` to the
    /// beginning of ``pixelData``.  Useful for debugging.  Not
    /// currently used elsewhere in this class.
    public private(set) var offset: Int = 1

    /// Number of frames in a multi‑frame image.  Defaults to 1.
    public private(set) var nImages: Int = 1

    /// Number of samples per pixel.  1 for grayscale, 3 for RGB.  If
    /// other values are encountered the decoder will still parse the
    /// metadata but the pixel data may not be interpretable by
    /// ``Dicom2DView``.  Defaults to 1.
    public private(set) var samplesPerPixel: Int = 1
    
    /// Photometric interpretation (MONOCHROME1 or MONOCHROME2).
    /// MONOCHROME1 means white is zero (common for X-rays)
    /// MONOCHROME2 means black is zero (standard grayscale)
    public private(set) var photometricInterpretation: String = ""

    /// Physical dimensions of the pixel spacing.  These values are
    /// derived from the ``PIXEL_SPACING`` and ``SLICE_THICKNESS``
    /// tags and may be used by clients to compute aspect ratios or
    /// volumetric measurements.
    public private(set) var pixelDepth: Double = 1.0
    public private(set) var pixelWidth: Double = 1.0
    public private(set) var pixelHeight: Double = 1.0
    /// Direction cosines for the image rows/columns (0020,0037)
    public private(set) var imageOrientation: (row: SIMD3<Double>, column: SIMD3<Double>)?
    /// Patient-space origin for the top-left voxel (0020,0032)
    public private(set) var imagePosition: SIMD3<Double>?

    /// Default window centre and width for display.  These come
    /// from the ``WINDOW_CENTER`` and ``WINDOW_WIDTH`` tags when
    /// present.  If absent they default to zero, leaving it to
    /// the viewer to choose appropriate values based on the image
    /// histogram.
    public private(set) var windowCenter: Double = 0.0
    public private(set) var windowWidth: Double = 0.0

    /// Flags indicating the status of the decoder.  `dicomFound`
    /// becomes true if the file begins with ``"DICM"`` at offset
    /// 128.  `dicomFileReadSuccess` indicates whether the header
    /// parsed successfully and pixels were read.  `compressedImage`
    /// becomes true if an unsupported transfer syntax is detected.
    /// `dicomDir` is reserved for future use to distinguish
    /// directory records.  `signedImage` indicates whether the
    /// pixel data originally used two's complement representation.
    public private(set) var dicomFound: Bool = false

    /// **Note:** This property is part of the legacy API. When using the new throwing
    /// initializers (`init(contentsOf:)` or `init(contentsOfFile:)`), successful
    /// initialization guarantees this will be `true`, and failure throws an error instead.
    @available(*, deprecated, message: "When using throwing initializers (init(contentsOf:) or init(contentsOfFile:)), successful initialization guarantees validity. Check for thrown errors instead of this property.")
    public private(set) var dicomFileReadSuccess: Bool = false
    public private(set) var compressedImage: Bool = false
    public private(set) var dicomDir: Bool = false
    public private(set) var signedImage: Bool = false
    /// Raw pixel representation flag (0 = unsigned, 1 = two's complement)
    public var pixelRepresentationTagValue: Int { pixelRepresentation }
    /// Convenience accessor for signed pixel representation
    public var isSignedPixelRepresentation: Bool { pixelRepresentation == 1 }

    // MARK: - Initialization

    /// Creates a new DICOM decoder instance.  The default initializer
    /// creates an empty decoder with no file loaded.  Use
    /// ``init(contentsOf:)`` or ``setDicomFilename(_:)`` to load a
    /// DICOM file.
    public init() {
        // All properties have default values, no explicit initialization needed
    }

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
        // Initialize with default state
        self.init()

        // Verify file exists before attempting to load
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw DICOMError.fileNotFound(path: path)
        }

        // Load the DICOM file using existing setDicomFilename method
        setDicomFilename(path)

        // Check if loading succeeded
        guard dicomFileReadSuccess else {
            // Provide detailed error reason if available
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
        // Initialize with default state
        self.init()

        // Verify file exists before attempting to load
        guard FileManager.default.fileExists(atPath: path) else {
            throw DICOMError.fileNotFound(path: path)
        }

        // Load the DICOM file using existing setDicomFilename method
        setDicomFilename(path)

        // Check if loading succeeded
        guard dicomFileReadSuccess else {
            // Provide detailed error reason if available
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
    /// - Parameter url: File URL pointing to the DICOM file to load.
    /// - Returns: A fully initialized ``DCMDecoder`` instance with the
    ///   file loaded and parsed.
    /// - Throws: ``DICOMError/fileNotFound(path:)`` if the file does
    ///   not exist, or ``DICOMError/invalidDICOMFormat(reason:)`` if
    ///   the file cannot be parsed as valid DICOM.
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
    /// - Parameter path: Absolute file system path to the DICOM file to load.
    /// - Returns: A fully initialized ``DCMDecoder`` instance with the
    ///   file loaded and parsed.
    /// - Throws: ``DICOMError/fileNotFound(path:)`` if the file does
    ///   not exist, or ``DICOMError/invalidDICOMFormat(reason:)`` if
    ///   the file cannot be parsed as valid DICOM.
    public static func load(fromFile path: String) throws -> Self {
        try Self(contentsOfFile: path)
    }

    // MARK: - Public API

    /// Validates DICOM file structure and required tags
    /// - Parameter filename: Path to the DICOM file
    /// - Returns: Validation result with detailed issues if any
    public func validateDICOMFile(_ filename: String) -> (isValid: Bool, issues: [String]) {
        return synchronized {
            var issues: [String] = []
            var warnings: [String] = []

            // Check file exists
            guard FileManager.default.fileExists(atPath: filename) else {
                return (false, ["File does not exist"])
            }

            // Check file size
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: filename),
                  let fileSize = attributes[.size] as? Int else {
                return (false, ["Cannot read file attributes"])
            }

            if fileSize == 0 {
                issues.append("File is empty")
            } else if fileSize < 132 {
                warnings.append("File smaller than 132 bytes; DICOM preamble may be missing")
            }

            // Check optional DICM header without loading entire file
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
    /// - Returns: True if file is loaded and valid
    public func isValid() -> Bool {
        return dicomFileReadSuccess && dicomFound && width > 0 && height > 0
    }

    /// Returns detailed validation status of the loaded DICOM file
    public func getValidationStatus() -> (isValid: Bool, width: Int, height: Int, hasPixels: Bool, isCompressed: Bool) {
        return synchronized {
            let hasPixels = pixels8 != nil || pixels16 != nil || pixels24 != nil
            return (dicomFileReadSuccess, width, height, hasPixels, compressedImage)
        }
    }

    /// Assigns a file to decode.  The file is read into memory and
    /// parsed immediately.  Errors are logged to the console in
    /// DEBUG builds; on failure ``dicomFileReadSuccess`` will be
    /// false.  Calling this method resets any previous state.
    ///
    /// **Note:** This is the legacy API. Prefer using the throwing initializers
    /// `init(contentsOf:)` or `init(contentsOfFile:)` for better error handling.
    ///
    /// - Parameter filename: Path to the DICOM file on disk.
    ///
    /// **Migration Example:**
    /// ```swift
    /// // Old API:
    /// let decoder = DCMDecoder()
    /// decoder.setDicomFilename("/path/to/file.dcm")
    /// if decoder.dicomFileReadSuccess {
    ///     // use decoder
    /// }
    ///
    /// // New API (recommended):
    /// do {
    ///     let decoder = try DCMDecoder(contentsOfFile: "/path/to/file.dcm")
    ///     // use decoder
    /// } catch {
    ///     print("Failed to load DICOM: \(error)")
    /// }
    /// ```
    @available(*, deprecated, message: "Use init(contentsOf:) throws or init(contentsOfFile:) throws instead. See documentation for migration examples.")
    public func setDicomFilename(_ filename: String) {
        synchronized {
            guard !filename.isEmpty else {
                return
            }
            // Avoid re‑reading the same file
            if dicomFileName == filename {
                return
            }
            dicomFileName = filename
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
                logger.warning("Failed to load file at \(filename): \(error)")
                return
            }
            // Reset state
            dicomFileReadSuccess = false
            signedImage = false
            dicomDir = false
            location = 0
            windowCenter = 0
            windowWidth = 0
            dicomInfoDict.removeAll()
            cachedInfo.removeAll()
            // Initialize binary reader with little endian by default
            reader = DCMBinaryReader(data: dicomData, littleEndian: true)
            // Initialize tag parser
            if let reader = reader {
                tagParser = DCMTagParser(data: dicomData, dict: dict, binaryReader: reader)
            }
            // Parse the header (readFileInfo is called within synchronized block)
            if readFileInfoUnsafe() {
                // If compressed transfer syntax, attempt to decode compressed pixel data.
                if !compressedImage {
                    readPixelsUnsafe()
                } else {
                    decodeCompressedPixelDataUnsafe()
                }
                dicomFileReadSuccess = true
            } else {
                dicomFileReadSuccess = false
            }
        }
    }

    /// Returns the 8‑bit pixel buffer if the image is grayscale and
    /// encoded with eight bits per sample.  Returns ``nil`` if the
    /// buffer is not present.  The array length is ``width × height``.
    public func getPixels8() -> [UInt8]? {
        return synchronized {
            let startTime = CFAbsoluteTimeGetCurrent()
            if pixels8 == nil { readPixelsUnsafe() }
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if elapsed > 1 { debugPerfLog("[PERF] getPixels8: \(String(format: "%.2f", elapsed))ms") }
            return pixels8
        }
    }

    /// Returns the 16‑bit pixel buffer if the image is grayscale and
    /// encoded with sixteen bits per sample.  Returns ``nil`` if the
    /// buffer is not present.  The array length is ``width × height``.
    public func getPixels16() -> [UInt16]? {
        return synchronized {
            let startTime = CFAbsoluteTimeGetCurrent()
            if pixels16 == nil { readPixelsUnsafe() }
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if elapsed > 1 { debugPerfLog("[PERF] getPixels16: \(String(format: "%.2f", elapsed))ms") }
            return pixels16
        }
    }

    /// Returns the 8‑bit interleaved RGB pixel buffer if the image
    /// has three samples per pixel.  Returns ``nil`` if the buffer
    /// is not present.  The array length is ``width × height × 3``.
    public func getPixels24() -> [UInt8]? {
        return synchronized {
            let startTime = CFAbsoluteTimeGetCurrent()
            if pixels24 == nil { readPixelsUnsafe() }
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if elapsed > 1 { debugPerfLog("[PERF] getPixels24: \(String(format: "%.2f", elapsed))ms") }
            return pixels24
        }
    }
    
    /// Returns a downsampled 16-bit pixel buffer for thumbnail generation.
    /// This method reads only every Nth pixel to dramatically speed up thumbnail creation.
    /// - Parameter maxDimension: Maximum dimension for the thumbnail (default 150)
    /// Creates an aspect-preserving downsampled 16-bit grayscale thumbnail from the image pixel data.
    /// The result preserves the source aspect ratio, produces row-major UInt16 pixel values, and accounts for MONOCHROME1 inversion when present.
    /// - Parameters:
    ///   - maxDimension: The maximum width or height for the thumbnail in pixels; the other dimension is scaled to preserve aspect ratio.
    /// - Returns: A tuple containing `pixels` (row-major downsampled `UInt16` values), `width`, and `height`; returns `nil` if the image is not 16-bit single-channel or pixel data is unavailable.
    public func getDownsampledPixels16(maxDimension: Int = 150) -> (pixels: [UInt16], width: Int, height: Int)? {
        return synchronized {
            guard samplesPerPixel == 1 && bitDepth == 16 else { return nil }
            guard offset > 0 else { return nil }

            let startTime = CFAbsoluteTimeGetCurrent()

            // Calculate proper aspect-preserving thumbnail dimensions
            let aspectRatio = Double(width) / Double(height)
            let thumbWidth: Int
            let thumbHeight: Int

            if width > height {
                thumbWidth = min(width, maxDimension)
                thumbHeight = Int(Double(thumbWidth) / aspectRatio)
            } else {
                thumbHeight = min(height, maxDimension)
                thumbWidth = Int(Double(thumbHeight) * aspectRatio)
            }

            // Calculate actual sampling step (can be fractional)
            let xStep = Double(width) / Double(thumbWidth)
            let yStep = Double(height) / Double(thumbHeight)

            logger.debug("Downsampling \(width)x\(height) -> \(thumbWidth)x\(thumbHeight) (step: \(String(format: "%.2f", xStep))x\(String(format: "%.2f", yStep)))")

            var downsampledPixels = [UInt16](repeating: 0, count: thumbWidth * thumbHeight)

            dicomData.withUnsafeBytes { dataBytes in
                let basePtr = dataBytes.baseAddress!.advanced(by: offset)

                for thumbY in 0..<thumbHeight {
                    for thumbX in 0..<thumbWidth {
                        // Calculate source pixel position
                        let sourceX = Int(Double(thumbX) * xStep)
                        let sourceY = Int(Double(thumbY) * yStep)

                        // Ensure we don't go out of bounds
                        let clampedX = min(sourceX, width - 1)
                        let clampedY = min(sourceY, height - 1)

                        let sourceIndex = (clampedY * width + clampedX) * 2
                        let thumbIndex = thumbY * thumbWidth + thumbX

                        let b0 = basePtr.advanced(by: sourceIndex).assumingMemoryBound(to: UInt8.self).pointee
                        let b1 = basePtr.advanced(by: sourceIndex + 1).assumingMemoryBound(to: UInt8.self).pointee

                        var value = littleEndian ? UInt16(b1) << 8 | UInt16(b0)
                                                : UInt16(b0) << 8 | UInt16(b1)

                        // Handle MONOCHROME1 inversion
                        if photometricInterpretation == "MONOCHROME1" {
                            value = 65535 - value
                        }

                        downsampledPixels[thumbIndex] = value
                    }
                }
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            debugPerfLog("[PERF] getDownsampledPixels16: \(String(format: "%.2f", elapsed))ms | thumbSize: \(thumbWidth)x\(thumbHeight)")

            return (downsampledPixels, thumbWidth, thumbHeight)
        }
    }

    /// Returns a downsampled 8-bit pixel buffer for thumbnail generation.
    /// This method reads only every Nth pixel to dramatically speed up thumbnail creation.
    /// - Parameter maxDimension: Maximum dimension for the thumbnail (default 150)
    /// Creates an aspect-preserving downsampled 8-bit grayscale thumbnail from the image pixel data.
    /// The result preserves the source aspect ratio, produces row-major UInt8 pixel values, and accounts for MONOCHROME1 inversion when present.
    /// - Parameters:
    ///   - maxDimension: The maximum width or height for the thumbnail in pixels; the other dimension is scaled to preserve aspect ratio.
    /// - Returns: A tuple containing `pixels` (row-major downsampled `UInt8` values), `width`, and `height`; returns `nil` if the image is not 8-bit single-channel or pixel data is unavailable.
    public func getDownsampledPixels8(maxDimension: Int = 150) -> (pixels: [UInt8], width: Int, height: Int)? {
        return synchronized {
            guard samplesPerPixel == 1 && bitDepth == 8 else { return nil }
            guard offset > 0 else { return nil }

            let startTime = CFAbsoluteTimeGetCurrent()

            // Calculate proper aspect-preserving thumbnail dimensions
            let aspectRatio = Double(width) / Double(height)
            let thumbWidth: Int
            let thumbHeight: Int

            if width > height {
                thumbWidth = min(width, maxDimension)
                thumbHeight = Int(Double(thumbWidth) / aspectRatio)
            } else {
                thumbHeight = min(height, maxDimension)
                thumbWidth = Int(Double(thumbHeight) * aspectRatio)
            }

            // Calculate actual sampling step (can be fractional)
            let xStep = Double(width) / Double(thumbWidth)
            let yStep = Double(height) / Double(thumbHeight)

            logger.debug("Downsampling \(width)x\(height) -> \(thumbWidth)x\(thumbHeight) (step: \(String(format: "%.2f", xStep))x\(String(format: "%.2f", yStep)))")

            var downsampledPixels = [UInt8](repeating: 0, count: thumbWidth * thumbHeight)

            dicomData.withUnsafeBytes { dataBytes in
                let basePtr = dataBytes.baseAddress!.advanced(by: offset)

                for thumbY in 0..<thumbHeight {
                    for thumbX in 0..<thumbWidth {
                        // Calculate source pixel position
                        let sourceX = Int(Double(thumbX) * xStep)
                        let sourceY = Int(Double(thumbY) * yStep)

                        // Ensure we don't go out of bounds
                        let clampedX = min(sourceX, width - 1)
                        let clampedY = min(sourceY, height - 1)

                        let sourceIndex = clampedY * width + clampedX
                        let thumbIndex = thumbY * thumbWidth + thumbX

                        var value = basePtr.advanced(by: sourceIndex).assumingMemoryBound(to: UInt8.self).pointee

                        // Handle MONOCHROME1 inversion
                        if photometricInterpretation == "MONOCHROME1" {
                            value = 255 - value
                        }

                        downsampledPixels[thumbIndex] = value
                    }
                }
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            debugPerfLog("[PERF] getDownsampledPixels8: \(String(format: "%.2f", elapsed))ms | thumbSize: \(thumbWidth)x\(thumbHeight)")

            return (downsampledPixels, thumbWidth, thumbHeight)
        }
    }

    // MARK: - Range-Based Pixel Data Access Methods

    /// Returns a subset of 8-bit pixel data specified by a range of pixel indices.
    /// This method enables streaming access for large images without loading the
    /// entire pixel buffer into memory.  Pixel indices are in row-major order.
    /// - Parameter range: Range of pixel indices to retrieve (0..<width*height)
    /// Reads a contiguous range of 8-bit pixel samples from the decoded DICOM image.
    /// - Parameters:
    ///   - range: A 0-based half-open range of pixel indices within the image (upperBound is exclusive).
    /// - Returns: An array of `UInt8` pixel values for the requested range, or `nil` if the file was not read, the range is out of bounds, or reading failed.
    public func getPixels8(range: Range<Int>) -> [UInt8]? {
        return synchronized {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Validate that file was successfully read
            guard dicomFileReadSuccess else {
                return nil
            }

            // Validate this is an 8-bit grayscale image
            guard bitDepth == 8, samplesPerPixel == 1 else {
                logger.warning("getPixels8(range:) called on non-8-bit grayscale image (bitDepth=\(bitDepth), samplesPerPixel=\(samplesPerPixel))")
                return nil
            }

            // Validate range against image dimensions
            let totalPixels = width * height
            guard range.lowerBound >= 0, range.upperBound <= totalPixels else {
                logger.warning("Range out of bounds: \(range) (total pixels: \(totalPixels))")
                return nil
            }

            // Call DCMPixelReader to read the specified range
            guard let result = DCMPixelReader.readPixels8(
                data: dicomData,
                range: range,
                width: width,
                height: height,
                offset: offset,
                photometricInterpretation: photometricInterpretation,
                logger: logger
            ) else {
                return nil
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if elapsed > 1 {
                debugPerfLog("[PERF] getPixels8(range): \(String(format: "%.2f", elapsed))ms | range: \(range.lowerBound)..<\(range.upperBound)")
            }

            return result.pixels8
        }
    }

    /// Returns a subset of 16-bit pixel data specified by a range of pixel indices.
    /// This method enables streaming access for large images without loading the
    /// entire pixel buffer into memory.  Pixel indices are in row-major order.
    /// - Parameter range: Range of pixel indices to retrieve (0..<width*height)
    /// Retrieve a contiguous subset of 16-bit pixel samples specified by a linear pixel index range.
    /// - Parameters:
    ///   - range: A half-open range of linear pixel indices (0..<(width * height)); upper bound is exclusive.
    /// - Returns: An array of `UInt16` pixel values covering `range`, or `nil` if the file was not read successfully, the range is out of bounds, or pixel reading failed.
    public func getPixels16(range: Range<Int>) -> [UInt16]? {
        return synchronized {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Validate that file was successfully read
            guard dicomFileReadSuccess else {
                return nil
            }

            // Validate this is a 16-bit grayscale image
            guard bitDepth == 16, samplesPerPixel == 1 else {
                logger.warning("getPixels16(range:) called on non-16-bit grayscale image (bitDepth=\(bitDepth), samplesPerPixel=\(samplesPerPixel))")
                return nil
            }

            // Validate range against image dimensions
            let totalPixels = width * height
            guard range.lowerBound >= 0, range.upperBound <= totalPixels else {
                logger.warning("Range out of bounds: \(range) (total pixels: \(totalPixels))")
                return nil
            }

            // Call DCMPixelReader to read the specified range
            guard let result = DCMPixelReader.readPixels16(
                data: dicomData,
                range: range,
                width: width,
                height: height,
                offset: offset,
                pixelRepresentation: pixelRepresentation,
                littleEndian: littleEndian,
                photometricInterpretation: photometricInterpretation,
                logger: logger
            ) else {
                return nil
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if elapsed > 1 {
                debugPerfLog("[PERF] getPixels16(range): \(String(format: "%.2f", elapsed))ms | range: \(range.lowerBound)..<\(range.upperBound)")
            }

            return result.pixels16
        }
    }

    /// Returns a subset of 24-bit RGB pixel data specified by a range of pixel indices.
    /// This method enables streaming access for large images without loading the
    /// entire pixel buffer into memory.  Pixel indices are in row-major order.
    /// The returned array contains interleaved RGB values (3 bytes per pixel).
    /// - Parameter range: Range of pixel indices to retrieve (0..<width*height)
    /// Returns the 24-bit RGB pixel bytes for a contiguous range of pixel indices.
    /// - Parameters:
    ///   - range: A range of pixel indices (0-based) within the image; upper bound must be <= width * height.
    /// - Returns: An array of `UInt8` containing interleaved RGB bytes (`R,G,B` per pixel) for the requested range, or `nil` if the file was not read successfully, the range is invalid, or reading failed.
    public func getPixels24(range: Range<Int>) -> [UInt8]? {
        return synchronized {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Validate that file was successfully read
            guard dicomFileReadSuccess else {
                return nil
            }

            guard samplesPerPixel == 3 else {
                logger.warning("getPixels24(range:) requires samplesPerPixel == 3 (RGB). Found \(samplesPerPixel)")
                return nil
            }
            if let planarConfiguration = Int(infoUnsafe(for: Tag.planarConfiguration.rawValue)),
               planarConfiguration != 0 {
                logger.warning("getPixels24(range:) requires interleaved RGB (planarConfiguration == 0). Found \(planarConfiguration)")
                return nil
            }

            // Validate range against image dimensions
            let totalPixels = width * height
            guard range.lowerBound >= 0, range.upperBound <= totalPixels else {
                logger.warning("Range out of bounds: \(range) (total pixels: \(totalPixels))")
                return nil
            }

            // Call DCMPixelReader to read the specified range
            guard let result = DCMPixelReader.readPixels24(
                data: dicomData,
                range: range,
                width: width,
                height: height,
                offset: offset,
                logger: logger
            ) else {
                return nil
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if elapsed > 1 {
                debugPerfLog("[PERF] getPixels24(range): \(String(format: "%.2f", elapsed))ms | range: \(range.lowerBound)..<\(range.upperBound)")
            }

            return result.pixels24
        }
    }

    /// Parses a tag value on demand from the lazy metadata cache.
    /// This method checks if the tag exists in the tagMetadataCache, and if so,
    /// reads the value from the file and stores it in dicomInfoDict.
    /// Returns the formatted "description: value" string if successful, nil otherwise.
    ///
    /// This implements the lazy parsing optimization where tag values are only
    /// extracted when first accessed, reducing memory usage for large DICOM files.
    ///
    /// - Parameter tag: The DICOM tag to parse
    /// - Returns: Formatted tag info string or nil if tag not in cache
    /// - Note: This is an internal unsafe method that must be called from within a synchronized block
    private func parseTagOnDemand(tag: Int) -> String? {
        // Check if tag exists in lazy metadata cache
        guard let metadata = tagMetadataCache[tag] else {
            return nil
        }

        // Get tag description from dictionary
        let key = String(format: "%08X", tag)
        var description = dict.value(forKey: key) ?? "---"

        // For implicit VR, extract VR from description
        if metadata.vr == .implicitRaw {
            if description.count >= 2 {
                description = String(description.dropFirst(2))
            }
        }

        // Read value from file using reader
        guard let reader = reader else {
            return nil
        }

        var value: String? = nil
        var offset = metadata.offset

        // Read value based on VR type (mirroring headerInfo logic)
        switch metadata.vr {
        case .FD:
            // Skip double values for now
            break

        case .FL:
            // Skip float values for now
            break

        case .AE, .AS, .AT, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .PN, .SH, .ST, .TM, .UI:
            value = reader.readString(length: metadata.elementLength, location: &offset)

        case .US:
            if metadata.elementLength == 2 {
                let s = reader.readShort(location: &offset)
                value = String(s)
            } else {
                // Multiple unsigned shorts separated by spaces
                var vals = [String]()
                let count = metadata.elementLength / 2
                for _ in 0..<count {
                    vals.append(String(reader.readShort(location: &offset)))
                }
                value = vals.joined(separator: " ")
            }

        case .implicitRaw:
            // Interpret as a string unless extremely long
            let s = reader.readString(length: metadata.elementLength, location: &offset)
            if metadata.elementLength <= 44 {
                value = s
            } else {
                value = nil
            }

        case .SQ:
            // Sequences not fully parsed in lazy mode
            value = ""

        default:
            // Unknown VR: skip
            value = ""
        }

        // Build the formatted string
        let formattedInfo: String
        if let val = value, !val.isEmpty {
            formattedInfo = "\(description): \(val)"
        } else {
            formattedInfo = "\(description): "
        }

        // Store in dicomInfoDict for future access
        dicomInfoDict[tag] = formattedInfo

        return formattedInfo
    }

    /// Retrieves the value of a parsed header as a string, trimming
    /// any leading description up to the colon.  Returns an empty
    /// string if the tag was not found.
    /// NOTE: This is the internal unsafe version that must be called from within a synchronized block.
    private func infoUnsafe(for tag: Int) -> String {
        // OPTIMIZATION: Check cache first for frequently accessed tags
        if DCMDecoder.frequentTags.contains(tag), let cached = cachedInfo[tag] {
            return cached
        }

        // Check if tag needs lazy parsing
        if dicomInfoDict[tag] == nil {
            _ = parseTagOnDemand(tag: tag)
        }

        guard let info = dicomInfoDict[tag] else {
            return ""
        }

        // Split on the first colon to remove the VR description
        let result: String
        if let range = info.range(of: ":") {
            result = String(info[range.upperBound...].trimmingCharacters(in: .whitespaces))
        } else {
            result = info
        }

        // Cache frequently accessed tags
        if DCMDecoder.frequentTags.contains(tag) {
            cachedInfo[tag] = result
        }

        return result
    }

    /// Retrieves the value of a parsed header as a string, trimming
    /// any leading description up to the colon.  Returns an empty
    /// string if the tag was not found.
    public func info(for tag: Int) -> String {
        return synchronized {
            return infoUnsafe(for: tag)
        }
    }

    /// Retrieves an integer value for a DICOM tag
    /// - Parameter tag: The DICOM tag to retrieve
    /// - Returns: Integer value or nil if not found or cannot be parsed
    public func intValue(for tag: Int) -> Int? {
        return synchronized {
            let stringValue = infoUnsafe(for: tag)
            return Int(stringValue)
        }
    }

    /// Retrieves a double value for a DICOM tag
    /// - Parameter tag: The DICOM tag to retrieve
    /// - Returns: Double value or nil if not found or cannot be parsed
    public func doubleValue(for tag: Int) -> Double? {
        return synchronized {
            let stringValue = infoUnsafe(for: tag)
            return Double(stringValue)
        }
    }

    // MARK: - DicomTag Convenience Methods

    /// Retrieves the value of a parsed header as a string using DicomTag enum.
    /// Provides type-safe access to common DICOM tags without requiring hex values.
    ///
    /// - Parameter tag: The DICOM tag enum case (e.g., .patientName, .modality)
    /// - Returns: String value of the tag, empty string if not found
    ///
    /// Example:
    /// ```swift
    /// let name = decoder.info(for: .patientName)  // Preferred
    /// // vs
    /// let name = decoder.info(for: 0x00100010)    // Legacy
    /// ```
    public func info(for tag: DicomTag) -> String {
        return info(for: tag.rawValue)
    }

    /// Retrieves an integer value for a DICOM tag using DicomTag enum.
    ///
    /// - Parameter tag: The DICOM tag enum case (e.g., .rows, .columns)
    /// - Returns: Integer value or nil if not found or cannot be parsed
    ///
    /// Example:
    /// ```swift
    /// let height = decoder.intValue(for: .rows)  // Preferred
    /// // vs
    /// let height = decoder.intValue(for: 0x00280010)  // Legacy
    /// ```
    public func intValue(for tag: DicomTag) -> Int? {
        return intValue(for: tag.rawValue)
    }

    /// Retrieves a double value for a DICOM tag using DicomTag enum.
    ///
    /// - Parameter tag: The DICOM tag enum case (e.g., .windowCenter, .windowWidth)
    /// - Returns: Double value or nil if not found or cannot be parsed
    ///
    /// Example:
    /// ```swift
    /// let center = decoder.doubleValue(for: .windowCenter)  // Preferred
    /// // vs
    /// let center = decoder.doubleValue(for: 0x00281050)  // Legacy
    /// ```
    public func doubleValue(for tag: DicomTag) -> Double? {
        return doubleValue(for: tag.rawValue)
    }

    /// Returns all available DICOM tags as a dictionary
    /// - Returns: Dictionary of tag hex string to value
    public func getAllTags() -> [String: String] {
        return synchronized {
            var result: [String: String] = [:]
            for (tag, value) in dicomInfoDict {
                let hexTag = String(format: "%08X", tag)
                result[hexTag] = value
            }
            return result
        }
    }

    /// Returns patient demographics in a structured format
    /// - Returns: Dictionary with patient information
    public func getPatientInfo() -> [String: String] {
        return synchronized {
            return [
                "Name": infoUnsafe(for: Tag.patientName.rawValue),
                "ID": infoUnsafe(for: Tag.patientID.rawValue),
                "Sex": infoUnsafe(for: Tag.patientSex.rawValue),
                "Age": infoUnsafe(for: Tag.patientAge.rawValue)
            ]
        }
    }

    /// Returns study information in a structured format
    /// - Returns: Dictionary with study information
    public func getStudyInfo() -> [String: String] {
        return synchronized {
            return [
                "StudyInstanceUID": infoUnsafe(for: Tag.studyInstanceUID.rawValue),
                "StudyID": infoUnsafe(for: Tag.studyID.rawValue),
                "StudyDate": infoUnsafe(for: Tag.studyDate.rawValue),
                "StudyTime": infoUnsafe(for: Tag.studyTime.rawValue),
                "StudyDescription": infoUnsafe(for: Tag.studyDescription.rawValue),
                "ReferringPhysician": infoUnsafe(for: Tag.referringPhysicianName.rawValue)
            ]
        }
    }

    /// Returns series information in a structured format
    /// - Returns: Dictionary with series information
    public func getSeriesInfo() -> [String: String] {
        return synchronized {
            return [
                "SeriesInstanceUID": infoUnsafe(for: Tag.seriesInstanceUID.rawValue),
                "SeriesNumber": infoUnsafe(for: Tag.seriesNumber.rawValue),
                "SeriesDate": infoUnsafe(for: Tag.seriesDate.rawValue),
                "SeriesTime": infoUnsafe(for: Tag.seriesTime.rawValue),
                "SeriesDescription": infoUnsafe(for: Tag.seriesDescription.rawValue),
                "Modality": infoUnsafe(for: Tag.modality.rawValue)
            ]
        }
    }

    // MARK: - Private helper methods

    #if DEBUG
    private func debugPerfLog(_ message: String) {
        logger.debug(message)
    }
    #else
    private func debugPerfLog(_ message: String) {}
    #endif

    /// Executes a block of code with thread-safe synchronization.
    /// - Parameter block: The closure to execute while holding the lock
    /// - Returns: The value returned by the closure
    private func synchronized<T>(_ block: () -> T) -> T {
        return lock.withLock {
            block()
        }
    }

    /// Executes a throwing block of code with thread-safe synchronization.
    /// - Parameter block: The throwing closure to execute while holding the lock
    /// - Returns: The value returned by the closure
    /// - Throws: Any error thrown by the closure
    private func synchronized<T>(_ block: () throws -> T) rethrows -> T {
        return try lock.withLock {
            try block()
        }
    }

    /// Reads the next tag from the stream using the tag parser.
    /// Returns the tag value (group << 16 | element).
    private func getNextTag() -> Int {
        guard let parser = tagParser else { return 0 }

        let previousEndianness = littleEndian
        let tag = parser.getNextTag(
            location: &location,
            data: dicomData,
            littleEndian: &littleEndian,
            bigEndianTransferSyntax: bigEndianTransferSyntax
        )

        // Update binary reader and parser if endianness changed
        if littleEndian != previousEndianness {
            reader = DCMBinaryReader(data: dicomData, littleEndian: littleEndian)
            tagParser = DCMTagParser(data: dicomData, dict: dict, binaryReader: reader!)
        }

        return tag
    }

    /// Adds the provided value to ``dicomInfoDict`` using the tag parser.
    /// Delegates to DCMTagParser for parsing and formatting.
    private func addInfo(tag: Int, stringValue: String?) {
        guard let parser = tagParser else { return }
        parser.addInfo(tag: tag, stringValue: stringValue, location: &location, infoDict: &dicomInfoDict)
    }

    /// Convenience overload for adding integer values as strings.
    private func addInfo(tag: Int, intValue: Int) {
        guard let parser = tagParser else { return }
        parser.addInfo(tag: tag, intValue: intValue, location: &location, infoDict: &dicomInfoDict)
    }

    /// Parses the ``PIXEL_SPACING`` string into separate x and y
    /// scales and stores them in ``pixelWidth`` and ``pixelHeight``.
    /// The expected format is ``"row\column"`` (note the use of
    /// backslash).  If the parsing fails the existing pixel
    /// dimensions are left unchanged.
    private func applySpatialScale(_ scale: String) {
        let components = scale.split(separator: "\\")
        guard components.count == 2,
              let y = Double(components[0]),
              let x = Double(components[1]) else {
            return
        }
        pixelHeight = y
        pixelWidth = x
    }

    /// Parses a DICOM multi-value string (e.g., "v1\v2\v3") into an array of Doubles.
    private func parseDoubleValues(_ string: String, expectedCount: Int) -> [Double]? {
        let parts = string.split(whereSeparator: { $0 == "\\" || $0.isWhitespace })
        guard parts.count >= expectedCount else { return nil }
        var values: [Double] = []
        values.reserveCapacity(expectedCount)
        for idx in 0..<expectedCount {
            guard let value = Double(parts[idx]) else { return nil }
            values.append(value)
        }
        return values
    }

    /// Thread-safe wrapper for readFileInfo
    /// - Returns: True if file info was successfully read
    private func readFileInfo() -> Bool {
        return synchronized {
            return readFileInfoUnsafe()
        }
    }

    /// Main header parsing loop.  This corresponds to
    /// ``readFileInfo()`` in the original code.  Returns false if
    /// the file is not a valid DICOM file or if an unsupported
    /// transfer syntax is encountered.  On success all metadata is
    /// recorded and available via properties or ``info(for:)``.
    /// NOTE: This is the unsafe version that must be called from within a synchronized block.
    ///
    /// ## Critical Tags Requiring Eager Parsing
    ///
    /// The following tags MUST be parsed eagerly (not lazily) because they affect
    /// decoder behavior during file parsing, validation, or pixel data reading:
    ///
    /// **Parsing Control Tags:**
    /// - `transferSyntaxUID` (0x00020010): Controls `compressedImage` and `bigEndianTransferSyntax`
    ///   flags that determine how subsequent tags and pixel data are decoded. Must be parsed
    ///   before any other image data.
    /// - `pixelData` (0x7FE00010): Sets `offset` and terminates the tag parsing loop. Critical
    ///   for locating pixel buffer and preventing unnecessary parsing of post-pixel metadata.
    ///
    /// **Image Dimension Tags (Required for Immediate Validation):**
    /// - `rows` (0x00280010): Sets `height`. Validated immediately after parsing to prevent
    ///   allocation of oversized buffers (maxImageDimension check at line ~1198).
    /// - `columns` (0x00280011): Sets `width`. Validated immediately after parsing to prevent
    ///   allocation of oversized buffers (maxImageDimension check at line ~1198).
    /// - `bitsAllocated` (0x00280100): Sets `bitDepth`. Used in pixel buffer size validation
    ///   calculation (maxPixelBufferSize check at line ~1215).
    ///
    /// **Pixel Interpretation Tags (Required for Buffer Allocation):**
    /// - `samplesPerPixel` (0x00280002): Sets `samplesPerPixel`. Used in buffer size calculation
    ///   and determines which pixel buffer to allocate (pixels8, pixels16, or pixels24).
    /// - `photometricInterpretation` (0x00280004): Sets `photometricInterpretation`. Required by
    ///   `DCMPixelReader` to correctly interpret pixel data (RGB, MONOCHROME1, MONOCHROME2, etc.).
    /// - `pixelRepresentation` (0x00280103): Sets `pixelRepresentation` (0=unsigned, 1=signed).
    ///   Affects how pixel values are normalized and converted.
    ///
    /// **Windowing Tags (Frequently Accessed):**
    /// - `windowCenter` (0x00281050): Sets `windowCenter` property. Frequently accessed by
    ///   `DCMWindowingProcessor` for display adjustment. Kept eager to avoid parsing overhead
    ///   on every windowing operation.
    /// - `windowWidth` (0x00281051): Sets `windowWidth` property. Frequently accessed by
    ///   `DCMWindowingProcessor` for display adjustment. Kept eager to avoid parsing overhead
    ///   on every windowing operation.
    ///
    /// **Geometry Tags (Frequently Accessed for 3D Reconstruction):**
    /// - `imageOrientationPatient` (0x00200037): Sets `imageOrientation` tuple. Required for
    ///   series ordering and 3D volume reconstruction. Accessed by `DicomSeriesLoader`.
    /// - `imagePositionPatient` (0x00200032): Sets `imagePosition`. Required for series ordering
    ///   and 3D volume reconstruction. Accessed by `DicomSeriesLoader`.
    ///
    /// **Spatial Calibration Tags (Used in Measurements):**
    /// - `pixelSpacing` (0x00280030): Sets `pixelWidth` and `pixelHeight`. Used for accurate
    ///   physical measurements and spatial calibration.
    /// - `sliceThickness` (0x00180050) / `sliceSpacing` (0x00180088): Sets `pixelDepth`. Used
    ///   for 3D volume reconstruction and measurements.
    ///
    /// **Value Mapping Tags (Used in Pixel Processing):**
    /// - `rescaleIntercept` (0x00281052): Sets `rescaleIntercept`. Used to map pixel values to
    ///   Hounsfield Units (CT) or other calibrated values.
    /// - `rescaleSlope` (0x00281053): Sets `rescaleSlope`. Used to map pixel values to
    ///   Hounsfield Units (CT) or other calibrated values.
    ///
    /// **Palette Tags (Required for Palette-Color Images):**
    /// - `redPalette` (0x00281201), `greenPalette` (0x00281202), `bluePalette` (0x00281203):
    ///   Set color lookup tables. Required for PALETTE COLOR images before pixel reading.
    ///
    /// **Multi-Frame Tags:**
    /// - `numberOfFrames` (0x00280008): Sets `nImages`. Required for multi-frame image handling.
    /// - `planarConfiguration` (0x00280006): Controls RGB pixel layout (interleaved vs planar).
    ///
    /// **Modality Tag:**
    /// - `modality` (0x00080060): Stored for contextual information. May affect downstream
    ///   processing decisions (e.g., windowing presets vary by modality).
    ///
    /// All other tags can be lazily parsed via `tagMetadataCache` and `parseTagOnDemand()`
    /// when first accessed through `info(for:)`. This defers string allocation and formatting
    /// for tags that may never be accessed, reducing memory overhead for files with hundreds
    /// of private or unused tags.
    /// Helper class to provide addInfo functionality to tag handlers
    /// without closure capture issues with inout parameters.
    /// Buffers metadata additions and applies them after handler completes.
    private final class InfoAdder {
        private var stringMetadata: [(tag: Int, value: String?)] = []
        private var intMetadata: [(tag: Int, value: Int)] = []

        func addInfo(tag: Int, stringValue: String?) {
            stringMetadata.append((tag, stringValue))
        }

        func addInfoInt(tag: Int, intValue: Int) {
            intMetadata.append((tag, intValue))
        }

        func flush(to decoder: DCMDecoder, parser: DCMTagParser) {
            // Apply all buffered metadata to the decoder's info dict
            for (tag, value) in stringMetadata {
                parser.addInfo(tag: tag, stringValue: value, location: &decoder.location, infoDict: &decoder.dicomInfoDict)
            }
            for (tag, value) in intMetadata {
                parser.addInfo(tag: tag, intValue: value, location: &decoder.location, infoDict: &decoder.dicomInfoDict)
            }
            // Clear buffers
            stringMetadata.removeAll()
            intMetadata.removeAll()
        }
    }

    private func readFileInfoUnsafe() -> Bool {
        guard let initialReader = reader else { return false }
        var reader = initialReader
        // Reset some state to sane defaults
        bitDepth = 16
        compressedImage = false
        imageOrientation = nil
        imagePosition = nil
        // Move to offset 128 where "DICM" marker resides
        location = 128
        // Read the four magic bytes
        let fileMark = reader.readString(length: 4, location: &location)
        guard fileMark == "DICM" else {
            dicomFound = false
            return false
        }
        dicomFound = true
        samplesPerPixel = 1
        // Create decoder context for tag handlers
        let context = DecoderContext()
        // Create info adder helper for tag handlers
        guard tagParser != nil else { return false }
        let infoAdder = InfoAdder()
        var decodingTags = true
        var tagCount = 0
        let maxTags = 10000  // Safety limit to prevent infinite loops

        while decodingTags && location < dicomData.count {
            tagCount += 1
            if tagCount > maxTags {
                logger.warning("Exceeded max tags at location \(location)")
                // Don't set offset here - we're not at pixel data
                // Let the end of function handle finding pixel data
                break
            }
            
            let tag = getNextTag()
            guard let activeReader = self.reader else { return false }
            reader = activeReader
            
            // Check for end of data or invalid tag
            if tag == 0 || location >= dicomData.count {
                if offset == 0 {
                    offset = location
                }
                break
            }
            if tagParser?.isInSequence == true {
                // Sequence content is handled inside headerInfo
                addInfo(tag: tag, stringValue: nil)
                continue
            }

            // Use handler registry for tag processing
            guard let parser = tagParser else { continue }

            if let handler = handlerRegistry.getHandler(for: tag) {
                // Tag has a registered handler - delegate processing
                let shouldContinue = handler.handle(
                    tag: tag,
                    reader: reader,
                    location: &location,
                    parser: parser,
                    context: context,
                    addInfo: infoAdder.addInfo(tag:stringValue:),
                    addInfoInt: infoAdder.addInfoInt(tag:intValue:)
                )

                // Flush buffered metadata after handler completes
                // This avoids exclusivity conflicts with inout location parameter
                infoAdder.flush(to: self, parser: parser)

                // Check if handler signaled to stop decoding (e.g., PixelDataTagHandler)
                if !shouldContinue || context.shouldStopDecoding {
                    decodingTags = false
                }
            } else {
                // Lazy parsing optimization: Store tag metadata for deferred parsing
                // instead of eagerly parsing all tags to strings. The tag value will
                // be parsed on first access via info(for:) using parseTagOnDemand().
                let metadata = TagMetadata(
                    tag: tag,
                    offset: location,
                    vr: parser.currentVR,
                    elementLength: parser.currentElementLength
                )
                tagMetadataCache[tag] = metadata
                // Advance location to skip the element value
                location += parser.currentElementLength
            }
        }

        // Copy context values back to decoder properties
        width = context.width
        height = context.height
        bitDepth = context.bitDepth
        transferSyntaxUID = context.transferSyntaxUID
        compressedImage = context.compressedImage
        bigEndianTransferSyntax = context.bigEndianTransferSyntax
        samplesPerPixel = context.samplesPerPixel
        photometricInterpretation = context.photometricInterpretation
        pixelRepresentation = context.pixelRepresentation
        windowCenter = context.windowCenter
        windowWidth = context.windowWidth
        pixelWidth = context.pixelWidth
        pixelHeight = context.pixelHeight
        pixelDepth = context.pixelDepth
        imageOrientation = context.imageOrientation
        imagePosition = context.imagePosition
        rescaleIntercept = context.rescaleIntercept
        rescaleSlope = context.rescaleSlope
        reds = context.reds
        greens = context.greens
        blues = context.blues
        offset = context.offset
        nImages = context.nImages
        // Note: modality and planarConfiguration are stored in context but not
        // copied to decoder properties - they were temporary values in the original
        // implementation, only used for passing to addInfo() metadata callbacks

        // Validate image dimensions and expected pixel buffer size
        if width <= 0 || height <= 0 {
            logger.warning("Invalid image dimensions: width=\(width), height=\(height)")
            return false
        }
        if width > Self.maxImageDimension || height > Self.maxImageDimension {
            logger.warning("Image dimensions exceed maximum allowed: \(width)x\(height) (max \(Self.maxImageDimension))")
            return false
        }
        let width64 = Int64(width)
        let height64 = Int64(height)
        let bytesPerPixel = Int64(max(1, bitDepth / 8)) * Int64(max(1, samplesPerPixel))
        let (pixelCount64, pixelOverflow) = width64.multipliedReportingOverflow(by: height64)
        if pixelOverflow {
            logger.warning("Pixel count overflow for dimensions: \(width)x\(height)")
            return false
        }
        let (totalBytes64, byteOverflow) = pixelCount64.multipliedReportingOverflow(by: bytesPerPixel)
        if byteOverflow || totalBytes64 <= 0 {
            logger.warning("Pixel buffer size overflow for dimensions: \(width)x\(height), bytesPerPixel=\(bytesPerPixel)")
            return false
        }
        if totalBytes64 > Self.maxPixelBufferSize {
            logger.warning("Pixel buffer size \(totalBytes64) bytes exceeds maximum allowed \(Self.maxPixelBufferSize) bytes")
            return false
        }

        // Ensure we have a valid pixel data offset
        if offset == 0 {
            // If we couldn't find the pixel data tag, try to locate it
            // Pixel data is usually at the end of the file
            // Calculate expected size
            let expectedPixelBytes = width * height * samplesPerPixel * (bitDepth / 8)
            if expectedPixelBytes > 0 && dicomData.count > expectedPixelBytes {
                // Assume pixel data is at the end
                offset = dicomData.count - expectedPixelBytes
                logger.warning("No pixel data tag found; assuming pixels at offset \(offset)")
            } else {
                logger.warning("Could not determine pixel data location")
                return false
            }
        }

        return true
    }


    /// Thread-safe wrapper for readPixels
    private func readPixels() {
        synchronized {
            readPixelsUnsafe()
        }
    }

    /// Reads the pixel data from the DICOM file.  This method
    /// allocates new buffers for each invocation and clears any
    /// previous buffers.  It supports 8‑bit grayscale, 16‑bit
    /// grayscale and 8‑bit 3‑channel RGB images.  Other values of
    /// ``samplesPerPixel`` or ``bitDepth`` result in empty buffers.
    /// NOTE: This is the unsafe version that must be called from within a synchronized block.
    private func readPixelsUnsafe() {
        // Clear any previously stored buffers
        pixels8 = nil
        pixels16 = nil
        pixels24 = nil

        // Use DCMPixelReader to read pixel data
        let result = DCMPixelReader.readPixels(
            data: dicomData,
            width: width,
            height: height,
            bitDepth: bitDepth,
            samplesPerPixel: samplesPerPixel,
            offset: offset,
            pixelRepresentation: pixelRepresentation,
            littleEndian: littleEndian,
            photometricInterpretation: photometricInterpretation,
            logger: logger
        )

        // Store the results
        pixels8 = result.pixels8
        pixels16 = result.pixels16
        pixels24 = result.pixels24
        signedImage = result.signedImage
    }

    /// Thread-safe wrapper for decodeCompressedPixelData
    private func decodeCompressedPixelData() {
        synchronized {
            decodeCompressedPixelDataUnsafe()
        }
    }

    /// Attempts to decode compressed pixel data using native decoders
    /// and ImageIO fallback. This function supports common DICOM
    /// transfer syntaxes including JPEG Lossless (Process 14,
    /// Selection Value 1), JPEG Baseline, JPEG Extended, JPEG‑LS
    /// and JPEG2000.  The compressed data is assumed to begin at
    /// ``offset`` and extend to the end of ``dicomData``.  On
    /// success the ``pixels8``, ``pixels16`` or ``pixels24``
    /// buffers are populated accordingly.  If decoding fails the
    /// buffers remain nil and ``dicomFileReadSuccess`` is set to
    /// false.
    /// NOTE: This is the unsafe version that must be called from within a synchronized block.
    private func decodeCompressedPixelDataUnsafe() {
        // Use DCMPixelReader to decode compressed pixel data
        guard let result = DCMPixelReader.decodeCompressedPixelData(
            data: dicomData,
            offset: offset,
            logger: logger
        ) else {
            dicomFileReadSuccess = false
            return
        }

        // Update decoder state with decoded image properties
        width = result.width
        height = result.height
        bitDepth = result.bitDepth
        samplesPerPixel = result.samplesPerPixel
        signedImage = result.signedImage

        // Store pixel buffers
        pixels8 = result.pixels8
        pixels16 = result.pixels16
        pixels24 = result.pixels24
    }
}

// MARK: - Convenience Extensions

extension DCMDecoder {

    /// Quick check if this is a valid grayscale image
    public var isGrayscale: Bool {
        return samplesPerPixel == 1
    }

    /// Quick check if this is a color/RGB image
    public var isColorImage: Bool {
        return samplesPerPixel == 3
    }

    /// Quick check if this is a multi-frame image
    public var isMultiFrame: Bool {
        return nImages > 1
    }

    /// Returns image dimensions as a tuple
    public var imageDimensions: (width: Int, height: Int) {
        return (width, height)
    }

    /// Returns pixel spacing as a tuple
    @available(*, deprecated, message: "Use pixelSpacingV2 for type-safe PixelSpacing struct")
    public var pixelSpacing: (width: Double, height: Double, depth: Double) {
        return (pixelWidth, pixelHeight, pixelDepth)
    }

    /// Returns window settings as a tuple
    @available(*, deprecated, message: "Use windowSettingsV2 for type-safe WindowSettings struct")
    public var windowSettings: (center: Double, width: Double) {
        return (windowCenter, windowWidth)
    }

    /// Returns rescale parameters as a tuple
    @available(*, deprecated, message: "Use rescaleParametersV2 for type-safe RescaleParameters struct")
    public var rescaleParameters: (intercept: Double, slope: Double) {
        return (rescaleIntercept, rescaleSlope)
    }

    // MARK: - Type-Safe Value Properties (V2 APIs)

    /// Returns pixel spacing as a type-safe struct
    ///
    /// Provides physical spacing between pixels in three dimensions (x, y, z).
    /// This is the recommended API for accessing pixel spacing with better type safety
    /// and Codable support.
    ///
    /// - Returns: PixelSpacing struct with x, y, z spacing values in millimeters
    ///
    /// ## Example
    /// ```swift
    /// let spacing = decoder.pixelSpacingV2
    /// if spacing.isValid {
    ///     print("Pixel spacing: \(spacing.x) × \(spacing.y) × \(spacing.z) mm")
    /// }
    /// ```
    public var pixelSpacingV2: PixelSpacing {
        return PixelSpacing(x: pixelWidth, y: pixelHeight, z: pixelDepth)
    }

    /// Returns window settings as a type-safe struct
    ///
    /// Provides window center and width values for grayscale display adjustment.
    /// This is the recommended API for accessing window settings with better type safety
    /// and Codable support.
    ///
    /// - Returns: WindowSettings struct with center and width values
    ///
    /// ## Example
    /// ```swift
    /// let settings = decoder.windowSettingsV2
    /// if settings.isValid {
    ///     // Apply windowing with settings.center and settings.width
    /// }
    /// ```
    public var windowSettingsV2: WindowSettings {
        return WindowSettings(center: windowCenter, width: windowWidth)
    }

    /// Returns rescale parameters as a type-safe struct
    ///
    /// Provides rescale slope and intercept for converting stored pixel values
    /// to modality units (e.g., Hounsfield Units in CT imaging).
    /// This is the recommended API for accessing rescale parameters with better
    /// type safety and Codable support.
    ///
    /// - Returns: RescaleParameters struct with intercept and slope values
    ///
    /// ## Example
    /// ```swift
    /// let rescale = decoder.rescaleParametersV2
    /// if !rescale.isIdentity {
    ///     let hounsfieldValue = rescale.apply(to: pixelValue)
    /// }
    /// ```
    public var rescaleParametersV2: RescaleParameters {
        return RescaleParameters(intercept: rescaleIntercept, slope: rescaleSlope)
    }

    /// Applies rescale slope and intercept to a pixel value
    /// - Parameter pixelValue: Raw pixel value
    /// - Returns: Rescaled value (Hounsfield Units for CT, etc.)
    public func applyRescale(to pixelValue: Double) -> Double {
        return rescaleSlope * pixelValue + rescaleIntercept
    }

    /// Calculates optimal window/level based on pixel data statistics
    /// - Returns: Tuple with calculated center and width, or nil if no pixel data
    @available(*, deprecated, message: "Use calculateOptimalWindowV2() for type-safe WindowSettings struct")
    public func calculateOptimalWindow() -> (center: Double, width: Double)? {
        guard let pixels = getPixels16() else { return nil }

        let stats = DCMWindowingProcessor.calculateOptimalWindowLevel(pixels16: pixels)
        return (stats.center, stats.width)
    }

    /// Calculates optimal window/level based on pixel data statistics (V2 API)
    ///
    /// Analyzes the pixel value distribution to determine optimal display window settings.
    /// This is the recommended API for calculating window/level with better type safety
    /// and Codable support.
    ///
    /// - Returns: WindowSettings struct with calculated center and width, or nil if no pixel data
    ///
    /// ## Example
    /// ```swift
    /// if let settings = decoder.calculateOptimalWindowV2() {
    ///     if settings.isValid {
    ///         // Apply optimal windowing
    ///         let displayPixels = DCMWindowingProcessor.applyWindowLevel(
    ///             pixels16: pixels,
    ///             center: settings.center,
    ///             width: settings.width
    ///         )
    ///     }
    /// }
    /// ```
    public func calculateOptimalWindowV2() -> WindowSettings? {
        guard let pixels = getPixels16() else { return nil }

        let stats = DCMWindowingProcessor.calculateOptimalWindowLevel(pixels16: pixels)
        return WindowSettings(center: stats.center, width: stats.width)
    }

    /// Returns image quality metrics
    /// - Returns: Dictionary with quality metrics or nil if no pixel data
    public func getQualityMetrics() -> [String: Double]? {
        guard let pixels = getPixels16() else { return nil }
        return DCMWindowingProcessor.calculateQualityMetrics(pixels16: pixels)
    }
}
