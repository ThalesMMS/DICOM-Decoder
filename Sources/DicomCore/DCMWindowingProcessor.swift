//
//  DCMWindowingProcessor.swift
//
//  This type encapsulates medical imaging window/level calculations,
//  basic image enhancement techniques and quality metrics.  All
//  methods are static and operate on Swift collection types
//  rather than raw pointers.  The use of generics and value
//  semantics improves safety and performance compared to the
//  original implementation.
//
//  Processing backends available:
//
//  **Window/Level Operations:**
//  - **vDSP (CPU)**: Accelerate framework vectorised operations.
//    Best for images <800×800 pixels (~1-2ms for 512×512).
//  - **Metal (GPU)**: Compute shader acceleration for large images.
//    Achieves 3.94× speedup on 1024×1024 images vs vDSP (~2.20ms vs ~8.67ms).
//  - Auto-selection uses a 800×800 pixel threshold (640,000 total pixels):
//    images ≥640K pixels use Metal (if available), smaller images use vDSP.
//  - For backward compatibility, the default processing mode is vDSP.
//
//  **Image Enhancement Operations:**
//  - **vImage**: Hardware-accelerated histogram equalization (CLAHE) and
//    convolution operations (noise reduction) using Accelerate framework.
//  - ``vImageEqualization_Planar8``: Optimized histogram equalization
//    with SIMD operations for contrast enhancement.
//    Performance: ~42ms for 512×512 images, ~180ms for 1024×1024 images.
//  - ``vImageConvolve_Planar8``: Cache-friendly 3×3 Gaussian convolution
//    with vector operations for noise reduction.
//    Performance: ~44ms for 512×512 images, ~190ms for 1024×1024 images.
//
//  **Performance Characteristics:**
//  vImage implementations provide significant performance improvements over
//  manual pixel-by-pixel operations through:
//  - SIMD vectorization: Multi-pixel operations processed in parallel
//  - Cache optimization: Tiled processing reduces memory latency
//  - Hardware acceleration: Leverages CPU vector units (NEON on ARM)
//  Typical speedups: 2-5× faster than manual implementations for images
//  larger than 512×512 pixels. Memory overhead: 2× image size for temporary
//  buffers (automatically managed by vImage).
//

import Foundation
import Accelerate

// MARK: - Medical Preset Enumeration

/// Enumeration of common preset window/level settings used in
/// medical imaging.  The underlying raw values mirror those used
/// in the Objective‑C NS_ENUM.  Each case describes a typical
/// anatomy or modality and can be mapped to a pair of centre and
/// width values via ``getPresetValuesV2(preset:)``.
public enum MedicalPreset: Int, CaseIterable {
    // Original CT presets (raw values preserved for backward compatibility)
    case lung       = 0
    case bone       = 1
    case softTissue = 2
    case brain      = 3
    case liver      = 4
    case custom     = 5

    // Additional CT presets
    case mediastinum = 6
    case abdomen     = 7
    case spine       = 8
    case pelvis      = 9

    // Angiography presets
    case angiography = 10
    case pulmonaryEmbolism = 11

    // Other modalities
    case mammography = 12
    case petScan     = 13

    /// Human-readable name for the preset
    public var displayName: String {
        switch self {
        case .lung: return "Lung"
        case .bone: return "Bone"
        case .softTissue: return "Soft Tissue"
        case .brain: return "Brain"
        case .liver: return "Liver"
        case .mediastinum: return "Mediastinum"
        case .abdomen: return "Abdomen"
        case .spine: return "Spine"
        case .pelvis: return "Pelvis"
        case .angiography: return "Angiography"
        case .pulmonaryEmbolism: return "Pulmonary Embolism"
        case .mammography: return "Mammography"
        case .petScan: return "PET Scan"
        case .custom: return "Custom"
        }
    }

    /// Typical modality associated with this preset
    public var associatedModality: String {
        switch self {
        case .lung, .bone, .softTissue, .brain, .liver, .mediastinum,
             .abdomen, .spine, .pelvis, .angiography, .pulmonaryEmbolism:
            return "CT"
        case .mammography:
            return "MG"
        case .petScan:
            return "PT"
        case .custom:
            return "OT"
        }
    }
}

// MARK: - Processing Mode Enumeration

/// Processing backend selection for window/level operations
public enum ProcessingMode {
    /// CPU-based processing using vDSP (Accelerate framework)
    /// - Best for: Small images (<800×800 pixels), guaranteed availability
    /// - Performance: Optimal for small datasets, 1-2ms for 512×512 images
    case vdsp

