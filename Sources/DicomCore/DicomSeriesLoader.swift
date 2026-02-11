//
//  DicomSeriesLoader.swift
//
//  High-level helper to load a DICOM series from a directory,
//  order slices by Image Position (Patient), compute spacing/orientation,
//  and assemble a contiguous 16-bit volume buffer.
//
//  This stays pure Swift and uses lightweight parallelism when
//  copying slices into the final buffer.
//

import Foundation
import simd

// MARK: - Error Handling

/// Errors that can occur during DICOM series loading operations.
///
/// These errors represent validation failures and inconsistencies detected
/// when loading and assembling multi-slice DICOM volumes.
public enum DicomSeriesLoaderError: Error {
    /// No valid DICOM files found in the specified directory
    case noDicomFiles

    /// Image has unsupported samples per pixel (only grayscale supported)
    /// - Parameter Int: The actual samples per pixel value
    case unsupportedSamplesPerPixel(Int)

    /// Image has unsupported bit depth (only 16-bit supported)
    /// - Parameter Int: The actual bit depth value
    case unsupportedBitDepth(Int)

    /// Slices have inconsistent dimensions (width/height mismatch)
    case inconsistentDimensions

    /// Slices have inconsistent orientation vectors
    case inconsistentOrientation

    /// Slices have inconsistent pixel representation (signed/unsigned)
    case inconsistentPixelRepresentation

    /// Failed to decode a specific DICOM file
    /// - Parameter URL: The file URL that failed to decode
    case failedToDecode(URL)
}

// MARK: - Volume Data Structure

/// Represents a loaded DICOM volume assembled from a directory of slices.
///
/// Contains the assembled voxel data buffer along with geometric metadata required
/// for 3D reconstruction, measurement, and visualization. The volume is assembled
/// from individual 2D slices ordered by their Image Position (Patient) coordinates.
///
/// ## Usage Example
/// ```swift
/// let loader = DicomSeriesLoader()
/// let volume = try loader.loadSeries(in: seriesDirectory) { progress, sliceCount, _, _ in
///     print("Loading: \(Int(progress * 100))% - \(sliceCount) slices")
/// }
/// print("Volume: \(volume.width)×\(volume.height)×\(volume.depth)")
/// print("Spacing: \(volume.spacing) mm")
/// ```
public struct DicomSeriesVolume: Sendable {
    /// Raw voxel data as contiguous 16-bit signed integers
    public let voxels: Data

    /// Volume width in pixels (X dimension)
    public let width: Int

    /// Volume height in pixels (Y dimension)
    public let height: Int

    /// Volume depth in slices (Z dimension)
    public let depth: Int

    /// Physical spacing between voxels in millimeters (X, Y, Z)
    public let spacing: SIMD3<Double>

    /// 3×3 orientation matrix defining anatomical axes
    public let orientation: simd_double3x3

    /// 3D origin position in patient coordinate system (mm)
    public let origin: SIMD3<Double>

    /// Rescale slope for converting to modality units (e.g., Hounsfield Units)
    public let rescaleSlope: Double

    /// Rescale intercept for converting to modality units
    public let rescaleIntercept: Double

    /// Bits allocated per pixel (typically 16)
    public let bitsAllocated: Int

    /// Whether pixel values are signed integers
    public let isSignedPixel: Bool

    /// Human-readable series description
    public let seriesDescription: String
}

private struct SliceMeta {
    let url: URL
    let position: SIMD3<Double>?
    let instanceNumber: Int?
    let projection: Double?
}

// MARK: - Series Loader

