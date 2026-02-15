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

// MARK: - Batch Loading Result

/// Result of loading a single DICOM file in batch operations.
///
/// Represents the outcome of loading an individual DICOM file, containing either
/// a successfully loaded decoder instance or an error that occurred during loading.
/// Used by ``DicomSeriesLoader/batchLoadFiles(urls:maxConcurrency:)`` for concurrent
/// file loading operations.
///
/// ## Usage Example
/// ```swift
/// let urls = [url1, url2, url3]
/// let results = await loader.batchLoadFiles(urls: urls, maxConcurrency: 4)
/// for result in results {
///     if result.success {
///         print("Loaded: \(result.decoder!.width) × \(result.decoder!.height)")
///     } else {
///         print("Failed to load \(result.url): \(result.error!)")
///     }
/// }
/// ```
public struct DicomFileResult: Sendable {
    /// The file URL that was processed
    public let url: URL

    /// The successfully loaded decoder, or nil if loading failed
    public let decoder: (any DicomDecoderProtocol)?

    /// The typed DICOM error that occurred, or nil if loading succeeded
    public let error: DICOMError?

    /// Whether the file loaded successfully
    public var success: Bool { decoder != nil }

    /// Creates a result representing a successful file load
    /// - Parameters:
    ///   - url: The file URL
    ///   - decoder: The successfully loaded decoder
    public init(url: URL, decoder: any DicomDecoderProtocol) {
        self.url = url
        self.decoder = decoder
        self.error = nil
    }

    /// Creates a result representing a failed file load
    /// - Parameters:
    ///   - url: The file URL
    ///   - error: The DICOM error that occurred
    public init(url: URL, error: DICOMError) {
        self.url = url
        self.decoder = nil
        self.error = error
    }
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
/// let loader = DicomSeriesLoader(decoderFactory: { _ in MockDicomDecoder() })
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

    private let decoderFactory: (String) throws -> DicomDecoderProtocol
    private var decoderCache: [URL: DicomDecoderProtocol] = [:]

    // MARK: - Initialization

    /// Required protocol initializer - uses default DCMDecoder.
    public init() {
        self.decoderFactory = { path in try DCMDecoder(contentsOfFile: path) }
    }

    /// Dependency injection initializer for testing and customization.
    /// - Parameter decoderFactory: Factory closure that creates DicomDecoderProtocol instances from a file path
    public init(decoderFactory: @escaping (String) throws -> DicomDecoderProtocol) {
        self.decoderFactory = decoderFactory
    }

    /// Backward-compatible dependency injection initializer.
    /// - Parameter decoderFactory: Factory closure that creates decoders without a path argument.
    @available(*, deprecated, message: "Use init(decoderFactory: (String) throws -> DicomDecoderProtocol) instead.")
    public convenience init(decoderFactory: @escaping () -> DicomDecoderProtocol) {
        self.init(decoderFactory: { _ in decoderFactory() })
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
            // Try to load DICOM file using factory
            let decoder: DicomDecoderProtocol
            do {
                decoder = try decoderFactory(url.path)
            } catch {
                // Skip files that fail to load
                continue
            }

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
                rescaleSlope = decoder.rescaleParametersV2.slope
                rescaleIntercept = decoder.rescaleParametersV2.intercept
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
            // Load DICOM file using factory
            decoder = try decoderFactory(url.path)
        }

        guard decoder.width == expectedWidth,
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

// MARK: - Legacy Decoder Compatibility

private extension DicomDecoderProtocol {
    @available(*, deprecated, message: "Use throwing initializers instead of setDicomFilename(_:).")
    func setDicomFilename(_ filename: String) {
        (self as? DCMDecoder)?.setDicomFilename(filename)
    }