    /// GPU-based processing using Metal compute shaders
    /// - Best for: Large images (≥800×800 pixels), modern hardware
    /// - Performance: 3.94× speedup on 1024×1024 images vs vDSP
    /// - Requires: Metal-capable device (all iOS 13+, macOS 12+ devices)
    case metal

    /// Automatic selection based on image size
    /// - Threshold: 800×800 pixels (640,000 total pixels)
    /// - Logic: images ≥640K pixels → Metal, smaller → vDSP
    /// - Fallback: vDSP if Metal unavailable
    case auto
}

// MARK: - Window/Level Operations Struct

/// Medical imaging window/level processor with GPU acceleration support.
///
/// ## Overview
///
/// ``DCMWindowingProcessor`` provides a comprehensive suite of static methods for window/level
/// transformations, image enhancement, and statistical analysis optimized for 16-bit medical images.
/// The processor supports both CPU (vDSP) and GPU (Metal) acceleration backends with automatic
/// selection based on image size.
///
/// **Key Features:**
/// - Linear window/level transformations with medical presets
/// - CPU acceleration via vDSP (Accelerate framework)
/// - GPU acceleration via Metal compute shaders (3.94× speedup on 1024×1024 images)
/// - CLAHE histogram equalization for contrast enhancement
/// - Gaussian noise reduction using vImage convolution
/// - Automatic optimal window/level calculation
/// - 13 medical imaging presets (lung, bone, brain, etc.)
/// - Quality metrics (PSNR, contrast)
///
/// **Processing Backends:**
/// - **vDSP (CPU)**: Best for images <800×800 pixels (~1-2ms for 512×512)
/// - **Metal (GPU)**: Best for large images (≥800×800 pixels, ~2.20ms for 1024×1024)
/// - **Auto**: Automatic selection with graceful fallback
///
/// ## Usage
///
/// Apply window/level with medical preset:
///
/// ```swift
/// let decoder = try DCMDecoder(contentsOf: url)
/// let pixels16 = decoder.getPixels16()
///
/// // Use medical preset
/// let settings = DCMWindowingProcessor.getPresetValuesV2(preset: .lung)
/// let pixels8 = DCMWindowingProcessor.applyWindowLevel(
///     pixels16: pixels16,
///     center: settings.center,
///     width: settings.width,
///     processingMode: .auto  // Automatically selects vDSP or Metal
/// )
/// ```
///
/// Apply custom window/level with GPU acceleration:
///
/// ```swift
/// // Explicitly use Metal GPU acceleration
/// let pixels8 = DCMWindowingProcessor.applyWindowLevel(
///     pixels16: pixels16,
///     center: 50.0,
///     width: 400.0,
///     processingMode: .metal
/// )
///
/// // Display with CGImage
/// if let pixels8 = pixels8,
///    let cgImage = createCGImage(from: pixels8, width: decoder.width, height: decoder.height) {
///     imageView.image = UIImage(cgImage: cgImage)
/// }
/// ```
///
/// Calculate optimal window/level automatically:
///
/// ```swift
/// let settings = DCMWindowingProcessor.calculateOptimalWindowLevelV2(pixels16: pixels16)
/// if settings.isValid {
///     print("Optimal: center=\(settings.center), width=\(settings.width)")
///     let pixels8 = DCMWindowingProcessor.applyWindowLevel(
///         pixels16: pixels16,
///         center: settings.center,
///         width: settings.width
///     )
/// }
/// ```
///
/// Apply image enhancement:
///
/// ```swift
/// // Apply CLAHE for contrast enhancement
/// if let enhancedData = DCMWindowingProcessor.applyCLAHE(
///     imageData: pixels8,
///     width: decoder.width,
///     height: decoder.height
/// ) {
///     // Display enhanced image
/// }
///
/// // Apply noise reduction
/// if let denoisedData = DCMWindowingProcessor.applyNoiseReduction(
///     imageData: pixels8,
///     width: decoder.width,
///     height: decoder.height
/// ) {
///     // Display denoised image
/// }
/// ```
///
/// Suggest presets based on modality:
///
/// ```swift
/// let modality = decoder.info(for: .modality) ?? ""
/// let bodyPart = decoder.info(for: .bodyPartExamined)
/// let presets = DCMWindowingProcessor.suggestPresets(for: modality, bodyPart: bodyPart)
///
/// for preset in presets {
///     let settings = DCMWindowingProcessor.getPresetValuesV2(preset: preset)
///     print("\(preset.displayName): \(settings.center)/\(settings.width)")
/// }
/// ```
///
/// ## Topics
///
/// ### Window/Level Operations
///
/// - ``applyWindowLevel(pixels16:center:width:processingMode:)``
/// - ``calculateOptimalWindowLevelV2(pixels16:)``
/// - ``batchCalculateOptimalWindowLevelV2(imagePixels:)``
/// - ``ProcessingMode``
///
/// ### Medical Presets
///
/// - ``MedicalPreset``
/// - ``getPresetValuesV2(preset:)``
/// - ``getPresetValuesV2(named:)``
/// - ``suggestPresets(for:bodyPart:)``
/// - ``getPreset(for:)``
/// - ``getPresetName(settings:tolerance:)``
///
/// ### Image Enhancement
///
/// - ``applyCLAHE(imageData:width:height:clipLimit:gridSize:)``
/// - ``applyNoiseReduction(imageData:width:height:)``
///
/// ### Quality Metrics
///
/// - ``calculatePSNR(original:processed:maxValue:)``
/// - ``calculateContrast(pixels:)``
public struct DCMWindowingProcessor {