/// High-level DICOM series loader with automatic slice ordering and volume assembly.
///
/// ## Overview
///
/// ``DicomSeriesLoader`` loads and assembles multi-slice DICOM volumes from directories.
/// It automatically orders slices by Image Position (Patient) coordinates, validates
/// geometric consistency, computes 3D spacing, and assembles a contiguous voxel buffer.
///
/// The loader uses protocol-based dependency injection for ``DicomDecoderProtocol``,
/// enabling testability and customization. Slices are validated for consistency in
/// dimensions, orientation, and pixel representation. The final volume includes complete
/// geometric metadata for 3D reconstruction.
///
/// **Key Features:**
/// - Automatic slice ordering by anatomical position
/// - Geometric validation across slices
/// - Computed Z-spacing from slice positions
/// - Progress callbacks during assembly
/// - Lightweight parallelism for buffer copying
/// - Async/await support for non-blocking loading
///
/// ## Usage
///
/// Basic series loading:
///
/// ```swift
/// let loader = DicomSeriesLoader()
/// do {
///     let volume = try loader.loadSeries(in: seriesDirectory)
///     print("Loaded \(volume.depth) slices: \(volume.width)×\(volume.height)")
/// } catch DicomSeriesLoaderError.noDicomFiles {
///     print("No DICOM files found")
/// } catch {
///     print("Loading failed: \(error)")
/// }
/// ```
///
/// Loading with progress tracking:
///
/// ```swift
/// let loader = DicomSeriesLoader()
/// let volume = try loader.loadSeries(in: seriesDirectory) { progress, sliceCount, _, _ in
///     DispatchQueue.main.async {
///         progressView.progress = Float(progress)
///         statusLabel.text = "Loading slice \(sliceCount)"
///     }
/// }
/// ```
///
/// Async loading with progress stream:
///
/// ```swift
/// Task {
///     for try await progress in loader.loadSeriesWithProgress(in: seriesDirectory) {
///         print("Progress: \(Int(progress.fractionComplete * 100))%")
///     }
/// }
/// ```
///
/// Custom decoder injection for testing:
///
/// ```swift
/// let loader = DicomSeriesLoader(decoderFactory: { MockDicomDecoder() })
/// let volume = try loader.loadSeries(in: testDirectory)
/// ```
///
/// ## Topics
///
/// ### Creating a Loader
///
/// - ``init()``
/// - ``init(decoderFactory:)``
///
/// ### Loading Series
///
/// - ``loadSeries(in:progress:)``
/// - ``loadSeries(in:progress:)-6zq7v``
/// - ``loadSeriesWithProgress(in:)``
/// - ``ProgressHandler``
///
/// ### Volume Data
///
/// - ``DicomSeriesVolume``
/// - ``SeriesLoadProgress``
///
/// ### Error Handling
///
/// - ``DicomSeriesLoaderError``
///
public final class DicomSeriesLoader: DicomSeriesLoaderProtocol {
    /// Progress callback invoked during volume assembly.
    ///
    /// - Parameters:
    ///   - progress: Fraction complete (0.0 to 1.0)
    ///   - sliceCount: Number of slices copied so far
    ///   - intermediateData: Reserved for future use (currently nil)
    ///   - volume: Partial volume descriptor with metadata
    public typealias ProgressHandler = (Double, Int, Data?, DicomSeriesVolume) -> Void

    // MARK: - Properties

    private let decoderFactory: () -> DicomDecoderProtocol
    private var decoderCache: [URL: DicomDecoderProtocol] = [:]

    // MARK: - Initialization

    /// Required protocol initializer - uses default DCMDecoder.
    public init() {
        self.decoderFactory = { DCMDecoder() }
    }

    /// Dependency injection initializer for testing and customization.
    /// - Parameter decoderFactory: Factory closure that creates DicomDecoderProtocol instances
    public init(decoderFactory: @escaping () -> DicomDecoderProtocol) {
        self.decoderFactory = decoderFactory
    }

