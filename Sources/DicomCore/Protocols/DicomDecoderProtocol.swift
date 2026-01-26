//
//  DicomDecoderProtocol.swift
//
//  Protocol abstraction for DICOM decoder implementations.
//  Defines the public API for parsing DICOM files, extracting
//  metadata, and accessing pixel data.  Implementations must
//  support 8-bit and 16-bit grayscale images as well as 24-bit
//  RGB images, handle both little and big endian byte order,
//  and provide thread-safe access to all methods and properties.
//
//  Thread Safety:
//
//  All protocol methods and properties must be thread-safe and
//  support concurrent access from multiple threads without
//  requiring external synchronization.
//

import Foundation
import simd

/// Protocol defining the public API for DICOM file decoding.
/// Implementations must handle uncompressed and compressed
/// transfer syntaxes, provide metadata extraction via DICOM
/// tags, and return pixel buffers in appropriate formats.
///
/// **Thread Safety:** All methods and properties must be
/// thread-safe and support concurrent access without data
/// races.  Implementations should use internal locking to
/// ensure data consistency.
public protocol DicomDecoderProtocol: AnyObject {

    // MARK: - Image Properties

    /// Bit depth of the decoded pixels (8 or 16).
    var bitDepth: Int { get }

    /// Image width in pixels.
    var width: Int { get }

    /// Image height in pixels.
    var height: Int { get }

    /// Byte offset from the start of file data to pixel data.
    var offset: Int { get }

    /// Number of frames in a multi-frame image. Defaults to 1.
    var nImages: Int { get }

    /// Number of samples per pixel. 1 for grayscale, 3 for RGB.
    var samplesPerPixel: Int { get }

    /// Photometric interpretation (MONOCHROME1, MONOCHROME2, RGB, etc.)
    var photometricInterpretation: String { get }

    // MARK: - Spatial Properties

    /// Physical depth of each pixel (slice thickness) in millimeters.
    var pixelDepth: Double { get }

    /// Physical width of each pixel in millimeters.
    var pixelWidth: Double { get }

    /// Physical height of each pixel in millimeters.
    var pixelHeight: Double { get }

    /// Direction cosines for image rows and columns (0020,0037).
    /// Defines orientation in patient coordinate system.
    var imageOrientation: (row: SIMD3<Double>, column: SIMD3<Double>)? { get }

    /// Patient-space origin for the top-left voxel (0020,0032).
    var imagePosition: SIMD3<Double>? { get }

    // MARK: - Display Properties

    /// Default window center for display.
    var windowCenter: Double { get }

    /// Default window width for display.
    var windowWidth: Double { get }

    // MARK: - Status Properties

    /// True if file contains DICM signature at offset 128.
    var dicomFound: Bool { get }

    /// True if file was successfully parsed and pixel data is available.
    var dicomFileReadSuccess: Bool { get }

    /// True if file uses a compressed transfer syntax.
    var compressedImage: Bool { get }

    /// True if this is a DICOMDIR file (reserved for future use).
    var dicomDir: Bool { get }

    /// True if pixel data uses two's complement representation.
    var signedImage: Bool { get }

    /// Raw pixel representation flag (0 = unsigned, 1 = two's complement).
    var pixelRepresentationTagValue: Int { get }

    /// Convenience accessor for signed pixel representation.
    var isSignedPixelRepresentation: Bool { get }

    // MARK: - Validation Methods

    /// Validates DICOM file structure and required tags.
    /// - Parameter filename: Path to the DICOM file
    /// - Returns: Validation result with detailed issues if any
    func validateDICOMFile(_ filename: String) -> (isValid: Bool, issues: [String])

    /// Checks if the decoder has successfully read and parsed the DICOM file.
    /// - Returns: True if file is loaded and valid
    func isValid() -> Bool

    /// Returns detailed validation status of the loaded DICOM file.
    /// - Returns: Tuple with validation status, dimensions, pixel availability, and compression status
    func getValidationStatus() -> (isValid: Bool, width: Int, height: Int, hasPixels: Bool, isCompressed: Bool)

    // MARK: - File Loading Methods

    /// Assigns a file to decode.  The file is read and parsed immediately.
    /// On failure, `dicomFileReadSuccess` will be false.  Calling this
    /// method resets any previous state.
    /// - Parameter filename: Path to the DICOM file on disk
    func setDicomFilename(_ filename: String)

