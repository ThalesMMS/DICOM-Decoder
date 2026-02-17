//
//  ImageExporter.swift
//
//  Utility for exporting medical imaging pixel data to standard image formats
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Image Format Types

/// Supported image export formats.
public enum ImageFormat: String, CaseIterable, Codable, Sendable {
    case png
    case tiff

    /// Uniform Type Identifier for the format.
    var uti: CFString {
        switch self {
        case .png:
            if #available(macOS 11.0, *) {
                return UTType.png.identifier as CFString
            } else {
                return kUTTypePNG
            }
        case .tiff:
            if #available(macOS 11.0, *) {
                return UTType.tiff.identifier as CFString
            } else {
                return kUTTypeTIFF
            }
        }
    }

    /// File extension for the format.
    public var fileExtension: String {
        rawValue
    }

    /// Human-readable description of the format.
    public var description: String {
        switch self {
        case .png:
            return "PNG (Portable Network Graphics)"
        case .tiff:
            return "TIFF (Tagged Image File Format)"
        }
    }
}

// MARK: - Export Options

/// Configuration options for image export.
public struct ExportOptions: Sendable {
    /// Image format to export.
    public let format: ImageFormat

    /// Compression quality (0.0-1.0). Only applicable to formats that support it.
    public let quality: Double

    /// Whether to overwrite existing files.
    public let overwrite: Bool

    /// Creates export options with specified parameters.
    ///
    /// - Parameters:
    ///   - format: Image format (default: .png).
    ///   - quality: Compression quality 0.0-1.0 (default: 1.0).
    ///   - overwrite: Whether to overwrite existing files (default: false).
    public init(format: ImageFormat = .png, quality: Double = 1.0, overwrite: Bool = false) {
        self.format = format
        self.quality = min(max(quality, 0.0), 1.0) // Clamp to 0.0-1.0
        self.overwrite = overwrite
    }
}

// MARK: - Image Exporter

/// Utility for exporting medical imaging pixel data to standard image formats.
///
/// ## Overview
///
/// ``ImageExporter`` provides high-performance image export functionality for medical imaging
/// applications. It converts 8-bit grayscale pixel data (typically output from
/// ``DCMWindowingProcessor``) to standard image file formats using CoreGraphics and ImageIO.
///
/// **Key Features:**
/// - PNG export with lossless compression
/// - TIFF export with configurable compression
/// - Grayscale colorspace preservation
/// - High-performance CoreGraphics integration
/// - Comprehensive error handling
///
/// ## Usage
///
/// Export 8-bit pixel data from a DICOM file:
///
/// ```swift
/// // Load and process DICOM file
/// let decoder = try DCMDecoder(contentsOf: url)
/// let pixels16 = decoder.getPixels16()
///
/// // Apply windowing
/// let pixels8 = DCMWindowingProcessor.applyWindowLevel(
///     pixels16: pixels16,
///     center: 50.0,
///     width: 400.0
/// )
///
/// // Export to PNG
/// guard let pixels8 = pixels8 else {
///     throw CLIError.outputGenerationFailed(operation: "windowing", reason: "No pixel data")
/// }
///
/// let exporter = ImageExporter()
/// let options = ExportOptions(format: .png, quality: 1.0, overwrite: true)
/// try exporter.export(
///     pixels: pixels8,
///     width: decoder.width,
///     height: decoder.height,
///     to: outputURL,
///     options: options
/// )
/// ```
///
/// ## Topics
///
/// ### Creating Exporters
///
/// - ``init()``
///
/// ### Exporting Images
///
/// - ``export(pixels:width:height:to:options:)``
/// - ``createCGImage(from:width:height:)``
///
/// ### Supporting Types
///
/// - ``ImageFormat``
/// - ``ExportOptions``
public struct ImageExporter {

    // MARK: - Initialization

    /// Creates a new image exporter.
    public init() {}

    // MARK: - Export Methods