    /// Loads a DICOM series from a directory, ordering slices by Image Position (Patient).
    /// - Parameters:
    ///   - directory: Directory containing DICOM slices.
    ///   - progress: Optional callback invoked with (fractionComplete, slicesCopied).
    /// - Returns: `DicomSeriesVolume` with voxel buffer and geometry metadata.
    public func loadSeries(in directory: URL,
                           progress: ProgressHandler? = nil) throws -> DicomSeriesVolume {
        let fileURLs = try listDicomFiles(in: directory)
        guard !fileURLs.isEmpty else {
            throw DicomSeriesLoaderError.noDicomFiles
        }

        // First pass: read headers to collect geometry and ordering data.
        var firstDecoder: DicomDecoderProtocol?
        var orientation: (row: SIMD3<Double>, column: SIMD3<Double>)?
        var origin: SIMD3<Double>?
        var rescaleSlope: Double = 1.0
        var rescaleIntercept: Double = 0.0
        var pixelRepresentation: Int = 0
        var seriesDescription = directory.lastPathComponent

        var width = 0
        var height = 0
        var bitsAllocated = 0
        var spacing = SIMD3<Double>(1, 1, 1)

        var slices: [SliceMeta] = []

        for url in fileURLs {
            let decoder = decoderFactory()
            decoder.setDicomFilename(url.path)
            guard decoder.dicomFileReadSuccess else { continue }

            // Validate modality: 16-bit grayscale only.
            guard decoder.samplesPerPixel == 1 else {
                throw DicomSeriesLoaderError.unsupportedSamplesPerPixel(decoder.samplesPerPixel)
            }
            guard decoder.bitDepth == 16 else {
                throw DicomSeriesLoaderError.unsupportedBitDepth(decoder.bitDepth)
            }

            // Cache the validated decoder for reuse in second pass
            decoderCache[url] = decoder

            // Capture baseline geometry from the first valid slice.
            if firstDecoder == nil {
                firstDecoder = decoder
                width = decoder.width
                height = decoder.height
                bitsAllocated = decoder.bitDepth
                spacing = SIMD3<Double>(decoder.pixelWidth, decoder.pixelHeight, decoder.pixelDepth)
                orientation = decoder.imageOrientation
                origin = decoder.imagePosition
                rescaleSlope = decoder.rescaleParameters.slope
                rescaleIntercept = decoder.rescaleParameters.intercept
                pixelRepresentation = decoder.pixelRepresentationTagValue
                let description = decoder.getSeriesInfo()["SeriesDescription"] ?? ""
                if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    seriesDescription = description
                }
            } else {
                // Check consistency across slices.
                guard decoder.width == width, decoder.height == height else {
                    throw DicomSeriesLoaderError.inconsistentDimensions
                }
                if let baseline = orientation, let candidate = decoder.imageOrientation {
                    if !isApproximatelyEqual(baseline.row, candidate.row) ||
                        !isApproximatelyEqual(baseline.column, candidate.column) {
                        throw DicomSeriesLoaderError.inconsistentOrientation
                    }
                }
                if decoder.pixelRepresentationTagValue != pixelRepresentation {
                    throw DicomSeriesLoaderError.inconsistentPixelRepresentation
                }
            }

            let normal = orientation.flatMap { simd_normalize(simd_cross($0.row, $0.column)) }
            let projection: Double?
            if let ipp = decoder.imagePosition, let normal {
                projection = simd_dot(ipp, normal)
            } else {
                projection = nil
            }
            let instance = decoder.intValue(for: DicomTag.instanceNumber.rawValue)

            slices.append(SliceMeta(url: url,
                                    position: decoder.imagePosition,
                                    instanceNumber: instance,
                                    projection: projection))
        }

        guard !slices.isEmpty, firstDecoder != nil else {
            throw DicomSeriesLoaderError.noDicomFiles
        }

        // Sort slices by projection on the normal; fallback to Instance Number then filename.
        let normal = orientation.flatMap { simd_normalize(simd_cross($0.row, $0.column)) } ?? SIMD3<Double>(0, 0, 1)
        slices.sort { lhs, rhs in
            if let lp = lhs.projection, let rp = rhs.projection, lp != rp {
                return lp < rp
            }
            if let li = lhs.instanceNumber, let ri = rhs.instanceNumber, li != ri {
                return li < ri
            }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }

        // Compute spacing Z from IPP deltas when available; if the value diverges
        // significantly from the reported slice spacing/thickness, prefer the tag.
        let computedZ = computeZSpacing(from: slices, normal: normal)
        let tagZ = spacing.z
        let zSpacing: Double
        if let computedZ {
            let tolerance = 0.2 // mm-level tolerance
            if tagZ > 0 && abs(computedZ - tagZ) > tolerance {
                zSpacing = tagZ
            } else {
                zSpacing = computedZ
            }
        } else {
            zSpacing = tagZ
        }
        spacing = SIMD3<Double>(spacing.x, spacing.y, zSpacing)

        let depth = slices.count
        let sliceVoxelCount = width * height
        var voxelData = Data(count: sliceVoxelCount * depth * MemoryLayout<Int16>.size)

        // Provide a lightweight volume descriptor for progress callbacks.
        let originForVolume = slices.first?.position ?? origin ?? SIMD3<Double>(repeating: 0)
        let orientationMatrix: simd_double3x3
        if let ori = orientation {
            let normalVec = simd_normalize(simd_cross(ori.row, ori.column))
            orientationMatrix = simd_double3x3(columns: (ori.row, ori.column, normalVec))
        } else {
            orientationMatrix = matrix_identity_double3x3
        }

        let progressVolume = DicomSeriesVolume(voxels: Data(),
                                               width: width,
                                               height: height,
                                               depth: depth,
                                               spacing: spacing,
                                               orientation: orientationMatrix,
                                               origin: originForVolume,
                                               rescaleSlope: rescaleSlope,
                                               rescaleIntercept: rescaleIntercept,
                                               bitsAllocated: bitsAllocated,
                                               isSignedPixel: pixelRepresentation == 1,
                                               seriesDescription: seriesDescription)