    // MARK: - Metal GPU Processing

    /// Lazily initialized Metal processor for GPU-accelerated operations.
    /// Returns nil if Metal is unavailable or initialization fails.
    private static var metalProcessor: MetalWindowingProcessor? = {
        return try? MetalWindowingProcessor()
    }()

    /// Checks whether Metal GPU processing is available on this device.
    private static var isMetalAvailable: Bool {
        return metalProcessor != nil
    }

    // MARK: - Core Window/Level Operations

    /// Applies a linear window/level transformation to a 16‑bit
    /// grayscale pixel buffer using vDSP (CPU-based processing).
    /// The resulting pixels are scaled to the 0–255 range and
    /// returned as ``Data``.  This function mirrors the Objective‑C
    /// `applyWindowLevel:length:center:width:` implementation but uses
    /// Swift arrays and vDSP for improved clarity.  If the input is
    /// empty or the width is non‑positive the function returns nil.
    ///
    /// - Parameters:
    ///   - pixels16: An array of unsigned 16‑bit pixel intensities.
    ///   - center: The centre of the window.
    ///   - width: The width of the window.
    /// - Returns: A ``Data`` object containing 8‑bit pixel values or
    ///   `nil` if the input is invalid.
    private static func applyWindowLevelVDSP(pixels16: [UInt16],
                                             center: Double,
                                             width: Double) -> Data? {
        guard !pixels16.isEmpty, width > 0 else { return nil }
        let length = vDSP_Length(pixels16.count)
        // Calculate min and max levels
        let minLevel = center - width / 2.0
        let maxLevel = center + width / 2.0
        let range = maxLevel - minLevel
        let rangeInv: Double = range > 0 ? 255.0 / range : 1.0
        // Convert UInt16 to Double for processing
        var doubles = pixels16.map { Double($0) }
        // Subtract min level (negate for vsaddD which adds)
        var minLevelScalar = -minLevel
        var tempDoubles = [Double](repeating: 0, count: pixels16.count)
        vDSP_vsaddD(&doubles, 1, &minLevelScalar, &tempDoubles, 1, length)
        // Multiply by scaling factor
        var scale = rangeInv
        vDSP_vsmulD(&tempDoubles, 1, &scale, &doubles, 1, length)
        // Allocate output buffer
        var bytes = [UInt8](repeating: 0, count: pixels16.count)
        for i in 0..<pixels16.count {
            var value = doubles[i]
            // Clamp between 0 and 255
            value = max(0.0, min(255.0, value))
            bytes[i] = UInt8(value)
        }
        return Data(bytes)
    }

    /// Applies a linear window/level transformation to a 16‑bit
    /// grayscale pixel buffer using Metal (GPU-based processing).
    /// The resulting pixels are scaled to the 0–255 range and
    /// returned as ``Data``.  This method delegates to the Metal
    /// compute shader for accelerated processing.  If Metal is
    /// unavailable or the input is invalid the function returns nil.
    ///
    /// - Parameters:
    ///   - pixels16: An array of unsigned 16‑bit pixel intensities.
    ///   - center: The centre of the window.
    ///   - width: The width of the window.
    /// - Returns: A ``Data`` object containing 8‑bit pixel values or
    ///   `nil` if the input is invalid or Metal is unavailable.
    private static func applyWindowLevelMetal(
        pixels16: [UInt16],
        center: Double,
        width: Double
    ) -> Data? {
        // Delegate to MetalWindowingProcessor
        return try? metalProcessor?.applyWindowLevel(pixels16: pixels16, center: center, width: width)
    }