    @available(*, deprecated, message: "Use throwing initializers/error handling instead of dicomFileReadSuccess.")
    var dicomFileReadSuccess: Bool {
        if let decoder = self as? DCMDecoder {
            return decoder.dicomFileReadSuccess
        }
        return isValid()
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
    /// Creates a stream of progress updates while loading a DICOM series from the specified directory.
    ///
    /// The stream yields `SeriesLoadProgress` values as slices are decoded and copied, and yields a final
    /// progress item containing the completed `DicomSeriesVolume`. If loading fails, the stream finishes with the encountered error.
    /// - Parameter directory: Filesystem directory containing the DICOM series to load.
    /// - Returns: An `AsyncThrowingStream` that emits `SeriesLoadProgress` updates and may finish throwing an error if loading fails.
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

    /// Loads multiple DICOM series directories concurrently with progress tracking.
    ///
    /// This method processes multiple series directories in parallel using Swift's TaskGroup,
    /// enabling efficient concurrent loading for batch operations. Each series is loaded
    /// using ``loadSeries(in:progress:)-6zq7v`` and assembled into a complete volume.
    ///
    /// Progress is aggregated across all series and reported through the callback handler.
    /// The progress fraction represents the overall completion (number of series completed
    /// divided by total series count), and the completed count indicates how many series
    /// have been fully loaded.
    ///
    /// ## Performance Characteristics
    ///
    /// - **Concurrency**: Respects `maxConcurrency` limit to avoid overwhelming the system
    /// - **Memory**: Each series loads independently, memory scales with concurrent count
    /// - **Thread-Safe**: Uses TaskGroup for structured concurrency, safe for actor contexts
    /// - **Progress**: Aggregated progress across all series operations
    ///
    /// ## Example
    /// ```swift
    /// let loader = DicomSeriesLoader()
    /// let seriesDirectories = [seriesDir1, seriesDir2, seriesDir3]
    ///
    /// let volumes = try await loader.batchLoadSeries(
    ///     seriesDirectories: seriesDirectories,
    ///     maxConcurrency: 2
    /// ) { fraction, completed in
    ///     print("Progress: \(Int(fraction * 100))% - \(completed) series completed")
    /// }
    ///
    /// for (index, volume) in volumes.enumerated() {
    ///     print("Series \(index): \(volume.width)×\(volume.height)×\(volume.depth)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - seriesDirectories: Array of directory URLs containing DICOM series
    ///   - maxConcurrency: Maximum number of concurrent series loading operations (default: 2)
    ///   - progressHandler: Optional callback invoked with (fractionComplete, seriesCompleted)
    /// - Returns: Array of ``DicomSeriesVolume`` in the same order as input directories
    /// Concurrently loads DICOM series from the given directories and returns their volumes in the same order as the input.
    /// - Parameters:
    ///   - seriesDirectories: Array of directory URLs, each containing a DICOM series to load.
    ///   - maxConcurrency: Maximum number of series to load in parallel (default is 2).
    ///   - progressHandler: Optional callback that receives `(fractionComplete, completedCount)` as each series finishes.
    /// - Returns: An array of `DicomSeriesVolume` objects ordered to match `seriesDirectories`.
    /// - Throws: Rethrows any error encountered while loading a series. May throw `DicomSeriesLoaderError.noDicomFiles` if a loaded result is unexpectedly missing.
    public func batchLoadSeries(
        seriesDirectories: [URL],
        maxConcurrency: Int = 2,
        progressHandler: (@Sendable (Double, Int) -> Void)? = nil
    ) async throws -> [DicomSeriesVolume] {
        // Early return for empty input
        guard !seriesDirectories.isEmpty else { return [] }

        // Ensure at least one task is scheduled before awaiting group.next().
        let effectiveMaxConcurrency = max(1, maxConcurrency)

        // Thread-safe counter for progress tracking
        final class Counter: @unchecked Sendable {
            private let lock = DicomLock()
            private var value = 0

            /// Atomically increments the internal counter and returns the updated value.
            /// - Returns: The counter value after incrementing.
            func increment() -> Int {
                lock.withLock {
                    value += 1
                    return value
                }
            }
        }

        let completedCount = Counter()
        let localDecoderFactory = decoderFactory

        // Store results indexed by original position
        var resultsByIndex: [Int: DicomSeriesVolume] = [:]

        // Use task group to load series concurrently
        try await withThrowingTaskGroup(of: (Int, DicomSeriesVolume).self) { group in
            // Enumerate directories to track ordering
            for (index, directory) in seriesDirectories.enumerated() {
                // Respect concurrency limit
                if index >= effectiveMaxConcurrency {
                    // Wait for one task to complete before adding more
                    let (completedIndex, volume) = try await group.next()!
                    resultsByIndex[completedIndex] = volume

                    // Update progress
                    let completed = completedCount.increment()
                    let fraction = Double(completed) / Double(seriesDirectories.count)
                    progressHandler?(fraction, completed)
                }

                // Add task to load this series
                // Create a separate loader instance for each series to avoid concurrent
                // access to the decoderCache which is not thread-safe
                group.addTask {
                    let loader = DicomSeriesLoader(decoderFactory: localDecoderFactory)
                    let volume = try await loader.loadSeries(in: directory, progress: nil)
                    return (index, volume)
                }
            }

            // Collect remaining results
            for try await (index, volume) in group {
                resultsByIndex[index] = volume

                // Update progress
                let completed = completedCount.increment()
                let fraction = Double(completed) / Double(seriesDirectories.count)
                progressHandler?(fraction, completed)
            }
        }

        // Reconstruct results in original order
        var results: [DicomSeriesVolume] = []
        results.reserveCapacity(seriesDirectories.count)

        for index in 0..<seriesDirectories.count {
            guard let volume = resultsByIndex[index] else {
                // This should never happen, but provide error handling
                throw DicomSeriesLoaderError.noDicomFiles
            }
            results.append(volume)
        }

        return results
    }

    /// Loads multiple DICOM files concurrently using structured concurrency.
    ///
    /// This method processes multiple DICOM files in parallel using Swift's TaskGroup,
    /// enabling efficient concurrent loading for batch operations. Each file is loaded
    /// into a separate decoder instance, respecting the specified concurrency limit.
    ///
    /// The method returns an array of ``DicomFileResult`` instances in the same order
    /// as the input URLs, where each result contains either a successfully loaded decoder
    /// or the error that occurred. This allows callers to handle partial successes and
    /// identify which specific files failed.
    ///
    /// ## Performance Characteristics
    ///
    /// - **Concurrency**: Respects `maxConcurrency` limit to avoid overwhelming the system
    /// - **Memory**: Each decoder is independent, memory scales linearly with concurrent count
    /// - **Thread-Safe**: Uses TaskGroup for structured concurrency, safe for actor contexts
    ///
    /// ## Example
    /// ```swift
    /// let loader = DicomSeriesLoader()
    /// let urls = try FileManager.default.contentsOfDirectory(at: directoryURL,
    ///                                                          includingPropertiesForKeys: nil)
    /// let results = await loader.batchLoadFiles(urls: urls, maxConcurrency: 4)
    /// let successes = results.compactMap { result -> DCMDecoder? in
    ///     if case .success(let decoder) = result.result { return decoder }
    ///     return nil
    /// }
    /// print("Successfully loaded \(successes.count) of \(results.count) files")
    /// ```
    ///
    /// - Parameters:
    ///   - urls: Array of DICOM file URLs to load
    ///   - maxConcurrency: Maximum number of concurrent loading operations (default: 4)
    /// - Returns: Array of ``DicomFileResult`` in the same order as input URLs
    /// Load multiple DICOM files concurrently and produce per-file results in the same order as the input URLs.
    /// - Parameters:
    ///   - urls: The file URLs to load.
    ///   - maxConcurrency: Maximum number of concurrent file-loading tasks; values less than 1 behave as 1.
    /// - Returns: An array of `DicomFileResult` ordered to match `urls`, where each element contains either a decoder for a successful load or an error describing the failure.
    public func batchLoadFiles(
        urls: [URL],
        maxConcurrency: Int = 4
    ) async -> [DicomFileResult] {
        // Early return for empty input
        guard !urls.isEmpty else { return [] }

        // Ensure at least one task is enqueued before waiting on group.next().
        let concurrency = max(1, maxConcurrency)

        // Create results array with same ordering as input
        var results: [DicomFileResult] = []
        results.reserveCapacity(urls.count)
        let localDecoderFactory = decoderFactory

        // Use dictionary to maintain ordering
        var resultsByIndex: [Int: DicomFileResult] = [:]

        await withTaskGroup(of: (Int, DicomFileResult).self) { group in
            // Enumerate URLs to track ordering
            for (index, url) in urls.enumerated() {
                // Respect concurrency limit
                if index >= concurrency {
                    // Wait for one task to complete before adding more
                    if let (completedIndex, result) = await group.next() {
                        resultsByIndex[completedIndex] = result
                    }
                }

                // Add task to load this file
                group.addTask {
                    let result = await Self.loadSingleFileStatic(
                        url: url,
                        factory: {
                            if let decoder = try? localDecoderFactory(url.path) {
                                return decoder
                            }
                            return DCMDecoder()
                        }
                    )
                    return (index, result)
                }
            }

            // Collect remaining results
            for await (index, result) in group {
                resultsByIndex[index] = result
            }
        }

        // Reconstruct results in original order
        for index in 0..<urls.count {
            if let result = resultsByIndex[index] {
                results.append(result)
            } else {
                // This should never happen, but provide fallback
                results.append(DicomFileResult(
                    url: urls[index],
                    error: DICOMError.unknown(underlyingError: "Unknown error during batch loading")
                ))
            }
        }

        return results
    }
}

// MARK: - Private Batch Loading Helpers

@available(macOS 10.15, iOS 13.0, *)
private extension DicomSeriesLoader {
    /// Loads a single DICOM file, returning a result with either the decoder or an error.
    /// - Parameters:
    ///   - url: The file URL to load.
    ///   - factory: Sendable factory used to instantiate decoders.
    /// Loads a single DICOM file and produces a `DicomFileResult` describing the outcome.
    /// - Parameters:
    ///   - url: File URL of the DICOM file to load.
    ///   - factory: Decoder factory used to create a fresh decoder instance.
    /// - Returns: A `DicomFileResult` containing a decoder when loading succeeds, or an error when loading fails.
    static func loadSingleFileStatic(
        url: URL,
        factory: @escaping @Sendable () -> DicomDecoderProtocol
    ) async -> DicomFileResult {
        let decoder = factory()

        // Try to load the file using the decoder
        decoder.setDicomFilename(url.path)

        // Check if loading succeeded
        if decoder.dicomFileReadSuccess {
            return DicomFileResult(url: url, decoder: decoder)
        } else {
            let error: DICOMError
            if !FileManager.default.fileExists(atPath: url.path) {
                error = .fileNotFound(path: url.path)
            } else {
                error = .invalidDICOMFormat(reason: "Failed to load DICOM file at \(url.path)")
            }
            return DicomFileResult(url: url, error: error)
        }
    }
}
