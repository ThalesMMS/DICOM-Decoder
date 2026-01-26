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

public enum DicomSeriesLoaderError: Error {
    case noDicomFiles
    case unsupportedSamplesPerPixel(Int)
    case unsupportedBitDepth(Int)
    case inconsistentDimensions
    case inconsistentOrientation
    case inconsistentPixelRepresentation
    case failedToDecode(URL)
}

/// Represents a loaded DICOM volume assembled from a directory of slices.
public struct DicomSeriesVolume {
    public let voxels: Data
    public let width: Int
    public let height: Int
    public let depth: Int
    public let spacing: SIMD3<Double>
    public let orientation: simd_double3x3
    public let origin: SIMD3<Double>
    public let rescaleSlope: Double
    public let rescaleIntercept: Double
    public let bitsAllocated: Int
    public let isSignedPixel: Bool
    public let seriesDescription: String
}

private struct SliceMeta {
    let url: URL
    let position: SIMD3<Double>?
    let instanceNumber: Int?
    let projection: Double?
}

public final class DicomSeriesLoader: DicomSeriesLoaderProtocol {
    public typealias ProgressHandler = (Double, Int, Data?, DicomSeriesVolume) -> Void

    // MARK: - Properties

    private let decoderFactory: () -> DicomDecoderProtocol

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
        let decoder = decoderFactory()
        decoder.setDicomFilename(url.path)
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
