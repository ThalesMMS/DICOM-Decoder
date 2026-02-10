//
//  DicomSeriesLoaderProtocol.swift
//
//  Protocol abstraction for DICOM series loader implementations.
//  Defines the public API for loading and assembling multi-slice
//  DICOM series from directories, ordering slices by Image Position
//  (Patient), computing spatial geometry, and assembling contiguous
//  3D volume buffers.  Implementations must support 16-bit grayscale
//  images and provide progress callbacks during loading operations.
//
//  Thread Safety:
//
//  All protocol methods must be thread-safe and support concurrent
//  access from multiple threads without requiring external
//  synchronization.
//

import Foundation
import simd

/// Protocol defining the public API for DICOM series loading.
/// Implementations must handle directory traversal, slice ordering,
/// geometry validation, and volume assembly.  Progress callbacks
/// are provided during loading to enable UI updates.
///
/// **Thread Safety:** All methods must be thread-safe and support
/// concurrent access without data races.  Implementations should
/// use internal locking to ensure data consistency.
public protocol DicomSeriesLoaderProtocol: AnyObject {

    /// Progress callback handler invoked during series loading.
    /// - Parameters:
    ///   - fraction: Completion fraction (0.0 to 1.0)
    ///   - slicesCopied: Number of slices processed so far
    ///   - sliceData: Pixel data for the current slice
    ///   - volume: Partial volume descriptor with geometry metadata
    typealias ProgressHandler = (Double, Int, Data?, DicomSeriesVolume) -> Void

    /// Initializes a new series loader instance.
    init()

    /// Loads a DICOM series from a directory, ordering slices by Image Position (Patient).
    ///
    /// This method:
    /// - Scans the directory for DICOM files (.dcm or extensionless)
    /// - Validates that all slices have consistent dimensions and orientation
    /// - Orders slices by their projection onto the normal vector
    /// - Computes spatial geometry (spacing, orientation, origin)
    /// - Assembles a contiguous 16-bit volume buffer
    /// - Invokes progress callbacks during loading
    ///
    /// - Parameters:
    ///   - directory: Directory containing DICOM slices
    ///   - progress: Optional callback invoked with (fractionComplete, slicesCopied, sliceData, volume)
    /// - Returns: `DicomSeriesVolume` with voxel buffer and geometry metadata
    /// - Throws: `DicomSeriesLoaderError` on validation or decoding failures
    func loadSeries(in directory: URL,
                    progress: ProgressHandler?) throws -> DicomSeriesVolume

    /// Asynchronously loads a DICOM series from a directory, ordering slices by Image Position (Patient).
    ///
    /// This async method performs the same operations as the synchronous version but allows
    /// non-blocking execution on background threads. Recommended for UI contexts to avoid
    /// blocking the main thread during long-running series loading operations.
    ///
    /// This method:
    /// - Scans the directory for DICOM files (.dcm or extensionless)
    /// - Validates that all slices have consistent dimensions and orientation
    /// - Orders slices by their projection onto the normal vector
    /// - Computes spatial geometry (spacing, orientation, origin)
    /// - Assembles a contiguous 16-bit volume buffer
    /// - Invokes progress callbacks during loading
    ///
    /// - Parameters:
    ///   - directory: Directory containing DICOM slices
    ///   - progress: Optional callback invoked with (fractionComplete, slicesCopied, sliceData, volume)
    /// - Returns: `DicomSeriesVolume` with voxel buffer and geometry metadata
    /// - Throws: `DicomSeriesLoaderError` on validation or decoding failures
    ///
    /// - Example:
    /// ```swift
    /// Task {
    ///     do {
    ///         let loader = DicomSeriesLoader()
    ///         let volume = try await loader.loadSeries(in: directoryURL) { fraction, slices, data, vol in
    ///             print("Loading: \(Int(fraction * 100))% (\(slices) slices)")
    ///         }
    ///         print("Loaded volume: \(volume.width) x \(volume.height) x \(volume.depth)")
    ///     } catch {
    ///         print("Failed to load series: \(error)")
    ///     }
    /// }
    /// ```
    func loadSeries(in directory: URL,
                    progress: ProgressHandler?) async throws -> DicomSeriesVolume
}
