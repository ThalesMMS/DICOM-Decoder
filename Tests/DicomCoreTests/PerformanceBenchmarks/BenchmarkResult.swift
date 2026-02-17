//
//  BenchmarkResult.swift
//  DicomCore
//
//  Results from a single benchmark run.
//  Contains timing measurements and statistical analysis including
//  mean, standard deviation, coefficient of variation, and percentiles.
//
//  Follows timing patterns from DCMDecoderPerformanceTests.swift with
//  CFAbsoluteTimeGetCurrent() for precise measurements.
//
//  Created by automated performance benchmarking suite.
//

import Foundation

/// Results from a single benchmark run
public struct BenchmarkResult {
    /// Mean execution time in seconds
    public let meanTime: Double

    /// Standard deviation of execution time in seconds
    public let stdDevTime: Double

    /// All individual timing measurements (seconds)
    public let timings: [Double]

    /// Number of iterations performed
    public let iterationCount: Int

    /// Initialize benchmark result with timing measurements
    ///
    /// - Parameter timings: Array of timing measurements in seconds
    /// - Throws: BenchmarkError.insufficientData if timings array is empty
    public init(timings: [Double]) throws {
        guard !timings.isEmpty else {
            throw BenchmarkError.insufficientData("Cannot create BenchmarkResult with empty timings array")
        }

        self.timings = timings
        self.iterationCount = timings.count

        // Calculate mean
        let sum = timings.reduce(0.0, +)
        let mean = sum / Double(timings.count)
        self.meanTime = mean

        // Calculate standard deviation
        if timings.count > 1 {
            let variance = timings.map { pow($0 - mean, 2) }.reduce(0.0, +) / Double(timings.count - 1)
            self.stdDevTime = sqrt(variance)
        } else {
            self.stdDevTime = 0.0
        }
    }

    /// Initialize benchmark result with pre-calculated statistics
    ///
    /// - Parameters:
    ///   - meanTime: Mean execution time in seconds
    ///   - stdDevTime: Standard deviation of execution time
    ///   - timings: Array of timing measurements
    ///   - iterationCount: Number of iterations performed
    public init(meanTime: Double, stdDevTime: Double, timings: [Double], iterationCount: Int) {
        self.meanTime = meanTime
        self.stdDevTime = stdDevTime
        self.timings = timings
        self.iterationCount = iterationCount
    }

    // MARK: - Statistical Metrics

    /// Coefficient of variation (stddev/mean as percentage)
    public var coefficientOfVariation: Double {
        guard meanTime > 0 else { return 0 }
        return (stdDevTime / meanTime) * 100.0
    }

    /// Minimum execution time in seconds
    public var minTime: Double {
        return timings.min() ?? 0
    }

    /// Maximum execution time in seconds
    public var maxTime: Double {
        return timings.max() ?? 0
    }

    /// Median execution time in seconds
    public var medianTime: Double {
        let sorted = timings.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }

    /// 95th percentile execution time in seconds
    public var p95Time: Double {
        return percentile(95.0)
    }

    /// 99th percentile execution time in seconds
    public var p99Time: Double {
        return percentile(99.0)
    }

    /// Calculate percentile value
    ///
    /// - Parameter percentile: Percentile to calculate (0-100)
    /// - Returns: Timing value at the specified percentile
    public func percentile(_ percentile: Double) -> Double {
        guard !timings.isEmpty else { return 0 }
        let sorted = timings.sorted()
        let index = Int(ceil(percentile / 100.0 * Double(sorted.count))) - 1
        let clampedIndex = max(0, min(sorted.count - 1, index))
        return sorted[clampedIndex]
    }

    /// Standard error of the mean
    public var standardError: Double {
        guard iterationCount > 0 else { return 0 }
        return stdDevTime / sqrt(Double(iterationCount))
    }

    // MARK: - Formatted Output

    /// Format timing value in milliseconds
    ///
    /// - Parameter time: Time in seconds
    /// - Returns: Formatted string with ms suffix
    public static func formatMilliseconds(_ time: Double) -> String {
        return String(format: "%.3f ms", time * 1000.0)
    }

    /// Format timing value in microseconds
    ///
    /// - Parameter time: Time in seconds
    /// - Returns: Formatted string with µs suffix
    public static func formatMicroseconds(_ time: Double) -> String {
        return String(format: "%.1f µs", time * 1_000_000.0)
    }

    /// Generate summary statistics string
    ///
    /// - Returns: Multi-line string with statistical summary
    public func summary() -> String {
        var lines = [String]()
        lines.append("Iterations: \(iterationCount)")
        lines.append("Mean: \(Self.formatMilliseconds(meanTime))")
        lines.append("Std Dev: \(Self.formatMilliseconds(stdDevTime))")
        lines.append("Min: \(Self.formatMilliseconds(minTime))")
        lines.append("Median: \(Self.formatMilliseconds(medianTime))")
        lines.append("Max: \(Self.formatMilliseconds(maxTime))")
        lines.append("P95: \(Self.formatMilliseconds(p95Time))")
        lines.append("P99: \(Self.formatMilliseconds(p99Time))")
        lines.append("CV: \(String(format: "%.2f%%", coefficientOfVariation))")
        return lines.joined(separator: "\n")
    }

    /// Compare this result with another and calculate speedup
    ///
    /// - Parameter other: Other benchmark result to compare with
    /// - Returns: Speedup ratio (this / other), positive values mean this is faster
    public func speedup(comparedTo other: BenchmarkResult) -> Double {
        guard other.meanTime > 0 else { return 0 }
        return other.meanTime / self.meanTime
    }

    /// Calculate relative performance difference as percentage
    ///
    /// - Parameter other: Other benchmark result to compare with
    /// - Returns: Percentage difference (positive = this is faster)
    public func percentageDifference(comparedTo other: BenchmarkResult) -> Double {
        guard other.meanTime > 0 else { return 0 }
        return ((other.meanTime - self.meanTime) / other.meanTime) * 100.0
    }
}

// MARK: - Codable Conformance

extension BenchmarkResult: Codable {
    enum CodingKeys: String, CodingKey {
        case meanTime
        case stdDevTime
        case timings
        case iterationCount
    }
}

// MARK: - CustomStringConvertible

extension BenchmarkResult: CustomStringConvertible {
    public var description: String {
        return summary()
    }
}