        var loadError: Error?
        // Allocate voxel buffer and copy slices sequentially for safety.
        voxelData.withUnsafeMutableBytes { rawBuffer in
            let dest = rawBuffer.bindMemory(to: Int16.self)
            for (index, slice) in slices.enumerated() {
                let pixels = try? self.decodeSlice(at: slice.url,
                                                   expectedWidth: width,
                                                   expectedHeight: height,
                                                   isSigned: pixelRepresentation == 1)
                guard let pixels, pixels.count == sliceVoxelCount else {
                    loadError = DicomSeriesLoaderError.failedToDecode(slice.url)
                    break
                }
                let base = dest.baseAddress!.advanced(by: index * sliceVoxelCount)
                base.update(from: pixels, count: sliceVoxelCount)
                if let progress {
                    let fraction = Double(index + 1) / Double(depth)
                    let sliceData = Data(bytes: pixels, count: pixels.count * MemoryLayout<Int16>.size)
                    progress(fraction, index + 1, sliceData, progressVolume)
                }
            }
        }

        if let error = loadError {
            throw error
        }

        let volume = DicomSeriesVolume(voxels: voxelData,
                                       width: width,
                                       height: height,
                                       depth: depth,
                                       spacing: spacing,
                                       orientation: orientationMatrix,
                                       origin: originForVolume,
                                       rescaleSlope: rescaleSlope,
                                       rescaleIntercept: rescaleIntercept,
                                       bitsAllocated: bitsAllocated,
                                       isSignedPixel: pixelRepresentation == 1,
                                       seriesDescription: seriesDescription)

        // Clear decoder cache to free memory
        decoderCache.removeAll()

        return volume
    }
}

// MARK: - Helpers

private extension DicomSeriesLoader {
    func listDicomFiles(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .nameKey]
        guard let enumerator = fm.enumerator(at: directory,
                                             includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles]) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
            if resourceValues.isDirectory == true { continue }
            if resourceValues.isRegularFile == true {
                if fileURL.pathExtension.lowercased() == "dcm" || fileURL.pathExtension.isEmpty {
                    urls.append(fileURL)
                }
            }
        }
        return urls
    }

    func decodeSlice(at url: URL,
                     expectedWidth: Int,
                     expectedHeight: Int,
                     isSigned: Bool) throws -> [Int16] {
        // Try to use cached decoder first, fallback to creating new one
        let decoder: DicomDecoderProtocol
        if let cachedDecoder = decoderCache[url] {
            decoder = cachedDecoder
        } else {
            decoder = decoderFactory()
            decoder.setDicomFilename(url.path)
        }

        guard decoder.dicomFileReadSuccess,
              decoder.width == expectedWidth,
              decoder.height == expectedHeight,
              decoder.bitDepth == 16,
              decoder.samplesPerPixel == 1 else {
            throw DicomSeriesLoaderError.failedToDecode(url)
        }

        guard let pixels = decoder.getPixels16() else {
            throw DicomSeriesLoaderError.failedToDecode(url)
        }

        if isSigned {
            return pixels.map { value in
                let signed = Int32(value) + Int32(Int16.min)
                return Int16(truncatingIfNeeded: signed)
            }
        } else {
            return pixels.map { Int16(bitPattern: $0) }
        }
    }

    func computeZSpacing(from slices: [SliceMeta],
                         normal: SIMD3<Double>) -> Double? {
        guard slices.count > 1 else { return nil }
        var distances: [Double] = []
        distances.reserveCapacity(slices.count - 1)

        for idx in 1..<slices.count {
            if let p0 = slices[idx - 1].position, let p1 = slices[idx].position {
                let d0 = simd_dot(p0, normal)
                let d1 = simd_dot(p1, normal)
                let delta = abs(d1 - d0)
                if delta > 0 {
                    distances.append(delta)
                }
            }
        }

        guard !distances.isEmpty else { return nil }
        let sum = distances.reduce(0, +)
        return sum / Double(distances.count)
    }

    func isApproximatelyEqual(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>, tolerance: Double = 1e-4) -> Bool {
        abs(lhs.x - rhs.x) < tolerance &&
        abs(lhs.y - rhs.y) < tolerance &&
        abs(lhs.z - rhs.z) < tolerance
    }
}

// MARK: - Async/Await Extensions

