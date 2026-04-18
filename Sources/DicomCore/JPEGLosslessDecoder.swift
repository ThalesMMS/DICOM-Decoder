//
//  JPEGLosslessDecoder.swift
//
//  JPEG Lossless decompression for DICOM images.
//  This module implements decoding for JPEG Lossless transfer syntaxes
//  (1.2.840.10008.1.2.4.57 and 1.2.840.10008.1.2.4.70) using predictive
//  coding with Huffman entropy coding. Supports Process 14 with Selection
//  Value 1 (first-order prediction).
//
//  The decoder parses JPEG markers (SOI, SOF3, DHT, SOS, EOI), constructs
//  Huffman decoding tables, and reconstructs pixels using spatial prediction.
//
//  Usage:
//
//    let decoder = JPEGLosslessDecoder()
//    let result = try decoder.decode(data: jpegData)
//    // result.pixels contains reconstructed 16-bit pixel buffer
//

import Foundation

// MARK: - JPEG Lossless Decoder

/// Decoder for JPEG Lossless compressed DICOM pixel data.
/// Implements JPEG Lossless (Process 14) with first-order prediction
/// as specified in ITU-T T.81 and DICOM PS3.5 Section 8.2.4.
///
/// This decoder handles:
/// - JPEG marker parsing (SOI, SOF3, DHT, SOS, EOI)
/// - Huffman table construction and symbol decoding
/// - Predictive coding with Selection Value 1 (left neighbor predictor)
/// - Bit-level stream parsing with byte stuffing removal
///
/// Supports DICOM Transfer Syntaxes:
/// - 1.2.840.10008.1.2.4.57: JPEG Lossless, Non-Hierarchical (Process 14)
/// - 1.2.840.10008.1.2.4.70: JPEG Lossless, First-Order Prediction (Process 14, SV1)
internal final class JPEGLosslessDecoder {

    // MARK: - Properties

    /// Parsed SOF3 (Start of Frame) information
    var sof3Info: SOF3Info?

    /// Parsed SOS (Start of Scan) information
    var sosInfo: SOSInfo?

    /// Huffman tables indexed by (tableClass << 4) | tableId
    var huffmanTables: [Int: HuffmanTable] = [:]

    /// Byte offset where compressed entropy-coded data begins (after SOS header)
    var compressedDataStart: Int = 0

    /// Logger for diagnostics and performance tracking
    let logger: LoggerProtocol?

    // MARK: - Initialization

    /// Creates a new JPEG Lossless decoder
    /// - Parameter logger: Optional logger for diagnostics
    internal init(logger: LoggerProtocol? = nil) {
        self.logger = logger
    }

    // MARK: - Public Decoding Interface

    /// Decodes JPEG Lossless compressed pixel data
    /// - Parameter data: Raw JPEG Lossless bitstream starting with SOI marker
    /// - Returns: Decoded pixel buffer with metadata
    /// Decode a JPEG Lossless (Process 14, first-order prediction / Selection Value 1) compressed scan from DICOM pixel data into reconstructed image pixels.
    /// - Parameters:
    ///   - data: The JPEG byte stream containing markers and entropy-coded scan data as stored in a DICOM PixelData element.
    /// - Returns: A `JPEGLosslessDecodeResult` containing the reconstructed pixel buffer, `width`, `height`, and `bitDepth`.
    /// - Throws: `DICOMError.invalidDICOMFormat` when required JPEG markers (SOF3 or SOS) are missing or the JPEG structure is invalid, or other errors thrown during marker parsing, frame validation, or entropy/predictive decoding.
    internal func decode(data: Data) throws -> JPEGLosslessDecodeResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Reset state
        sof3Info = nil
        sosInfo = nil
        huffmanTables.removeAll()
        compressedDataStart = 0

        // Parse JPEG markers
        try parseMarkers(data: data)

        // Validate required markers were found
        guard let sof3 = sof3Info else {
            throw DICOMError.invalidDICOMFormat(reason: "Missing SOF3 (Start of Frame) marker in JPEG Lossless stream")
        }
        guard let sos = sosInfo else {
            throw DICOMError.invalidDICOMFormat(reason: "Missing SOS (Start of Scan) marker in JPEG Lossless stream")
        }

        // Validate frame parameters
        try validateFrameParameters(sof3: sof3, sos: sos)

        // Decode pixels
        let pixels = try decodePixels(
            data: data,
            sof3: sof3,
            sos: sos,
            compressedDataStart: compressedDataStart
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger?.info("JPEG Lossless decode completed in \(String(format: "%.3f", elapsed))s")

        return JPEGLosslessDecodeResult(
            pixels: pixels,
            width: sof3.width,
            height: sof3.height,
            bitDepth: sof3.precision
        )
    }

}