    // MARK: - Pixel Data Access Methods

    /// Returns the 8-bit pixel buffer if the image is grayscale and
    /// encoded with eight bits per sample.  Returns nil if not available.
    /// Array length is width × height.
    /// - Returns: 8-bit pixel buffer or nil
    func getPixels8() -> [UInt8]?

    /// Returns the 16-bit pixel buffer if the image is grayscale and
    /// encoded with sixteen bits per sample.  Returns nil if not available.
    /// Array length is width × height.
    /// - Returns: 16-bit pixel buffer or nil
    func getPixels16() -> [UInt16]?

    /// Returns the 8-bit interleaved RGB pixel buffer if the image
    /// has three samples per pixel.  Returns nil if not available.
    /// Array length is width × height × 3.
    /// - Returns: 24-bit RGB pixel buffer or nil
    func getPixels24() -> [UInt8]?

    /// Returns a downsampled 16-bit pixel buffer for thumbnail generation.
    /// This method reads only every Nth pixel to dramatically speed up
    /// thumbnail creation.
    /// - Parameter maxDimension: Maximum dimension for the thumbnail (default 150)
    /// - Returns: Tuple with downsampled pixels and dimensions, or nil if not available
    func getDownsampledPixels16(maxDimension: Int) -> (pixels: [UInt16], width: Int, height: Int)?

    // MARK: - Metadata Access Methods

    /// Retrieves the value of a parsed header as a string.
    /// Returns an empty string if the tag was not found.
    /// - Parameter tag: DICOM tag identifier (e.g., 0x00100010)
    /// - Returns: Tag value as string
    func info(for tag: Int) -> String

    /// Retrieves an integer value for a DICOM tag.
    /// - Parameter tag: The DICOM tag to retrieve
    /// - Returns: Integer value or nil if not found or cannot be parsed
    func intValue(for tag: Int) -> Int?

    /// Retrieves a double value for a DICOM tag.
    /// - Parameter tag: The DICOM tag to retrieve
    /// - Returns: Double value or nil if not found or cannot be parsed
    func doubleValue(for tag: Int) -> Double?

    /// Returns all available DICOM tags as a dictionary.
    /// - Returns: Dictionary of tag hex string to value
    func getAllTags() -> [String: String]

    /// Returns patient demographics in a structured format.
    /// - Returns: Dictionary with patient information (Name, ID, Sex, Age)
    func getPatientInfo() -> [String: String]

    /// Returns study information in a structured format.
    /// - Returns: Dictionary with study information (StudyInstanceUID, StudyID, StudyDate, etc.)
    func getStudyInfo() -> [String: String]

    /// Returns series information in a structured format.
    /// - Returns: Dictionary with series information (SeriesInstanceUID, SeriesNumber, etc.)
    func getSeriesInfo() -> [String: String]

    // MARK: - Convenience Properties

    /// Quick check if this is a valid grayscale image.
    var isGrayscale: Bool { get }

    /// Quick check if this is a color/RGB image.
    var isColorImage: Bool { get }

    /// Quick check if this is a multi-frame image.
    var isMultiFrame: Bool { get }

    /// Returns image dimensions as a tuple.
    var imageDimensions: (width: Int, height: Int) { get }

    /// Returns pixel spacing as a tuple.
    var pixelSpacing: (width: Double, height: Double, depth: Double) { get }

    /// Returns window settings as a tuple.
    var windowSettings: (center: Double, width: Double) { get }

    /// Returns rescale parameters as a tuple.
    var rescaleParameters: (intercept: Double, slope: Double) { get }

    // MARK: - Utility Methods

    /// Applies rescale slope and intercept to a pixel value.
    /// - Parameter pixelValue: Raw pixel value
    /// - Returns: Rescaled value (Hounsfield Units for CT, etc.)
    func applyRescale(to pixelValue: Double) -> Double

    /// Calculates optimal window/level based on pixel data statistics.
    /// - Returns: Tuple with calculated center and width, or nil if no pixel data
    func calculateOptimalWindow() -> (center: Double, width: Double)?

    /// Returns image quality metrics.
    /// - Returns: Dictionary with quality metrics or nil if no pixel data
    func getQualityMetrics() -> [String: Double]?
}