/// Progress update structure for async series loading.
///
/// Provides real-time progress information during asynchronous series loading operations.
/// Used by ``DicomSeriesLoader/loadSeriesWithProgress(in:)`` to report loading progress
/// through an `AsyncStream`.
///
/// ## Usage Example
/// ```swift
/// for try await progress in loader.loadSeriesWithProgress(in: directory) {
///     print("Loaded \(progress.slicesCopied) slices (\(Int(progress.fractionComplete * 100))%)")
///     if progress.fractionComplete >= 1.0 {
///         print("Final volume: \(progress.volumeInfo.width)×\(progress.volumeInfo.height)×\(progress.volumeInfo.depth)")
///     }
/// }
/// ```
public struct SeriesLoadProgress: Sendable {
    /// Fraction of loading complete (0.0 to 1.0)
    public let fractionComplete: Double

    /// Number of slices successfully copied to the volume buffer
    public let slicesCopied: Int

    /// Optional pixel data for the current slice being processed
    public let currentSliceData: Data?

    /// Volume descriptor with metadata (includes final data when loading is complete)
    public let volumeInfo: DicomSeriesVolume
}

@available(macOS 10.15, iOS 13.0, *)
extension DicomSeriesLoader {

    /// Asynchronously loads a DICOM series from a directory.
    ///
    /// This async method provides the same functionality as the synchronous
    /// ``loadSeries(in:progress:)`` but can be called from async contexts without
    /// blocking the calling thread.
    ///
    /// The file loading and volume assembly is performed on a background thread
    /// using `Task.detached` to avoid blocking the calling thread. Progress callbacks
    /// are still supported for monitoring loading progress.
    ///
    /// ## Example
    /// ```swift
    /// Task {
    ///     do {
    ///         let volume = try await loader.loadSeries(in: directoryURL) { fraction, slices, _, _ in
    ///             print("Loading: \(Int(fraction * 100))% (\(slices) slices)")
    ///         }
    ///         print("Loaded volume: \(volume.width)×\(volume.height)×\(volume.depth)")
    ///     } catch {
    ///         print("Failed to load series: \(error)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - directory: Directory containing DICOM slices
    ///   - progress: Optional callback invoked with (fractionComplete, slicesCopied, sliceData, volume)
    /// - Returns: ``DicomSeriesVolume`` with voxel buffer and geometry metadata
    /// - Throws: ``DicomSeriesLoaderError`` on validation or decoding failures
    public func loadSeries(
        in directory: URL,
        progress: ProgressHandler? = nil
    ) async throws -> DicomSeriesVolume {
        try await Task.detached(priority: .userInitiated) {
            try self.loadSeries(in: directory, progress: progress)
        }.value
    }

    /// Asynchronously loads a DICOM series from a directory with progress reporting via AsyncStream.
    ///
    /// This async method provides the same functionality as the synchronous
    /// ``loadSeries(in:progress:)`` but can be called from async contexts and
    /// provides progress updates through an `AsyncThrowingStream`.
    ///
    /// The file loading and volume assembly is performed on a background thread
    /// using `Task.detached` to avoid blocking the calling thread. Progress updates
    /// are yielded through the returned stream, allowing callers to monitor
    /// loading progress in real-time using a `for try await` loop.
    ///
    /// ## Example
    /// ```swift
    /// Task {
    ///     for try await progress in loader.loadSeriesWithProgress(in: directoryURL) {
    ///         print("Progress: \(Int(progress.fractionComplete * 100))%")
    ///         if progress.fractionComplete >= 1.0 {
    ///             let volume = progress.volumeInfo
    ///             print("Volume: \(volume.width)×\(volume.height)×\(volume.depth)")
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter directory: Directory containing DICOM slices
    /// - Returns: `AsyncThrowingStream` that yields ``SeriesLoadProgress`` updates
    /// - Throws: ``DicomSeriesLoaderError`` on validation or decoding failures
    public func loadSeriesWithProgress(
        in directory: URL
    ) -> AsyncThrowingStream<SeriesLoadProgress, Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    // Load series using synchronous method with progress callback
                    let volume = try self.loadSeries(in: directory) { fraction, slicesCopied, sliceData, volumeInfo in
                        // Yield progress update through the stream
                        let progress = SeriesLoadProgress(
                            fractionComplete: fraction,
                            slicesCopied: slicesCopied,
                            currentSliceData: sliceData,
                            volumeInfo: volumeInfo
                        )
                        continuation.yield(progress)
                    }

                    // Yield final progress update with complete volume
                    let finalProgress = SeriesLoadProgress(
                        fractionComplete: 1.0,
                        slicesCopied: volume.depth,
                        currentSliceData: nil,
                        volumeInfo: volume
                    )
                    continuation.yield(finalProgress)

                    // Complete the stream successfully
                    continuation.finish()
                } catch {
                    // Complete the stream with error
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
