import Foundation
import simd

// MARK: - Helpers

extension DicomSeriesLoader {
    /// Finds DICOM candidate files by recursively enumerating a directory and returning regular files with a `.dcm` extension or no extension.
    /// - Parameters:
    ///   - directory: The directory URL to search.
    /// - Returns: An array of file URLs for regular files within `directory` whose path extension is `"dcm"` (case-insensitive) or is empty. Returns an empty array if the directory cannot be enumerated.
    /// - Throws: An error from `URL.resourceValues(forKeys:)` if reading resource values for an entry fails.
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

    /// Decode a DICOM image slice at the given URL and return its pixel values as an array of 16-bit integers.
    /// - Parameters:
    ///   - url: File URL of the DICOM slice to decode.
    ///   - expectedWidth: Expected image width in pixels; decoder must match this value.
    ///   - expectedHeight: Expected image height in pixels; decoder must match this value.
    ///   - isSigned: If `true`, map pixel values into signed `Int16` range using an offset; if `false`, preserve the raw 16-bit bit pattern as `Int16`.
    /// - Returns: An array of `Int16` pixel values for the decoded slice, converted according to `isSigned`.
    /// - Throws: `DicomSeriesLoaderError.failedToDecode(url)` if the decoder's format does not match the expected dimensions/format or pixel data cannot be obtained; also rethrows errors from the `decoderFactory` when creating a decoder.
    func decodeSlice(at url: URL,
                     expectedWidth: Int,
                     expectedHeight: Int,
                     isSigned: Bool,
                     cachedDecoder: (URL) -> DicomDecoderProtocol? = { _ in nil },
                     cacheDecoder: (DicomDecoderProtocol, URL) -> Void = { _, _ in }) throws -> [Int16] {
        // Try to use cached decoder first, fallback to creating new one
        let decoder: DicomDecoderProtocol
        let createdNewDecoder: Bool
        if let cached = cachedDecoder(url) {
            decoder = cached
            createdNewDecoder = false
        } else {
            // Load DICOM file using factory
            decoder = try decoderFactory(url.path)
            createdNewDecoder = true
        }

        guard decoder.width == expectedWidth,
              decoder.height == expectedHeight,
              decoder.bitDepth == 16,
              decoder.samplesPerPixel == 1 else {
            throw DicomSeriesLoaderError.failedToDecode(url)
        }

        if createdNewDecoder {
            cacheDecoder(decoder, url)
        }

        guard let pixels = decoder.getPixels16() else {
            throw DicomSeriesLoaderError.failedToDecode(url)
        }

        // When isSigned is true, shift 0...65535 samples by Int16.min to map
        // them into signed DICOM range. Otherwise preserve the raw bit pattern.
        if isSigned {
            return pixels.map { value in
                let signed = Int32(value) + Int32(Int16.min)
                return Int16(truncatingIfNeeded: signed)
            }
        } else {
            return pixels.map { Int16(bitPattern: $0) }
        }
    }

    /// Decodes a DICOM slice directly into a provided buffer for memory efficiency.
    ///
    /// This method writes decoded pixel data directly into the provided buffer,
    /// avoiding intermediate allocations. Used by loadSeries() to reuse a single
    /// buffer across multiple slices.
    ///
    /// - Parameters:
    ///   - url: File URL of the DICOM slice
    ///   - buffer: Mutable buffer to write decoded pixels into (must have sufficient capacity)
    ///   - expectedWidth: Expected image width for validation
    ///   - expectedHeight: Expected image height for validation
    ///   - isSigned: Whether pixel representation is signed
    /// - Returns: Number of pixels written to buffer
    /// Decode a DICOM slice from `url` into the provided `buffer`, converting pixel samples to `Int16` using the specified signedness and validating expected image dimensions and format.
    /// - Parameters:
    ///   - url: File URL of the DICOM slice to decode.
    ///   - buffer: Destination buffer to receive decoded pixels. Must have a count greater than or equal to the number of pixels in the slice.
    ///   - expectedWidth: Expected image width; decoding fails if the decoder reports a different width.
    ///   - expectedHeight: Expected image height; decoding fails if the decoder reports a different height.
    ///   - isSigned: Interpret decoded 16-bit samples as signed when `true`, as unsigned when `false`.
    /// - Returns: The number of pixels written into `buffer`.
    /// - Throws: `DicomSeriesLoaderError.failedToDecode(url)` if the decoder or pixel data cannot be obtained, the decoder's format does not match the expectations, or `buffer` is too small.
    func decodeSliceIntoBuffer(
        at url: URL,
        buffer: inout [Int16],
        expectedWidth: Int,
        expectedHeight: Int,
        isSigned: Bool,
        cachedDecoder: (URL) -> DicomDecoderProtocol? = { _ in nil },
        cacheDecoder: (DicomDecoderProtocol, URL) -> Void = { _, _ in }
    ) throws -> Int {
        // Try to use cached decoder first, fallback to creating new one
        let decoder: DicomDecoderProtocol
        let createdNewDecoder: Bool
        if let cached = cachedDecoder(url) {
            decoder = cached
            createdNewDecoder = false
        } else {
            // Load DICOM file using factory
            decoder = try decoderFactory(url.path)
            createdNewDecoder = true
        }

        guard decoder.width == expectedWidth,
              decoder.height == expectedHeight,
              decoder.bitDepth == 16,
              decoder.samplesPerPixel == 1 else {
            throw DicomSeriesLoaderError.failedToDecode(url)
        }

        if createdNewDecoder {
            cacheDecoder(decoder, url)
        }

        guard let pixels = decoder.getPixels16() else {
            throw DicomSeriesLoaderError.failedToDecode(url)
        }

        let pixelCount = pixels.count

        // Ensure buffer has sufficient capacity
        guard buffer.count >= pixelCount else {
            throw DicomSeriesLoaderError.failedToDecode(url)
        }

        // When isSigned is true, Int32(Int16.min) maps unsigned samples into
        // signed DICOM range; otherwise Int16(bitPattern:) keeps raw bits.
        if isSigned {
            for i in 0..<pixelCount {
                let signed = Int32(pixels[i]) + Int32(Int16.min)
                buffer[i] = Int16(truncatingIfNeeded: signed)
            }
        } else {
            for i in 0..<pixelCount {
                buffer[i] = Int16(bitPattern: pixels[i])
            }
        }

        return pixelCount
    }

    /// Computes the average spacing between adjacent slices along a given normal vector.
    /// 
    /// The function projects slice positions onto `normal`, measures absolute distances between consecutive projections,
    /// and returns the arithmetic mean of all non-zero distances. Slices with missing `position` values are skipped.
    /// - Parameters:
    ///   - slices: An ordered array of `SliceMeta` representing the series (order defines adjacency).
    ///   - normal: The unit or non-unit vector to project positions onto; spacing is measured along this direction.
    /// - Returns: The average spacing along `normal` as a `Double`, or `nil` if fewer than two valid distances are available.
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

    /// Checks whether two 3D vectors are equal within a per-component tolerance.
    /// - Parameters:
    ///   - lhs: The left-hand side vector.
    ///   - rhs: The right-hand side vector.
    ///   - tolerance: Maximum allowed absolute difference for each component.
    /// - Returns: `true` if the absolute difference of `x`, `y`, and `z` components are each less than `tolerance`, `false` otherwise.
    func isApproximatelyEqual(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>, tolerance: Double = 1e-4) -> Bool {
        abs(lhs.x - rhs.x) < tolerance &&
        abs(lhs.y - rhs.y) < tolerance &&
        abs(lhs.z - rhs.z) < tolerance
    }
}
