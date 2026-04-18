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

struct SliceMeta {
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

    let decoderFactory: (String) throws -> DicomDecoderProtocol

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
        self.init(decoderFactory: { path in
            let decoder = decoderFactory()
            decoder.setDicomFilename(path)
            return decoder
        })
    }

    /// Loads a DICOM series from a directory and assembles all slices into a single 16-bit volume.
    /// - Parameters:
    ///   - directory: URL of the directory containing the DICOM files to load.
    ///   - progress: Optional callback invoked after each decoded slice with the fraction complete, the 1-based slice index, the decoded slice voxel `Data`, and a lightweight `DicomSeriesVolume` descriptor for the series.
    /// - Returns: A `DicomSeriesVolume` containing the assembled contiguous 16-bit voxel buffer and associated geometry, spacing, orientation, origin, rescale parameters, pixel format, and series description.
    /// - Throws:
    ///   - `DicomSeriesLoaderError.noDicomFiles` if no valid DICOM files are found or no valid slices could be loaded.
    ///   - `DicomSeriesLoaderError.unsupportedSamplesPerPixel(_)` if a decoded file reports `samplesPerPixel` other than 1.
    ///   - `DicomSeriesLoaderError.unsupportedBitDepth(_)` if a decoded file reports a bit depth other than 16.
    ///   - `DicomSeriesLoaderError.inconsistentDimensions` if slice widths/heights differ across the series.
    ///   - `DicomSeriesLoaderError.inconsistentOrientation` if slice row/column orientation vectors differ across the series.
    ///   - `DicomSeriesLoaderError.inconsistentPixelRepresentation` if `pixelRepresentation` differs across slices.
    ///   - `DicomSeriesLoaderError.failedToDecode(_)` if decoding any slice's pixel data fails during assembly.
    ///   - `CancellationError` if the calling task was cancelled during loading.
    public func loadSeries(in directory: URL,
                           progress: ProgressHandler? = nil) throws -> DicomSeriesVolume {
        let decoderCacheLock = DicomLock()
        var decoderCache: [URL: DicomDecoderProtocol] = [:]

        func cachedDecoder(for url: URL) -> DicomDecoderProtocol? {
            decoderCacheLock.withLock {
                decoderCache[url]
            }
        }

        func cacheDecoder(_ decoder: DicomDecoderProtocol, for url: URL) {
            decoderCacheLock.withLock {
                decoderCache[url] = decoder
            }
        }

        if Task.isCancelled {
            throw CancellationError()
        }

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
            if Task.isCancelled {
                throw CancellationError()
            }

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
            cacheDecoder(decoder, for: url)

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
            let instance = decoder.intValue(for: .instanceNumber)

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

        // Acquire a single pooled buffer for reuse across all slices
        var sliceBuffer = BufferPool.shared.acquire(type: [Int16].self, count: sliceVoxelCount)
        defer {
            BufferPool.shared.release(sliceBuffer)
        }

        // Ensure buffer is large enough (pool uses bucketing, may return larger buffer)
        if sliceBuffer.count < sliceVoxelCount {
            // Shouldn't happen, but handle gracefully by extending buffer
            sliceBuffer.append(contentsOf: repeatElement(Int16(0), count: sliceVoxelCount - sliceBuffer.count))
        }

        // Allocate voxel buffer and copy slices sequentially for safety.
        voxelData.withUnsafeMutableBytes { rawBuffer in
            let dest = rawBuffer.bindMemory(to: Int16.self)
            for (index, slice) in slices.enumerated() {
                if Task.isCancelled {
                    loadError = CancellationError()
                    break
                }

                // Decode directly into reused buffer
                let pixelCount = try? self.decodeSliceIntoBuffer(
                    at: slice.url,
                    buffer: &sliceBuffer,
                    expectedWidth: width,
                    expectedHeight: height,
                    isSigned: pixelRepresentation == 1,
                    cachedDecoder: cachedDecoder(for:),
                    cacheDecoder: cacheDecoder(_:for:)
                )

                guard let pixelCount, pixelCount == sliceVoxelCount else {
                    loadError = DicomSeriesLoaderError.failedToDecode(slice.url)
                    break
                }

                let base = dest.baseAddress!.advanced(by: index * sliceVoxelCount)
                base.update(from: sliceBuffer, count: sliceVoxelCount)

                if let progress {
                    let fraction = Double(index + 1) / Double(depth)
                    let sliceData = Data(bytes: sliceBuffer, count: sliceVoxelCount * MemoryLayout<Int16>.size)
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

        return volume
    }
}