    /// Exports 8-bit grayscale pixel data to an image file.
    ///
    /// This method creates a CoreGraphics image from the pixel data and writes it to disk
    /// using ImageIO. The pixel data is expected to be in row-major order (left-to-right,
    /// top-to-bottom) with one byte per pixel.
    ///
    /// - Parameters:
    ///   - pixels: Array of 8-bit pixel values (length must equal width × height).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - url: Destination file URL.
    ///   - options: Export configuration options.
    /// - Throws:
    ///   - ``CLIError.invalidArgument(argument:value:reason:)`` if pixel array size doesn't match dimensions.
    ///   - ``CLIError.outputGenerationFailed(operation:reason:)`` if image creation fails.
    ///   - ``CLIError.fileNotWritable(path:reason:)`` if file cannot be written.
    ///   - ``CLIError.outputFileExists(path:)`` if file exists and overwrite is false.
    public func export(
        pixels: [UInt8],
        width: Int,
        height: Int,
        to url: URL,
        options: ExportOptions = ExportOptions()
    ) throws {
        // Validate dimensions
        guard width > 0, height > 0 else {
            throw CLIError.invalidArgument(
                argument: "dimensions",
                value: "\(width)x\(height)",
                reason: "Width and height must be positive"
            )
        }

        // Validate pixel data
        let expectedSize = width * height
        guard pixels.count == expectedSize else {
            throw CLIError.invalidArgument(
                argument: "pixels",
                value: "\(pixels.count) bytes",
                reason: "Expected \(expectedSize) bytes for \(width)x\(height) image"
            )
        }

        // Check if file exists
        if FileManager.default.fileExists(atPath: url.path) && !options.overwrite {
            throw CLIError.outputFileExists(path: url.path)
        }

        // Create CGImage from pixel data
        guard let cgImage = createCGImage(from: pixels, width: width, height: height) else {
            throw CLIError.outputGenerationFailed(
                operation: "image creation",
                reason: "Failed to create CGImage from pixel data"
            )
        }

        // Write to file using ImageIO
        try writeImage(cgImage, to: url, format: options.format, quality: options.quality)
    }

    /// Creates a CoreGraphics image from 8-bit grayscale pixel data.
    ///
    /// This method constructs a ``CGImage`` using a grayscale colorspace and the provided
    /// pixel data. The resulting image can be further processed or displayed using
    /// CoreGraphics or AppKit/UIKit APIs.
    ///
    /// - Parameters:
    ///   - pixels: Array of 8-bit pixel values (length must equal width × height).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    /// - Returns: A ``CGImage`` instance, or nil if creation fails.
    public func createCGImage(from pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        // Validate input
        guard width > 0, height > 0, pixels.count == width * height else {
            return nil
        }

        // Create grayscale colorspace
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray) else {
            return nil
        }

        // Image parameters
        let bitsPerComponent = 8
        let bytesPerPixel = 1
        let bytesPerRow = width * bytesPerPixel
        let bitmapInfo = CGImageAlphaInfo.none.rawValue

        // Create data provider from pixel array
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }

        // Create CGImage
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerComponent * bytesPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Private Helpers

    /// Writes a CGImage to disk using ImageIO.
    ///
    /// - Parameters:
    ///   - image: The image to write.
    ///   - url: Destination file URL.
    ///   - format: Image format.
    ///   - quality: Compression quality (0.0-1.0).
    /// - Throws: ``CLIError.fileNotWritable(path:reason:)`` if write fails.
    private func writeImage(_ image: CGImage, to url: URL, format: ImageFormat, quality: Double) throws {
        // Create image destination
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.uti,
            1,
            nil
        ) else {
            throw CLIError.fileNotWritable(
                path: url.path,
                reason: "Failed to create image destination"
            )
        }

        // Set compression properties
        var properties: [CFString: Any] = [:]

        switch format {
        case .png:
            // PNG is lossless. Lossy compression quality does not apply.
            break
        case .tiff:
            // TIFF compression quality
            properties[kCGImageDestinationLossyCompressionQuality] = quality as CFNumber
        }

        // Add image to destination
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        // Write to disk
        guard CGImageDestinationFinalize(destination) else {
            throw CLIError.fileNotWritable(
                path: url.path,
                reason: "Failed to finalize image write"
            )
        }
    }
}

// MARK: - Convenience Extensions

extension ImageExporter {
    /// Exports image data to a file path (convenience method).
    ///
    /// - Parameters:
    ///   - pixels: Array of 8-bit pixel values.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - path: Destination file path.
    ///   - options: Export configuration options.
    /// - Throws: Same errors as ``export(pixels:width:height:to:options:)``.
    public func export(
        pixels: [UInt8],
        width: Int,
        height: Int,
        to path: String,
        options: ExportOptions = ExportOptions()
    ) throws {
        let url = URL(fileURLWithPath: path)
        try export(pixels: pixels, width: width, height: height, to: url, options: options)
    }
}
