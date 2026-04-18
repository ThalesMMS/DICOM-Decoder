import Foundation

// MARK: - DCMWindowingProcessor Batch Processing Extensions

enum WindowingBatchError: Error, Equatable, LocalizedError {
    case mismatchedInputCounts(imagePixels: Int, centers: Int, widths: Int)

    var errorDescription: String? {
        switch self {
        case .mismatchedInputCounts(let imagePixels, let centers, let widths):
            return "Mismatched input counts: imagePixels=\(imagePixels), centers=\(centers), widths=\(widths)"
        }
    }
}

extension DCMWindowingProcessor {

    /// Internal batch windowing helper used by implementation and tests; this is not part of the public API.
    ///
    /// Applies window/level to a batch of 16-bit image pixel buffers using corresponding centers and widths.
    /// - Parameters:
    ///   - imagePixels: An array of 16-bit pixel buffers (one buffer per image).
    ///   - centers: Window center values aligned by index with `imagePixels`.
    ///   - widths: Window width values aligned by index with `imagePixels`.
    /// - Returns: An array of optional `Data` objects where each element is the windowed 8-bit image for the corresponding input, or `nil` if processing that image failed.
    /// - Throws: `WindowingBatchError.mismatchedInputCounts` when the three input arrays do not have the same count.
    static func batchApplyWindowLevel(
        imagePixels: [[UInt16]],
        centers: [Double],
        widths: [Double]
    ) throws -> [Data?] {
        guard imagePixels.count == centers.count && centers.count == widths.count else {
            throw WindowingBatchError.mismatchedInputCounts(
                imagePixels: imagePixels.count,
                centers: centers.count,
                widths: widths.count
            )
        }

        return zip(zip(imagePixels, centers), widths).map { imageCenterWidth in
            let ((pixels, center), width) = imageCenterWidth
            return applyWindowLevel(pixels16: pixels, center: center, width: width, processingMode: .auto)
        }
    }

    /// Computes optimal window/level settings for each image in a batch.
    /// - Parameter imagePixels: An array where each element is a 16‑bit pixel buffer for one image.
    /// - Returns: An array of `WindowSettings`, one entry for each input pixel buffer.
    public static func batchCalculateOptimalWindowLevelV2(imagePixels: [[UInt16]]) -> [WindowSettings] {
        return imagePixels.map { pixels in
            calculateOptimalWindowLevelV2(pixels16: pixels)
        }
    }
}

// MARK: - DCMWindowingProcessor Performance Extensions

extension DCMWindowingProcessor {

    /// Converts a 16-bit pixel buffer to an 8-bit windowed Data buffer using a linear window/level transform.
    /// - Parameters:
    ///   - pixels16: Row-major 16-bit pixel values to be windowed.
    ///   - center: Window center value.
    ///   - width: Window width (must be greater than 0).
    ///   - useParallel: When `true`, uses concurrent processing for large buffers (threshold: > 10,000 pixels).
    /// - Returns: A `Data` buffer of 8-bit pixel values clamped to `0...255`, or `nil` if `pixels16` is empty or `width ≤ 0`.
    static func optimizedApplyWindowLevel(
        pixels16: [UInt16],
        center: Double,
        width: Double,
        useParallel: Bool = true
    ) -> Data? {
        guard !pixels16.isEmpty, width > 0 else { return nil }

        let minLevel = center - width / 2.0
        let maxLevel = center + width / 2.0
        let range = maxLevel - minLevel
        let rangeInv: Double = range > 0 ? 255.0 / range : 1.0

        var bytes = [UInt8](repeating: 0, count: pixels16.count)

        if useParallel && pixels16.count > 10000 {
            let concurrentWorkers = max(1, min(pixels16.count, ProcessInfo.processInfo.activeProcessorCount))

            // Use parallel processing for large datasets with thread-safe buffer access
            bytes.withUnsafeMutableBufferPointer { bufferPointer in
                DispatchQueue.concurrentPerform(iterations: concurrentWorkers) { chunk in
                    let start = chunk * pixels16.count / concurrentWorkers
                    let end = (chunk == concurrentWorkers - 1) ? pixels16.count : (chunk + 1) * pixels16.count / concurrentWorkers

                    for i in start..<end {
                        let value = (Double(pixels16[i]) - minLevel) * rangeInv
                        bufferPointer[i] = UInt8(max(0.0, min(255.0, value)))
                    }
                }
            }
        } else {
            // Sequential processing for smaller datasets
            for i in 0..<pixels16.count {
                let value = (Double(pixels16[i]) - minLevel) * rangeInv
                bytes[i] = UInt8(max(0.0, min(255.0, value)))
            }
        }

        return Data(bytes)
    }
}