    /// Applies a linear window/level transformation to a 16‑bit
    /// grayscale pixel buffer with selectable processing backend.
    /// The resulting pixels are scaled to the 0–255 range and
    /// returned as ``Data``.
    ///
    /// This function supports three processing modes:
    /// - `.vdsp`: CPU-based processing using Accelerate framework
    /// - `.metal`: GPU-based processing using Metal (falls back to vDSP if unavailable)
    /// - `.auto`: Automatic selection based on image size (≥640K pixels → Metal, otherwise vDSP)
    ///
    /// The default mode is `.vdsp` for backward compatibility.
    ///
    /// - Parameters:
    ///   - pixels16: An array of unsigned 16‑bit pixel intensities.
    ///   - center: The centre of the window.
    ///   - width: The width of the window.
    ///   - processingMode: The processing backend to use (default: `.vdsp`).
    /// - Returns: A ``Data`` object containing 8‑bit pixel values or
    ///   `nil` if the input is invalid.
    public static func applyWindowLevel(
        pixels16: [UInt16],
        center: Double,
        width: Double,
        processingMode: ProcessingMode = .vdsp
    ) -> Data? {
        guard !pixels16.isEmpty, width > 0 else { return nil }

        // Determine effective mode
        let effectiveMode: ProcessingMode
        switch processingMode {
        case .vdsp:
            effectiveMode = .vdsp
        case .metal:
            effectiveMode = isMetalAvailable ? .metal : .vdsp
        case .auto:
            let pixelCount = pixels16.count
            let threshold = 800 * 800  // 640,000 pixels
            effectiveMode = (pixelCount >= threshold && isMetalAvailable) ? .metal : .vdsp
        }

        // Dispatch to appropriate implementation
        switch effectiveMode {
        case .vdsp:
            return applyWindowLevelVDSP(pixels16: pixels16, center: center, width: width)
        case .metal:
            return try? metalProcessor?.applyWindowLevel(pixels16: pixels16, center: center, width: width)
        case .auto:
            fatalError("Should have been resolved to .vdsp or .metal")
        }
    }

    /// Estimates optimal window center and width using approximate 1st and 99th percentile bounds derived from a 256-bin histogram.
    ///
    /// Computes a histogram and basic statistics, then selects values near the 1st and 99th percentiles to
    /// derive the window center and width. For empty input returns center 0 and width 0; if percentiles cannot
    /// be determined it falls back to the image mean with a minimum width of 1.0.
    /// - Parameter pixels16: An array of 16-bit pixel samples representing the image.
    /// - Returns: A `WindowSettings` value whose `center` is the midpoint between the estimated 1st and 99th percentile values and whose `width` is the difference between those percentiles (minimum 1.0).
    public static func calculateOptimalWindowLevelV2(pixels16: [UInt16]) -> WindowSettings {
        guard !pixels16.isEmpty else { return WindowSettings(center: 0.0, width: 0.0) }
        // Compute histogram and basic stats
        var minValue: Double = 0
        var maxValue: Double = 0
        var meanValue: Double = 0
        let histogram = calculateHistogram(pixels16: pixels16,
                                           minValue: &minValue,
                                           maxValue: &maxValue,
                                           meanValue: &meanValue)
        guard !histogram.isEmpty else {
            // Ensure minimum width of 1.0 for edge cases
            let width = max(maxValue - minValue, 1.0)
            return WindowSettings(center: meanValue, width: width)
        }
        // Determine thresholds for 1st and 99th percentiles
        let totalPixels = pixels16.count
        let p1Threshold = Int(Double(totalPixels) * 0.01)
        let p99Threshold = Int(Double(totalPixels) * 0.99)
        var cumulativeCount = 0
        var p1Value = minValue
        var p99Value = maxValue
        let binWidth = (maxValue - minValue) / Double(histogram.count)
        for (i, count) in histogram.enumerated() {
            cumulativeCount += count
            let binValue = minValue + (Double(i) + 0.5) * binWidth
            if cumulativeCount >= p1Threshold && p1Value == minValue {
                p1Value = binValue
            }
            if cumulativeCount >= p99Threshold {
                p99Value = binValue
                break
            }
        }
        let center = (p1Value + p99Value) / 2.0
        let width = p99Value - p1Value
        // Ensure minimum width of 1.0 for edge cases (single pixel, uniform values)
        let finalWidth = max(width, 1.0)
        return WindowSettings(center: center, width: finalWidth)
    }

}